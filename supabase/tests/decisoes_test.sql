-- decisoes_test.sql — testes das 3 decisões de negócio (v3.4.3)
-- Corre DEPOIS das outras suítes (usa fixtures do seed e do schedule_test).
SET TIME ZONE 'America/Sao_Paulo';

CREATE OR REPLACE FUNCTION teste_proximo_dia(dow INT, hora TEXT) RETURNS TIMESTAMPTZ
LANGUAGE sql STABLE AS $$
    SELECT ((CURRENT_DATE + ((dow - EXTRACT(DOW FROM CURRENT_DATE)::INT + 7) % 7 + 7))::TEXT || ' ' || hora)::TIMESTAMPTZ
$$;

-- ===== D1: CARDÁPIO OBRIGATÓRIO =====
-- D1a: sem cardápio → rejeição com mensagem clara
DO $$
BEGIN
    BEGIN
        PERFORM public.criar_pre_reserva('00000000-0000-0000-0000-000000000001',
            'cccccccc-0000-0000-0000-000000000001',
            jsonb_build_array(jsonb_build_object('servico_id','aaaaaaaa-0000-0000-0000-000000000001',
                'profissional_id','33333333-3333-3333-3333-333333333333',
                'inicio', teste_proximo_dia(2,'10:00'))),
            'd1-sem-cardapio');
        RAISE EXCEPTION 'D1a FALHOU: aceitou sem cardápio';
    EXCEPTION WHEN OTHERS THEN
        ASSERT SQLERRM LIKE '%cardápio%', format('D1a erro inesperado: %s', SQLERRM);
        RAISE NOTICE 'D1a OK — sem cardápio rejeitado: %', SQLERRM;
    END;
END $$;

-- D1b: cardápio vazio → rejeição
DO $$
BEGIN
    BEGIN
        PERFORM public.criar_pre_reserva('00000000-0000-0000-0000-000000000001',
            'cccccccc-0000-0000-0000-000000000001',
            jsonb_build_array(jsonb_build_object('servico_id','aaaaaaaa-0000-0000-0000-000000000001',
                'profissional_id','33333333-3333-3333-3333-333333333333',
                'cardapio', '',
                'inicio', teste_proximo_dia(2,'11:00'))),
            'd1-cardapio-vazio');
        RAISE EXCEPTION 'D1b FALHOU: aceitou cardápio vazio';
    EXCEPTION WHEN OTHERS THEN
        ASSERT SQLERRM LIKE '%cardápio%', format('D1b erro inesperado: %s', SQLERRM);
        RAISE NOTICE 'D1b OK — cardápio vazio rejeitado';
    END;
END $$;

-- D1c: cardápio válido (ella_studio) → cria
DO $$
DECLARE v JSONB;
BEGIN
    v := public.criar_pre_reserva('00000000-0000-0000-0000-000000000001',
        'cccccccc-0000-0000-0000-000000000001',
        jsonb_build_array(jsonb_build_object('servico_id','aaaaaaaa-0000-0000-0000-000000000001',
            'profissional_id','33333333-3333-3333-3333-333333333333',
            'cardapio', 'ella_studio',
            'inicio', teste_proximo_dia(2,'12:00'))),
        'd1-cardapio-ok');
    ASSERT (v->>'idempotente')::BOOLEAN = false, 'D1c: devia ser nova';
    RAISE NOTICE 'D1c OK — cardápio ella_studio aceite';
END $$;

