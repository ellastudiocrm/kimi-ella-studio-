-- webhook_flow_test.sql (v3.4 NOVO) — a RPC atômica processar_pagamento_webhook
-- Impeditivo comum às duas auditorias: a corrida webhook×cron e a fila sem saída
-- resolvem-se AQUI. Corre como superuser (a RPC é só-service_role; no Supabase
-- quem chama é a Edge Function do Mercado Pago).
SET TIME ZONE 'America/Sao_Paulo';

CREATE OR REPLACE FUNCTION teste_proximo_dia(dow INT, hora TEXT) RETURNS TIMESTAMPTZ
LANGUAGE sql STABLE AS $$
    SELECT ((CURRENT_DATE + ((dow - EXTRACT(DOW FROM CURRENT_DATE)::INT + 7) % 7 + 7))::TEXT || ' ' || hora)::TIMESTAMPTZ
$$;

-- W1: webhook no prazo → confirma TUDO na mesma transação
DO $$
DECLARE v_r UUID; v_cob UUID; v_res JSONB;
BEGIN
    v_r := teste_cria_reserva(5, '10:00', 'wh-1');
    SELECT id INTO v_cob FROM cobrancas WHERE reserva_id = v_r;

    v_res := public.processar_pagamento_webhook('mercado_pago', 'evt-w1', 30.00,
        NULL, v_cob, 'mp-tx-w1', '{"type":"payment"}'::JSONB, true);

    ASSERT v_res->>'status' = 'confirmada', format('W1: status %s', v_res->>'status');
    ASSERT (SELECT estado FROM reservas WHERE id = v_r) = 'confirmada';
    ASSERT (SELECT estado FROM cobrancas WHERE id = v_cob) = 'sinal_pago';
    ASSERT EXISTS (SELECT 1 FROM agenda_ocupacoes
        WHERE origem = 'reserva' AND origem_id = v_r AND estado = 'ativa' AND expires_at IS NULL);
    ASSERT (SELECT processado FROM webhook_inbox WHERE external_event_id = 'evt-w1') = true;
    ASSERT EXISTS (SELECT 1 FROM eventos_pagamento WHERE mp_event_id = 'evt-w1' AND processado = true);
    PERFORM set_config('app.wh.reserva', v_r::TEXT, false);
    PERFORM set_config('app.wh.cobranca', v_cob::TEXT, false);
    RAISE NOTICE 'W1 OK — webhook confirmou atomicamente (reserva + itens + ocupações + cobrança + inbox)';
END $$;

-- W2: MESMO evento reenviado pelo provedor → 'duplicado', sem segunda transação
DO $$
DECLARE v_res JSONB; v_n INT;
BEGIN
    v_res := public.processar_pagamento_webhook('mercado_pago', 'evt-w1', 30.00,
        NULL, current_setting('app.wh.cobranca')::UUID, 'mp-tx-w1', '{}'::JSONB, true);
    ASSERT v_res->>'status' = 'duplicado', format('W2: status %s', v_res->>'status');
    SELECT COUNT(*) INTO v_n FROM transacoes t
    WHERE t.cobranca_id = current_setting('app.wh.cobranca')::UUID AND t.estado = 'pago';
    ASSERT v_n = 1, format('W2 REGRESSÃO: evento duplicado criou %s transações', v_n);
    RAISE NOTICE 'W2 OK — idempotência por (origem, external_event_id): replay inócuo';
END $$;

