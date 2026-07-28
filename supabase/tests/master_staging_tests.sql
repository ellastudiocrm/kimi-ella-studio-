-- =========================================================
-- MASTER: SuÃ­tes 7-11 (v3.4.3 staging)
-- Gerado automaticamente â€” nÃ£o editar diretamente
-- =========================================================
-- SuÃ­te 7: anamnese_submit_test  (17 asserts, S1-S7)
-- SuÃ­te 8: bloqueio_flow_test    (13 asserts, B1-B4)
-- SuÃ­te 9: v341_fixes_test       (57 asserts, F1-F14)
-- SuÃ­te 10: decisoes_test        (8 asserts, D1-D3)
-- SuÃ­te 11: auditoria2_test      (14 asserts, A1-A7)
-- TOTAL ESPERADO: 109 asserts
-- =========================================================


-- =========================================================
-- SUÃTE 7: anamnese_submit_test.sql
-- =========================================================

-- anamnese_submit_test.sql (v3.4 NOVO) â€” submeter_anamnese: o cliente entrega a ficha
-- pelo link (token = credencial); as REGRAS do modelo decidem liberada Ã— requer_avaliacao.
SET TIME ZONE 'America/Sao_Paulo';

CREATE OR REPLACE FUNCTION teste_proximo_dia(dow INT, hora TEXT) RETURNS TIMESTAMPTZ
LANGUAGE sql STABLE AS $$
    SELECT ((CURRENT_DATE + ((dow - EXTRACT(DOW FROM CURRENT_DATE)::INT + 7) % 7 + 7))::TEXT || ' ' || hora)::TIMESTAMPTZ
$$;

-- Modelo com regra: "JÃ¡ fez alergia a esmalte?" = sim â†’ requer_avaliacao
INSERT INTO modelos_anamnese (id, empresa_id, nome, versao) VALUES
('bbbbbbbb-0000-0000-0000-000000000002', '00000000-0000-0000-0000-000000000001', 'Modelo Regras', 1)
ON CONFLICT (id) DO NOTHING;
INSERT INTO modelo_perguntas (id, modelo_id, ordem, pergunta, tipo_resposta, obrigatoria, operador, valor_disparador, resultado_estado) VALUES
('bbbbbbbb-0000-0000-0000-0000000000a1', 'bbbbbbbb-0000-0000-0000-000000000002', 1, 'Tem alergia a esmalte?', 'sim_nao', true, 'igual', 'sim', 'requer_avaliacao'),
('bbbbbbbb-0000-0000-0000-0000000000a2', 'bbbbbbbb-0000-0000-0000-000000000002', 2, 'ObservaÃ§Ãµes', 'texto', false, NULL, NULL, NULL)
ON CONFLICT (modelo_id, ordem) DO NOTHING;

INSERT INTO servicos (id, empresa_id, nome_tecnico, tipo_recurso_id, duracao_minutos, preco_base, anamnese_obrigatoria, modelo_anamnese_id) VALUES
('aaaaaaaa-0000-0000-0000-000000000041', '00000000-0000-0000-0000-000000000001', 'teste_regras_anamnese', '11111111-1111-1111-1111-111111111111', 60, 80.00, true, 'bbbbbbbb-0000-0000-0000-000000000002')
ON CONFLICT (empresa_id, nome_tecnico) DO NOTHING;
INSERT INTO profissional_servicos (profissional_id, servico_id, empresa_id) VALUES
('dddddddd-0000-0000-0000-000000000001', 'aaaaaaaa-0000-0000-0000-000000000041', '00000000-0000-0000-0000-000000000001'),
('dddddddd-0000-0000-0000-000000000001', 'aaaaaaaa-0000-0000-0000-000000000002', '00000000-0000-0000-0000-000000000001')
ON CONFLICT DO NOTHING;

-- Helper: agenda com a Prof B e devolve {reserva_id, token, anamnese_id}
CREATE OR REPLACE FUNCTION teste_agenda_com_anamnese(p_servico TEXT, dow INT, hora TEXT, chave TEXT)
RETURNS JSONB
LANGUAGE plpgsql VOLATILE AS $$
DECLARE v JSONB; v_tok TEXT;
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

-- S1: respostas sem disparo â†’ liberada; token queima; reuso â†’ erro
DO $$
DECLARE v JSONB; v_estado TEXT;
BEGIN
    v := teste_agenda_com_anamnese('aaaaaaaa-0000-0000-0000-000000000041', 4, '14:00', 'sub-s1');
    v_estado := public.submeter_anamnese(v->>'token',
        jsonb_build_array(
            jsonb_build_object('pergunta_id','bbbbbbbb-0000-0000-0000-0000000000a1','resposta','nÃ£o'),
            jsonb_build_object('pergunta_id','bbbbbbbb-0000-0000-0000-0000000000a2','resposta','primeira vez')),
        true, 'Li e aceito o tratamento dos dados de saÃºde (LGPD)');

    ASSERT v_estado = 'liberada', format('S1: estado %s', v_estado);
    ASSERT (SELECT estado FROM anamneses WHERE id = (v->>'anamnese_id')::UUID) = 'liberada';
    ASSERT (SELECT consentimento_lgpd FROM anamneses WHERE id = (v->>'anamnese_id')::UUID) = true;
    ASSERT (SELECT COUNT(*) FROM anamnese_respostas WHERE anamnese_id = (v->>'anamnese_id')::UUID) = 2;
    ASSERT (SELECT usado FROM anamnese_tokens WHERE anamnese_id = (v->>'anamnese_id')::UUID) = true;

    BEGIN
        PERFORM public.submeter_anamnese(v->>'token', '[]'::JSONB, true, 'termo');
        RAISE EXCEPTION 'S1 FALHOU: token reutilizado';
    EXCEPTION WHEN OTHERS THEN
        ASSERT SQLERRM LIKE '%Link invÃ¡lido%', format('S1 reuso erro inesperado: %s', SQLERRM);
    END;
    RAISE NOTICE 'S1 OK â€” ficha liberada, respostas gravadas, token queimado';
END $$;

-- S2: regra dispara ("sim" na alergia) â†’ requer_avaliacao + staff notificado â€” COMO ANON
DO $$
DECLARE v JSONB;
BEGIN
    v := teste_agenda_com_anamnese('aaaaaaaa-0000-0000-0000-000000000041', 4, '15:00', 'sub-s2');
    PERFORM set_config('app.sub.s2_token', v->>'token', false);
    PERFORM set_config('app.sub.s2_anam', v->>'anamnese_id', false);
END $$;

SET ROLE anon;
SELECT set_config('request.jwt.claims', '{"role":"anon"}', false);
DO $$
DECLARE v_estado TEXT;
BEGIN
    v_estado := public.submeter_anamnese(current_setting('app.sub.s2_token'),
        jsonb_build_array(jsonb_build_object('pergunta_id','bbbbbbbb-0000-0000-0000-0000000000a1','resposta','Sim')),
        true, 'termo');
    ASSERT v_estado = 'requer_avaliacao', format('S2: estado %s', v_estado);
    RAISE NOTICE 'S2 OK â€” regra disparou via ANON (link pÃºblico): requer_avaliacao';
END $$;
RESET ROLE;

DO $$
BEGIN
    ASSERT (SELECT estado FROM anamneses WHERE id = current_setting('app.sub.s2_anam')::UUID) = 'requer_avaliacao';
    ASSERT EXISTS (SELECT 1 FROM notificacoes_internas WHERE tipo = 'anamnese_requer_avaliacao'
                   AND mensagem LIKE '%' || current_setting('app.sub.s2_anam') || '%'),
        'S2: staff devia ter sido notificado';
    RAISE NOTICE 'S2b OK â€” ficha na fila da profissional com notificaÃ§Ã£o ao staff';
END $$;

-- S3+S5: obrigatÃ³ria em falta â†’ erro; sem consentimento â†’ erro; depois correto â†’ liberada
DO $$
DECLARE v JSONB;
BEGIN
    v := teste_agenda_com_anamnese('aaaaaaaa-0000-0000-0000-000000000041', 4, '16:00', 'sub-s3');
    PERFORM set_config('app.sub.s3_token', v->>'token', false);
    PERFORM set_config('app.sub.s3_anam', v->>'anamnese_id', false);

    BEGIN
        PERFORM public.submeter_anamnese(v->>'token',
            jsonb_build_array(jsonb_build_object('pergunta_id','bbbbbbbb-0000-0000-0000-0000000000a2','resposta','sÃ³ a opcional')),
            true, 'termo');
        RAISE EXCEPTION 'S3 FALHOU: obrigatÃ³ria em falta aceite';
    EXCEPTION WHEN OTHERS THEN
        ASSERT SQLERRM LIKE '%obrigatÃ³ria%', format('S3 erro inesperado: %s', SQLERRM);
        RAISE NOTICE 'S3 OK â€” obrigatÃ³ria em falta rejeitada';
    END;

    BEGIN
        PERFORM public.submeter_anamnese(v->>'token',
            jsonb_build_array(jsonb_build_object('pergunta_id','bbbbbbbb-0000-0000-0000-0000000000a1','resposta','nÃ£o')),
            false, NULL);
        RAISE EXCEPTION 'S5 FALHOU: sem consentimento aceite';
    EXCEPTION WHEN OTHERS THEN
        ASSERT SQLERRM LIKE '%consentimento%', format('S5 erro inesperado: %s', SQLERRM);
        RAISE NOTICE 'S5 OK â€” LGPD: sem consentimento nÃ£o entra';
    END;

    -- o token SOBREVIVEU aos erros (rollback por tentativa): corrigir e enviar funciona
    PERFORM public.submeter_anamnese(v->>'token',
        jsonb_build_array(jsonb_build_object('pergunta_id','bbbbbbbb-0000-0000-0000-0000000000a1','resposta','nÃ£o')),
        true, 'termo');
    ASSERT (SELECT estado FROM anamneses WHERE id = (v->>'anamnese_id')::UUID) = 'liberada';
    RAISE NOTICE 'S3b OK â€” erros nÃ£o queimam o token; correÃ§Ã£o entra';