-- ===== D2: SINAL 30% FIXO =====
-- Serviço de R$ 100, 60 min → sinal de R$ 30
DO $$
DECLARE v JSONB; v_r UUID; v_sinal DECIMAL; v_pct INT;
BEGIN
    v := public.criar_pre_reserva('00000000-0000-0000-0000-000000000001',
        'cccccccc-0000-0000-0000-000000000001',
        jsonb_build_array(jsonb_build_object('servico_id','aaaaaaaa-0000-0000-0000-000000000011',
            'profissional_id','33333333-3333-3333-3333-333333333333',
            'cardapio', 'ella_studio',
            'inicio', teste_proximo_dia(3,'10:00'))),
        'd2-sinal-30');
    v_r := (v->>'reserva_id')::UUID;

    SELECT valor_sinal_total, percentual_sinal INTO v_sinal, v_pct
    FROM reservas WHERE id = v_r;

    ASSERT v_pct = 30, format('D2: percentual_sinal % (devia ser 30)', v_pct);
    ASSERT v_sinal = 30.00, format('D2: sinal de R$ % (devia ser R$ 30.00 para serviço de R$ 100.00)', v_sinal);

    SELECT valor_sinal INTO v_sinal FROM cobrancas WHERE reserva_id = v_r;
    ASSERT v_sinal = 30.00, format('D2: cobrança sinal R$ % (devia ser R$ 30.00)', v_sinal);

    RAISE NOTICE 'D2 OK — sinal 30%% fixo: R$ % sobre R$ 100', v_sinal;
END $$;

-- ===== D3: AVALIAÇÃO GRATUITA (preço 0) =====
-- Serviço com preço 0 confirma diretamente, cobrança de valor 0 como registo interno
DO $$
DECLARE v JSONB; v_r UUID; v_estado TEXT; v_total DECIMAL; v_cob_valor DECIMAL;
BEGIN
    -- Fixture: serviço de avaliação gratuita
    INSERT INTO servicos (id, empresa_id, nome_tecnico, tipo_recurso_id, duracao_minutos, preco_base, percentual_sinal, anamnese_obrigatoria)
    VALUES ('aaaaaaaa-0000-0000-0000-0000000000a0', '00000000-0000-0000-0000-000000000001', 'teste_avaliacao_gratis', '11111111-1111-1111-1111-111111111111', 30, 0.00, 30, false)
    ON CONFLICT (empresa_id, nome_tecnico) DO NOTHING;
    INSERT INTO profissional_servicos (profissional_id, servico_id, empresa_id) VALUES
    ('33333333-3333-3333-3333-333333333333', 'aaaaaaaa-0000-0000-0000-0000000000a0', '00000000-0000-0000-0000-000000000001')
    ON CONFLICT DO NOTHING;

    v := public.criar_pre_reserva('00000000-0000-0000-0000-000000000001',
        'cccccccc-0000-0000-0000-000000000001',
        jsonb_build_array(jsonb_build_object('servico_id','aaaaaaaa-0000-0000-0000-0000000000a0',
            'profissional_id','33333333-3333-3333-3333-333333333333',
            'cardapio', 'ella_studio',
            'inicio', teste_proximo_dia(4,'10:00'))),
        'd3-avaliacao-gratis');
    v_r := (v->>'reserva_id')::UUID;
    v_estado := v->>'estado';

    -- Confirmação direta (sem PIX, sem 30 min de espera)
    ASSERT v_estado = 'confirmada', format('D3: estado devolvido % (devia ser confirmada)', v_estado);
    ASSERT (SELECT estado FROM reservas WHERE id = v_r) = 'confirmada',
        'D3 REGRESSÃO: avaliação gratuita não nasceu confirmada';

    -- Ocupações definitivas (sem expires_at)
    ASSERT (SELECT COUNT(*) FROM agenda_ocupacoes
            WHERE origem = 'reserva' AND origem_id = v_r AND estado = 'ativa' AND expires_at IS NULL) = 2,
        'D3: ocupações deviam ser definitivas (sem expires_at)';

    -- Cobrança de valor 0 como registo interno (Alternativa A)
    SELECT valor_total, valor_sinal INTO v_total, v_cob_valor
    FROM cobrancas WHERE reserva_id = v_r;
    ASSERT v_total = 0.00, format('D3: cobrança total R$ % (devia ser 0.00)', v_total);
    ASSERT v_cob_valor = 0.00, format('D3: cobrança sinal R$ % (devia ser 0.00)', v_cob_valor);

    -- O cron NÃO deve mexer em reserva confirmada
    PERFORM public.expirar_pre_reservas();
    ASSERT (SELECT estado FROM reservas WHERE id = v_r) = 'confirmada', 'D3: cron mexeu em avaliação gratuita';

    RAISE NOTICE 'D3 OK — avaliação gratuita: confirmada direto, cobrança R$ 0 (registo interno), cron ignora';
END $$;
