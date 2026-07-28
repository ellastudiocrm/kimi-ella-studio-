-- 015_fix_cobranca_revisao.sql (v3.4.3-patch) — fix da migration 014
-- Problema: resolver_revisao só atualizava cobrança para 'cancelada' quando
-- a reserva estava em 'pagamento_em_revisao'. Reservas já 'cancelada' não
-- tinham a cobrança fechada.
--
-- Fix: atualizar cobrança em TODOS os ramos financeiros (credito, estorno, perdido)
-- independentemente do estado da reserva, desde que a cobrança não esteja já
-- em estado terminal.

CREATE OR REPLACE FUNCTION resolver_revisao(
    p_revisao_id UUID,
    p_decisao TEXT,
    p_motivo TEXT DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER SET search_path = ''
AS $$
DECLARE
    v_rev RECORD;
    v_reserva RECORD;
    v_item RECORD;
    v_conta UUID;
    v_saldo DECIMAL(10,2);
BEGIN
    IF p_decisao NOT IN ('credito', 'estorno', 'perdido', 'confirmar') THEN
        RAISE EXCEPTION 'Decisão inválida: %', p_decisao;
    END IF;

    IF auth.role() = 'authenticated' THEN
        IF public.meu_perfil() NOT IN ('admin', 'gestor') THEN
            RAISE EXCEPTION 'Apenas admin/gestor resolvem revisões';
        END IF;
        IF COALESCE(auth.jwt() ->> 'aal', 'aal1') <> 'aal2' THEN
            RAISE EXCEPTION 'Decisão financeira exige verificação em duas etapas (MFA)';
        END IF;
    END IF;

    SELECT * INTO v_rev FROM public.revisoes_cancelamento WHERE id = p_revisao_id FOR UPDATE;
    IF NOT FOUND THEN RAISE EXCEPTION 'Revisão não encontrada'; END IF;
    IF auth.role() = 'authenticated' AND v_rev.empresa_id IS DISTINCT FROM public.minha_empresa_id() THEN
        RAISE EXCEPTION 'Sem permissão para esta empresa';
    END IF;
    IF v_rev.decisao_final IS NOT NULL THEN
        RAISE EXCEPTION 'Revisão já decidida (%) — decisões são finais', v_rev.decisao_final;
    END IF;

    SELECT * INTO v_reserva FROM public.reservas WHERE id = v_rev.reserva_id FOR UPDATE;

    -- ===================== CONFIRMAR =====================
    IF p_decisao = 'confirmar' THEN
        IF v_reserva.estado <> 'pagamento_em_revisao' THEN
            RAISE EXCEPTION 'Só se pode confirmar reserva em pagamento_em_revisao (estado: %)', v_reserva.estado;
        END IF;
        IF EXISTS (SELECT 1 FROM public.reserva_itens ri
                   WHERE ri.reserva_id = v_reserva.id AND ri.inicio <= now()) THEN
            RAISE EXCEPTION 'O horário desta reserva já passou — escolha estorno ou crédito';
        END IF;
        FOR v_item IN SELECT * FROM public.reserva_itens
                      WHERE reserva_id = v_reserva.id AND estado = 'pendente' LOOP
            IF EXISTS (SELECT 1 FROM public.agenda_ocupacoes o
                       WHERE o.estado = 'ativa' AND o.profissional_id = v_item.profissional_id
                         AND o.periodo && tstzrange(v_item.inicio, v_item.fim, '[)')) THEN
                RAISE EXCEPTION 'Horário de % já foi ocupado por outro agendamento — escolha estorno ou crédito',
                    to_char(v_item.inicio AT TIME ZONE 'America/Sao_Paulo', 'DD/MM HH24:MI');
            END IF;
            IF EXISTS (SELECT 1 FROM public.agenda_ocupacoes o
                       WHERE o.estado = 'ativa' AND o.recurso_id = v_item.recurso_id
                         AND o.periodo && tstzrange(v_item.inicio, v_item.fim, '[)')) THEN
                RAISE EXCEPTION 'Recurso do horário de % ocupado — escolha estorno ou crédito',
                    to_char(v_item.inicio AT TIME ZONE 'America/Sao_Paulo', 'DD/MM HH24:MI');
            END IF;
        END LOOP;
        FOR v_item IN SELECT * FROM public.reserva_itens
                      WHERE reserva_id = v_reserva.id AND estado = 'pendente' LOOP
            INSERT INTO public.agenda_ocupacoes (empresa_id, tipo_ocupacao, recurso_id, reserva_item_id, inicio, fim, origem, origem_id, estado)
            VALUES (v_reserva.empresa_id, 'recurso', v_item.recurso_id, v_item.id, v_item.inicio, v_item.fim, 'reserva', v_reserva.id, 'ativa');
            INSERT INTO public.agenda_ocupacoes (empresa_id, tipo_ocupacao, profissional_id, reserva_item_id, inicio, fim, origem, origem_id, estado)
            VALUES (v_reserva.empresa_id, 'profissional', v_item.profissional_id, v_item.id, v_item.inicio, v_item.fim, 'reserva', v_reserva.id, 'ativa');
            UPDATE public.reserva_itens SET estado = 'confirmado' WHERE id = v_item.id;
        END LOOP;
        UPDATE public.reservas SET estado = 'confirmada' WHERE id = v_reserva.id;
        UPDATE public.cobrancas c
        SET estado = CASE WHEN (SELECT COALESCE(SUM(t.valor),0) FROM public.transacoes t
                                WHERE t.cobranca_id = c.id AND t.estado = 'pago') >= c.valor_total
                          THEN 'total_pago' ELSE 'sinal_pago' END
        WHERE c.reserva_id = v_reserva.id;

    -- ===================== CRÉDITO =====================
    ELSIF p_decisao = 'credito' THEN
        INSERT INTO public.contas_creditos (cliente_id, empresa_id, tipo)
        VALUES (v_reserva.cliente_id, v_reserva.empresa_id, 'pago')
        ON CONFLICT (cliente_id, empresa_id, tipo) DO NOTHING;
        SELECT c.id INTO v_conta FROM public.contas_creditos c
        WHERE c.cliente_id = v_reserva.cliente_id AND c.empresa_id = v_reserva.empresa_id AND c.tipo = 'pago'
        FOR UPDATE;
        SELECT COALESCE(SUM(l.valor), 0) INTO v_saldo
        FROM public.lancamentos_creditos l WHERE l.conta_id = v_conta;
        INSERT INTO public.lancamentos_creditos
            (conta_id, tipo_lancamento, valor, saldo_apos, idempotencia_key, origem_id, origem_tipo, observacoes)
        VALUES
            (v_conta, 'credito_cancelamento', v_rev.valor_sinal, v_saldo + v_rev.valor_sinal,
             'revisao-' || v_rev.id::text, v_rev.reserva_id, 'revisao_cancelamento',
             COALESCE(p_motivo, 'Revisão ' || v_rev.regra_aplicada))
        ON CONFLICT (idempotencia_key) DO NOTHING;
        IF v_reserva.estado = 'pagamento_em_revisao' THEN
            UPDATE public.reservas SET estado = 'cancelada' WHERE id = v_reserva.id;
            UPDATE public.reserva_itens SET estado = 'cancelado'
            WHERE reserva_id = v_reserva.id AND estado = 'pendente';
        END IF;
        -- v3.4.3-patch: cobrança sempre terminal 'cancelada' nos ramos financeiros
        UPDATE public.cobrancas SET estado = 'cancelada'
        WHERE reserva_id = v_reserva.id
          AND estado IN ('pendente', 'sinal_pago', 'total_pago');

    -- ===================== ESTORNO =====================
    ELSIF p_decisao = 'estorno' THEN
        UPDATE public.transacoes t SET estado = 'estornado'
        FROM public.cobrancas c
        WHERE t.cobranca_id = c.id AND c.reserva_id = v_reserva.id
          AND t.finalidade IN ('sinal', 'saldo', 'pagamento_total') AND t.estado = 'pago';
        INSERT INTO public.jobs (empresa_id, tipo, payload)
        VALUES (v_reserva.empresa_id, 'estorno_mercado_pago',
                jsonb_build_object('reserva_id', v_reserva.id, 'revisao_id', v_rev.id,
                                   'valor', v_rev.valor_sinal, 'motivo', p_motivo));
        IF v_reserva.estado = 'pagamento_em_revisao' THEN
            UPDATE public.reservas SET estado = 'cancelada' WHERE id = v_reserva.id;
            UPDATE public.reserva_itens SET estado = 'cancelado'
            WHERE reserva_id = v_reserva.id AND estado = 'pendente';
        END IF;
        -- v3.4.3-patch: cobrança sempre terminal 'cancelada' nos ramos financeiros
        UPDATE public.cobrancas SET estado = 'cancelada'
        WHERE reserva_id = v_reserva.id
          AND estado IN ('pendente', 'sinal_pago', 'total_pago');

    -- ===================== PERDIDO =====================
    ELSE
        IF v_reserva.estado = 'pagamento_em_revisao' THEN
            UPDATE public.reservas SET estado = 'cancelada' WHERE id = v_reserva.id;
            UPDATE public.reserva_itens SET estado = 'cancelado'
            WHERE reserva_id = v_reserva.id AND estado = 'pendente';
        END IF;
        -- v3.4.3-patch: cobrança sempre terminal 'cancelada' nos ramos financeiros
        UPDATE public.cobrancas SET estado = 'cancelada'
        WHERE reserva_id = v_reserva.id
          AND estado IN ('pendente', 'sinal_pago', 'total_pago');
    END IF;

    UPDATE public.revisoes_cancelamento
    SET decisao_final = p_decisao, decidido_por = public.meu_usuario_id(), motivo_decisao = p_motivo
    WHERE id = p_revisao_id;

    INSERT INTO public.log_acoes (empresa_id, tabela, registro_id, acao, usuario_id, perfil, motivo)
    VALUES (v_rev.empresa_id, 'revisoes_cancelamento', p_revisao_id, 'UPDATE',
            public.meu_usuario_id(), public.meu_perfil(),
            'decisao=' || p_decisao || COALESCE(': ' || p_motivo, ''));

    RETURN jsonb_build_object('revisao_id', p_revisao_id, 'decisao', p_decisao,
                              'reserva_id', v_reserva.id,
                              'reserva_status', (SELECT estado FROM public.reservas WHERE id = v_reserva.id));
END;
$$;

-- Permissões preservadas
REVOKE ALL ON FUNCTION public.resolver_revisao(UUID, TEXT, TEXT) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.resolver_revisao(UUID, TEXT, TEXT) TO authenticated, service_role;