END $$;

-- S4: pergunta de OUTRO modelo â†’ erro
DO $$
DECLARE v JSONB;
BEGIN
    v := teste_agenda_com_anamnese('aaaaaaaa-0000-0000-0000-000000000041', 5, '10:00', 'sub-s4');
    BEGIN
        PERFORM public.submeter_anamnese(v->>'token',
            jsonb_build_array(
                jsonb_build_object('pergunta_id','bbbbbbbb-0000-0000-0000-0000000000a1','resposta','nÃ£o'),
                jsonb_build_object('pergunta_id', (SELECT id FROM modelo_perguntas WHERE modelo_id = 'bbbbbbbb-0000-0000-0000-000000000001' LIMIT 1),'resposta','intrusa')),
            true, 'termo');
        RAISE EXCEPTION 'S4 FALHOU: pergunta estranha ao modelo aceite';
    EXCEPTION WHEN OTHERS THEN
        ASSERT SQLERRM LIKE '%nÃ£o pertence%', format('S4 erro inesperado: %s', SQLERRM);
        RAISE NOTICE 'S4 OK â€” resposta para pergunta de outro modelo rejeitada';
    END;
END $$;

-- S6: token expirado â†’ erro claro; regenerar devolve NOVO token que funciona
DO $$
DECLARE v JSONB; v_novo TEXT; v_estado TEXT;
BEGIN
    v := teste_agenda_com_anamnese('aaaaaaaa-0000-0000-0000-000000000041', 2, '09:00', 'sub-s6');
    UPDATE anamnese_tokens SET expira_em = now() - interval '1 minute'
    WHERE anamnese_id = (v->>'anamnese_id')::UUID;

    BEGIN
        PERFORM public.submeter_anamnese(v->>'token',
            jsonb_build_array(jsonb_build_object('pergunta_id','bbbbbbbb-0000-0000-0000-0000000000a1','resposta','nÃ£o')),
            true, 'termo');
        RAISE EXCEPTION 'S6 FALHOU: token expirado aceite';
    EXCEPTION WHEN OTHERS THEN
        ASSERT SQLERRM LIKE '%expirou%', format('S6 erro inesperado: %s', SQLERRM);
        RAISE NOTICE 'S6 OK â€” expirado rejeitado com mensagem Ãºtil';
    END;

    v_novo := public.regenerar_token_anamnese((v->>'anamnese_id')::UUID);
    ASSERT v_novo IS NOT NULL AND v_novo <> v->>'token';
    v_estado := public.submeter_anamnese(v_novo,
        jsonb_build_array(jsonb_build_object('pergunta_id','bbbbbbbb-0000-0000-0000-0000000000a1','resposta','nÃ£o')),
        true, 'termo');
    ASSERT v_estado = 'liberada';
    RAISE NOTICE 'S6b OK â€” regeneraÃ§Ã£o (sÃ³ equipe) emite novo link funcional';
END $$;

-- S7: ficha respondida NÃƒO aceita segunda submissÃ£o nem com token novo
DO $$
DECLARE v_anam UUID := current_setting('app.sub.s3_anam')::UUID; v_tok TEXT;
BEGIN
    v_tok := public.regenerar_token_anamnese(v_anam);
    BEGIN
        PERFORM public.submeter_anamnese(v_tok,
            jsonb_build_array(jsonb_build_object('pergunta_id','bbbbbbbb-0000-0000-0000-0000000000a1','resposta','sim')),
            true, 'termo');
        RAISE EXCEPTION 'S7 FALHOU: ficha jÃ¡ respondida re-submetida';
    EXCEPTION WHEN OTHERS THEN
        ASSERT SQLERRM LIKE '%jÃ¡ foi respondida%', format('S7 erro inesperado: %s', SQLERRM);
        RAISE NOTICE 'S7 OK â€” ficha respondida Ã© terminal';
    END;
END $$;


-- =========================================================
-- SUÃTE 8: bloqueio_flow_test.sql
-- =========================================================

-- bloqueio_flow_test.sql (v3.4 NOVO) â€” criar_bloqueio_com_conflito (regressÃ£o Ricardo):
-- bloquear a agenda em cima de horÃ¡rio ocupado NÃƒO estoura exclusion_violation crua â€”
-- cancela os itens afetados pelo fluxo normal (regra 16h + revisÃ£o de valores) e avisa.
SET TIME ZONE 'America/Sao_Paulo';

CREATE OR REPLACE FUNCTION teste_proximo_dia(dow INT, hora TEXT) RETURNS TIMESTAMPTZ
LANGUAGE sql STABLE AS $$
    SELECT ((CURRENT_DATE + ((dow - EXTRACT(DOW FROM CURRENT_DATE)::INT + 7) % 7 + 7))::TEXT || ' ' || hora)::TIMESTAMPTZ
$$;

INSERT INTO profissional_servicos (profissional_id, servico_id, empresa_id) VALUES
('dddddddd-0000-0000-0000-000000000001', 'aaaaaaaa-0000-0000-0000-000000000011', '00000000-0000-0000-0000-000000000001')
ON CONFLICT DO NOTHING;

-- B1: reserva confirmada paga + bloqueio por cima â†’ cancelada com revisÃ£o CHEIA + aviso na fila
DO $$
DECLARE v_r UUID; v_inicio TIMESTAMPTZ; v_res JSONB; v_valor DECIMAL;
BEGIN
    v_r := teste_cria_reserva(5, '14:00', 'bloq-b1');
    PERFORM teste_paga_sinal(v_r, 'sinal', 30.00);
    PERFORM public.confirmar_reserva(v_r);
    v_inicio := teste_proximo_dia(5, '13:00');

    v_res := public.criar_bloqueio_com_conflito(
        '33333333-3333-3333-3333-333333333333', v_inicio, v_inicio + interval '2 hours',
        'imprevisto', 'Encanador estourou no salÃ£o');

    ASSERT (v_res->>'itens_cancelados')::INT = 1, format('B1: itens %s', v_res->>'itens_cancelados');
    ASSERT (SELECT estado FROM reservas WHERE id = v_r) = 'cancelada';
    SELECT valor_sinal INTO v_valor FROM revisoes_cancelamento WHERE reserva_id = v_r;
    ASSERT v_valor = 30.00, format('B1: revisÃ£o devia ter o sinal CHEIO (R$ 30), veio %s', v_valor);
    ASSERT EXISTS (SELECT 1 FROM agenda_ocupacoes
                   WHERE origem = 'bloqueio' AND origem_id = (v_res->>'bloqueio_id')::UUID AND estado = 'ativa'),
        'B1: ocupaÃ§Ã£o do bloqueio devia estar ativa';
    ASSERT EXISTS (SELECT 1 FROM jobs WHERE tipo = 'notificar_cliente_cancelamento'
                   AND payload->>'reserva_id' = v_r::TEXT),
        'B1: aviso ao cliente devia estar enfileirado';
    RAISE NOTICE 'B1 OK â€” bloqueio com conflito: reserva cancelada, revisÃ£o de R$ %, cliente avisado', v_valor;
END $$;

-- B2: reserva de DOIS itens â€” bloqueio atinge sÃ³ a Laira; o item da Prof B sobrevive
DO $$
DECLARE v_r UUID; v_item_laira UUID; v_item_profb UUID; v_inicio TIMESTAMPTZ; v_res JSONB; v_valor DECIMAL;
BEGIN
    v_r := (public.criar_pre_reserva('00000000-0000-0000-0000-000000000001',
        'cccccccc-0000-0000-0000-000000000011',
        jsonb_build_array(
            jsonb_build_object('servico_id','aaaaaaaa-0000-0000-0000-000000000011',
                'profissional_id','33333333-3333-3333-3333-333333333333', 'cardapio','ella_studio', 'inicio', teste_proximo_dia(3,'15:00')),
            jsonb_build_object('servico_id','aaaaaaaa-0000-0000-0000-000000000011',
                'profissional_id','dddddddd-0000-0000-0000-000000000001', 'cardapio','ella_studio', 'inicio', teste_proximo_dia(3,'15:00'))
        ), 'bloq-b2') ->> 'reserva_id')::UUID;
    PERFORM teste_paga_sinal(v_r, 'sinal', 60.00);
    PERFORM public.confirmar_reserva(v_r);

    SELECT id INTO v_item_laira FROM reserva_itens WHERE reserva_id = v_r
        AND profissional_id = '33333333-3333-3333-3333-333333333333';
    SELECT id INTO v_item_profb FROM reserva_itens WHERE reserva_id = v_r
        AND profissional_id = 'dddddddd-0000-0000-0000-000000000001';
    v_inicio := teste_proximo_dia(3, '15:00');

    v_res := public.criar_bloqueio_com_conflito(
        '33333333-3333-3333-3333-333333333333', v_inicio, v_inicio + interval '1 hour',
        'folga', 'Consulta mÃ©dica da Laira');

    ASSERT (v_res->>'itens_cancelados')::INT = 1, format('B2: devia cancelar 1 item, cancelou %s', v_res->>'itens_cancelados');
    ASSERT (SELECT estado FROM reserva_itens WHERE id = v_item_laira) = 'cancelado';
    ASSERT (SELECT estado FROM reserva_itens WHERE id = v_item_profb) = 'confirmado',
        'B2: item da Prof B devia sobreviver';
    ASSERT (SELECT estado FROM reservas WHERE id = v_r) = 'confirmada';
    SELECT valor_sinal INTO v_valor FROM revisoes_cancelamento WHERE reserva_item_id = v_item_laira;
    ASSERT v_valor = 30.00, format('B2: revisÃ£o proporcional devia ser 30.00, veio %s', v_valor);
    ASSERT (SELECT COUNT(*) FROM agenda_ocupacoes WHERE reserva_item_id = v_item_profb AND estado = 'ativa') = 2;
    RAISE NOTICE 'B2 OK â€” bloqueio cirÃºrgico: sÃ³ o item da Laira cai (revisÃ£o R$ %), Prof B intacta', v_valor;
