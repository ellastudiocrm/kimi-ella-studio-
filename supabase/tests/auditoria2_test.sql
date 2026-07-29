-- auditoria2_test.sql — testes da 2ª auditoria (v3.4.3)
SET TIME ZONE 'America/Sao_Paulo';
RESET ROLE;
SELECT set_config('request.jwt.claims', '{}', false);

CREATE OR REPLACE FUNCTION teste_proximo_dia(dow INT, hora TEXT) RETURNS TIMESTAMPTZ
LANGUAGE sql STABLE AS $$
    SELECT ((CURRENT_DATE + ((dow - EXTRACT(DOW FROM CURRENT_DATE)::INT + 7) % 7 + 7))::TEXT || ' ' || hora)::TIMESTAMPTZ
$$;

-- Helper: paga o sinal de uma reserva
CREATE OR REPLACE FUNCTION teste_paga_sinal(p_reserva UUID, p_finalidade TEXT, p_valor NUMERIC) RETURNS VOID
LANGUAGE sql VOLATILE AS $$
    INSERT INTO transacoes (cobranca_id, empresa_id, mp_idempotency_key, valor, meio, finalidade, estado)
    SELECT c.id, c.empresa_id, 'teste-' || gen_random_uuid()::TEXT, p_valor, 'pix', p_finalidade, 'pago'
    FROM cobrancas c WHERE c.reserva_id = p_reserva
$$;

-- Fixtures defensivas (idempotentes)
INSERT INTO profissionais (id, empresa_id, nome) VALUES
('dddddddd-0000-0000-0000-000000000001', '00000000-0000-0000-0000-000000000001', 'Prof B Teste'),
('dddddddd-0000-0000-0000-00000000000d', '00000000-0000-0000-0000-000000000001', 'Prof D Teste')
ON CONFLICT (id) DO NOTHING;

INSERT INTO horarios_profissional (profissional_id, dia_semana, abertura, fechamento) VALUES
('dddddddd-0000-0000-0000-000000000001', 2, '09:00', '17:00'),
('dddddddd-0000-0000-0000-000000000001', 3, '09:00', '17:00'),
('dddddddd-0000-0000-0000-000000000001', 4, '09:00', '17:00'),
('dddddddd-0000-0000-0000-000000000001', 5, '09:00', '17:00'),
('dddddddd-0000-0000-0000-000000000001', 6, '09:00', '13:00'),
('dddddddd-0000-0000-0000-00000000000d', 2, '09:00', '17:00'),
('dddddddd-0000-0000-0000-00000000000d', 3, '09:00', '17:00'),
('dddddddd-0000-0000-0000-00000000000d', 4, '09:00', '17:00'),
('dddddddd-0000-0000-0000-00000000000d', 5, '09:00', '17:00'),
('dddddddd-0000-0000-0000-00000000000d', 6, '09:00', '13:00')
ON CONFLICT DO NOTHING;

INSERT INTO servicos (id, empresa_id, nome_tecnico, tipo_recurso_id, duracao_minutos, preco_base, anamnese_obrigatoria) VALUES
('aaaaaaaa-0000-0000-0000-000000000011', '00000000-0000-0000-0000-000000000001', 'teste_pagamento', '11111111-1111-1111-1111-111111111111', 60, 100.00, false)
ON CONFLICT (empresa_id, nome_tecnico) DO NOTHING;

INSERT INTO profissional_servicos (profissional_id, servico_id, empresa_id) VALUES
('dddddddd-0000-0000-0000-00000000000d', 'aaaaaaaa-0000-0000-0000-000000000011', '00000000-0000-0000-0000-000000000001')
ON CONFLICT DO NOTHING;

INSERT INTO clientes (id, empresa_id, nome, telefone_normalizado) VALUES
('cccccccc-0000-0000-0000-000000000001', '00000000-0000-0000-0000-000000000001', 'Cliente Teste', '5519999990001'),
('cccccccc-0000-0000-0000-000000000011', '00000000-0000-0000-0000-000000000001', 'Cliente Pagamento', '5519999990011')
ON CONFLICT (id) DO NOTHING;

