-- review_flow_test.sql (v3.4 NOVO) — resolver_revisao: a fila de revisões tem SAÍDA.
-- Cobre os dois impeditivos comuns às auditorias:
--   (1) pagamento atrasado já não sequestra o slot E tem destino (confirmar/estorno/crédito/perdido);
--   (2) 'confirmar' re-verifica a disponibilidade antes de recriar as ocupações.
SET TIME ZONE 'America/Sao_Paulo';

CREATE OR REPLACE FUNCTION teste_proximo_dia(dow INT, hora TEXT) RETURNS TIMESTAMPTZ
LANGUAGE sql STABLE AS $$
    SELECT ((CURRENT_DATE + ((dow - EXTRACT(DOW FROM CURRENT_DATE)::INT + 7) % 7 + 7))::TEXT || ' ' || hora)::TIMESTAMPTZ
$$;

-- Helper: cria reserva paga ATRASADA (em pagamento_em_revisao) e devolve a revisão
CREATE OR REPLACE FUNCTION teste_cria_revisao_atrasada(dow INT, hora TEXT, chave TEXT, valor NUMERIC)
RETURNS UUID
LANGUAGE plpgsql VOLATILE AS $$
DECLARE v_r UUID; v_cob UUID; v_rev UUID;
BEGIN
    v_r := teste_cria_reserva(dow, hora, chave);
    SELECT id INTO v_cob FROM cobrancas WHERE reserva_id = v_r;
    UPDATE agenda_ocupacoes SET expires_at = now() - interval '1 minute'
    WHERE origem = 'pre_reserva' AND origem_id = v_r;
    PERFORM public.processar_pagamento_webhook('mercado_pago', 'evt-' || chave, valor,
        NULL, v_cob, 'mp-' || chave, '{}'::JSONB, true);
    SELECT id INTO v_rev FROM revisoes_cancelamento WHERE reserva_id = v_r AND decisao_final IS NULL;
    RETURN v_rev;
END $$;

-- R1: confirmar com slot LIVRE → reagenda de verdade (ocupações recriadas sem expiração)
DO $$
DECLARE v_rev UUID; v_res JSONB; v_r UUID;
BEGIN
    v_rev := teste_cria_revisao_atrasada(5, '09:00', 'rev-r1', 30.00);
    SELECT reserva_id INTO v_r FROM revisoes_cancelamento WHERE id = v_rev;

    v_res := public.resolver_revisao(v_rev, 'confirmar', 'Cliente avisou que o PIX ia atrasar');

    ASSERT v_res->>'reserva_status' = 'confirmada', format('R1: status %s', v_res->>'reserva_status');
    ASSERT (SELECT estado FROM reservas WHERE id = v_r) = 'confirmada';
    ASSERT (SELECT COUNT(*) FROM agenda_ocupacoes
            WHERE origem = 'reserva' AND origem_id = v_r AND estado = 'ativa' AND expires_at IS NULL) = 2,
        'R1: ocupações (profissional+recurso) deviam estar recriadas';
    ASSERT (SELECT estado FROM reserva_itens WHERE reserva_id = v_r) = 'confirmado';
    ASSERT (SELECT estado FROM cobrancas WHERE reserva_id = v_r) = 'sinal_pago';
    ASSERT (SELECT decisao_final FROM revisoes_cancelamento WHERE id = v_rev) = 'confirmar';
    RAISE NOTICE 'R1 OK — confirmar: reserva reagendada, ocupações vivas, cobrança sinal_pago';
END $$;

-- R2: segunda decisão na MESMA revisão → erro (decisões são finais)
DO $$
DECLARE v_rev UUID;
BEGIN
    SELECT id INTO v_rev FROM revisoes_cancelamento WHERE decisao_final = 'confirmar' LIMIT 1;
    BEGIN
        PERFORM public.resolver_revisao(v_rev, 'estorno', 'tentativa dupla');
        RAISE EXCEPTION 'R2 FALHOU: revisão decidida duas vezes';
    EXCEPTION WHEN OTHERS THEN
        ASSERT SQLERRM LIKE '%já decidida%', format('R2 erro inesperado: %s', SQLERRM);
        RAISE NOTICE 'R2 OK — revisão decidida é imutável';
    END;
