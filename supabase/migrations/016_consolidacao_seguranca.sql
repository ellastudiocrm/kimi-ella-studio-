-- 016_consolidacao_seguranca.sql (v3.4.3-patch2)
-- Sprint de consolidação: segurança, MFA e validações defensivas

-- ============================================================
-- ETAPA 1: Revogar funções de teste e helpers do público
-- ============================================================

-- Funções de teste (nenhuma deve ser pública para anon/authenticated)
-- NOTA: não revogar de PUBLIC para não remover o acesso implícito do dono (postgres);
--       as suítes recriam/dropam estas helpers, pelo que usamos IF EXISTS defensivo.
DO $$
BEGIN
    IF to_regprocedure('public.teste_paga_sinal(uuid,text,numeric)') IS NOT NULL THEN
        EXECUTE 'REVOKE ALL ON FUNCTION public.teste_paga_sinal(UUID, TEXT, NUMERIC) FROM anon, authenticated';
    END IF;
    IF to_regprocedure('public.teste_cria_reserva(int,text,text)') IS NOT NULL THEN
        EXECUTE 'REVOKE ALL ON FUNCTION public.teste_cria_reserva(INT, TEXT, TEXT) FROM anon, authenticated';
    END IF;
    IF to_regprocedure('public.teste_agenda_com_anamnese(text,int,text,text)') IS NOT NULL THEN
        EXECUTE 'REVOKE ALL ON FUNCTION public.teste_agenda_com_anamnese(TEXT, INT, TEXT, TEXT) FROM anon, authenticated';
    END IF;
    IF to_regprocedure('public.teste_cria_revisao_atrasada(int,text,text,numeric)') IS NOT NULL THEN
        EXECUTE 'REVOKE ALL ON FUNCTION public.teste_cria_revisao_atrasada(INT, TEXT, TEXT, NUMERIC) FROM anon, authenticated';
    END IF;
    IF to_regprocedure('public.teste_proximo_dia(int,text)') IS NOT NULL THEN
        EXECUTE 'REVOKE ALL ON FUNCTION public.teste_proximo_dia(INT, TEXT) FROM anon, authenticated';
    END IF;
END $$;

-- Helpers internos (só o sistema/triggers usam)
REVOKE ALL ON FUNCTION public.validar_transicao_reserva() FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.validar_transicao_reserva_item() FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.validar_transicao_ocupacao() FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.validar_recurso_compativel() FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.validar_alocacao_mesma_empresa() FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.validar_credito_servico_mesma_empresa() FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.validar_compra_item_mesma_empresa() FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.validar_utilizacao_mesma_empresa() FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.validar_resposta_mesma_empresa() FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.validar_usuario_profissional_mesma_empresa() FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.set_updated_at() FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.sincronizar_bloqueio_ocupacoes() FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.atualizar_bloqueio_ocupacoes() FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.remover_bloqueio_ocupacoes() FROM PUBLIC, anon, authenticated;

-- notificar_staff: só service_role e authenticated (nunca anon)
REVOKE ALL ON FUNCTION public.notificar_staff(UUID, TEXT, TEXT, TEXT[]) FROM anon;

-- ============================================================
-- ETAPA 2a: MFA em cancelar_item_reserva quando há exceção financeira
-- ============================================================

CREATE OR REPLACE FUNCTION public.cancelar_item_reserva(
    p_reserva_item_id UUID,
    p_excecao TEXT DEFAULT NULL,
    p_motivo TEXT DEFAULT NULL
)
RETURNS TEXT
LANGUAGE plpgsql
SECURITY DEFINER SET search_path = ''
AS $$
DECLARE
    v_item RECORD;
    v_restantes INT;
    v_limite TIMESTAMP;
    v_regra TEXT;
    v_pago_reserva DECIMAL(10,2);
    v_valor_item DECIMAL(10,2);