INSERT INTO horarios_profissional (profissional_id, dia_semana, abertura, fechamento) VALUES
('33333333-3333-3333-3333-333333333333', 2, '09:00', '17:00'),
('33333333-3333-3333-3333-333333333333', 3, '09:00', '17:00'),
('33333333-3333-3333-3333-333333333333', 4, '09:00', '17:00'),
('33333333-3333-3333-3333-333333333333', 5, '09:00', '17:00'),
('33333333-3333-3333-3333-333333333333', 6, '09:00', '13:00')
ON CONFLICT DO NOTHING;

-- Helper: agenda com anamnese e devolve {reserva_id, token, anamnese_id}
CREATE OR REPLACE FUNCTION teste_agenda_com_anamnese(p_servico TEXT, dow INT, hora TEXT, chave TEXT)
RETURNS JSONB
LANGUAGE plpgsql VOLATILE AS $$
DECLARE v JSONB;
BEGIN
    v := public.criar_pre_reserva('00000000-0000-0000-0000-000000000001',
        'cccccccc-0000-0000-0000-000000000001',
        jsonb_build_array(jsonb_build_object('servico_id', p_servico,
            'profissional_id', 'dddddddd-0000-0000-0000-000000000001',
            'cardapio', 'ella_studio',
            'inicio', teste_proximo_dia(dow, hora))), chave);
    RETURN jsonb_build_object(
        'reserva_id', v->>'reserva_id',
        'anamnese_id', v->'anamneses'->0->>'anamnese_id',
        'token', v->'anamneses'->0->>'token');
END $$;

-- =====================================================================
-- ITEM 7: Cardápio oficial
-- =====================================================================
DO $$
BEGIN
    BEGIN
        INSERT INTO servico_cardapios (servico_id, cardapio, nome_comercial)
        VALUES ('aaaaaaaa-0000-0000-0000-000000000011', 'feminino', 'Teste Cardápio Antigo');
        RAISE EXCEPTION 'A7a FALHOU: aceitou feminino';
    EXCEPTION WHEN check_violation THEN
        RAISE NOTICE 'A7a OK — feminino rejeitado (CHECK atualizado)';
    END;
END $$;

DO $$
BEGIN
    BEGIN
        INSERT INTO servico_cardapios (servico_id, cardapio, nome_comercial)
        VALUES ('aaaaaaaa-0000-0000-0000-000000000011', 'masculino', 'Teste Cardápio Antigo');
        RAISE EXCEPTION 'A7b FALHOU: aceitou masculino';
    EXCEPTION WHEN check_violation THEN
        RAISE NOTICE 'A7b OK — masculino rejeitado (CHECK atualizado)';
    END;
END $$;

DO $$
BEGIN
    INSERT INTO servico_cardapios (servico_id, cardapio, nome_comercial)
    VALUES ('aaaaaaaa-0000-0000-0000-000000000011', 'ella_studio', 'Teste Cardápio Novo')
    ON CONFLICT (servico_id, cardapio) DO NOTHING;
    ASSERT EXISTS (SELECT 1 FROM servico_cardapios WHERE servico_id = 'aaaaaaaa-0000-0000-0000-000000000011' AND cardapio = 'ella_studio');
    RAISE NOTICE 'A7c OK — ella_studio aceite';
END $$;

-- =====================================================================
-- ITEM 1: Verificação de perfil nas 3 RPCs
-- =====================================================================
DO $$
DECLARE v_r UUID;
BEGIN
    v_r := (public.criar_pre_reserva('00000000-0000-0000-0000-000000000001',
        'cccccccc-0000-0000-0000-000000000011',
        jsonb_build_array(jsonb_build_object('servico_id','aaaaaaaa-0000-0000-0000-000000000011',
            'profissional_id','dddddddd-0000-0000-0000-00000000000d', 'cardapio','ella_studio', 'inicio', teste_proximo_dia(2,'14:00'))),
        'a1-fixture')) ->> 'reserva_id';
    PERFORM set_config('app.a1.r', v_r::TEXT, false);