END $$;

-- R3: confirmar com slot OCUPADO → erro claro; depois crédito → conta + lançamento
DO $$
DECLARE v_rev UUID; v_res JSONB; v_r UUID; v_saldo DECIMAL; v_key TEXT;
BEGIN
    v_rev := teste_cria_revisao_atrasada(2, '09:00', 'rev-r3', 30.00);
    SELECT reserva_id INTO v_r FROM revisoes_cancelamento WHERE id = v_rev;

    -- outro cliente fica com o horário libertado
    PERFORM teste_cria_reserva(2, '09:00', 'rev-r3-concorrente');

    BEGIN
        PERFORM public.resolver_revisao(v_rev, 'confirmar', 'tenta reagendar');
        RAISE EXCEPTION 'R3 FALHOU: confirmou em cima de outro agendamento';
    EXCEPTION WHEN OTHERS THEN
        ASSERT SQLERRM LIKE '%ocupado%', format('R3 erro inesperado: %s', SQLERRM);
        RAISE NOTICE 'R3a OK — confirmar bloqueado: %', SQLERRM;
    END;

    v_res := public.resolver_revisao(v_rev, 'credito', 'Cliente escolheu crédito para remarcar');
    ASSERT v_res->>'reserva_status' = 'cancelada', format('R3: status %s', v_res->>'reserva_status');
    SELECT saldo_apos, idempotencia_key INTO v_saldo, v_key
    FROM lancamentos_creditos l
    JOIN contas_creditos c ON c.id = l.conta_id
    WHERE l.origem_id = v_r AND l.tipo_lancamento = 'credito_cancelamento';
    ASSERT v_saldo = 30.00, format('R3: saldo devia ser 30.00, veio %s', v_saldo);
    ASSERT v_key = 'revisao-' || v_rev::TEXT, format('R3: chave de idempotência %s', v_key);
    ASSERT (SELECT estado FROM cobrancas WHERE reserva_id = v_r) = 'cancelada';
    RAISE NOTICE 'R3b OK — crédito de R$ % na conta da cliente (idempotente: %)', v_saldo, v_key;
END $$;

-- R4: revisão de CANCELAMENTO (regra 16h) → estorno: transação estornada + job na fila
DO $$
DECLARE v_r UUID; v_rev UUID; v_res JSONB;
BEGIN
    v_r := teste_cria_reserva(3, '10:00', 'rev-r4');
    PERFORM teste_paga_sinal(v_r, 'sinal', 30.00);
    PERFORM public.confirmar_reserva(v_r);
    PERFORM public.cancelar_reserva(v_r);   -- daqui a 7+ dias → credito_automatico
    SELECT id INTO v_rev FROM revisoes_cancelamento WHERE reserva_id = v_r AND decisao_final IS NULL;
    ASSERT v_rev IS NOT NULL, 'R4: cancelamento com dinheiro devia abrir revisão';

    v_res := public.resolver_revisao(v_rev, 'estorno', 'Cliente pediu o dinheiro de volta');
    ASSERT (SELECT decisao_final FROM revisoes_cancelamento WHERE id = v_rev) = 'estorno';
    ASSERT EXISTS (SELECT 1 FROM transacoes t JOIN cobrancas c ON c.id = t.cobranca_id
                   WHERE c.reserva_id = v_r AND t.estado = 'estornado'),
        'R4: transação devia estar estornada';
    ASSERT EXISTS (SELECT 1 FROM jobs WHERE tipo = 'estorno_mercado_pago'
                   AND payload->>'reserva_id' = v_r::TEXT),
        'R4: job de estorno para a Edge Function devia estar na fila';
    RAISE NOTICE 'R4 OK — estorno: transação marcada + reembolso real enfileirado para a Edge';
END $$;