BEGIN
    SELECT ri.*, r.empresa_id AS r_empresa_id INTO v_item
    FROM public.reserva_itens ri
    JOIN public.reservas r ON r.id = ri.reserva_id
    WHERE ri.id = p_reserva_item_id;
    IF NOT FOUND THEN RAISE EXCEPTION 'Item não encontrado'; END IF;

    IF auth.role() = 'authenticated' THEN
        IF v_item.r_empresa_id IS DISTINCT FROM public.minha_empresa_id() THEN
            RAISE EXCEPTION 'Sem permissão para esta empresa';
        END IF;
        IF public.meu_perfil() NOT IN ('admin','gestor','recepcao')
           AND NOT (public.meu_perfil() = 'profissional' AND v_item.profissional_id = public.meu_profissional_id()) THEN
            RAISE EXCEPTION 'Sem permissão para cancelar este item';
        END IF;
    END IF;

    IF p_excecao IS NOT NULL THEN
        IF p_excecao NOT IN ('credito', 'estorno', 'perdido') THEN
            RAISE EXCEPTION 'Exceção inválida: %', p_excecao;
        END IF;
        -- v3.4.3-patch2: MFA obrigatório para exceção financeira (alinhado com cancelar_reserva)
        IF auth.role() = 'authenticated' THEN
            IF public.meu_perfil() <> 'admin' THEN
                RAISE EXCEPTION 'Exceção de cancelamento exige perfil admin';
            END IF;
            IF COALESCE(auth.jwt() ->> 'aal', 'aal1') <> 'aal2' THEN
                RAISE EXCEPTION 'Exceção de cancelamento exige verificação em duas etapas (MFA)';
            END IF;
        END IF;
        IF p_motivo IS NULL OR length(trim(p_motivo)) = 0 THEN
            RAISE EXCEPTION 'Exceção de cancelamento exige motivo';
        END IF;
    END IF;

    -- Ordem de lock global (anti-deadlock): RESERVA primeiro, depois o item
    PERFORM 1 FROM public.reservas WHERE id = v_item.reserva_id FOR UPDATE;

    -- Re-lê o item já sob lock (leitura anterior era sem lock)
    SELECT ri.*, r.empresa_id AS r_empresa_id, r.estado AS r_estado INTO v_item
    FROM public.reserva_itens ri
    JOIN public.reservas r ON r.id = ri.reserva_id
    WHERE ri.id = p_reserva_item_id FOR UPDATE OF ri;

    -- v3.4.1: dinheiro em revisão só sai pela fila
    IF v_item.r_estado = 'pagamento_em_revisao' THEN
        RAISE EXCEPTION 'Reserva em revisão de pagamento — decida pela RPC resolver_revisao';
    END IF;

    IF v_item.estado NOT IN ('pendente', 'confirmado') THEN
        RAISE EXCEPTION 'Item não pode ser cancelado no estado atual';
    END IF;

    SELECT COUNT(*) INTO v_restantes
    FROM public.reserva_itens
    WHERE reserva_id = v_item.reserva_id AND estado IN ('pendente', 'confirmado') AND id <> p_reserva_item_id;

    -- Último item: cancela a RESERVA primeiro
    IF v_restantes = 0 THEN
        PERFORM public.cancelar_reserva(v_item.reserva_id, p_excecao, p_motivo);
        RETURN 'reserva_cancelada';
    END IF;

    -- Regra das 16h calculada para ESTE item
    v_limite := ((v_item.inicio AT TIME ZONE 'America/Sao_Paulo')::DATE - 1) + interval '16 hours';
    v_regra := CASE WHEN (now() AT TIME ZONE 'America/Sao_Paulo') <= v_limite
                    THEN 'credito_automatico' ELSE 'perda_automatica' END;

    UPDATE public.reserva_itens SET estado = 'cancelado' WHERE id = p_reserva_item_id;

    UPDATE public.agenda_ocupacoes SET estado = 'cancelada'
    WHERE reserva_item_id = p_reserva_item_id AND estado = 'ativa';

    SELECT COALESCE(SUM(t.valor), 0) INTO v_pago_reserva
    FROM public.cobrancas c
    JOIN public.transacoes t ON t.cobranca_id = c.id
    WHERE c.reserva_id = v_item.reserva_id AND t.estado = 'pago'
      AND t.finalidade IN ('sinal', 'saldo', 'pagamento_total');

    -- v3.4.1b: 'confirmar' devolve o dinheiro à reserva viva
    v_valor_item := LEAST(v_item.valor_sinal,
        v_pago_reserva - COALESCE((SELECT SUM(rev.valor_sinal) FROM public.revisoes_cancelamento rev
                                   WHERE rev.reserva_id = v_item.reserva_id
                                     AND rev.decisao_final IS DISTINCT FROM 'confirmar'), 0));

    IF v_valor_item > 0 THEN
        INSERT INTO public.revisoes_cancelamento
            (reserva_id, reserva_item_id, empresa_id, valor_sinal, regra_aplicada, decisao_final, decidido_por, motivo_decisao)
        VALUES
            (v_item.reserva_id, p_reserva_item_id, v_item.r_empresa_id, v_valor_item,
             v_regra, p_excecao, public.meu_usuario_id(), p_motivo)
        ON CONFLICT DO NOTHING;

        PERFORM public.notificar_staff(v_item.r_empresa_id, 'cancelamento_item',
            'Item cancelado com R$ ' || trim(to_char(v_valor_item, '999990D00')) ||
            ' pago — ' || v_item.nome_servico || ' (' || v_regra || ')');
    END IF;

    UPDATE public.reservas r SET
        valor_total = t.total,
        valor_sinal_total = t.sinal
    FROM (SELECT COALESCE(SUM(preco_final),0) AS total, COALESCE(SUM(valor_sinal),0) AS sinal
          FROM public.reserva_itens
          WHERE reserva_id = v_item.reserva_id AND estado <> 'cancelado') t
    WHERE r.id = v_item.reserva_id;

    UPDATE public.cobrancas c SET
        valor_total = r.valor_total,
        valor_sinal = r.valor_sinal_total
    FROM public.reservas r
    WHERE c.reserva_id = r.id AND r.id = v_item.reserva_id AND c.estado = 'pendente';

    RETURN v_regra;
