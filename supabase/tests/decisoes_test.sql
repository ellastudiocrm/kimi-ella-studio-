-- decisoes_test.sql — testes das 3 decisões de negócio (v3.4.3)
SET TIME ZONE 'America/Sao_Paulo';
RESET ROLE;
SELECT set_config('request.jwt.claims', '{}', false);

CREATE OR REPLACE FUNCTION teste_proximo_dia(dow INT, hora TEXT) RETURNS TIMESTAMPTZ
LANGUAGE sql STABLE AS $$
    SELECT ((CURRENT_DATE + ((dow - EXTRACT(DOW FROM CURRENT_DATE)::INT + 7) % 7 + 7))::TEXT || ' ' || hora)::TIMESTAMPTZ
$$;

-- Fixtures defensivas (idempotentes)
INSERT INTO clientes (id, empresa_id, nome, telefone_normalizado) VALUES
('cccccccc-0000-0000-0000-000000000001', '00000000-0000-0000-0000-000000000001', 'Cliente Teste', '5519999990001')
ON CONFLICT (id) DO NOTHING;

INSERT INTO profissionais (id, empresa_id, nome) VALUES
('dddddddd-0000-0000-0000-00000000000d', '00000000-0000-0000-0000-000000000001', 'Prof D Teste')
ON CONFLICT (id) DO NOTHING;
INSERT INTO horarios_profissional (profissional_id, dia_semana, abertura, fechamento) VALUES
('dddddddd-0000-0000-0000-00000000000d', 2, '09:00', '17:00'),
('dddddddd-0000-0000-0000-00000000000d', 3, '09:00', '17:00'),
('dddddddd-0000-0000-0000-00000000000d', 4, '09:00', '17:00'),
('dddddddd-0000-0000-0000-00000000000d', 5, '09:00', '17:00'),
('dddddddd-0000-0000-0000-00000000000d', 6, '09:00', '13:00')
ON CONFLICT DO NOTHING;

INSERT INTO servicos (id, empresa_id, nome_tecnico, tipo_recurso_id, duracao_minutos, preco_base, anamnese_obrigatoria) VALUES
('aaaaaaaa-0000-0000-0000-000000000001', '00000000-0000-0000-0000-000000000001', 'teste_manicure', '11111111-1111-1111-1111-111111111111', 60, 50.00, false),
('aaaaaaaa-0000-0000-0000-000000000011', '00000000-0000-0000-0000-000000000001', 'teste_pagamento', '11111111-1111-1111-1111-111111111111', 60, 100.00, false)
ON CONFLICT (empresa_id, nome_tecnico) DO NOTHING;

INSERT INTO profissional_servicos (profissional_id, servico_id, empresa_id) VALUES
('33333333-3333-3333-3333-333333333333', 'aaaaaaaa-0000-0000-0000-000000000001', '00000000-0000-0000-0000-000000000001'),
('dddddddd-0000-0000-0000-00000000000d', 'aaaaaaaa-0000-0000-0000-000000000001', '00000000-0000-0000-0000-000000000001'),
('dddddddd-0000-0000-0000-00000000000d', 'aaaaaaaa-0000-0000-0000-000000000011', '00000000-0000-0000-0000-000000000001')
ON CONFLICT DO NOTHING;

INSERT INTO horarios_profissional (profissional_id, dia_semana, abertura, fechamento) VALUES
('33333333-3333-3333-3333-333333333333', 2, '09:00', '17:00'),
('33333333-3333-3333-3333-333333333333', 3, '09:00', '17:00'),
('33333333-3333-3333-3333-333333333333', 4, '09:00', '17:00'),
('33333333-3333-3333-3333-333333333333', 5, '09:00', '17:00'),
('33333333-3333-3333-3333-333333333333', 6, '09:00', '13:00')
ON CONFLICT DO NOTHING;

-- ===== D1: CARDÁPIO OBRIGATÓRIO =====
DO $$
BEGIN
    BEGIN
        PERFORM public.criar_pre_reserva('00000000-0000-0000-0000-000000000001',
            'cccccccc-0000-0000-0000-000000000001',
            jsonb_build_array(jsonb_build_object('servico_id','aaaaaaaa-0000-0000-0000-000000000001',
                'profissional_id','dddddddd-0000-0000-0000-00000000000d',
                'inicio', teste_proximo_dia(2,'10:00'))),
            'd1-sem-cardapio');
        RAISE EXCEPTION 'D1a FALHOU: aceitou sem cardápio';
    EXCEPTION WHEN OTHERS THEN
        ASSERT SQLERRM LIKE '%cardápio%', format('D1a erro inesperado: %s', SQLERRM);
        RAISE NOTICE 'D1a OK — sem cardápio rejeitado: %', SQLERRM;
    END;
END $$;

DO $$
BEGIN
    BEGIN
        PERFORM public.criar_pre_reserva('00000000-0000-0000-0000-000000000001',
            'cccccccc-0000-0000-0000-000000000001',
            jsonb_build_array(jsonb_build_object('servico_id','aaaaaaaa-0000-0000-0000-000000000001',
                'profissional_id','dddddddd-0000-0000-0000-00000000000d',
                'cardapio', '',
                'inicio', teste_proximo_dia(2,'11:00'))),
            'd1-cardapio-vazio');
        RAISE EXCEPTION 'D1b FALHOU: aceitou cardápio vazio';
    EXCEPTION WHEN OTHERS THEN
        ASSERT SQLERRM LIKE '%cardápio%', format('D1b erro inesperado: %s', SQLERRM);
        RAISE NOTICE 'D1b OK — cardápio vazio rejeitado';
    END;
END $$;