-- R5: perdido (o estúdio fica com o sinal) → reserva cancelada, cobrança cancelada
DO $$
DECLARE v_rev UUID; v_res JSONB; v_r UUID;
BEGIN
    v_rev := teste_cria_revisao_atrasada(4, '15:00', 'rev-r5', 30.00);
    SELECT reserva_id INTO v_r FROM revisoes_cancelamento WHERE id = v_rev;
    v_res := public.resolver_revisao(v_rev, 'perdido', 'Cliente não apareceu e não respondeu');
    ASSERT v_res->>'reserva_status' = 'cancelada';
    ASSERT (SELECT estado FROM cobrancas WHERE reserva_id = v_r) = 'cancelada',
        'R5: cobrança fechada como cancelada (reserva perdida/cancelada)';
    RAISE NOTICE 'R5 OK — perdido: cobrança cancelada, reserva encerrada';
END $$;

-- R6: decisão financeira exige MFA (aal2) para staff autenticado
DO $$
DECLARE v_rev UUID;
BEGIN
    v_rev := teste_cria_revisao_atrasada(6, '09:00', 'rev-r6', 30.00);
    PERFORM set_config('app.rev.r6', v_rev::TEXT, false);
END $$;

-- aal1 → bloqueado
SET ROLE authenticated;
SELECT set_config('request.jwt.claims', '{"sub":"ffffffff-0000-0000-0000-000000000001","role":"authenticated","aal":"aal1"}', false);
DO $$
BEGIN
    BEGIN
        PERFORM public.resolver_revisao(current_setting('app.rev.r6')::UUID, 'perdido', 'sem mfa');
        RAISE EXCEPTION 'R6 FALHOU: decisão financeira sem MFA';
    EXCEPTION WHEN OTHERS THEN
        ASSERT SQLERRM LIKE '%duas etapas%' OR SQLERRM LIKE '%MFA%', format('R6 erro inesperado: %s', SQLERRM);
        RAISE NOTICE 'R6a OK — aal1 bloqueado: %', SQLERRM;
    END;
END $$;
RESET ROLE;

-- aal2 → decide
SET ROLE authenticated;
SELECT set_config('request.jwt.claims', '{"sub":"ffffffff-0000-0000-0000-000000000001","role":"authenticated","aal":"aal2"}', false);
DO $$
DECLARE v_res JSONB;
BEGIN
    v_res := public.resolver_revisao(current_setting('app.rev.r6')::UUID, 'perdido', 'com mfa');
    ASSERT v_res->>'decisao' = 'perdido';
    ASSERT EXISTS (SELECT 1 FROM log_acoes WHERE tabela = 'revisoes_cancelamento'
                   AND registro_id = current_setting('app.rev.r6')::UUID),
        'R6: decisão devia estar auditada em log_acoes';
    RAISE NOTICE 'R6b OK — aal2 decide e fica auditado';
END $$;
RESET ROLE;

-- R7: recepção NÃO resolve revisão (só admin/gestor) — fixture criada como sistema
DO $$
DECLARE v_rev UUID;
BEGIN
    v_rev := teste_cria_revisao_atrasada(2, '15:00', 'rev-r7', 30.00);
    PERFORM set_config('app.rev.r7', v_rev::TEXT, false);
END $$;

SET ROLE authenticated;
SELECT set_config('request.jwt.claims', '{"sub":"ffffffff-0000-0000-0000-000000000002","role":"authenticated","aal":"aal2"}', false);
DO $$
BEGIN
    BEGIN
        PERFORM public.resolver_revisao(current_setting('app.rev.r7')::UUID, 'perdido', 'receção a tentar');
        RAISE EXCEPTION 'R7 FALHOU: receção resolveu revisão';
    EXCEPTION WHEN OTHERS THEN
        ASSERT SQLERRM LIKE '%admin/gestor%', format('R7 erro inesperado: %s', SQLERRM);
        RAISE NOTICE 'R7 OK — receção bloqueada: %', SQLERRM;
    END;
END $$;
RESET ROLE;