-- W3: webhook ATRASADO (ocupações vencidas) → pagamento_em_revisao, slot livre
DO $$
DECLARE v_r UUID; v_cob UUID; v_res JSONB;
BEGIN
    v_r := teste_cria_reserva(5, '11:00', 'wh-3');
    SELECT id INTO v_cob FROM cobrancas WHERE reserva_id = v_r;
    UPDATE agenda_ocupacoes SET expires_at = now() - interval '1 minute'
    WHERE origem = 'pre_reserva' AND origem_id = v_r;

    v_res := public.processar_pagamento_webhook('mercado_pago', 'evt-w3', 30.00,
        NULL, v_cob, 'mp-tx-w3', '{}'::JSONB, true);

    ASSERT v_res->>'status' = 'pagamento_em_revisao', format('W3: status %s', v_res->>'status');
    ASSERT (SELECT estado FROM reservas WHERE id = v_r) = 'pagamento_em_revisao';
    ASSERT EXISTS (SELECT 1 FROM revisoes_cancelamento
        WHERE reserva_id = v_r AND regra_aplicada = 'pagamento_atrasado' AND decisao_final IS NULL);
    ASSERT NOT EXISTS (SELECT 1 FROM agenda_ocupacoes WHERE origem_id = v_r AND estado = 'ativa');
    -- slot libertado de verdade:
    PERFORM teste_cria_reserva(5, '11:00', 'wh-3b');
    RAISE NOTICE 'W3 OK — atrasado: dinheiro na fila, slot libertado, horário re-agendável';
END $$;

-- W4: cron expirou PRIMEIRO, webhook chegou DEPOIS → revisão, nunca confirma
DO $$
DECLARE v_r UUID; v_cob UUID; v_res JSONB;
BEGIN
    v_r := teste_cria_reserva(5, '14:00', 'wh-4');
    SELECT id INTO v_cob FROM cobrancas WHERE reserva_id = v_r;
    UPDATE agenda_ocupacoes SET expires_at = now() - interval '1 minute'
    WHERE origem = 'pre_reserva' AND origem_id = v_r;
    PERFORM public.expirar_pre_reservas();
    ASSERT (SELECT estado FROM reservas WHERE id = v_r) = 'expirada';

    v_res := public.processar_pagamento_webhook('mercado_pago', 'evt-w4', 30.00,
        NULL, v_cob, 'mp-tx-w4', '{}'::JSONB, true);

    ASSERT v_res->>'status' = 'pagamento_em_revisao', format('W4: status %s', v_res->>'status');
    ASSERT (SELECT estado FROM reservas WHERE id = v_r) = 'pagamento_em_revisao',
        'W4 REGRESSÃO: webhook confirmou reserva já expirada pelo cron';
    ASSERT EXISTS (SELECT 1 FROM revisoes_cancelamento WHERE reserva_id = v_r);
    RAISE NOTICE 'W4 OK — ordem cron→webhook: dinheiro vai para a fila (nunca confirma expirada)';
END $$;

-- W5: assinatura inválida → RAISE com rollback TOTAL (inbox incluída); retry válido funciona
DO $$
DECLARE v_r UUID; v_cob UUID; v_res JSONB; v_inbox INT;
BEGIN
    v_r := teste_cria_reserva(6, '12:00', 'wh-5');
    SELECT id INTO v_cob FROM cobrancas WHERE reserva_id = v_r;

    BEGIN
        PERFORM public.processar_pagamento_webhook('mercado_pago', 'evt-w5', 100.00,
            NULL, v_cob, 'mp-tx-w5', '{}'::JSONB, false);  -- assinatura NÃO verificada
        RAISE EXCEPTION 'W5 FALHOU: webhook sem assinatura processado';
    EXCEPTION WHEN OTHERS THEN
        ASSERT SQLERRM LIKE '%assinatura%' OR SQLERRM LIKE '%Assinatura%', format('W5 erro inesperado: %s', SQLERRM);
    END;

    SELECT COUNT(*) INTO v_inbox FROM webhook_inbox WHERE external_event_id = 'evt-w5';
    ASSERT v_inbox = 0, format('W5 REGRESSÃO: rejeitado ficou na inbox (%s linhas) — retry seria ignorado', v_inbox);

    v_res := public.processar_pagamento_webhook('mercado_pago', 'evt-w5', 100.00,
        NULL, v_cob, 'mp-tx-w5', '{}'::JSONB, true);
    ASSERT v_res->>'status' = 'confirmada', format('W5 retry: status %s', v_res->>'status');
    RAISE NOTICE 'W5 OK — assinatura inválida: rollback total; reenvio assinado confirma';