DO $$
DECLARE v JSONB;
BEGIN
    v := public.criar_pre_reserva('00000000-0000-0000-0000-000000000001',
        'cccccccc-0000-0000-0000-000000000001',
        jsonb_build_array(jsonb_build_object('servico_id','aaaaaaaa-0000-0000-0000-000000000001',
            'profissional_id','dddddddd-0000-0000-0000-00000000000d',
            'cardapio', 'ella_studio',
            'inicio', teste_proximo_dia(2,'12:00'))),
        'd1-cardapio-ok');
    ASSERT (v->>'idempotente')::BOOLEAN = false, 'D1c: devia ser nova';
    RAISE NOTICE 'D1c OK — cardápio ella_studio aceite';
END $$;

-- ===== D2: SINAL 30% FIXO =====
DO $$
DECLARE v JSONB; v_r UUID; v_sinal DECIMAL; v_pct INT;
BEGIN
    v := public.criar_pre_reserva('00000000-0000-0000-0000-000000000001',
        'cccccccc-0000-0000-0000-000000000001',
        jsonb_build_array(jsonb_build_object('servico_id','aaaaaaaa-0000-0000-0000-000000000011',
            'profissional_id','dddddddd-0000-0000-0000-00000000000d',
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
DO $$
DECLARE v JSONB; v_r UUID; v_estado TEXT; v_total DECIMAL; v_cob_valor DECIMAL;
BEGIN
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
            'inicio', teste_proximo_dia(5,'13:30'))),
        'd3-avaliacao-gratis');
    v_r := (v->>'reserva_id')::UUID;
    v_estado := v->>'estado';

    ASSERT v_estado = 'confirmada', format('D3: estado devolvido % (devia ser confirmada)', v_estado);
    ASSERT (SELECT estado FROM reservas WHERE id = v_r) = 'confirmada',
        'D3 REGRESSÃO: avaliação gratuita não nasceu confirmada';

    ASSERT (SELECT COUNT(*) FROM agenda_ocupacoes
            WHERE origem = 'reserva' AND origem_id = v_r AND estado = 'ativa' AND expires_at IS NULL) = 2,
        'D3: ocupações deviam ser definitivas (sem expires_at)';

    SELECT valor_total, valor_sinal INTO v_total, v_cob_valor
    FROM cobrancas WHERE reserva_id = v_r;
    ASSERT v_total = 0.00, format('D3: cobrança total R$ % (devia ser 0.00)', v_total);
    ASSERT v_cob_valor = 0.00, format('D3: cobrança sinal R$ % (devia ser 0.00)', v_cob_valor);

    PERFORM public.expirar_pre_reservas();
    ASSERT (SELECT estado FROM reservas WHERE id = v_r) = 'confirmada', 'D3: cron mexeu em avaliação gratuita';

    RAISE NOTICE 'D3 OK — avaliação gratuita: confirmada direto, cobrança R$ 0 (registo interno), cron ignora';
END $$;

-- Limpeza dos dados criados por esta suíte
DO $$
DECLARE
    v_reserva_ids UUID[];
BEGIN
    SELECT array_agg(id) INTO v_reserva_ids
    FROM public.reservas
    WHERE empresa_id = '00000000-0000-0000-0000-000000000001'
      AND idempotencia_key IN ('d1-sem-cardapio','d1-cardapio-vazio','d1-cardapio-ok','d2-sinal-30','d3-avaliacao-gratis');

    IF v_reserva_ids IS NOT NULL AND array_length(v_reserva_ids, 1) > 0 THEN
        DELETE FROM public.eventos_pagamento WHERE transacao_id IN (
            SELECT id FROM public.transacoes WHERE cobranca_id IN (
                SELECT id FROM public.cobrancas WHERE reserva_id = ANY(v_reserva_ids)
            )
        );
        DELETE FROM public.alocacoes_pagamento WHERE transacao_id IN (
            SELECT id FROM public.transacoes WHERE cobranca_id IN (
                SELECT id FROM public.cobrancas WHERE reserva_id = ANY(v_reserva_ids)
            )
        );
        DELETE FROM public.transacoes WHERE cobranca_id IN (
            SELECT id FROM public.cobrancas WHERE reserva_id = ANY(v_reserva_ids)
        );
        DELETE FROM public.revisoes_cancelamento WHERE reserva_id = ANY(v_reserva_ids);
        DELETE FROM public.anamnese_respostas WHERE anamnese_id IN (
            SELECT id FROM public.anamneses WHERE reserva_item_id IN (
                SELECT id FROM public.reserva_itens WHERE reserva_id = ANY(v_reserva_ids)
            )
        );
        DELETE FROM public.anamnese_tokens WHERE reserva_id = ANY(v_reserva_ids);
        DELETE FROM public.anamneses WHERE reserva_item_id IN (
            SELECT id FROM public.reserva_itens WHERE reserva_id = ANY(v_reserva_ids)
        );
        DELETE FROM public.cobrancas WHERE reserva_id = ANY(v_reserva_ids);
        DELETE FROM public.agenda_ocupacoes WHERE reserva_item_id IN (
            SELECT id FROM public.reserva_itens WHERE reserva_id = ANY(v_reserva_ids)
        );
        DELETE FROM public.reserva_itens WHERE reserva_id = ANY(v_reserva_ids);
        DELETE FROM public.reservas WHERE id = ANY(v_reserva_ids);
    END IF;

    DELETE FROM public.excecoes_calendario
    WHERE empresa_id = '00000000-0000-0000-0000-000000000001'
      AND motivo LIKE 'Teste%';

    DROP FUNCTION IF EXISTS public.teste_proximo_dia(INT, TEXT);
END $$;