END $$;

-- B3: INSERT direto de bloqueio em cima de horÃ¡rio ocupado CONTINUA protegido pelo EXCLUDE
-- (a RPC Ã© o caminho certo; o banco Ã© a rede de seguranÃ§a)
DO $$
DECLARE v_inicio TIMESTAMPTZ;
BEGIN
    v_inicio := teste_proximo_dia(3, '15:00');
    BEGIN
        INSERT INTO bloqueios (empresa_id, profissional_id, inicio, fim, motivo, tipo)
        VALUES ('00000000-0000-0000-0000-000000000001', 'dddddddd-0000-0000-0000-000000000001',
                v_inicio, v_inicio + interval '1 hour', 'direto no banco', 'folga');
        RAISE EXCEPTION 'B3 FALHOU: INSERT direto passou por cima de ocupaÃ§Ã£o ativa';
    EXCEPTION WHEN OTHERS THEN
        ASSERT SQLERRM LIKE '%exclude_profissional_conflito%' OR SQLERRM LIKE '%conflicting key%', format('B3 erro inesperado: %s', SQLERRM);
        RAISE NOTICE 'B3 OK â€” EXCLUDE continua a proteger a agenda (rede de seguranÃ§a)';
    END;
END $$;

-- B4: bloqueio sem conflito nenhum â†’ cria direto, zero cancelamentos
DO $$
DECLARE v_res JSONB; v_inicio TIMESTAMPTZ;
BEGIN
    v_inicio := teste_proximo_dia(6, '11:30');
    v_res := public.criar_bloqueio_com_conflito(
        'dddddddd-0000-0000-0000-000000000001', v_inicio, v_inicio + interval '30 minutes',
        'almoco', 'AlmoÃ§o Prof B');
    ASSERT (v_res->>'itens_cancelados')::INT = 0;
    RAISE NOTICE 'B4 OK â€” bloqueio limpo sem efeitos colaterais';
END $$;


-- =========================================================
-- SUÃTE 9: v341_fixes_test.sql
-- =========================================================

-- v341_fixes_test.sql â€” provas das 9 correÃ§Ãµes da auditoria v3.4 â†’ v3.4.1
-- Corre DEPOIS das 8 suÃ­tes anteriores (usa as fixtures delas).
SET TIME ZONE 'America/Sao_Paulo';

CREATE OR REPLACE FUNCTION teste_proximo_dia(dow INT, hora TEXT) RETURNS TIMESTAMPTZ
LANGUAGE sql STABLE AS $$
    SELECT ((CURRENT_DATE + ((dow - EXTRACT(DOW FROM CURRENT_DATE)::INT + 7) % 7 + 7))::TEXT || ' ' || hora)::TIMESTAMPTZ
$$;

-- Prof C (terceira profissional) â€” usada para nÃ£o colidir com os slots das suites anteriores
INSERT INTO profissionais (id, empresa_id, nome) VALUES
('dddddddd-0000-0000-0000-00000000000c', '00000000-0000-0000-0000-000000000001', 'Prof C Testes')
ON CONFLICT (id) DO NOTHING;
INSERT INTO horarios_profissional (profissional_id, dia_semana, abertura, fechamento) VALUES
('dddddddd-0000-0000-0000-00000000000c', 2, '09:00', '17:00'),
('dddddddd-0000-0000-0000-00000000000c', 3, '09:00', '17:00'),
('dddddddd-0000-0000-0000-00000000000c', 4, '09:00', '17:00'),
('dddddddd-0000-0000-0000-00000000000c', 5, '09:00', '17:00'),
('dddddddd-0000-0000-0000-00000000000c', 6, '09:00', '13:00')
ON CONFLICT DO NOTHING;
INSERT INTO profissional_servicos (profissional_id, servico_id, empresa_id) VALUES
('dddddddd-0000-0000-0000-00000000000c', 'aaaaaaaa-0000-0000-0000-000000000011', '00000000-0000-0000-0000-000000000001'),
('dddddddd-0000-0000-0000-00000000000c', 'aaaaaaaa-0000-0000-0000-000000000031', '00000000-0000-0000-0000-000000000001')
ON CONFLICT DO NOTHING;

