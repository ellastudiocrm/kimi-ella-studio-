-- 009_payment_rpc.sql (v3.4) — confirmação, cancelamento (regra 16h), pagamento
-- presencial, desistência de pré-reserva, revisão de anamnese, reemissão de token,
-- expiração — + GRANT/REVOKE de EXECUTE.
--
-- v3.4:
--  - pagamento ATRASADO não confirma: libera o slot (ocupações expiradas), move a
--    reserva para 'pagamento_em_revisao' e notifica o staff (Ricardo/Carlos — fim
--    do sequestro do slot e da fila sem saída);
--  - estado novo 'expirada' separa expiração de cancelamento (006);
--  - registrar_pagamento_presencial idempotente (chave do caixa), retorna JSONB,
--    valor ≤ pendente, MFA (aal2) para staff — Ricardo A4/#7;
--  - cancelar_reserva: regra das 16h em hora LOCAL do estúdio (Ricardo #4),
--    exceção exige admin + aal2 + motivo, revisão só quando há dinheiro pago;
--  - regenerar_token: expiração = MIN(agendamento, 24h) (Carlos #2) e exige
--    perfil de equipe (Carlos #3);
--  - expirar_pre_reservas: FOR UPDATE SKIP LOCKED — nunca espera atrás de
--    confirmar/webhook (Ricardo A1).

-- ---------------------------------------------------------------- confirmar_reserva
CREATE OR REPLACE FUNCTION confirmar_reserva(p_reserva_id UUID)
RETURNS TEXT
LANGUAGE plpgsql
SECURITY DEFINER SET search_path = ''
AS $$
DECLARE
    v_reserva RECORD;
    v_pago DECIMAL(10,2);
    v_atrasado BOOLEAN;
BEGIN
    SELECT * INTO v_reserva FROM public.reservas WHERE id = p_reserva_id FOR UPDATE;
    IF NOT FOUND THEN RAISE EXCEPTION 'Reserva não encontrada'; END IF;

    IF auth.role() = 'authenticated' AND v_reserva.empresa_id IS DISTINCT FROM public.minha_empresa_id() THEN
        RAISE EXCEPTION 'Sem permissão para esta empresa';
    END IF;

    IF v_reserva.estado = 'confirmada' THEN RETURN 'ja_confirmada'; END IF;
    IF v_reserva.estado = 'pagamento_em_revisao' THEN RETURN 'pagamento_em_revisao'; END IF;
    IF v_reserva.estado <> 'pre_reserva' THEN
        RAISE EXCEPTION 'Reserva não está em pré-reserva (estado: %)', v_reserva.estado;
    END IF;

    -- Aceita sinal OU pagamento 100%, conferindo o VALOR
    SELECT COALESCE(SUM(t.valor), 0) INTO v_pago
    FROM public.cobrancas c
    JOIN public.transacoes t ON t.cobranca_id = c.id
    WHERE c.reserva_id = p_reserva_id
      AND t.finalidade IN ('sinal', 'saldo', 'pagamento_total')
      AND t.estado = 'pago';

    IF v_pago < COALESCE(v_reserva.valor_sinal_total, 0) THEN
        RAISE EXCEPTION 'Sinal não pago (pago: %, exigido: %)', v_pago, v_reserva.valor_sinal_total;
    END IF;

    -- Atraso = ocupação já expirada OU expires_at passou (mesmo que o cron ainda não tenha corrido)
    SELECT EXISTS (
        SELECT 1 FROM public.agenda_ocupacoes
        WHERE origem = 'pre_reserva' AND origem_id = p_reserva_id
          AND (estado = 'expirada' OR (estado = 'ativa' AND expires_at <= now()))
    ) INTO v_atrasado;

    IF v_atrasado THEN
        -- v3.4: o slot é LIBERADO na hora; o dinheiro vai para a fila de revisão
        UPDATE public.agenda_ocupacoes SET estado = 'expirada'
        WHERE origem = 'pre_reserva' AND origem_id = p_reserva_id AND estado = 'ativa';

        UPDATE public.reservas SET estado = 'pagamento_em_revisao' WHERE id = p_reserva_id;

        INSERT INTO public.revisoes_cancelamento (reserva_id, empresa_id, valor_sinal, regra_aplicada, motivo_decisao)
        VALUES (p_reserva_id, v_reserva.empresa_id, v_pago, 'pagamento_atrasado',
                'Sinal pago após o prazo da pré-reserva — confirmar (se o horário ainda estiver livre), estornar ou dar crédito')
        ON CONFLICT DO NOTHING;   -- uma única revisão aberta por reserva (índice parcial 006)

        PERFORM public.notificar_staff(v_reserva.empresa_id, 'pagamento_em_revisao',
            'Pagamento atrasado na reserva ' || p_reserva_id::text || ' (R$ ' ||
            trim(to_char(v_pago, '999990D00')) || '). O horário foi liberado. Decida: confirmar, estornar, crédito ou perdido.');

        RETURN 'pagamento_em_revisao';
    END IF;

    UPDATE public.reservas SET estado = 'confirmada' WHERE id = p_reserva_id;

    UPDATE public.reserva_itens SET estado = 'confirmado'
    WHERE reserva_id = p_reserva_id AND estado = 'pendente';

    UPDATE public.agenda_ocupacoes
    SET origem = 'reserva', expires_at = NULL
    WHERE origem = 'pre_reserva' AND origem_id = p_reserva_id AND estado = 'ativa';

    UPDATE public.cobrancas
    SET estado = CASE WHEN v_pago >= v_reserva.valor_total THEN 'total_pago' ELSE 'sinal_pago' END
    WHERE reserva_id = p_reserva_id AND estado = 'pendente';

    RETURN 'confirmada';
END;
$$;

-- --------------------------------------------------- revisao_completar_fila
-- v3.4.1b (achado da prova de corrida F9: webhook de saldo × cancelar_reserva).
-- A fila aberta ao nível da reserva vale SEMPRE:
--     dinheiro pago − já decidido (≠ 'confirmar') − já na fila por item.
-- Pagamento novo em reserva morta/em revisão COMPLETA a fila até esse valor —
-- antes, o INSERT bruto com ON CONFLICT DO NOTHING era engolido pelo índice
-- uq_revisao_aberta_reserva (dinheiro sem rasto) ou contava a fila em dobro.
-- Pré-condição: o chamador TEM de estar com a linha da reserva bloqueada (FOR UPDATE).
CREATE OR REPLACE FUNCTION public.revisao_completar_fila(
    p_reserva_id UUID,
    p_regra TEXT,
    p_motivo TEXT
)
RETURNS DECIMAL               -- quanto ficou na revisão aberta ao nível da reserva
LANGUAGE plpgsql
SECURITY DEFINER SET search_path = ''
AS $$
DECLARE
    v_empresa UUID;
    v_pago DECIMAL(10,2);
    v_coberto DECIMAL(10,2);
    v_alvo DECIMAL(10,2);
BEGIN
    SELECT r.empresa_id INTO v_empresa FROM public.reservas r WHERE r.id = p_reserva_id;
    IF NOT FOUND THEN RAISE EXCEPTION 'Reserva não encontrada'; END IF;

    SELECT COALESCE(SUM(t.valor), 0) INTO v_pago
    FROM public.cobrancas c
    JOIN public.transacoes t ON t.cobranca_id = c.id
    WHERE c.reserva_id = p_reserva_id AND t.estado = 'pago'
      AND t.finalidade IN ('sinal', 'saldo', 'pagamento_total');

    -- Coberto = dinheiro já encaminhado (decisões ≠ confirmar, em qualquer nível)
    --         + dinheiro já à espera na fila POR ITEM. A revisão aberta ao nível
    -- da reserva NÃO entra: é ela que estamos a completar.
    SELECT COALESCE(SUM(rev.valor_sinal), 0) INTO v_coberto
    FROM public.revisoes_cancelamento rev
    WHERE rev.reserva_id = p_reserva_id
      AND ((rev.decisao_final IS NOT NULL AND rev.decisao_final <> 'confirmar')
           OR (rev.decisao_final IS NULL AND rev.reserva_item_id IS NOT NULL));

    v_alvo := v_pago - v_coberto;
    IF v_alvo <= 0 THEN RETURN 0; END IF;

    UPDATE public.revisoes_cancelamento rev
    SET valor_sinal = v_alvo, motivo_decisao = p_motivo
    WHERE rev.reserva_id = p_reserva_id
      AND rev.reserva_item_id IS NULL AND rev.decisao_final IS NULL;

    IF NOT FOUND THEN
        INSERT INTO public.revisoes_cancelamento (reserva_id, empresa_id, valor_sinal, regra_aplicada, motivo_decisao)
        VALUES (p_reserva_id, v_empresa, v_alvo, p_regra, p_motivo)
        ON CONFLICT DO NOTHING;
    END IF;
    RETURN v_alvo;
END;
$$;

REVOKE ALL ON FUNCTION public.revisao_completar_fila(UUID, TEXT, TEXT) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.revisao_completar_fila(UUID, TEXT, TEXT) TO service_role;

-- ---------------------------------------------------------------- cancelar_reserva
CREATE OR REPLACE FUNCTION cancelar_reserva(
    p_reserva_id UUID,
    p_excecao TEXT DEFAULT NULL,   -- 'credito' | 'estorno' | 'perdido'
    p_motivo TEXT DEFAULT NULL
)
RETURNS TEXT
LANGUAGE plpgsql
SECURITY DEFINER SET search_path = ''
AS $$
DECLARE
    v_reserva RECORD;
    v_limite TIMESTAMP;
    v_regra TEXT;
    v_usuario UUID;
    v_pago DECIMAL(10,2);
BEGIN
    SELECT * INTO v_reserva FROM public.reservas WHERE id = p_reserva_id FOR UPDATE;
    IF NOT FOUND THEN RAISE EXCEPTION 'Reserva não encontrada'; END IF;

    IF auth.role() = 'authenticated' AND v_reserva.empresa_id IS DISTINCT FROM public.minha_empresa_id() THEN
        RAISE EXCEPTION 'Sem permissão para esta empresa';
    END IF;

    IF v_reserva.estado = 'pagamento_em_revisao' THEN
        RAISE EXCEPTION 'Reserva em revisão de pagamento — decida pela RPC resolver_revisao';
    END IF;

    IF p_excecao IS NOT NULL THEN
        IF p_excecao NOT IN ('credito', 'estorno', 'perdido') THEN
            RAISE EXCEPTION 'Exceção inválida: %', p_excecao;
        END IF;
        IF auth.role() = 'authenticated' THEN
            IF public.meu_perfil() <> 'admin' THEN
                RAISE EXCEPTION 'Exceção de cancelamento exige perfil admin';
            END IF;
            -- v3.4 (Ricardo A2): exceção mexe com dinheiro → MFA obrigatório
            IF COALESCE(auth.jwt() ->> 'aal', 'aal1') <> 'aal2' THEN
                RAISE EXCEPTION 'Exceção de cancelamento exige verificação em duas etapas (MFA)';
            END IF;
        END IF;
        IF p_motivo IS NULL OR length(trim(p_motivo)) = 0 THEN
            RAISE EXCEPTION 'Exceção de cancelamento exige motivo';
        END IF;
    END IF;

    -- Regra das 16h: até as 16:00 do dia anterior ao primeiro atendimento → crédito.
    -- v3.4: calculada no horário do ESTÚDIO, não no timezone da sessão (Ricardo #4)
    SELECT ((MIN(ri.inicio) AT TIME ZONE 'America/Sao_Paulo')::DATE - 1) + interval '16 hours' INTO v_limite
    FROM public.reserva_itens ri
    WHERE ri.reserva_id = p_reserva_id AND ri.estado NOT IN ('cancelado');

    v_regra := CASE WHEN (now() AT TIME ZONE 'America/Sao_Paulo') <= v_limite
                    THEN 'credito_automatico' ELSE 'perda_automatica' END;
    v_usuario := public.meu_usuario_id();  -- NULL sob service_role = "sistema"

    UPDATE public.reservas SET estado = 'cancelada'
    WHERE id = p_reserva_id AND estado IN ('pre_reserva', 'confirmada');
    IF NOT FOUND THEN RAISE EXCEPTION 'Reserva não pode ser cancelada no estado atual'; END IF;

    UPDATE public.reserva_itens SET estado = 'cancelado'
    WHERE reserva_id = p_reserva_id AND estado IN ('pendente', 'confirmado');

    UPDATE public.agenda_ocupacoes SET estado = 'cancelada'
    WHERE origem IN ('pre_reserva', 'reserva') AND origem_id = p_reserva_id AND estado = 'ativa';

    UPDATE public.cobrancas SET estado = 'cancelada'
    WHERE reserva_id = p_reserva_id AND estado = 'pendente';

    -- v3.4: revisão só quando há DINHEIRO em jogo, e pelo valor efetivamente pago
    SELECT COALESCE(SUM(t.valor), 0) INTO v_pago
    FROM public.cobrancas c
    JOIN public.transacoes t ON t.cobranca_id = c.id
    WHERE c.reserva_id = p_reserva_id
      AND t.finalidade IN ('sinal', 'saldo', 'pagamento_total')
      AND t.estado = 'pago';

    -- v3.4.1 (auditoria #1): desconta o que já está na fila por cancelamentos de
    -- itens — a fila nunca pode valer mais do que o dinheiro recebido.
    -- v3.4.1b: revisões decididas 'confirmar' NÃO descontam — o dinheiro voltou à reserva
    v_pago := v_pago - COALESCE((SELECT SUM(rev.valor_sinal) FROM public.revisoes_cancelamento rev
                                 WHERE rev.reserva_id = p_reserva_id
                                   AND rev.decisao_final IS DISTINCT FROM 'confirmar'), 0);

    IF v_pago > 0 THEN
        INSERT INTO public.revisoes_cancelamento
            (reserva_id, empresa_id, valor_sinal, regra_aplicada, decisao_final, decidido_por, motivo_decisao)
        VALUES
            (p_reserva_id, v_reserva.empresa_id, v_pago, v_regra, p_excecao, v_usuario, p_motivo)
        ON CONFLICT DO NOTHING;

        IF p_excecao IS NULL THEN
            PERFORM public.notificar_staff(v_reserva.empresa_id, 'revisao_cancelamento',
                'Cancelamento com R$ ' || trim(to_char(v_pago, '999990D00')) || ' pago — regra ' ||
                v_regra || '. Confirme a decisão na fila de revisões.');
        END IF;
    END IF;

    IF p_excecao IS NOT NULL THEN
        INSERT INTO public.log_acoes (empresa_id, tabela, registro_id, acao, usuario_id, perfil, motivo)
        VALUES (v_reserva.empresa_id, 'reservas', p_reserva_id, 'UPDATE', v_usuario,
                public.meu_perfil(), 'excecao_cancelamento=' || p_excecao || ': ' || p_motivo);
    END IF;

    RETURN v_regra;
END;
$$;

-- ------------------------------------------------ registrar_pagamento_presencial
-- v3.4.1:
--  - ordem de lock global (anti-deadlock): RESERVA → COBRANÇA → transação;
--  - pagar NÃO marca 'realizada' (auditoria #4) — atendimento realizado é uma
--    AÇÃO da profissional (finalizar_atendimento), nunca efeito de pagamento;
--  - pagamento em reserva EXPIRADA/CANCELADA não fica órfão: vira revisão de
--    pagamento_atrasado + alerta ao staff (auditoria #2), como no webhook;
--  - MFA: decisão de negócio — o caixa recebe dinheiro ENTRANDO várias vezes ao
--    dia (risco baixo, tudo auditado); aal2 fica só onde o dinheiro SAI ou muda
--    de destino (resolver_revisao, exceção de cancelamento).
CREATE OR REPLACE FUNCTION registrar_pagamento_presencial(
    p_cobranca_id UUID,
    p_valor DECIMAL,
    p_meio TEXT,
    p_finalidade TEXT,                  -- 'sinal' | 'saldo' | 'pagamento_total'
    p_idempotencia_key TEXT DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER SET search_path = ''
AS $$
DECLARE
    v_cobranca RECORD;
    v_reserva RECORD;
    v_transacao_id UUID;
    v_pago DECIMAL(10,2);
    v_pendente DECIMAL(10,2);
    v_status TEXT;
    v_existente UUID;
BEGIN
    IF auth.role() = 'authenticated' THEN
        IF public.meu_perfil() NOT IN ('admin', 'gestor', 'recepcao') THEN
            RAISE EXCEPTION 'Apenas admin, gestor ou receção registam pagamentos presenciais';
        END IF;
    END IF;

    IF p_meio NOT IN ('dinheiro', 'pix', 'cartao_debito', 'cartao_credito') THEN
        RAISE EXCEPTION 'Meio de pagamento inválido';
    END IF;
    IF p_finalidade NOT IN ('sinal', 'saldo', 'pagamento_total') THEN
        RAISE EXCEPTION 'Finalidade inválida';
    END IF;
    IF p_valor IS NULL OR p_valor <= 0 THEN
        RAISE EXCEPTION 'Valor deve ser positivo';
    END IF;

    -- Replay idempotente: a chave já existe → devolve a transação original
    IF p_idempotencia_key IS NOT NULL THEN
        SELECT id INTO v_existente FROM public.transacoes WHERE mp_idempotency_key = p_idempotencia_key;
        IF FOUND THEN
            RETURN jsonb_build_object('transacao_id', v_existente, 'idempotente', true);
        END IF;
    END IF;

    -- Leitura sem lock para achar a reserva...
    SELECT * INTO v_cobranca FROM public.cobrancas WHERE id = p_cobranca_id;
    IF NOT FOUND THEN RAISE EXCEPTION 'Cobrança não encontrada'; END IF;

    -- ...ordem de lock global: RESERVA primeiro, COBRANÇA depois
    SELECT * INTO v_reserva FROM public.reservas WHERE id = v_cobranca.reserva_id FOR UPDATE;
    SELECT * INTO v_cobranca FROM public.cobrancas WHERE id = p_cobranca_id FOR UPDATE;

    IF auth.role() = 'authenticated' AND v_cobranca.empresa_id IS DISTINCT FROM public.minha_empresa_id() THEN
        RAISE EXCEPTION 'Sem permissão para esta empresa';
    END IF;

    IF v_cobranca.estado IN ('total_pago', 'cancelada') THEN
        RAISE EXCEPTION 'Cobrança não está aberta (estado: %)', v_cobranca.estado;
    END IF;

    -- Valor nunca maior que o pendente (Ricardo A4)
    SELECT COALESCE(SUM(t.valor), 0) INTO v_pago
    FROM public.transacoes t
    WHERE t.cobranca_id = p_cobranca_id AND t.estado = 'pago'
      AND t.finalidade IN ('sinal', 'saldo', 'pagamento_total');
    v_pendente := (CASE WHEN p_finalidade = 'sinal' THEN v_cobranca.valor_sinal ELSE v_cobranca.valor_total END) - v_pago;
    IF p_valor > v_pendente THEN
        RAISE EXCEPTION 'Valor R$ % maior que o pendente (R$ %)', p_valor, v_pendente;
    END IF;

    INSERT INTO public.transacoes (cobranca_id, empresa_id, mp_idempotency_key, valor, meio, finalidade, estado)
    VALUES (p_cobranca_id, v_cobranca.empresa_id,
            COALESCE(p_idempotencia_key, 'presencial-' || gen_random_uuid()::text),
            p_valor, p_meio, p_finalidade, 'pago')
    RETURNING id INTO v_transacao_id;

    UPDATE public.cobrancas c
    SET estado = CASE
        WHEN p_finalidade = 'pagamento_total' THEN 'total_pago'
        WHEN (SELECT COALESCE(SUM(t.valor),0) FROM public.transacoes t
              WHERE t.cobranca_id = c.id AND t.estado = 'pago'
                AND t.finalidade IN ('sinal','saldo','pagamento_total')) >= c.valor_total THEN 'total_pago'
        WHEN p_finalidade = 'sinal' THEN 'sinal_pago'
        ELSE c.estado END
    WHERE c.id = p_cobranca_id;

    IF p_finalidade IN ('sinal', 'pagamento_total') AND v_reserva.estado = 'pre_reserva' THEN
        -- Sinal pago no balcão confirma a reserva no mesmo ato (atrasado → fila de revisão)
        v_status := public.confirmar_reserva(v_reserva.id);
    ELSIF v_reserva.estado IN ('expirada', 'cancelada') THEN
        -- v3.4.1 (auditoria #2): dinheiro em reserva morta NUNCA fica órfão
        IF v_reserva.estado = 'expirada' THEN
            UPDATE public.reservas SET estado = 'pagamento_em_revisao' WHERE id = v_reserva.id;
            v_status := 'pagamento_em_revisao';
        ELSE
            v_status := v_reserva.estado;  -- cancelada é terminal; o dinheiro vai à fila mesmo assim
        END IF;

        -- v3.4.1b: a fila é completada até ao pago total (nunca engolida, nunca em dobro)
        PERFORM public.revisao_completar_fila(v_reserva.id, 'pagamento_atrasado',
            'Pagamento presencial registado com a reserva ' || v_reserva.estado || ' — confirmar (se couber), estornar ou dar crédito');

        PERFORM public.notificar_staff(v_reserva.empresa_id, 'pagamento_em_revisao',
            'Pagamento no balcão de R$ ' || trim(to_char(p_valor, '999990D00')) ||
            ' em reserva ' || v_reserva.estado || ' (' || v_reserva.id::text || '). Decida na fila de revisões.');
    ELSIF v_reserva.estado = 'pagamento_em_revisao' THEN
        -- v3.4.1b: dinheiro novo em revisão também ENTRA na fila (antes só notificava)
        PERFORM public.revisao_completar_fila(v_reserva.id, 'pagamento_atrasado',
            'Novo pagamento presencial com a reserva em revisão — fila completada');
        PERFORM public.notificar_staff(v_reserva.empresa_id, 'pagamento_em_revisao',
            'Novo pagamento no balcão (R$ ' || trim(to_char(p_valor, '999990D00')) ||
            ') em reserva já em revisão: ' || v_reserva.id::text);
        v_status := 'pagamento_em_revisao';
    ELSE
        -- confirmada/realizada: saldo registado; o ESTADO do atendimento não muda
        -- por pagamento — 'realizada' é só pela RPC finalizar_atendimento
        v_status := v_reserva.estado;
    END IF;

    RETURN jsonb_build_object(
        'transacao_id', v_transacao_id,
        'idempotente', false,
        'cobranca_id', p_cobranca_id,
        'valor', p_valor,
        'reserva_id', v_reserva.id,
        'reserva_status', v_status);
END;
$$;

-- --------------------------------------------------------- finalizar_atendimento
-- v3.4.1 (auditoria #4): 'realizada' passa a ser uma AÇÃO da profissional/equipe
-- ("atendi esta cliente"), nunca consequência de pagamento.
CREATE OR REPLACE FUNCTION finalizar_atendimento(p_reserva_id UUID)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER SET search_path = ''
AS $$
DECLARE
    v_reserva RECORD;
BEGIN
    SELECT * INTO v_reserva FROM public.reservas WHERE id = p_reserva_id FOR UPDATE;
    IF NOT FOUND THEN RAISE EXCEPTION 'Reserva não encontrada'; END IF;

    IF auth.role() = 'authenticated' THEN
        IF v_reserva.empresa_id IS DISTINCT FROM public.minha_empresa_id()
           OR public.meu_perfil() NOT IN ('admin', 'gestor', 'recepcao', 'profissional') THEN
            RAISE EXCEPTION 'Apenas a equipe finaliza atendimentos';
        END IF;
    END IF;

    IF v_reserva.estado <> 'confirmada' THEN
        RAISE EXCEPTION 'Só se finaliza reserva confirmada (estado: %)', v_reserva.estado;
    END IF;

    UPDATE public.reservas SET estado = 'realizada' WHERE id = p_reserva_id;
    UPDATE public.reserva_itens SET estado = 'realizado'
    WHERE reserva_id = p_reserva_id AND estado = 'confirmado';
END;
$$;

-- ---------------------------------------------------------- cancelar_pre_reserva
-- Desistência SEM pagamento: nunca gera revisão
CREATE OR REPLACE FUNCTION cancelar_pre_reserva(p_reserva_id UUID)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER SET search_path = ''
AS $$
DECLARE
    v_reserva RECORD;
BEGIN
    SELECT * INTO v_reserva FROM public.reservas WHERE id = p_reserva_id FOR UPDATE;
    IF NOT FOUND THEN RAISE EXCEPTION 'Reserva não encontrada'; END IF;

    IF auth.role() = 'authenticated' AND v_reserva.empresa_id IS DISTINCT FROM public.minha_empresa_id() THEN
        RAISE EXCEPTION 'Sem permissão para esta empresa';
    END IF;

    -- v3.4.1: 'expirada' também limpa por aqui (era um estado sem saída)
    IF v_reserva.estado NOT IN ('pre_reserva', 'expirada') THEN
        RAISE EXCEPTION 'Reserva não é uma pré-reserva (estado: %)', v_reserva.estado;
    END IF;

    UPDATE public.agenda_ocupacoes SET estado = 'cancelada'
    WHERE origem = 'pre_reserva' AND origem_id = p_reserva_id AND estado = 'ativa';
    UPDATE public.reserva_itens SET estado = 'cancelado'
    WHERE reserva_id = p_reserva_id AND estado = 'pendente';
    UPDATE public.cobrancas SET estado = 'cancelada'
    WHERE reserva_id = p_reserva_id AND estado = 'pendente';
    UPDATE public.reservas SET estado = 'cancelada' WHERE id = p_reserva_id;
END;
$$;

-- ---------------------------------------------------------- revisar_anamnese (v3.3)
CREATE OR REPLACE FUNCTION revisar_anamnese(
    p_anamnese_id UUID,
    p_estado TEXT                -- 'liberada' | 'requer_avaliacao'
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER SET search_path = ''
AS $$
BEGIN
    IF p_estado NOT IN ('liberada', 'requer_avaliacao') THEN
        RAISE EXCEPTION 'Estado de revisão inválido';
    END IF;

    IF NOT EXISTS (
        SELECT 1 FROM public.anamneses a
        WHERE a.id = p_anamnese_id
          AND a.empresa_id = public.minha_empresa_id()
          AND (public.meu_perfil() = 'admin' OR a.profissional_revisora_id = public.meu_profissional_id())
    ) THEN
        RAISE EXCEPTION 'Anamnese não encontrada ou sem permissão de revisão';
    END IF;

    UPDATE public.anamneses
    SET estado = p_estado,
        profissional_revisora_id = COALESCE(profissional_revisora_id, public.meu_profissional_id()),
        data_revisao = now()
    WHERE id = p_anamnese_id;
END;
$$;

-- ------------------------------------------------------ regenerar_token_anamnese
CREATE OR REPLACE FUNCTION regenerar_token_anamnese(p_anamnese_id UUID)
RETURNS TEXT
LANGUAGE plpgsql
SECURITY DEFINER SET search_path = ''
AS $$
DECLARE
    v_token TEXT;
    v_anamnese RECORD;
    v_inicio TIMESTAMPTZ;
BEGIN
    SELECT * INTO v_anamnese FROM public.anamneses WHERE id = p_anamnese_id;
    IF NOT FOUND THEN RAISE EXCEPTION 'Anamnese não encontrada'; END IF;

    IF auth.role() = 'authenticated' THEN
        -- v3.4 (Carlos #3): exige perfil de equipe EXISTENTE, não só tenant correto
        IF v_anamnese.empresa_id IS DISTINCT FROM public.minha_empresa_id()
           OR public.meu_perfil() NOT IN ('admin', 'gestor', 'recepcao') THEN
            RAISE EXCEPTION 'Apenas a equipe pode regenerar tokens de anamnese';
        END IF;
    END IF;

    -- Invalida tokens anteriores (o índice parcial garante ≤1 ativo por ficha)
    UPDATE public.anamnese_tokens
    SET usado = true, usado_em = now()
    WHERE anamnese_id = p_anamnese_id AND usado = false;

    -- v3.4 (Carlos #2): o link nunca vive além do próprio agendamento
    SELECT ri.inicio INTO v_inicio
    FROM public.reserva_itens ri
    WHERE ri.id = v_anamnese.reserva_item_id AND ri.estado NOT IN ('cancelado');

    v_token := public.gerar_token_opaco();

    INSERT INTO public.anamnese_tokens (empresa_id, token_hash, anamnese_id, cliente_id, reserva_id, expira_em)
    SELECT v_anamnese.empresa_id, public.sha256_hex(v_token), p_anamnese_id,
           v_anamnese.cliente_id, ri.reserva_id,
           LEAST(ri.inicio, now() + interval '24 hours')
    FROM public.reserva_itens ri
    WHERE ri.id = v_anamnese.reserva_item_id;

    -- Ficha avulsa (sem item): 24h padrão
    IF NOT FOUND THEN
        INSERT INTO public.anamnese_tokens (empresa_id, token_hash, anamnese_id, cliente_id, expira_em)
        VALUES (v_anamnese.empresa_id, public.sha256_hex(v_token), p_anamnese_id,
                v_anamnese.cliente_id, now() + interval '24 hours');
    END IF;

    RETURN v_token;
END;
$$;

-- ----------------------------------------------------------- expirar_pre_reservas
-- v3.4: SKIP LOCKED (Ricardo A1) + estado próprio 'expirada'
-- v3.4.1 (auditoria: "parcial vencido prendendo o horário"): nenhuma pré-reserva
-- vencida fica PRESa — o destino depende do dinheiro que entrou:
--   ZERO pagamento   → 'expirada' (slot livre, fim);
--   PARCIAL ou TOTAL → 'pagamento_em_revisao' + revisão + alerta (slot livre TAMBÉM;
--                      o dinheiro espera decisão humana — confirmar/estorno/crédito/perdido).
CREATE OR REPLACE FUNCTION expirar_pre_reservas(p_limite INT DEFAULT 200)
RETURNS INT
LANGUAGE plpgsql
SECURITY DEFINER SET search_path = ''
AS $$
DECLARE
    v_r RECORD;
    v_count INT := 0;
    v_pago DECIMAL(10,2);
BEGIN
    FOR v_r IN
        SELECT r.id, r.empresa_id
        FROM public.reservas r
        WHERE r.estado = 'pre_reserva'
          AND EXISTS (
              SELECT 1 FROM public.agenda_ocupacoes o
              WHERE o.origem = 'pre_reserva' AND o.origem_id = r.id
                AND o.estado = 'ativa' AND o.expires_at < now()
          )
        ORDER BY r.id
        LIMIT p_limite
        FOR UPDATE OF r SKIP LOCKED   -- confirmar/webhook com a linha? o cron NÃO espera
    LOOP
        SELECT COALESCE(SUM(t.valor), 0) INTO v_pago
        FROM public.cobrancas c
        JOIN public.transacoes t ON t.cobranca_id = c.id
        WHERE c.reserva_id = v_r.id
          AND t.finalidade IN ('sinal', 'saldo', 'pagamento_total')
          AND t.estado = 'pago';

        -- Em ambos os ramos o slot é LIBERTADO
        UPDATE public.agenda_ocupacoes SET estado = 'expirada'
        WHERE origem = 'pre_reserva' AND origem_id = v_r.id AND estado = 'ativa';

        IF v_pago > 0 THEN
            UPDATE public.reservas SET estado = 'pagamento_em_revisao' WHERE id = v_r.id;
            -- itens ficam 'pendente': resolver_revisao('confirmar') pode reagendar

            -- v3.4.1b: fila completada pelo helper (idempotente, nunca em dobro)
            PERFORM public.revisao_completar_fila(v_r.id, 'pagamento_atrasado',
                'Pré-reserva vencida com pagamento registado — confirmar (se couber), estornar, dar crédito ou marcar perdido');

            PERFORM public.notificar_staff(v_r.empresa_id, 'pagamento_em_revisao',
                'Pré-reserva ' || v_r.id::text || ' venceu com R$ ' ||
                trim(to_char(v_pago, '999990D00')) || ' pago. O horário foi libertado. Decida na fila de revisões.');
        ELSE
            UPDATE public.reservas SET estado = 'expirada' WHERE id = v_r.id;
            -- v3.4.1b: itens ficam 'pendente' também aqui (o ramo com pagamento já fazia).
            -- Assim 'cancelado' significa SEMPRE "alguém cancelou de propósito" e o
            -- resolver_revisao('confirmar') pode reviver só 'pendente' sem ressuscitar
            -- itens que a cliente recusou.
        END IF;

        -- A cobrança fica 'pendente' DE PROPÓSITO: se o PIX atrasado cair, o
        -- webhook usa-a e a reserva segue para 'pagamento_em_revisao' (010).
        v_count := v_count + 1;
    END LOOP;
    RETURN v_count;
END;
$$;

-- =====================================================================
-- EXECUTE explícito — fim do PUBLIC por defeito
-- =====================================================================
REVOKE ALL ON FUNCTION public.criar_pre_reserva(UUID, UUID, JSONB, TEXT) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.criar_pre_reserva(UUID, UUID, JSONB, TEXT) TO authenticated, service_role;

REVOKE ALL ON FUNCTION public.cancelar_item_reserva(UUID, TEXT, TEXT) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.cancelar_item_reserva(UUID, TEXT, TEXT) TO authenticated, service_role;

REVOKE ALL ON FUNCTION public.confirmar_reserva(UUID) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.confirmar_reserva(UUID) TO authenticated, service_role;

REVOKE ALL ON FUNCTION public.cancelar_reserva(UUID, TEXT, TEXT) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.cancelar_reserva(UUID, TEXT, TEXT) TO authenticated, service_role;

REVOKE ALL ON FUNCTION public.registrar_pagamento_presencial(UUID, DECIMAL, TEXT, TEXT, TEXT) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.registrar_pagamento_presencial(UUID, DECIMAL, TEXT, TEXT, TEXT) TO authenticated, service_role;

REVOKE ALL ON FUNCTION public.cancelar_pre_reserva(UUID) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.cancelar_pre_reserva(UUID) TO authenticated, service_role;

REVOKE ALL ON FUNCTION public.finalizar_atendimento(UUID) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.finalizar_atendimento(UUID) TO authenticated, service_role;

REVOKE ALL ON FUNCTION public.revisar_anamnese(UUID, TEXT) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.revisar_anamnese(UUID, TEXT) TO authenticated, service_role;

REVOKE ALL ON FUNCTION public.regenerar_token_anamnese(UUID) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.regenerar_token_anamnese(UUID) TO authenticated, service_role;

REVOKE ALL ON FUNCTION public.expirar_pre_reservas(INT) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.expirar_pre_reservas(INT) TO service_role;