END $$;

SET ROLE authenticated;
SELECT set_config('request.jwt.claims', '{"sub":"ffffffff-0000-0000-0000-000000000002","role":"authenticated","aal":"aal1"}', false);
DO $$
DECLARE v_r UUID;
BEGIN
    v_r := current_setting('app.a1.r')::UUID;
    BEGIN
        PERFORM public.cancelar_reserva(v_r);
        RAISE EXCEPTION 'A1a FALHOU: recepcao de outra empresa cancelou reserva';
    EXCEPTION WHEN OTHERS THEN
        ASSERT SQLERRM LIKE '%Sem permissão%', format('A1a erro inesperado: %s', SQLERRM);
        RAISE NOTICE 'A1a OK — inquilino estranho não cancela: %', SQLERRM;
    END;
END $$;
RESET ROLE;
SELECT set_config('request.jwt.claims', '{}', false);

SET ROLE authenticated;
SELECT set_config('request.jwt.claims', '{"sub":"ffffffff-0000-0000-0000-000000000003","role":"authenticated","aal":"aal1"}', false);
DO $$
DECLARE v_r UUID;
BEGIN
    v_r := current_setting('app.a1.r')::UUID;
    BEGIN
        PERFORM public.cancelar_reserva(v_r);
        RAISE EXCEPTION 'A1b FALHOU: profissional cancelou reserva alheia';
    EXCEPTION WHEN OTHERS THEN
        ASSERT SQLERRM LIKE '%Sem permissão%', format('A1b erro inesperado: %s', SQLERRM);
        RAISE NOTICE 'A1b OK — profissional sem vínculo não cancela: %', SQLERRM;
    END;
END $$;
RESET ROLE;
SELECT set_config('request.jwt.claims', '{}', false);

SET ROLE authenticated;
SELECT set_config('request.jwt.claims', '{"sub":"ffffffff-0000-0000-0000-000000000003","role":"authenticated","aal":"aal1"}', false);
DO $$
DECLARE v_r UUID;
BEGIN
    v_r := current_setting('app.a1.r')::UUID;
    BEGIN
        PERFORM public.confirmar_reserva(v_r);
        RAISE EXCEPTION 'A1c FALHOU: profissional confirmou reserva alheia';
    EXCEPTION WHEN OTHERS THEN
        ASSERT SQLERRM LIKE '%Sem permissão%', format('A1c erro inesperado: %s', SQLERRM);
        RAISE NOTICE 'A1c OK — profissional sem vínculo não confirma: %', SQLERRM;
    END;
END $$;
RESET ROLE;
SELECT set_config('request.jwt.claims', '{}', false);

SET ROLE authenticated;
SELECT set_config('request.jwt.claims', '{"sub":"ffffffff-0000-0000-0000-000000000003","role":"authenticated","aal":"aal1"}', false);
DO $$
DECLARE v_r UUID;
BEGIN
    v_r := current_setting('app.a1.r')::UUID;
    BEGIN
        PERFORM public.cancelar_pre_reserva(v_r);
        RAISE EXCEPTION 'A1d FALHOU: profissional cancelou pré-reserva alheia';
    EXCEPTION WHEN OTHERS THEN
        ASSERT SQLERRM LIKE '%Sem permissão%', format('A1d erro inesperado: %s', SQLERRM);
        RAISE NOTICE 'A1d OK — profissional sem vínculo não cancela pré-reserva: %', SQLERRM;
    END;
END $$;
RESET ROLE;
SELECT set_config('request.jwt.claims', '{}', false);