-- F1 (auditoria #1): cancelar os DOIS itens um a um â†’ a fila vale EXATAMENTE o pago
DO $$
DECLARE v_r UUID; v_i1 UUID; v_i2 UUID; v_soma DECIMAL; v_n INT;
BEGIN
    v_r := (public.criar_pre_reserva('00000000-0000-0000-0000-000000000001',
        'cccccccc-0000-0000-0000-000000000011',
        jsonb_build_array(
            jsonb_build_object('servico_id','aaaaaaaa-0000-0000-0000-000000000011',
                'profissional_id','dddddddd-0000-0000-0000-00000000000c', 'cardapio','ella_studio', 'inicio', teste_proximo_dia(4,'09:00')),
            jsonb_build_object('servico_id','aaaaaaaa-0000-0000-0000-000000000011',
                'profissional_id','dddddddd-0000-0000-0000-00000000000c', 'cardapio','ella_studio', 'inicio', teste_proximo_dia(5,'12:00'))
        ), 'f1-dupla') ->> 'reserva_id')::UUID;
    PERFORM teste_paga_sinal(v_r, 'sinal', 60.00);
    PERFORM public.confirmar_reserva(v_r);

    SELECT id INTO v_i1 FROM reserva_itens WHERE reserva_id = v_r ORDER BY inicio LIMIT 1;
    SELECT id INTO v_i2 FROM reserva_itens WHERE reserva_id = v_r ORDER BY inicio OFFSET 1 LIMIT 1;

    PERFORM public.cancelar_item_reserva(v_i1);
    PERFORM public.cancelar_item_reserva(v_i2);   -- Ãºltimo â†’ delega em cancelar_reserva

    SELECT COALESCE(SUM(valor_sinal),0), COUNT(*) INTO v_soma, v_n
    FROM revisoes_cancelamento WHERE reserva_id = v_r;
    ASSERT v_soma = 60.00, format('F1 REGRESSÃƒO (auditoria #1): fila com R$ %s por R$ 60 pagos â€” dinheiro contado em dobro', v_soma);
    ASSERT (SELECT estado FROM reservas WHERE id = v_r) = 'cancelada';
    RAISE NOTICE 'F1 OK â€” fila vale exatamente o pago (R$ % em % revisÃµes)', v_soma, v_n;
END $$;

-- F2 (auditoria #1): bloqueio pegando DOIS itens da mesma reserva â†’ mesma garantia
DO $$
DECLARE v_r UUID; v_inicio TIMESTAMPTZ; v_res JSONB; v_soma DECIMAL;
BEGIN
    v_r := (public.criar_pre_reserva('00000000-0000-0000-0000-000000000001',
        'cccccccc-0000-0000-0000-000000000011',
        jsonb_build_array(
            jsonb_build_object('servico_id','aaaaaaaa-0000-0000-0000-000000000011',
                'profissional_id','dddddddd-0000-0000-0000-00000000000c', 'cardapio','ella_studio', 'inicio', teste_proximo_dia(2,'14:00')),
            jsonb_build_object('servico_id','aaaaaaaa-0000-0000-0000-000000000011',
                'profissional_id','dddddddd-0000-0000-0000-00000000000c', 'cardapio','ella_studio', 'inicio', teste_proximo_dia(2,'16:00'))
        ), 'f2-bloqueio') ->> 'reserva_id')::UUID;
    PERFORM teste_paga_sinal(v_r, 'sinal', 60.00);
    PERFORM public.confirmar_reserva(v_r);
    v_inicio := teste_proximo_dia(2, '13:30');

    v_res := public.criar_bloqueio_com_conflito(
        'dddddddd-0000-0000-0000-00000000000c', v_inicio, v_inicio + interval '3 hours',
        'imprevisto', 'Prof C ficou doente');

    ASSERT (v_res->>'itens_cancelados')::INT = 2;
    SELECT COALESCE(SUM(valor_sinal),0) INTO v_soma FROM revisoes_cancelamento WHERE reserva_id = v_r;
    ASSERT v_soma = 60.00, format('F2 REGRESSÃƒO (auditoria #1): bloqueio em 2 itens gerou fila de R$ %s por R$ 60 pagos', v_soma);
    ASSERT (SELECT estado FROM reservas WHERE id = v_r) = 'cancelada';
    PERFORM set_config('app.f2.bloqueio', v_res->>'bloqueio_id', false);
    RAISE NOTICE 'F2 OK â€” bloqueio em 2 itens: fila de R$ % (sem dupla contagem)', v_soma;
END $$;

-- F3 (auditoria #3): percentual_sinal = 0 â†’ nasce CONFIRMADA, sem expires_at, cron nÃ£o toca
INSERT INTO servicos (id, empresa_id, nome_tecnico, tipo_recurso_id, duracao_minutos, preco_base, percentual_sinal, anamnese_obrigatoria) VALUES
('aaaaaaaa-0000-0000-0000-000000000051', '00000000-0000-0000-0000-000000000001', 'teste_sem_sinal', '11111111-1111-1111-1111-111111111111', 60, 120.00, 0, false)
ON CONFLICT (empresa_id, nome_tecnico) DO NOTHING;
INSERT INTO profissional_servicos (profissional_id, servico_id, empresa_id) VALUES
('dddddddd-0000-0000-0000-00000000000c', 'aaaaaaaa-0000-0000-0000-000000000051', '00000000-0000-0000-0000-000000000001')
ON CONFLICT DO NOTHING;

DO $$
DECLARE v JSONB; v_r UUID;
BEGIN
    v := public.criar_pre_reserva('00000000-0000-0000-0000-000000000001',
        'cccccccc-0000-0000-0000-000000000011',
        jsonb_build_array(jsonb_build_object('servico_id','aaaaaaaa-0000-0000-0000-000000000051',
            'profissional_id','dddddddd-0000-0000-0000-00000000000c', 'cardapio','ella_studio', 'inicio', teste_proximo_dia(3,'14:00'))),
        'f3-zero-sinal');
    v_r := (v->>'reserva_id')::UUID;

    ASSERT v->>'estado' = 'confirmada', format('F3: estado devolvido %s', v->>'estado');
    ASSERT (SELECT estado FROM reservas WHERE id = v_r) = 'confirmada',
        'F3 REGRESSÃƒO (auditoria #3): sinal zero nÃ£o nasceu confirmada â€” morreria em 30 min';
    ASSERT (SELECT COUNT(*) FROM agenda_ocupacoes
            WHERE origem = 'reserva' AND origem_id = v_r AND estado = 'ativa' AND expires_at IS NULL) = 2,
        'F3: ocupaÃ§Ãµes deviam ser definitivas (sem expires_at)';
    ASSERT (SELECT valor_sinal FROM cobrancas WHERE reserva_id = v_r) = 0;
    PERFORM public.expirar_pre_reservas();
    ASSERT (SELECT estado FROM reservas WHERE id = v_r) = 'confirmada', 'F3: cron mexeu em reserva sem sinal';
    RAISE NOTICE 'F3 OK â€” agenda vazia funciona: sinal 0 nasce confirmada e o cron ignora';
END $$;

-- F4 (auditoria #4): pagar 100% no balcÃ£o NÃƒO realiza; finalizar_atendimento sim â€” e sem MFA no caixa
DO $$
DECLARE v_r UUID; v_cob UUID; v_res JSONB;
BEGIN
    v_r := teste_cria_reserva(6, '09:00', 'f4-presencial');
    PERFORM teste_paga_sinal(v_r, 'sinal', 30.00);
    PERFORM public.confirmar_reserva(v_r);
    SELECT id INTO v_cob FROM cobrancas WHERE reserva_id = v_r;
    PERFORM set_config('app.f4.cob', v_cob::TEXT, false);
    PERFORM set_config('app.f4.r', v_r::TEXT, false);
END $$;

-- caixa autenticado com aal1 (sem TOTP) â€” decisÃ£o de negÃ³cio: dinheiro ENTRANDO nÃ£o exige MFA
SET ROLE authenticated;
SELECT set_config('request.jwt.claims', '{"sub":"ffffffff-0000-0000-0000-000000000001","role":"authenticated","aal":"aal1"}', false);
DO $$
DECLARE v_res JSONB;
BEGIN
    v_res := public.registrar_pagamento_presencial(
        current_setting('app.f4.cob')::UUID, 70.00, 'dinheiro', 'saldo', 'f4-caixa-1');
    ASSERT v_res->>'reserva_status' = 'confirmada', format('F4 REGRESSÃƒO (auditoria #4): pagamento marcou %s â€” pagar adiantado nÃ£o Ã© ter atendido', v_res->>'reserva_status');
    ASSERT (SELECT estado FROM cobrancas WHERE id = current_setting('app.f4.cob')::UUID) = 'total_pago';
    RAISE NOTICE 'F4a OK â€” total pago no balcÃ£o (aal1): cobranÃ§a fecha, atendimento NÃƒO vira realizado';
END $$;
RESET ROLE;
SELECT set_config('request.jwt.claims', '{}', false);

DO $$
BEGIN
    PERFORM public.finalizar_atendimento(current_setting('app.f4.r')::UUID);
    ASSERT (SELECT estado FROM reservas WHERE id = current_setting('app.f4.r')::UUID) = 'realizada';
    ASSERT (SELECT COUNT(*) FROM reserva_itens WHERE reserva_id = current_setting('app.f4.r')::UUID AND estado = 'realizado') = 1;
    BEGIN
        PERFORM public.cancelar_reserva(current_setting('app.f4.r')::UUID);
        RAISE EXCEPTION 'F4 FALHOU: cancelou atendimento jÃ¡ realizado';
    EXCEPTION WHEN OTHERS THEN
        ASSERT SQLERRM LIKE '%nÃ£o pode ser cancelada%', format('F4 erro inesperado: %s', SQLERRM);
    END;
    RAISE NOTICE 'F4b OK â€” realizada Ã© aÃ§Ã£o da equipe e Ã© terminal';
END $$;

-- F5 (auditoria #5): resolver 'confirmar' nÃ£o reagenda o passado; e confirmaÃ§Ã£o apÃ³s cron revive os itens
DO $$
DECLARE v_rev UUID; v_r UUID;
BEGIN
    v_rev := teste_cria_revisao_atrasada(2, '15:00', 'f5-passado', 30.00);
    SELECT reserva_id INTO v_r FROM revisoes_cancelamento WHERE id = v_rev;
    UPDATE reserva_itens SET inicio = now() - interval '2 days', fim = now() - interval '2 days' + interval '1 hour'
    WHERE reserva_id = v_r;
    BEGIN
        PERFORM public.resolver_revisao(v_rev, 'confirmar', 'pix caiu 3 dias depois');
        RAISE EXCEPTION 'F5 FALHOU: reagendou no passado';
    EXCEPTION WHEN OTHERS THEN
        ASSERT SQLERRM LIKE '%jÃ¡ passou%', format('F5 erro inesperado: %s', SQLERRM);
        RAISE NOTICE 'F5a OK â€” passado nÃ£o se reagenda: %', SQLERRM;
    END;
    PERFORM public.resolver_revisao(v_rev, 'credito', 'horÃ¡rio jÃ¡ era');
    ASSERT (SELECT decisao_final FROM revisoes_cancelamento WHERE id = v_rev) = 'credito';
END $$;

DO $$
DECLARE v_r UUID; v_cob UUID; v_rev UUID; v_res JSONB;
BEGIN
    -- cron expira SEM pagamento (v3.4.1b: itens ficam 'pendente'), webhook chega depois â†’ revisÃ£o â†’ confirmar
    v_r := teste_cria_reserva(2, '15:00', 'f5b-cron-webhook');
    SELECT id INTO v_cob FROM cobrancas WHERE reserva_id = v_r;
    UPDATE agenda_ocupacoes SET expires_at = now() - interval '1 minute'
    WHERE origem = 'pre_reserva' AND origem_id = v_r;
    PERFORM public.expirar_pre_reservas();
    ASSERT (SELECT estado FROM reservas WHERE id = v_r) = 'expirada';
    ASSERT (SELECT COUNT(*) FROM reserva_itens WHERE reserva_id = v_r AND estado = 'pendente') = 1,
        'F5b: v3.4.1b â€” cron nÃ£o-pago deixa itens pendente (cancelado = sÃ³ desistÃªncia)';

    v_res := public.processar_pagamento_webhook('mercado_pago', 'evt-f5b', 30.00, NULL, v_cob, 'mp-f5b', '{}'::JSONB, true);
    ASSERT v_res->>'status' = 'pagamento_em_revisao';
    SELECT id INTO v_rev FROM revisoes_cancelamento WHERE reserva_id = v_r AND decisao_final IS NULL;

    v_res := public.resolver_revisao(v_rev, 'confirmar', 'cliente provou o pix');
    ASSERT v_res->>'reserva_status' = 'confirmada', format('F5b: status %s', v_res->>'reserva_status');
    ASSERT (SELECT COUNT(*) FROM reserva_itens WHERE reserva_id = v_r AND estado = 'confirmado') = 1,
        'F5b REGRESSÃƒO: reserva confirmada SEM itens (bug do cron)';
    ASSERT (SELECT COUNT(*) FROM agenda_ocupacoes
            WHERE origem = 'reserva' AND origem_id = v_r AND estado = 'ativa' AND expires_at IS NULL) = 2,
        'F5b REGRESSÃƒO: ocupaÃ§Ãµes nÃ£o foram recriadas';
    RAISE NOTICE 'F5b OK â€” cronâ†’webhookâ†’confirmar: reserva completa (item revivido + 2 ocupaÃ§Ãµes)';
END $$;

-- F6 (auditoria #6): tabelas de workflow/dinheiro tambÃ©m sÃ£o 100% RPC
SET ROLE authenticated;
SELECT set_config('request.jwt.claims', '{"sub":"ffffffff-0000-0000-0000-000000000001","role":"authenticated","aal":"aal2"}', false);
DO $$
DECLARE v_rev UUID;
BEGIN
    BEGIN
        INSERT INTO bloqueios (empresa_id, profissional_id, inicio, fim, motivo, tipo)
        VALUES ('00000000-0000-0000-0000-000000000001', '33333333-3333-3333-3333-333333333333',
                now() + interval '30 days', now() + interval '30 days 1 hour', 'direto', 'folga');
        RAISE EXCEPTION 'F6 FALHOU: admin inseriu bloqueio direto';
    EXCEPTION WHEN OTHERS THEN
        ASSERT SQLERRM LIKE '%permission denied%', format('F6a erro inesperado: %s', SQLERRM);
        RAISE NOTICE 'F6a OK â€” bloqueios sÃ³ via RPC (o frontend nÃ£o consegue recriar o 23P01)';
    END;

    SELECT id INTO v_rev FROM revisoes_cancelamento WHERE decisao_final IS NULL LIMIT 1;
    IF v_rev IS NOT NULL THEN
        BEGIN
            UPDATE revisoes_cancelamento SET decisao_final = 'perdido' WHERE id = v_rev;
            RAISE EXCEPTION 'F6 FALHOU: admin decidiu revisÃ£o na mÃ£o (sem MFA, sem resolver_revisao)';
        EXCEPTION WHEN OTHERS THEN
            ASSERT SQLERRM LIKE '%permission denied%', format('F6b erro inesperado: %s', SQLERRM);
            RAISE NOTICE 'F6b OK â€” decisÃ£o de revisÃ£o sÃ³ via resolver_revisao (com MFA)';
        END;
    END IF;

    BEGIN
        INSERT INTO lancamentos_creditos (conta_id, tipo_lancamento, valor, saldo_apos, idempotencia_key)
        SELECT conta_id, 'credito_cancelamento', 999, 999, 'fraude' FROM lancamentos_creditos LIMIT 1;
        RAISE EXCEPTION 'F6 FALHOU: admin criou crÃ©dito na mÃ£o';
    EXCEPTION WHEN OTHERS THEN
        ASSERT SQLERRM LIKE '%permission denied%' OR SQLERRM LIKE '%null value%', format('F6c erro inesperado: %s', SQLERRM);
        RAISE NOTICE 'F6c OK â€” crÃ©ditos sÃ³ via resolver_revisao';
    END;
END $$;
RESET ROLE;
SELECT set_config('request.jwt.claims', '{}', false);

-- remover_bloqueio: a saÃ­da operacional com o REVOKE em vigor
DO $$
BEGIN
    PERFORM public.remover_bloqueio(current_setting('app.f2.bloqueio')::UUID);
    ASSERT NOT EXISTS (SELECT 1 FROM bloqueios WHERE id = current_setting('app.f2.bloqueio')::UUID);
    ASSERT NOT EXISTS (SELECT 1 FROM agenda_ocupacoes
        WHERE origem = 'bloqueio' AND origem_id = current_setting('app.f2.bloqueio')::UUID AND estado = 'ativa');
    RAISE NOTICE 'F6d OK â€” remover_bloqueio remove e liberta as ocupaÃ§Ãµes';
END $$;

-- F7 (parcial vencido): parcela de sinal SEM complemento nÃ£o prende o horÃ¡rio â€” vai Ã  fila
DO $$
DECLARE v_r UUID; v_valor DECIMAL;
BEGIN
    v_r := teste_cria_reserva(5, '16:00', 'f7-parcial');
    PERFORM teste_paga_sinal(v_r, 'saldo', 10.00);   -- parcela de 10 de um sinal de 30
    UPDATE agenda_ocupacoes SET expires_at = now() - interval '1 minute'
    WHERE origem = 'pre_reserva' AND origem_id = v_r;
    PERFORM public.expirar_pre_reservas();

    ASSERT (SELECT estado FROM reservas WHERE id = v_r) = 'pagamento_em_revisao',
        'F7 REGRESSÃƒO: parcial vencido ficou preso em pre_reserva';
    ASSERT NOT EXISTS (SELECT 1 FROM agenda_ocupacoes WHERE origem_id = v_r AND estado = 'ativa'),
        'F7 REGRESSÃƒO: parcial vencido continua a prender o slot';
    SELECT valor_sinal INTO v_valor FROM revisoes_cancelamento WHERE reserva_id = v_r;
    ASSERT v_valor = 10.00, format('F7: revisÃ£o devia ser pela parcela (10.00), veio %s', v_valor);
    PERFORM teste_cria_reserva(5, '16:00', 'f7-remarcacao');  -- o horÃ¡rio foi mesmo libertado
    RAISE NOTICE 'F7 OK â€” parcial vencido: fila de R$ % + horÃ¡rio re-agendÃ¡vel', v_valor;
END $$;

-- F8 (menor): ficha de agendamento cancelado nÃ£o se responde
DO $$
DECLARE v JSONB;
BEGIN
    v := teste_agenda_com_anamnese('aaaaaaaa-0000-0000-0000-000000000041', 2, '13:30', 'f8-anamnese-morta');
    PERFORM public.cancelar_pre_reserva((v->>'reserva_id')::UUID);
    BEGIN
        PERFORM public.submeter_anamnese(v->>'token',
            jsonb_build_array(jsonb_build_object('pergunta_id','bbbbbbbb-0000-0000-0000-0000000000a1','resposta','nÃ£o')),
            true, 'termo');
        RAISE EXCEPTION 'F8 FALHOU: ficha de reserva cancelada aceite';
    EXCEPTION WHEN OTHERS THEN
        ASSERT SQLERRM LIKE '%jÃ¡ nÃ£o estÃ¡ ativo%', format('F8 erro inesperado: %s', SQLERRM);
        RAISE NOTICE 'F8 OK â€” ficha de agendamento morto rejeitada';
    END;
END $$;

-- F10 (menor): expirada tem saÃ­da â€” cancelar_pre_reserva limpa
DO $$
DECLARE v_r UUID;
BEGIN
    v_r := teste_cria_reserva(4, '15:00', 'f10-expirada');
    UPDATE agenda_ocupacoes SET expires_at = now() - interval '1 minute'
    WHERE origem = 'pre_reserva' AND origem_id = v_r;
    PERFORM public.expirar_pre_reservas();
    ASSERT (SELECT estado FROM reservas WHERE id = v_r) = 'expirada';
    PERFORM public.cancelar_pre_reserva(v_r);
    ASSERT (SELECT estado FROM reservas WHERE id = v_r) = 'cancelada';
    ASSERT (SELECT estado FROM cobrancas WHERE reserva_id = v_r) = 'cancelada';
    RAISE NOTICE 'F10 OK â€” expirada deixou de ser um estado sem saÃ­da';
END $$;

-- F11 (auditoria v3.4.1 â€” GRAVE): revisÃ£o decidida 'confirmar' NÃƒO pode
-- descontar da fila â€” o dinheiro voltou Ã  reserva viva. Sem o filtro
-- IS DISTINCT FROM 'confirmar', um cancelamento posterior calculava 30 âˆ’ 30 = 0
-- e R$ 30 ficava sem destino e sem rasto.
DO $$
DECLARE v_r UUID; v_cob UUID; v_rev UUID; v_res JSONB; v_soma DECIMAL;
BEGIN
    v_r := (public.criar_pre_reserva('00000000-0000-0000-0000-000000000001',
        'cccccccc-0000-0000-0000-000000000011',
        jsonb_build_array(jsonb_build_object('servico_id','aaaaaaaa-0000-0000-0000-000000000011',
            'profissional_id','dddddddd-0000-0000-0000-00000000000c', 'cardapio','ella_studio', 'inicio', teste_proximo_dia(3,'16:00'))),
        'f11-grave')) ->> 'reserva_id';
    SELECT id INTO v_cob FROM cobrancas WHERE reserva_id = v_r;

    -- sinal cai fora do prazo: cron expira, webhook confirma o atrasado, admin confirma
    UPDATE agenda_ocupacoes SET expires_at = now() - interval '1 minute'
    WHERE origem = 'pre_reserva' AND origem_id = v_r;
    PERFORM public.expirar_pre_reservas();
    v_res := public.processar_pagamento_webhook('mercado_pago', 'evt-f11', 30.00, NULL, v_cob, 'mp-f11', '{}'::JSONB, true);
    ASSERT v_res->>'status' = 'pagamento_em_revisao';
    SELECT id INTO v_rev FROM revisoes_cancelamento WHERE reserva_id = v_r AND decisao_final IS NULL;
    v_res := public.resolver_revisao(v_rev, 'confirmar', 'horÃ¡rio livre, cliente provou o pix');
    ASSERT (SELECT estado FROM reservas WHERE id = v_r) = 'confirmada';
    ASSERT (SELECT decisao_final FROM revisoes_cancelamento WHERE id = v_rev) = 'confirmar';

    -- semanas depois a cliente cancela: a fila TEM de nascer com os R$ 30 outra vez
    PERFORM public.cancelar_reserva(v_r, NULL, 'cliente desistiu');
    SELECT COALESCE(SUM(valor_sinal), 0) INTO v_soma
    FROM revisoes_cancelamento WHERE reserva_id = v_r AND decisao_final IS NULL;
    ASSERT v_soma = 30.00, format('F11 REGRESSÃƒO (GRAVE): cancelamento apÃ³s confirmar abriu fila de R$ %s â€” devia ser R$ 30.00 (o confirmar devolveu o dinheiro Ã  reserva)', v_soma);
    ASSERT (SELECT estado FROM reservas WHERE id = v_r) = 'cancelada';
    RAISE NOTICE 'F11 OK â€” confirmar nÃ£o desconta: cancelamento posterior reabre fila de R$ 30';
END $$;

-- F12 (auditoria v3.4.1 â€” MÃ‰DIO): resolver('confirmar') NÃƒO ressuscita item que a
-- cliente cancelou de propÃ³sito. PrÃ©-reserva com 2 serviÃ§os, desistÃªncia de um
-- (sem dinheiro â†’ sem revisÃ£o), sinal atrasado, admin confirma â†’ sÃ³ o item
-- 'pendente' volta; o 'cancelado' fica cancelado.
DO $$
DECLARE v_r UUID; v_cob UUID; v_rev UUID; v_i1 UUID; v_i2 UUID; v_res JSONB; v_soma DECIMAL;
BEGIN
    v_r := (public.criar_pre_reserva('00000000-0000-0000-0000-000000000001',
        'cccccccc-0000-0000-0000-000000000011',
        jsonb_build_array(
            jsonb_build_object('servico_id','aaaaaaaa-0000-0000-0000-000000000011',
                'profissional_id','dddddddd-0000-0000-0000-00000000000c', 'cardapio','ella_studio', 'inicio', teste_proximo_dia(6,'10:00')),
            jsonb_build_object('servico_id','aaaaaaaa-0000-0000-0000-000000000011',
                'profissional_id','dddddddd-0000-0000-0000-00000000000c', 'cardapio','ella_studio', 'inicio', teste_proximo_dia(6,'11:00'))),
        'f12-medio')) ->> 'reserva_id';
    SELECT id INTO v_cob FROM cobrancas WHERE reserva_id = v_r;
    SELECT id INTO v_i1 FROM reserva_itens WHERE reserva_id = v_r ORDER BY inicio LIMIT 1;
    SELECT id INTO v_i2 FROM reserva_itens WHERE reserva_id = v_r ORDER BY inicio OFFSET 1 LIMIT 1;

    -- cliente desiste do 2.Âº serviÃ§o ANTES de pagar (sem dinheiro â†’ sem revisÃ£o)
    PERFORM public.cancelar_item_reserva(v_i2, NULL, 'cliente desistiu deste serviÃ§o');
    ASSERT (SELECT estado FROM reserva_itens WHERE id = v_i2) = 'cancelado';
    ASSERT NOT EXISTS (SELECT 1 FROM revisoes_cancelamento WHERE reserva_id = v_r);

    -- sinal chega atrasado: cron expira (v3.4.1b: itens ficam pendente), webhook, admin confirma
    UPDATE agenda_ocupacoes SET expires_at = now() - interval '1 minute'
    WHERE origem = 'pre_reserva' AND origem_id = v_r;
    PERFORM public.expirar_pre_reservas();
    v_res := public.processar_pagamento_webhook('mercado_pago', 'evt-f12', 30.00, NULL, v_cob, 'mp-f12', '{}'::JSONB, true);
    ASSERT v_res->>'status' = 'pagamento_em_revisao';
    SELECT id INTO v_rev FROM revisoes_cancelamento WHERE reserva_id = v_r AND decisao_final IS NULL;
    v_res := public.resolver_revisao(v_rev, 'confirmar', 'horÃ¡rio livre');

    ASSERT (SELECT estado FROM reserva_itens WHERE id = v_i1) = 'confirmado',
        'F12: item pendente devia ter sido revivido';
    ASSERT (SELECT estado FROM reserva_itens WHERE id = v_i2) = 'cancelado',
        'F12 REGRESSÃƒO (MÃ‰DIO): item recusado pela cliente foi RESSUSCITADO pelo confirmar';
    ASSERT (SELECT COUNT(*) FROM agenda_ocupacoes
            WHERE origem = 'reserva' AND origem_id = v_r AND estado = 'ativa') = 2,
        'F12 REGRESSÃƒO: ocupaÃ§Ãµes a mais â€” item cancelado voltou Ã  agenda';

    -- bÃ³nus (amarra F11 ao caminho do item): cancelar o item revivido â†’ fila com os R$ 30
    PERFORM public.cancelar_item_reserva(v_i1, NULL, 'cliente cancelou tudo');
    SELECT COALESCE(SUM(valor_sinal), 0) INTO v_soma
    FROM revisoes_cancelamento WHERE reserva_id = v_r AND decisao_final IS NULL;
    ASSERT v_soma = 30.00, format('F12/F11 REGRESSÃƒO: fila de R$ %s apÃ³s cancelar item confirmado â€” devia ser R$ 30.00', v_soma);
    RAISE NOTICE 'F12 OK â€” confirmar revive sÃ³ pendente; item recusado nÃ£o volta (e cancelar depois abre fila certa)';
END $$;

-- F13 (achado da prova de corrida F9 â€” GRAVE): webhook de saldo chega DEPOIS do
-- cancelamento. Antes: a revisÃ£o aberta (30) fazia o Ã­ndice Ãºnico engolir o novo
-- INSERT (100) â†’ R$ 70 sem rasto. Agora a fila aberta Ã© completada para o pago total.
DO $$
DECLARE v_r UUID; v_cob UUID; v_res JSONB; v_soma DECIMAL; v_n INT;
BEGIN
    v_r := (public.criar_pre_reserva('00000000-0000-0000-0000-000000000001',
        'cccccccc-0000-0000-0000-000000000011',
        jsonb_build_array(jsonb_build_object('servico_id','aaaaaaaa-0000-0000-0000-000000000011',
            'profissional_id','dddddddd-0000-0000-0000-00000000000c', 'cardapio','ella_studio', 'inicio', teste_proximo_dia(3,'13:00'))),
        'f13-saldo-pos-cancel')) ->> 'reserva_id';
    SELECT id INTO v_cob FROM cobrancas WHERE reserva_id = v_r;

    PERFORM teste_paga_sinal(v_r, 'sinal', 30.00);
    PERFORM public.confirmar_reserva(v_r);
    PERFORM public.cancelar_reserva(v_r, NULL, 'cliente desistiu');
    ASSERT (SELECT valor_sinal FROM revisoes_cancelamento WHERE reserva_id = v_r AND decisao_final IS NULL) = 30.00;

    -- o saldo (70) cai no webhook com a reserva jÃ¡ cancelada
    v_res := public.processar_pagamento_webhook('mercado_pago', 'evt-f13', 70.00, NULL, v_cob, 'mp-f13', '{}'::JSONB, true);
    ASSERT v_res->>'status' = 'revisao_manual', format('F13: status %s', v_res->>'status');

    SELECT COALESCE(SUM(valor_sinal),0), COUNT(*) INTO v_soma, v_n
    FROM revisoes_cancelamento WHERE reserva_id = v_r AND decisao_final IS NULL;
    ASSERT v_soma = 100.00, format('F13 REGRESSÃƒO (GRAVE): fila aberta de R$ %s por R$ 100 pagos â€” dinheiro sem rasto', v_soma);
    ASSERT v_n = 1, format('F13: devia haver UMA revisÃ£o aberta ao nÃ­vel da reserva, hÃ¡ %s', v_n);
    RAISE NOTICE 'F13 OK â€” saldo pÃ³s-cancelamento: fila completada para os R$ 100 pagos';
END $$;

-- F14 (mesma famÃ­lia): 2.Âº pagamento com a reserva JÃ em revisÃ£o entra na fila
-- (antes sÃ³ notificava â€” a fila ficava curta)
DO $$
DECLARE v_r UUID; v_cob UUID; v_res JSONB; v_soma DECIMAL; v_n INT;
BEGIN
    v_r := (public.criar_pre_reserva('00000000-0000-0000-0000-000000000001',
        'cccccccc-0000-0000-0000-000000000011',
        jsonb_build_array(jsonb_build_object('servico_id','aaaaaaaa-0000-0000-0000-000000000011',
            'profissional_id','dddddddd-0000-0000-0000-00000000000c', 'cardapio','ella_studio', 'inicio', teste_proximo_dia(4,'13:00'))),
        'f14-topup-revisao')) ->> 'reserva_id';
    SELECT id INTO v_cob FROM cobrancas WHERE reserva_id = v_r;

    -- parcial de 10 (< sinal 30) â†’ registado; cron expira â†’ revisÃ£o de 10
    v_res := public.processar_pagamento_webhook('mercado_pago', 'evt-f14a', 10.00, NULL, v_cob, 'mp-f14a', '{}'::JSONB, true);
    ASSERT v_res->>'status' = 'parcial_registrado', format('F14: status %s', v_res->>'status');
    UPDATE agenda_ocupacoes SET expires_at = now() - interval '1 minute'
    WHERE origem = 'pre_reserva' AND origem_id = v_r;
    PERFORM public.expirar_pre_reservas();
    ASSERT (SELECT estado FROM reservas WHERE id = v_r) = 'pagamento_em_revisao';
    ASSERT (SELECT valor_sinal FROM revisoes_cancelamento WHERE reserva_id = v_r AND decisao_final IS NULL) = 10.00;

    -- mais 20 no webhook com a reserva em revisÃ£o â†’ fila passa a valer 30
    v_res := public.processar_pagamento_webhook('mercado_pago', 'evt-f14b', 20.00, NULL, v_cob, 'mp-f14b', '{}'::JSONB, true);
    ASSERT v_res->>'status' = 'pagamento_em_revisao';
    SELECT COALESCE(SUM(valor_sinal),0), COUNT(*) INTO v_soma, v_n
    FROM revisoes_cancelamento WHERE reserva_id = v_r AND decisao_final IS NULL;
    ASSERT v_soma = 30.00, format('F14 REGRESSÃƒO: fila de R$ %s por R$ 30 pagos â€” 2.Âº pagamento nÃ£o entrou na fila', v_soma);
    ASSERT v_n = 1, format('F14: devia haver UMA revisÃ£o aberta ao nÃ­vel da reserva, hÃ¡ %s', v_n);
    RAISE NOTICE 'F14 OK â€” pagamento em revisÃ£o entra na fila: R$ 10 + R$ 20 = R$ 30';
END $$;


-- =========================================================
-- SUÃTE 10: decisoes_test.sql
-- =========================================================

-- decisoes_test.sql â€” testes das 3 decisÃµes de negÃ³cio (v3.4.3)
-- Corre DEPOIS das outras suÃ­tes (usa fixtures do seed e do schedule_test).
SET TIME ZONE 'America/Sao_Paulo';

CREATE OR REPLACE FUNCTION teste_proximo_dia(dow INT, hora TEXT) RETURNS TIMESTAMPTZ
LANGUAGE sql STABLE AS $$
    SELECT ((CURRENT_DATE + ((dow - EXTRACT(DOW FROM CURRENT_DATE)::INT + 7) % 7 + 7))::TEXT || ' ' || hora)::TIMESTAMPTZ
$$;

-- ===== D1: CARDÃPIO OBRIGATÃ“RIO =====
-- D1a: sem cardÃ¡pio â†’ rejeiÃ§Ã£o com mensagem clara
DO $$
BEGIN
    BEGIN
        PERFORM public.criar_pre_reserva('00000000-0000-0000-0000-000000000001',
            'cccccccc-0000-0000-0000-000000000001',
            jsonb_build_array(jsonb_build_object('servico_id','aaaaaaaa-0000-0000-0000-000000000001',
                'profissional_id','33333333-3333-3333-3333-333333333333',
                'inicio', teste_proximo_dia(2,'10:00'))),
            'd1-sem-cardapio');
        RAISE EXCEPTION 'D1a FALHOU: aceitou sem cardÃ¡pio';
    EXCEPTION WHEN OTHERS THEN
        ASSERT SQLERRM LIKE '%cardÃ¡pio%', format('D1a erro inesperado: %s', SQLERRM);
        RAISE NOTICE 'D1a OK â€” sem cardÃ¡pio rejeitado: %', SQLERRM;
    END;
END $$;

-- D1b: cardÃ¡pio vazio â†’ rejeiÃ§Ã£o
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
        RAISE EXCEPTION 'D1b FALHOU: aceitou cardÃ¡pio vazio';
    EXCEPTION WHEN OTHERS THEN
        ASSERT SQLERRM LIKE '%cardÃ¡pio%', format('D1b erro inesperado: %s', SQLERRM);
        RAISE NOTICE 'D1b OK â€” cardÃ¡pio vazio rejeitado';
    END;
END $$;

-- D1c: cardÃ¡pio vÃ¡lido (ella_studio) â†’ cria
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
    RAISE NOTICE 'D1c OK â€” cardÃ¡pio ella_studio aceite';
END $$;

-- ===== D2: SINAL 30% FIXO =====
-- ServiÃ§o de R$ 100, 60 min â†’ sinal de R$ 30
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
    ASSERT v_sinal = 30.00, format('D2: sinal de R$ % (devia ser R$ 30.00 para serviÃ§o de R$ 100.00)', v_sinal);

    SELECT valor_sinal INTO v_sinal FROM cobrancas WHERE reserva_id = v_r;
    ASSERT v_sinal = 30.00, format('D2: cobranÃ§a sinal R$ % (devia ser R$ 30.00)', v_sinal);

    RAISE NOTICE 'D2 OK â€” sinal 30%% fixo: R$ % sobre R$ 100', v_sinal;
END $$;

-- ===== D3: AVALIAÃ‡ÃƒO GRATUITA (preÃ§o 0) =====
-- ServiÃ§o com preÃ§o 0 confirma diretamente, cobranÃ§a de valor 0 como registo interno
DO $$
DECLARE v JSONB; v_r UUID; v_estado TEXT; v_total DECIMAL; v_cob_valor DECIMAL;
BEGIN
    -- Fixture: serviÃ§o de avaliaÃ§Ã£o gratuita
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

    -- ConfirmaÃ§Ã£o direta (sem PIX, sem 30 min de espera)
    ASSERT v_estado = 'confirmada', format('D3: estado devolvido % (devia ser confirmada)', v_estado);
    ASSERT (SELECT estado FROM reservas WHERE id = v_r) = 'confirmada',
        'D3 REGRESSÃƒO: avaliaÃ§Ã£o gratuita nÃ£o nasceu confirmada';

    -- OcupaÃ§Ãµes definitivas (sem expires_at)
    ASSERT (SELECT COUNT(*) FROM agenda_ocupacoes
            WHERE origem = 'reserva' AND origem_id = v_r AND estado = 'ativa' AND expires_at IS NULL) = 2,
        'D3: ocupaÃ§Ãµes deviam ser definitivas (sem expires_at)';

    -- CobranÃ§a de valor 0 como registo interno (Alternativa A)
    SELECT valor_total, valor_sinal INTO v_total, v_cob_valor
    FROM cobrancas WHERE reserva_id = v_r;
    ASSERT v_total = 0.00, format('D3: cobranÃ§a total R$ % (devia ser 0.00)', v_total);
    ASSERT v_cob_valor = 0.00, format('D3: cobranÃ§a sinal R$ % (devia ser 0.00)', v_cob_valor);

    -- O cron NÃƒO deve mexer em reserva confirmada
    PERFORM public.expirar_pre_reservas();
    ASSERT (SELECT estado FROM reservas WHERE id = v_r) = 'confirmada', 'D3: cron mexeu em avaliaÃ§Ã£o gratuita';

    RAISE NOTICE 'D3 OK â€” avaliaÃ§Ã£o gratuita: confirmada direto, cobranÃ§a R$ 0 (registo interno), cron ignora';
END $$;


-- =========================================================
-- SUÃTE 11: auditoria2_test.sql
-- =========================================================

-- auditoria2_test.sql â€” testes da 2Âª auditoria (v3.4.3)
-- Corre DEPOIS das outras suÃ­tes. Cobre os 7 itens da 014_auditoria2_fixes.sql.
SET TIME ZONE 'America/Sao_Paulo';

-- =====================================================================
-- ITEM 7: CardÃ¡pio oficial ('ella_studio' / 'ella_men')
-- =====================================================================

-- A7a: valor antigo 'feminino' Ã© rejeitado no INSERT
DO $$
BEGIN
    BEGIN
        INSERT INTO servico_cardapios (servico_id, cardapio, nome_comercial)
        VALUES ('aaaaaaaa-0000-0000-0000-000000000011', 'feminino', 'Teste CardÃ¡pio Antigo');
        RAISE EXCEPTION 'A7a FALHOU: aceitou feminino';
    EXCEPTION WHEN check_violation THEN
        RAISE NOTICE 'A7a OK â€” feminino rejeitado (CHECK atualizado)';
    END;
END $$;

-- A7b: valor antigo 'masculino' Ã© rejeitado no INSERT
DO $$
BEGIN
    BEGIN
        INSERT INTO servico_cardapios (servico_id, cardapio, nome_comercial)
        VALUES ('aaaaaaaa-0000-0000-0000-000000000011', 'masculino', 'Teste CardÃ¡pio Antigo');
        RAISE EXCEPTION 'A7b FALHOU: aceitou masculino';
    EXCEPTION WHEN check_violation THEN
        RAISE NOTICE 'A7b OK â€” masculino rejeitado (CHECK atualizado)';
    END;
END $$;

-- A7c: valor novo 'ella_studio' Ã© aceite
DO $$
BEGIN
    INSERT INTO servico_cardapios (servico_id, cardapio, nome_comercial)
    VALUES ('aaaaaaaa-0000-0000-0000-000000000011', 'ella_studio', 'Teste CardÃ¡pio Novo')
    ON CONFLICT (servico_id, cardapio) DO NOTHING;
    ASSERT EXISTS (SELECT 1 FROM servico_cardapios WHERE servico_id = 'aaaaaaaa-0000-0000-0000-000000000011' AND cardapio = 'ella_studio');
    RAISE NOTICE 'A7c OK â€” ella_studio aceite';
END $$;

-- =====================================================================
-- ITEM 1: VerificaÃ§Ã£o de perfil nas 3 RPCs (GRAVE #2)
-- =====================================================================

-- Fixture: reserva com Prof C (nÃ£o Ã© a Laira) como sistema
DO $$
DECLARE v_r UUID;
BEGIN
    v_r := (public.criar_pre_reserva('00000000-0000-0000-0000-000000000001',
        'cccccccc-0000-0000-0000-000000000011',
        jsonb_build_array(jsonb_build_object('servico_id','aaaaaaaa-0000-0000-0000-000000000011',
            'profissional_id','dddddddd-0000-0000-0000-00000000000c', 'cardapio','ella_studio', 'inicio', now() + interval '2 days')),
        'a1-fixture')) ->> 'reserva_id';
    PERFORM set_config('app.a1.r', v_r::TEXT, false);
END $$;

-- A1a: recepcao de OUTRA empresa tenta cancelar â†’ rejeitado (guarda de inquilino)
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
        ASSERT SQLERRM LIKE '%Sem permissÃ£o%', format('A1a erro inesperado: %s', SQLERRM);
        RAISE NOTICE 'A1a OK â€” inquilino estranho nÃ£o cancela: %', SQLERRM;
    END;
END $$;
RESET ROLE;
SELECT set_config('request.jwt.claims', '{}', false);

-- A1b: Laira (profissional) tenta cancelar reserva da Prof C â†’ rejeitado (guarda de perfil)
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
        ASSERT SQLERRM LIKE '%Sem permissÃ£o%', format('A1b erro inesperado: %s', SQLERRM);
        RAISE NOTICE 'A1b OK â€” profissional sem vÃ­nculo nÃ£o cancela: %', SQLERRM;
    END;
END $$;
RESET ROLE;
SELECT set_config('request.jwt.claims', '{}', false);

-- A1c: Laira tenta confirmar reserva da Prof C â†’ rejeitado
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
        ASSERT SQLERRM LIKE '%Sem permissÃ£o%', format('A1c erro inesperado: %s', SQLERRM);
        RAISE NOTICE 'A1c OK â€” profissional sem vÃ­nculo nÃ£o confirma: %', SQLERRM;
    END;
END $$;
RESET ROLE;
SELECT set_config('request.jwt.claims', '{}', false);

-- A1d: Laira tenta cancelar_pre_reserva da Prof C â†’ rejeitado
SET ROLE authenticated;
SELECT set_config('request.jwt.claims', '{"sub":"ffffffff-0000-0000-0000-000000000003","role":"authenticated","aal":"aal1"}', false);
DO $$
DECLARE v_r UUID;
BEGIN
    v_r := current_setting('app.a1.r')::UUID;
    BEGIN
        PERFORM public.cancelar_pre_reserva(v_r);
        RAISE EXCEPTION 'A1d FALHOU: profissional cancelou prÃ©-reserva alheia';
    EXCEPTION WHEN OTHERS THEN
        ASSERT SQLERRM LIKE '%Sem permissÃ£o%', format('A1d erro inesperado: %s', SQLERRM);
        RAISE NOTICE 'A1d OK â€” profissional sem vÃ­nculo nÃ£o cancela prÃ©-reserva: %', SQLERRM;
    END;
END $$;
RESET ROLE;
SELECT set_config('request.jwt.claims', '{}', false);

-- =====================================================================
-- ITEM 2: CobranÃ§a 'cancelada' nos 3 ramos de resolver_revisao (MÃ‰DIO #3)
-- =====================================================================

-- A2a: ramo 'credito' â†’ cobranÃ§a cancelada
DO $$
DECLARE v_rev UUID; v_r UUID; v_res JSONB;
BEGIN
    v_r := (public.criar_pre_reserva('00000000-0000-0000-0000-000000000001',
        'cccccccc-0000-0000-0000-000000000011',
        jsonb_build_array(jsonb_build_object('servico_id','aaaaaaaa-0000-0000-0000-000000000011',
            'profissional_id','dddddddd-0000-0000-0000-00000000000c', 'cardapio','ella_studio', 'inicio', now() + interval '3 days')),
        'a2-credito')) ->> 'reserva_id';
    PERFORM teste_paga_sinal(v_r::UUID, 'sinal', 30.00);
    PERFORM public.confirmar_reserva(v_r::UUID);
    PERFORM public.cancelar_reserva(v_r::UUID);
    SELECT id INTO v_rev FROM revisoes_cancelamento WHERE reserva_id = v_r::UUID AND decisao_final IS NULL;
    v_res := public.resolver_revisao(v_rev, 'credito', 'cliente quer crÃ©dito');
    ASSERT v_res->>'reserva_status' = 'cancelada';
    ASSERT (SELECT estado FROM cobrancas WHERE reserva_id = v_r::UUID) = 'cancelada',
        'A2a: cobranÃ§a devia estar cancelada no ramo credito';
    RAISE NOTICE 'A2a OK â€” credito: cobranÃ§a cancelada';
END $$;

-- A2b: ramo 'estorno' â†’ cobranÃ§a cancelada
DO $$
DECLARE v_rev UUID; v_r UUID; v_res JSONB;
BEGIN
    v_r := (public.criar_pre_reserva('00000000-0000-0000-0000-000000000001',
        'cccccccc-0000-0000-0000-000000000011',
        jsonb_build_array(jsonb_build_object('servico_id','aaaaaaaa-0000-0000-0000-000000000011',
            'profissional_id','dddddddd-0000-0000-0000-00000000000c', 'cardapio','ella_studio', 'inicio', now() + interval '4 days')),
        'a2-estorno')) ->> 'reserva_id';
    PERFORM teste_paga_sinal(v_r::UUID, 'sinal', 30.00);
    PERFORM public.confirmar_reserva(v_r::UUID);
    PERFORM public.cancelar_reserva(v_r::UUID);
    SELECT id INTO v_rev FROM revisoes_cancelamento WHERE reserva_id = v_r::UUID AND decisao_final IS NULL;
    v_res := public.resolver_revisao(v_rev, 'estorno', 'cliente quer dinheiro de volta');
    ASSERT v_res->>'reserva_status' = 'cancelada';
    ASSERT (SELECT estado FROM cobrancas WHERE reserva_id = v_r::UUID) = 'cancelada',
        'A2b: cobranÃ§a devia estar cancelada no ramo estorno';
    RAISE NOTICE 'A2b OK â€” estorno: cobranÃ§a cancelada';
END $$;

-- A2c: ramo 'perdido' â†’ cobranÃ§a cancelada (nÃ£o 'sinal_pago')
DO $$
DECLARE v_rev UUID; v_r UUID; v_res JSONB;
BEGIN
    v_r := (public.criar_pre_reserva('00000000-0000-0000-0000-000000000001',
        'cccccccc-0000-0000-0000-000000000011',
        jsonb_build_array(jsonb_build_object('servico_id','aaaaaaaa-0000-0000-0000-000000000011',
            'profissional_id','dddddddd-0000-0000-0000-00000000000c', 'cardapio','ella_studio', 'inicio', now() + interval '5 days')),
        'a2-perdido')) ->> 'reserva_id';
    PERFORM teste_paga_sinal(v_r::UUID, 'sinal', 30.00);
    PERFORM public.confirmar_reserva(v_r::UUID);
    PERFORM public.cancelar_reserva(v_r::UUID);
    SELECT id INTO v_rev FROM revisoes_cancelamento WHERE reserva_id = v_r::UUID AND decisao_final IS NULL;
    v_res := public.resolver_revisao(v_rev, 'perdido', 'cliente nÃ£o apareceu');
    ASSERT v_res->>'reserva_status' = 'cancelada';
    ASSERT (SELECT estado FROM cobrancas WHERE reserva_id = v_r::UUID) = 'cancelada',
        'A2c: cobranÃ§a devia estar cancelada no ramo perdido (nÃ£o sinal_pago)';
    RAISE NOTICE 'A2c OK â€” perdido: cobranÃ§a cancelada (regressÃ£o sinal_pago evitada)';
END $$;

-- =====================================================================
-- ITEM 3: CHECK em log_acoes_sensiveis.acao (MENOR #4)
-- =====================================================================

DO $$
BEGIN
    BEGIN
        INSERT INTO log_acoes_sensiveis (empresa_id, tabela, registro_id, acao)
        VALUES ('00000000-0000-0000-0000-000000000001', 'teste', gen_random_uuid(), 'SELECT');
        RAISE EXCEPTION 'A3 FALHOU: aceitou acao=SELECT';
    EXCEPTION WHEN check_violation THEN
        RAISE NOTICE 'A3 OK â€” acao invÃ¡lida rejeitada (CHECK)';
    END;
END $$;

-- =====================================================================
-- ITEM 4: ValidaÃ§Ã£o em submeter_anamnese (MENOR #5)
-- =====================================================================

-- Criar modelo de teste com pergunta numero e multipla_escolha
DO $$
DECLARE v_modelo UUID; v_perg_num UUID; v_perg_mul UUID; v_token TEXT; v_anamnese_id UUID;
BEGIN
    INSERT INTO modelos_anamnese (id, empresa_id, nome) VALUES
    ('cccccccc-0000-0000-0000-0000000000a4', '00000000-0000-0000-0000-000000000001', 'Modelo Teste ValidaÃ§Ã£o')
    ON CONFLICT (id) DO NOTHING;

    INSERT INTO modelo_perguntas (id, modelo_id, ordem, pergunta, tipo_resposta, opcoes, obrigatoria)
    VALUES ('dddddddd-0000-0000-0000-0000000000a1', 'cccccccc-0000-0000-0000-0000000000a4', 1, 'Idade?', 'numero', NULL, true)
    ON CONFLICT (id) DO NOTHING;

    INSERT INTO modelo_perguntas (id, modelo_id, ordem, pergunta, tipo_resposta, opcoes, obrigatoria)
    VALUES ('dddddddd-0000-0000-0000-0000000000a2', 'cccccccc-0000-0000-0000-0000000000a4', 2, 'Cor preferida?', 'multipla_escolha', '["azul","vermelho","verde"]'::JSONB, true)
    ON CONFLICT (id) DO NOTHING;

    -- Criar serviÃ§o com este modelo
    INSERT INTO servicos (id, empresa_id, nome_tecnico, tipo_recurso_id, duracao_minutos, preco_base, percentual_sinal, anamnese_obrigatoria, modelo_anamnese_id)
    VALUES ('aaaaaaaa-0000-0000-0000-0000000000a4', '00000000-0000-0000-0000-000000000001', 'teste_validacao_anamnese', '11111111-1111-1111-1111-111111111111', 30, 50.00, 30, true, 'cccccccc-0000-0000-0000-0000000000a4')
    ON CONFLICT (empresa_id, nome_tecnico) DO NOTHING;
    INSERT INTO profissional_servicos (profissional_id, servico_id, empresa_id) VALUES
    ('33333333-3333-3333-3333-333333333333', 'aaaaaaaa-0000-0000-0000-0000000000a4', '00000000-0000-0000-0000-000000000001')
    ON CONFLICT DO NOTHING;

    RAISE NOTICE 'A4 FIXTURES OK â€” modelo de teste criado';
END $$;

-- A4a: numero invÃ¡lido (texto) â†’ rejeitado
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
        ASSERT SQLERRM LIKE '%nÃºmero%', format('A4a erro inesperado: %s', SQLERRM);
        RAISE NOTICE 'A4a OK â€” numero invÃ¡lido rejeitado: %', SQLERRM;
    END;
END $$;

-- A4b: multipla_escolha fora das opÃ§Ãµes â†’ rejeitado
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
        ASSERT SQLERRM LIKE '%opÃ§Ãµes%', format('A4b erro inesperado: %s', SQLERRM);
        RAISE NOTICE 'A4b OK â€” multipla_escolha fora das opÃ§Ãµes rejeitada: %', SQLERRM;
    END;
END $$;

-- A4c: respostas vÃ¡lidas â†’ aceite
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
    RAISE NOTICE 'A4c OK â€” respostas vÃ¡lidas aceites';
END $$;


-- =========================================================
-- FIM DAS SUÃTES 7-11
-- =========================================================