END $$;

-- W6: fluxo com TRANSAÇÃO PENDENTE (PIX gerado pela Edge) → webhook liquida a pendente
DO $$
DECLARE v_r UUID; v_cob UUID; v_tx UUID; v_res JSONB;
BEGIN
    v_r := teste_cria_reserva(5, '15:00', 'wh-6');
    SELECT id INTO v_cob FROM cobrancas WHERE reserva_id = v_r;
    INSERT INTO transacoes (cobranca_id, empresa_id, mp_idempotency_key, valor, meio, finalidade, estado)
    VALUES (v_cob, '00000000-0000-0000-0000-000000000001', 'w6-pending', 30.00, 'pix', 'sinal', 'pendente')
    RETURNING id INTO v_tx;

    v_res := public.processar_pagamento_webhook('mercado_pago', 'evt-w6', 30.00,
        v_tx, NULL, 'mp-tx-w6', '{}'::JSONB, true);

    ASSERT v_res->>'status' = 'confirmada', format('W6: status %s', v_res->>'status');
    ASSERT (SELECT estado FROM transacoes WHERE id = v_tx) = 'pago';
    ASSERT (SELECT mp_transaction_id FROM transacoes WHERE id = v_tx) = 'mp-tx-w6';

    -- evento NOVO para a MESMA transação já paga → ja_processado
    v_res := public.processar_pagamento_webhook('mercado_pago', 'evt-w6b', 30.00,
        v_tx, NULL, 'mp-tx-w6', '{}'::JSONB, true);
    ASSERT v_res->>'status' = 'ja_processado', format('W6 replay: status %s', v_res->>'status');
    RAISE NOTICE 'W6 OK — pendente liquidada pelo webhook; reenvio por outro evento = ja_processado';
END $$;

-- W7: segundo webhook (saldo) em reserva confirmada → saldo_registrado + total_pago
DO $$
DECLARE v_res JSONB;
BEGIN
    v_res := public.processar_pagamento_webhook('mercado_pago', 'evt-w7', 70.00,
        NULL, current_setting('app.wh.cobranca')::UUID, 'mp-tx-w7', '{}'::JSONB, true);
    ASSERT v_res->>'status' = 'saldo_registrado', format('W7: status %s', v_res->>'status');
    ASSERT (SELECT estado FROM cobrancas WHERE id = current_setting('app.wh.cobranca')::UUID) = 'total_pago';
    RAISE NOTICE 'W7 OK — saldo via webhook fecha a cobrança (total_pago)';
END $$;

-- W8: pagamento parcial NO PRAZO → registra e aguarda o restante (não confirma, não revisa)
DO $$
DECLARE v_r UUID; v_cob UUID; v_res JSONB;
BEGIN
    v_r := teste_cria_reserva(4, '09:00', 'wh-8');
    SELECT id INTO v_cob FROM cobrancas WHERE reserva_id = v_r;
    v_res := public.processar_pagamento_webhook('mercado_pago', 'evt-w8', 10.00,
        NULL, v_cob, 'mp-tx-w8', '{}'::JSONB, true);
    ASSERT v_res->>'status' = 'parcial_registrado', format('W8: status %s', v_res->>'status');
    ASSERT (SELECT estado FROM reservas WHERE id = v_r) = 'pre_reserva';
    ASSERT NOT EXISTS (SELECT 1 FROM revisoes_cancelamento WHERE reserva_id = v_r);
    -- completou o sinal no evento seguinte → confirma
    v_res := public.processar_pagamento_webhook('mercado_pago', 'evt-w8b', 20.00,
        NULL, v_cob, 'mp-tx-w8b', '{}'::JSONB, true);
    ASSERT v_res->>'status' = 'confirmada', format('W8b: status %s', v_res->>'status');
    RAISE NOTICE 'W8 OK — parcial no prazo aguarda; complemento confirma';
END $$;