-- =====================================================================
-- ITEM 2: Cobrança 'cancelada' nos 3 ramos de resolver_revisao
-- =====================================================================
DO $$
DECLARE v_rev UUID; v_r UUID; v_res JSONB;
BEGIN
    v_r := (public.criar_pre_reserva('00000000-0000-0000-0000-000000000001',
        'cccccccc-0000-0000-0000-000000000011',
        jsonb_build_array(jsonb_build_object('servico_id','aaaaaaaa-0000-0000-0000-000000000011',
            'profissional_id','dddddddd-0000-0000-0000-00000000000d', 'cardapio','ella_studio', 'inicio', teste_proximo_dia(3,'14:00'))),
        'a2-credito')) ->> 'reserva_id';
    PERFORM teste_paga_sinal(v_r::UUID, 'sinal', 30.00);
    PERFORM public.confirmar_reserva(v_r::UUID);
    PERFORM public.cancelar_reserva(v_r::UUID);
    SELECT id INTO v_rev FROM revisoes_cancelamento WHERE reserva_id = v_r::UUID AND decisao_final IS NULL;
    v_res := public.resolver_revisao(v_rev, 'credito', 'cliente quer crédito');
    ASSERT v_res->>'reserva_status' = 'cancelada';
    ASSERT (SELECT estado FROM cobrancas WHERE reserva_id = v_r::UUID) = 'cancelada',
        'A2a: cobrança devia estar cancelada no ramo credito';
    RAISE NOTICE 'A2a OK — credito: cobrança cancelada';
END $$;

DO $$
DECLARE v_rev UUID; v_r UUID; v_res JSONB;
BEGIN
    v_r := (public.criar_pre_reserva('00000000-0000-0000-0000-000000000001',
        'cccccccc-0000-0000-0000-000000000011',
        jsonb_build_array(jsonb_build_object('servico_id','aaaaaaaa-0000-0000-0000-000000000011',
            'profissional_id','dddddddd-0000-0000-0000-00000000000d', 'cardapio','ella_studio', 'inicio', teste_proximo_dia(4,'14:00'))),
        'a2-estorno')) ->> 'reserva_id';
    PERFORM teste_paga_sinal(v_r::UUID, 'sinal', 30.00);
    PERFORM public.confirmar_reserva(v_r::UUID);
    PERFORM public.cancelar_reserva(v_r::UUID);
    SELECT id INTO v_rev FROM revisoes_cancelamento WHERE reserva_id = v_r::UUID AND decisao_final IS NULL;
    v_res := public.resolver_revisao(v_rev, 'estorno', 'cliente quer dinheiro de volta');
    ASSERT v_res->>'reserva_status' = 'cancelada';
    ASSERT (SELECT estado FROM cobrancas WHERE reserva_id = v_r::UUID) = 'cancelada',
        'A2b: cobrança devia estar cancelada no ramo estorno';
    RAISE NOTICE 'A2b OK — estorno: cobrança cancelada';
END $$;

DO $$
DECLARE v_rev UUID; v_r UUID; v_res JSONB;
BEGIN
    v_r := (public.criar_pre_reserva('00000000-0000-0000-0000-000000000001',
        'cccccccc-0000-0000-0000-000000000011',
        jsonb_build_array(jsonb_build_object('servico_id','aaaaaaaa-0000-0000-0000-000000000011',
            'profissional_id','dddddddd-0000-0000-0000-00000000000d', 'cardapio','ella_studio', 'inicio', teste_proximo_dia(5,'14:00'))),
        'a2-perdido')) ->> 'reserva_id';
    PERFORM teste_paga_sinal(v_r::UUID, 'sinal', 30.00);
    PERFORM public.confirmar_reserva(v_r::UUID);
    PERFORM public.cancelar_reserva(v_r::UUID);
    SELECT id INTO v_rev FROM revisoes_cancelamento WHERE reserva_id = v_r::UUID AND decisao_final IS NULL;
    v_res := public.resolver_revisao(v_rev, 'perdido', 'cliente não apareceu');
    ASSERT v_res->>'reserva_status' = 'cancelada';
    ASSERT (SELECT estado FROM cobrancas WHERE reserva_id = v_r::UUID) = 'cancelada',
        'A2c: cobrança devia estar cancelada no ramo perdido (não sinal_pago)';
    RAISE NOTICE 'A2c OK — perdido: cobrança cancelada (regressão sinal_pago evitada)';
