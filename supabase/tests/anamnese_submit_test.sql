-- anamnese_submit_test.sql (v3.4 NOVO) — submeter_anamnese: o cliente entrega a ficha
-- pelo link (token = credencial); as REGRAS do modelo decidem liberada × requer_avaliacao.
SET TIME ZONE 'America/Sao_Paulo';

CREATE OR REPLACE FUNCTION teste_proximo_dia(dow INT, hora TEXT) RETURNS TIMESTAMPTZ
LANGUAGE sql STABLE AS $$
    SELECT ((CURRENT_DATE + ((dow - EXTRACT(DOW FROM CURRENT_DATE)::INT + 7) % 7 + 7))::TEXT || ' ' || hora)::TIMESTAMPTZ
$$;

-- Modelo com regra: "Já fez alergia a esmalte?" = sim → requer_avaliacao
INSERT INTO modelos_anamnese (id, empresa_id, nome, versao) VALUES
('bbbbbbbb-0000-0000-0000-000000000002', '00000000-0000-0000-0000-000000000001', 'Modelo Regras', 1)
ON CONFLICT (id) DO NOTHING;
INSERT INTO modelo_perguntas (id, modelo_id, ordem, pergunta, tipo_resposta, obrigatoria, operador, valor_disparador, resultado_estado) VALUES
('bbbbbbbb-0000-0000-0000-0000000000a1', 'bbbbbbbb-0000-0000-0000-000000000002', 1, 'Tem alergia a esmalte?', 'sim_nao', true, 'igual', 'sim', 'requer_avaliacao'),
('bbbbbbbb-0000-0000-0000-0000000000a2', 'bbbbbbbb-0000-0000-0000-000000000002', 2, 'Observações', 'texto', false, NULL, NULL, NULL)
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

-- S1: respostas sem disparo → liberada; token queima; reuso → erro
DO $$
DECLARE v JSONB; v_estado TEXT;
BEGIN
    v := teste_agenda_com_anamnese('aaaaaaaa-0000-0000-0000-000000000041', 4, '14:00', 'sub-s1');
    v_estado := public.submeter_anamnese(v->>'token',
        jsonb_build_array(
            jsonb_build_object('pergunta_id','bbbbbbbb-0000-0000-0000-0000000000a1','resposta','não'),
            jsonb_build_object('pergunta_id','bbbbbbbb-0000-0000-0000-0000000000a2','resposta','primeira vez')),
        true, 'Li e aceito o tratamento dos dados de saúde (LGPD)');

    ASSERT v_estado = 'liberada', format('S1: estado %s', v_estado);
    ASSERT (SELECT estado FROM anamneses WHERE id = (v->>'anamnese_id')::UUID) = 'liberada';
    ASSERT (SELECT consentimento_lgpd FROM anamneses WHERE id = (v->>'anamnese_id')::UUID) = true;
    ASSERT (SELECT COUNT(*) FROM anamnese_respostas WHERE anamnese_id = (v->>'anamnese_id')::UUID) = 2;
    ASSERT (SELECT usado FROM anamnese_tokens WHERE anamnese_id = (v->>'anamnese_id')::UUID) = true;

    BEGIN
        PERFORM public.submeter_anamnese(v->>'token', '[]'::JSONB, true, 'termo');
        RAISE EXCEPTION 'S1 FALHOU: token reutilizado';
    EXCEPTION WHEN OTHERS THEN
        ASSERT SQLERRM LIKE '%Link inválido%', format('S1 reuso erro inesperado: %s', SQLERRM);
    END;
    RAISE NOTICE 'S1 OK — ficha liberada, respostas gravadas, token queimado';
END $$;

-- S2: regra dispara ("sim" na alergia) → requer_avaliacao + staff notificado — COMO ANON
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
    RAISE NOTICE 'S2 OK — regra disparou via ANON (link público): requer_avaliacao';
END $$;
RESET ROLE;

DO $$
BEGIN
    ASSERT (SELECT estado FROM anamneses WHERE id = current_setting('app.sub.s2_anam')::UUID) = 'requer_avaliacao';
    ASSERT EXISTS (SELECT 1 FROM notificacoes_internas WHERE tipo = 'anamnese_requer_avaliacao'
                   AND mensagem LIKE '%' || current_setting('app.sub.s2_anam') || '%'),
        'S2: staff devia ter sido notificado';
    RAISE NOTICE 'S2b OK — ficha na fila da profissional com notificação ao staff';
END $$;