END;
$$;

-- Repete privilégios da RPC alterada
REVOKE ALL ON FUNCTION public.cancelar_item_reserva(UUID, TEXT, TEXT) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.cancelar_item_reserva(UUID, TEXT, TEXT) TO authenticated, service_role;

-- ============================================================
-- ETAPA 2b: Validação defensiva no webhook
-- ============================================================

CREATE OR REPLACE FUNCTION public.processar_pagamento_webhook(
    p_origem TEXT,
    p_external_event_id TEXT,
    p_valor DECIMAL,
    p_transacao_id UUID DEFAULT NULL,
    p_cobranca_id UUID DEFAULT NULL,
    p_mp_transaction_id TEXT DEFAULT NULL,
    p_payload JSONB DEFAULT '{}'::JSONB,
    p_assinatura_verificada BOOLEAN DEFAULT false
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER SET search_path = ''
AS $$
DECLARE
    v_inbox UUID;
    v_tx RECORD;
    v_cobranca RECORD;
    v_reserva RECORD;
    v_tx_id UUID;
    v_pago DECIMAL(10,2);
    v_atrasado BOOLEAN := false;
    v_reserva_id_lookup UUID;
BEGIN
    -- v3.4.3-patch2: validação defensiva do valor
    IF p_valor IS NULL OR p_valor <= 0 THEN
        RAISE EXCEPTION 'Valor de pagamento inválido: % (deve ser > 0)', p_valor;
    END IF;

    -- 1) Dedupe pela caixa de entrada
    INSERT INTO public.webhook_inbox (empresa_id, origem, external_event_id, payload, assinatura_verificada)
    SELECT c.empresa_id, p_origem, p_external_event_id, p_payload, p_assinatura_verificada
    FROM public.cobrancas c
    WHERE c.id = p_cobranca_id
       OR c.id = (SELECT t.cobranca_id FROM public.transacoes t WHERE t.id = p_transacao_id)
    ON CONFLICT (origem, external_event_id) DO NOTHING
    RETURNING id INTO v_inbox;

    IF v_inbox IS NULL THEN
        IF EXISTS (SELECT 1 FROM public.webhook_inbox WHERE origem = p_origem AND external_event_id = p_external_event_id) THEN
            RETURN jsonb_build_object('status', 'duplicado', 'external_event_id', p_external_event_id);
        END IF;
        RAISE EXCEPTION 'Cobrança/transação não encontrada para o webhook';
    END IF;

    -- 2) Assinatura
    IF NOT p_assinatura_verificada THEN
        RAISE EXCEPTION 'Assinatura do webhook não verificada — evento rejeitado';
    END IF;

    -- 3) Resolve a cobrança
    IF p_cobranca_id IS NULL AND p_transacao_id IS NOT NULL THEN
        SELECT t.cobranca_id INTO p_cobranca_id FROM public.transacoes t WHERE t.id = p_transacao_id;
    END IF;
    IF p_cobranca_id IS NULL THEN
        RAISE EXCEPTION 'Webhook sem transação nem cobrança identificada';
    END IF;

    SELECT c.reserva_id INTO v_reserva_id_lookup FROM public.cobrancas c WHERE c.id = p_cobranca_id;
    IF v_reserva_id_lookup IS NULL THEN RAISE EXCEPTION 'Cobrança % não encontrada', p_cobranca_id; END IF;

    SELECT * INTO v_reserva FROM public.reservas WHERE id = v_reserva_id_lookup FOR UPDATE;
    SELECT * INTO v_cobranca FROM public.cobrancas WHERE id = p_cobranca_id FOR UPDATE;

    -- 4) Liquida a transação pendente ou insere nova
    v_tx_id := NULL;
    IF p_transacao_id IS NOT NULL THEN
        SELECT * INTO v_tx FROM public.transacoes t WHERE t.id = p_transacao_id FOR UPDATE;
        IF FOUND THEN
            IF v_tx.cobranca_id <> p_cobranca_id THEN
                RAISE EXCEPTION 'Transação % não pertence à cobrança %', p_transacao_id, p_cobranca_id;
            END IF;
            IF v_tx.estado = 'pago' THEN
                UPDATE public.webhook_inbox SET processado = true WHERE id = v_inbox;
                RETURN jsonb_build_object('status', 'ja_processado', 'transacao_id', v_tx.id);
            END IF;
            UPDATE public.transacoes
            SET estado = 'pago', mp_transaction_id = COALESCE(p_mp_transaction_id, mp_transaction_id),
                payload_webhook = p_payload
            WHERE id = v_tx.id;
            v_tx_id := v_tx.id;
        END IF;
    END IF;

    IF v_tx_id IS NULL THEN
        INSERT INTO public.transacoes (cobranca_id, empresa_id, mp_idempotency_key, mp_transaction_id, valor, meio, finalidade, estado, payload_webhook)
        SELECT p_cobranca_id, c.empresa_id, 'mp-' || p_external_event_id, p_mp_transaction_id,
               p_valor, 'pix',
               CASE
                   WHEN EXISTS (SELECT 1 FROM public.transacoes t
                                WHERE t.cobranca_id = c.id AND t.finalidade = 'sinal' AND t.estado = 'pago')
                        OR p_valor < c.valor_sinal THEN 'saldo'
                   WHEN p_valor >= c.valor_total THEN 'pagamento_total'
                   ELSE 'sinal'
               END,
               'pago', p_payload
        FROM public.cobrancas c WHERE c.id = p_cobranca_id
        RETURNING id INTO v_tx_id;
    END IF;

    INSERT INTO public.eventos_pagamento (transacao_id, mp_event_id, tipo_evento, payload, processado)
    VALUES (v_tx_id, p_external_event_id, 'payment.updated', p_payload, true)
    ON CONFLICT (mp_event_id) DO NOTHING;

    SELECT COALESCE(SUM(t.valor), 0) INTO v_pago
    FROM public.transacoes t
    WHERE t.cobranca_id = p_cobranca_id AND t.estado = 'pago'
      AND t.finalidade IN ('sinal', 'saldo', 'pagamento_total');

    -- 5) Decisão pelo estado atual da reserva
    IF v_reserva.estado = 'pre_reserva' THEN
        SELECT EXISTS (
            SELECT 1 FROM public.agenda_ocupacoes
            WHERE origem = 'pre_reserva' AND origem_id = v_reserva.id
              AND (estado = 'expirada' OR (estado = 'ativa' AND expires_at <= now()))
        ) INTO v_atrasado;

        IF NOT v_atrasado AND v_pago >= COALESCE(v_reserva.valor_sinal_total, 0) THEN
            UPDATE public.reservas SET estado = 'confirmada' WHERE id = v_reserva.id;
            UPDATE public.reserva_itens SET estado = 'confirmado'
            WHERE reserva_id = v_reserva.id AND estado = 'pendente';
            UPDATE public.agenda_ocupacoes SET origem = 'reserva', expires_at = NULL
            WHERE origem = 'pre_reserva' AND origem_id = v_reserva.id AND estado = 'ativa';
            UPDATE public.cobrancas
            SET estado = CASE WHEN v_pago >= valor_total THEN 'total_pago' ELSE 'sinal_pago' END
            WHERE id = p_cobranca_id;

            UPDATE public.webhook_inbox SET processado = true WHERE id = v_inbox;
            RETURN jsonb_build_object('status', 'confirmada', 'reserva_id', v_reserva.id, 'transacao_id', v_tx_id);
        END IF;

        IF NOT v_atrasado THEN
            UPDATE public.webhook_inbox SET processado = true WHERE id = v_inbox;
            RETURN jsonb_build_object('status', 'parcial_registrado', 'reserva_id', v_reserva.id,
                                      'transacao_id', v_tx_id, 'pago_ate_agora', v_pago);
        END IF;
    END IF;

    IF (v_reserva.estado = 'expirada' OR (v_reserva.estado = 'pre_reserva' AND v_atrasado)) AND v_pago > 0 THEN
        UPDATE public.agenda_ocupacoes SET estado = 'expirada'
        WHERE origem = 'pre_reserva' AND origem_id = v_reserva.id AND estado = 'ativa';
        UPDATE public.reservas SET estado = 'pagamento_em_revisao' WHERE id = v_reserva.id;

        PERFORM public.revisao_completar_fila(v_reserva.id, 'pagamento_atrasado',
            'Pagamento identificado após o prazo — confirmar (se o horário estiver livre), estornar, dar crédito ou marcar perdido');

        PERFORM public.notificar_staff(v_reserva.empresa_id, 'pagamento_em_revisao',
            'Pagamento atrasado na reserva ' || v_reserva.id::text || ' (R$ ' ||
            trim(to_char(v_pago, '999990D00')) || '). O horário foi liberado. Decida na fila de revisões.');

        UPDATE public.webhook_inbox SET processado = true WHERE id = v_inbox;
        RETURN jsonb_build_object('status', 'pagamento_em_revisao', 'reserva_id', v_reserva.id, 'transacao_id', v_tx_id);
    END IF;

    IF v_reserva.estado = 'confirmada' THEN
        UPDATE public.cobrancas
        SET estado = CASE WHEN v_pago >= valor_total THEN 'total_pago' ELSE 'sinal_pago' END
        WHERE id = p_cobranca_id;
        UPDATE public.webhook_inbox SET processado = true WHERE id = v_inbox;
        RETURN jsonb_build_object('status', 'saldo_registrado', 'reserva_id', v_reserva.id, 'transacao_id', v_tx_id);
    END IF;

    IF v_reserva.estado = 'pagamento_em_revisao' THEN
        PERFORM public.revisao_completar_fila(v_reserva.id, 'pagamento_atrasado',
            'Novo pagamento com a reserva em revisão — fila completada');
        PERFORM public.notificar_staff(v_reserva.empresa_id, 'pagamento_em_revisao',
            'Novo pagamento (R$ ' || trim(to_char(p_valor, '999990D00')) || ') em reserva já em revisão: ' || v_reserva.id::text);
        UPDATE public.webhook_inbox SET processado = true WHERE id = v_inbox;
        RETURN jsonb_build_object('status', 'pagamento_em_revisao', 'reserva_id', v_reserva.id, 'transacao_id', v_tx_id);
    END IF;

    PERFORM public.revisao_completar_fila(v_reserva.id, 'pagamento_atrasado',
            'Pagamento recebido com a reserva em estado ' || v_reserva.estado || ' — avaliar estorno/crédito');
    PERFORM public.notificar_staff(v_reserva.empresa_id, 'pagamento_inesperado',
        'Pagamento de R$ ' || trim(to_char(p_valor, '999990D00')) || ' em reserva ' || v_reserva.estado || ': ' || v_reserva.id::text);
    UPDATE public.webhook_inbox SET processado = true WHERE id = v_inbox;
    RETURN jsonb_build_object('status', 'revisao_manual', 'reserva_id', v_reserva.id, 'transacao_id', v_tx_id);
END;
$$;

-- Repete privilégios da RPC alterada
REVOKE ALL ON FUNCTION public.processar_pagamento_webhook(TEXT, TEXT, DECIMAL, UUID, UUID, TEXT, JSONB, BOOLEAN) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.processar_pagamento_webhook(TEXT, TEXT, DECIMAL, UUID, UUID, TEXT, JSONB, BOOLEAN) TO service_role;