END $$;

-- =====================================================================
-- ITEM 3: CHECK em log_acoes_sensiveis.acao
-- =====================================================================
DO $$
BEGIN
    BEGIN
        INSERT INTO log_acoes_sensiveis (empresa_id, tabela, registro_id, acao)
        VALUES ('00000000-0000-0000-0000-000000000001', 'teste', gen_random_uuid(), 'SELECT');
        RAISE EXCEPTION 'A3 FALHOU: aceitou acao=SELECT';
    EXCEPTION WHEN check_violation THEN
        RAISE NOTICE 'A3 OK — acao inválida rejeitada (CHECK)';
    END;
END $$;

-- =====================================================================
-- ITEM 4: Validação em submeter_anamnese
-- =====================================================================
DO $$
DECLARE v_modelo UUID; v_perg_num UUID; v_perg_mul UUID; v_token TEXT; v_anamnese_id UUID;
BEGIN
    INSERT INTO modelos_anamnese (id, empresa_id, nome) VALUES
    ('cccccccc-0000-0000-0000-0000000000a4', '00000000-0000-0000-0000-000000000001', 'Modelo Teste Validação')
    ON CONFLICT (id) DO NOTHING;

    INSERT INTO modelo_perguntas (id, modelo_id, ordem, pergunta, tipo_resposta, opcoes, obrigatoria)
    VALUES ('dddddddd-0000-0000-0000-0000000000a1', 'cccccccc-0000-0000-0000-0000000000a4', 1, 'Idade?', 'numero', NULL, true)
    ON CONFLICT (id) DO NOTHING;

    INSERT INTO modelo_perguntas (id, modelo_id, ordem, pergunta, tipo_resposta, opcoes, obrigatoria)
    VALUES ('dddddddd-0000-0000-0000-0000000000a2', 'cccccccc-0000-0000-0000-0000000000a4', 2, 'Cor preferida?', 'multipla_escolha', '["azul","vermelho","verde"]'::JSONB, true)
    ON CONFLICT (id) DO NOTHING;

    INSERT INTO servicos (id, empresa_id, nome_tecnico, tipo_recurso_id, duracao_minutos, preco_base, percentual_sinal, anamnese_obrigatoria, modelo_anamnese_id)
    VALUES ('aaaaaaaa-0000-0000-0000-0000000000a4', '00000000-0000-0000-0000-000000000001', 'teste_validacao_anamnese', '11111111-1111-1111-1111-111111111111', 30, 50.00, 30, true, 'cccccccc-0000-0000-0000-0000000000a4')
    ON CONFLICT (empresa_id, nome_tecnico) DO NOTHING;
    INSERT INTO profissional_servicos (profissional_id, servico_id, empresa_id) VALUES
    ('33333333-3333-3333-3333-333333333333', 'aaaaaaaa-0000-0000-0000-0000000000a4', '00000000-0000-0000-0000-000000000001'),
    ('dddddddd-0000-0000-0000-000000000001', 'aaaaaaaa-0000-0000-0000-0000000000a4', '00000000-0000-0000-0000-000000000001'),
    ('dddddddd-0000-0000-0000-00000000000d', 'aaaaaaaa-0000-0000-0000-0000000000a4', '00000000-0000-0000-0000-000000000001')
    ON CONFLICT DO NOTHING;

    RAISE NOTICE 'A4 FIXTURES OK — modelo de teste criado';
END $$;