-- S3+S5: obrigatória em falta → erro; sem consentimento → erro; depois correto → liberada
DO $$
DECLARE v JSONB;
BEGIN
    v := teste_agenda_com_anamnese('aaaaaaaa-0000-0000-0000-000000000041', 4, '16:00', 'sub-s3');
    PERFORM set_config('app.sub.s3_token', v->>'token', false);
    PERFORM set_config('app.sub.s3_anam', v->>'anamnese_id', false);

    BEGIN
        PERFORM public.submeter_anamnese(v->>'token',
            jsonb_build_array(jsonb_build_object('pergunta_id','bbbbbbbb-0000-0000-0000-0000000000a2','resposta','só a opcional')),
            true, 'termo');
        RAISE EXCEPTION 'S3 FALHOU: obrigatória em falta aceite';
    EXCEPTION WHEN OTHERS THEN
        ASSERT SQLERRM LIKE '%obrigatória%', format('S3 erro inesperado: %s', SQLERRM);
        RAISE NOTICE 'S3 OK — obrigatória em falta rejeitada';
    END;

    BEGIN
        PERFORM public.submeter_anamnese(v->>'token',
            jsonb_build_array(jsonb_build_object('pergunta_id','bbbbbbbb-0000-0000-0000-0000000000a1','resposta','não')),
            false, NULL);
        RAISE EXCEPTION 'S5 FALHOU: sem consentimento aceite';
    EXCEPTION WHEN OTHERS THEN
        ASSERT SQLERRM LIKE '%consentimento%', format('S5 erro inesperado: %s', SQLERRM);
        RAISE NOTICE 'S5 OK — LGPD: sem consentimento não entra';
    END;

    -- o token SOBREVIVEU aos erros (rollback por tentativa): corrigir e enviar funciona
    PERFORM public.submeter_anamnese(v->>'token',
        jsonb_build_array(jsonb_build_object('pergunta_id','bbbbbbbb-0000-0000-0000-0000000000a1','resposta','não')),
        true, 'termo');
    ASSERT (SELECT estado FROM anamneses WHERE id = (v->>'anamnese_id')::UUID) = 'liberada';
    RAISE NOTICE 'S3b OK — erros não queimam o token; correção entra';
END $$;

-- S4: pergunta de OUTRO modelo → erro
DO $$
DECLARE v JSONB;
BEGIN
    v := teste_agenda_com_anamnese('aaaaaaaa-0000-0000-0000-000000000041', 5, '10:00', 'sub-s4');
    BEGIN
        PERFORM public.submeter_anamnese(v->>'token',
            jsonb_build_array(
                jsonb_build_object('pergunta_id','bbbbbbbb-0000-0000-0000-0000000000a1','resposta','não'),
                jsonb_build_object('pergunta_id', (SELECT id FROM modelo_perguntas WHERE modelo_id = 'bbbbbbbb-0000-0000-0000-000000000001' LIMIT 1),'resposta','intrusa')),
            true, 'termo');
        RAISE EXCEPTION 'S4 FALHOU: pergunta estranha ao modelo aceite';
    EXCEPTION WHEN OTHERS THEN
        ASSERT SQLERRM LIKE '%não pertence%', format('S4 erro inesperado: %s', SQLERRM);
        RAISE NOTICE 'S4 OK — resposta para pergunta de outro modelo rejeitada';
    END;
END $$;

-- S6: token expirado → erro claro; regenerar devolve NOVO token que funciona
DO $$
DECLARE v JSONB; v_novo TEXT; v_estado TEXT;
BEGIN
    v := teste_agenda_com_anamnese('aaaaaaaa-0000-0000-0000-000000000041', 2, '09:00', 'sub-s6');
    UPDATE anamnese_tokens SET expira_em = now() - interval '1 minute'
    WHERE anamnese_id = (v->>'anamnese_id')::UUID;

    BEGIN
        PERFORM public.submeter_anamnese(v->>'token',
            jsonb_build_array(jsonb_build_object('pergunta_id','bbbbbbbb-0000-0000-0000-0000000000a1','resposta','não')),
            true, 'termo');
        RAISE EXCEPTION 'S6 FALHOU: token expirado aceite';
    EXCEPTION WHEN OTHERS THEN
        ASSERT SQLERRM LIKE '%expirou%', format('S6 erro inesperado: %s', SQLERRM);
        RAISE NOTICE 'S6 OK — expirado rejeitado com mensagem útil';
    END;

    v_novo := public.regenerar_token_anamnese((v->>'anamnese_id')::UUID);
    ASSERT v_novo IS NOT NULL AND v_novo <> v->>'token';
    v_estado := public.submeter_anamnese(v_novo,
        jsonb_build_array(jsonb_build_object('pergunta_id','bbbbbbbb-0000-0000-0000-0000000000a1','resposta','não')),
        true, 'termo');
    ASSERT v_estado = 'liberada';
    RAISE NOTICE 'S6b OK — regeneração (só equipe) emite novo link funcional';
END $$;

-- S7: ficha respondida NÃO aceita segunda submissão nem com token novo
DO $$
DECLARE v_anam UUID := current_setting('app.sub.s3_anam')::UUID; v_tok TEXT;
BEGIN
    v_tok := public.regenerar_token_anamnese(v_anam);
    BEGIN
        PERFORM public.submeter_anamnese(v_tok,
            jsonb_build_array(jsonb_build_object('pergunta_id','bbbbbbbb-0000-0000-0000-0000000000a1','resposta','sim')),
            true, 'termo');
        RAISE EXCEPTION 'S7 FALHOU: ficha já respondida re-submetida';
    EXCEPTION WHEN OTHERS THEN
        ASSERT SQLERRM LIKE '%já foi respondida%', format('S7 erro inesperado: %s', SQLERRM);
        RAISE NOTICE 'S7 OK — ficha respondida é terminal';
    END;
END $$;