DO $$
DECLARE v JSONB; v_token TEXT;
BEGIN
    v := teste_agenda_com_anamnese('aaaaaaaa-0000-0000-0000-0000000000a4', 6, '10:00', 'a4a-numero');
    v_token := v->>'token';
    BEGIN
        PERFORM public.submeter_anamnese(v_token,
            jsonb_build_array(
                jsonb_build_object('pergunta_id','dddddddd-0000-0000-0000-0000000000a1','resposta','trinta'),
                jsonb_build_object('pergunta_id','dddddddd-0000-0000-0000-0000000000a2','resposta','azul')
            ), true, 'termo');
        RAISE EXCEPTION 'A4a FALHOU: aceitou numero="trinta"';
    EXCEPTION WHEN OTHERS THEN
        ASSERT SQLERRM LIKE '%número%', format('A4a erro inesperado: %s', SQLERRM);
        RAISE NOTICE 'A4a OK — numero inválido rejeitado: %', SQLERRM;
    END;
END $$;

DO $$
DECLARE v JSONB; v_token TEXT;
BEGIN
    v := teste_agenda_com_anamnese('aaaaaaaa-0000-0000-0000-0000000000a4', 6, '11:00', 'a4b-multipla');
    v_token := v->>'token';
    BEGIN
        PERFORM public.submeter_anamnese(v_token,
            jsonb_build_array(
                jsonb_build_object('pergunta_id','dddddddd-0000-0000-0000-0000000000a1','resposta','30'),
                jsonb_build_object('pergunta_id','dddddddd-0000-0000-0000-0000000000a2','resposta','amarelo')
            ), true, 'termo');
        RAISE EXCEPTION 'A4b FALHOU: aceitou multipla="amarelo"';
    EXCEPTION WHEN OTHERS THEN
        ASSERT SQLERRM LIKE '%opções%', format('A4b erro inesperado: %s', SQLERRM);
        RAISE NOTICE 'A4b OK — multipla_escolha fora das opções rejeitada: %', SQLERRM;
    END;
END $$;

DO $$
DECLARE v JSONB; v_token TEXT; v_estado TEXT;
BEGIN
    v := teste_agenda_com_anamnese('aaaaaaaa-0000-0000-0000-0000000000a4', 6, '12:00', 'a4c-valido');
    v_token := v->>'token';
    v_estado := public.submeter_anamnese(v_token,
        jsonb_build_array(
            jsonb_build_object('pergunta_id','dddddddd-0000-0000-0000-0000000000a1','resposta','25'),
            jsonb_build_object('pergunta_id','dddddddd-0000-0000-0000-0000000000a2','resposta','azul')
        ), true, 'termo');
    ASSERT v_estado = 'liberada', format('A4c: estado %s', v_estado);
    RAISE NOTICE 'A4c OK — respostas válidas aceites';
END $$;

-- Limpeza dos dados criados por esta suíte
DO $$
DECLARE
    v_reserva_ids UUID[];
BEGIN
    SELECT array_agg(id) INTO v_reserva_ids
    FROM public.reservas
    WHERE empresa_id = '00000000-0000-0000-0000-000000000001'
      AND idempotencia_key IN ('a1-fixture','a2-credito','a2-estorno','a2-perdido','a4a-numero','a4b-multipla','a4c-valido');

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

    -- v3.4.4: limpa créditos criados pelo teste A2a (resolver_revisao ramo 'credito')
    DELETE FROM public.lancamentos_creditos WHERE conta_id IN (
        SELECT id FROM public.contas_creditos
        WHERE cliente_id = 'cccccccc-0000-0000-0000-000000000011'
          AND empresa_id = '00000000-0000-0000-0000-000000000001'
    );
    DELETE FROM public.contas_creditos
    WHERE cliente_id = 'cccccccc-0000-0000-0000-000000000011'
      AND empresa_id = '00000000-0000-0000-0000-000000000001';

    DROP FUNCTION IF EXISTS public.teste_proximo_dia(INT, TEXT);
    DROP FUNCTION IF EXISTS public.teste_agenda_com_anamnese(TEXT, INT, TEXT, TEXT);
    DROP FUNCTION IF EXISTS public.teste_paga_sinal(UUID, TEXT, NUMERIC);
END $$;
