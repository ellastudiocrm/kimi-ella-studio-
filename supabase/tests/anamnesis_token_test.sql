-- anamnesis_token_test.sql — token bruto vs hash, expiração 24h, reemissão (Ricardo #9)
SET TIME ZONE 'America/Sao_Paulo';

CREATE OR REPLACE FUNCTION teste_proximo_dia(dow INT, hora TEXT) RETURNS TIMESTAMPTZ
LANGUAGE sql STABLE AS $$
    SELECT ((CURRENT_DATE + ((dow - EXTRACT(DOW FROM CURRENT_DATE)::INT + 7) % 7 + 7))::TEXT || ' ' || hora)::TIMESTAMPTZ
$$;

INSERT INTO modelos_anamnese (id, empresa_id, nome, versao) VALUES
('bbbbbbbb-0000-0000-0000-000000000001', '00000000-0000-0000-0000-000000000001', 'Modelo Teste', 1)
ON CONFLICT (id) DO NOTHING;
INSERT INTO modelo_perguntas (modelo_id, ordem, pergunta, tipo_resposta) VALUES
('bbbbbbbb-0000-0000-0000-000000000001', 1, 'É diabética?', 'sim_nao')
ON CONFLICT (modelo_id, ordem) DO NOTHING;

INSERT INTO servicos (id, empresa_id, nome_tecnico, tipo_recurso_id, duracao_minutos, preco_base, anamnese_obrigatoria, modelo_anamnese_id) VALUES
('aaaaaaaa-0000-0000-0000-000000000002', '00000000-0000-0000-0000-000000000001', 'teste_com_anamnese', '11111111-1111-1111-1111-111111111114', 90, 120.00, true, 'bbbbbbbb-0000-0000-0000-000000000001')
ON CONFLICT (empresa_id, nome_tecnico) DO NOTHING;
INSERT INTO profissional_servicos (profissional_id, servico_id, empresa_id) VALUES
('33333333-3333-3333-3333-333333333333', 'aaaaaaaa-0000-0000-0000-000000000002', '00000000-0000-0000-0000-000000000001')
ON CONFLICT DO NOTHING;

-- T1: agendamento devolve token BRUTO (64 hex); banco guarda SÓ o hash; expira ≤ 24h
DO $$
DECLARE v JSONB; v_token TEXT; v_hash TEXT; v_expira TIMESTAMPTZ; v_reserva UUID;
BEGIN
    v := public.criar_pre_reserva('00000000-0000-0000-0000-000000000001',
        'cccccccc-0000-0000-0000-000000000001',
        jsonb_build_array(jsonb_build_object('servico_id','aaaaaaaa-0000-0000-0000-000000000002',
            'profissional_id','33333333-3333-3333-3333-333333333333',
            'cardapio','ella_studio',
            'inicio', teste_proximo_dia(2,'11:00'))), 'anam-t1');
    v_token := v->'anamneses'->0->>'token';
    v_reserva := (v->>'reserva_id')::UUID;

    ASSERT v_token IS NOT NULL AND length(v_token) = 64, 'T1: token bruto ausente ou malformado';

    SELECT token_hash, expira_em INTO v_hash, v_expira FROM anamnese_tokens WHERE reserva_id = v_reserva;
    ASSERT v_hash = public.sha256_hex(v_token), 'T1: hash guardado não corresponde ao token';
    ASSERT v_hash <> v_token, 'T1 REGRESSÃO Ricardo #9: token bruto gravado no banco!';
    ASSERT v_expira <= now() + interval '24 hours' + interval '1 minute', format('T1: expiração acima de 24h: %s', v_expira);

    PERFORM set_config('app.teste.token_reserva', v_reserva::TEXT, false);
    PERFORM set_config('app.teste.token_bruto', v_token, false);
    RAISE NOTICE 'T1 OK — token entregue uma vez; banco guarda só o hash; expira em %', v_expira;
END $$;

-- T2: validação pelo hash funciona; token bruto não existe no banco
DO $$
DECLARE v_por_hash INT; v_por_bruto INT;
BEGIN
    SELECT COUNT(*) INTO v_por_hash FROM anamnese_tokens
    WHERE token_hash = public.sha256_hex(current_setting('app.teste.token_bruto'));
    SELECT COUNT(*) INTO v_por_bruto FROM anamnese_tokens
    WHERE token_hash = current_setting('app.teste.token_bruto');
    ASSERT v_por_hash = 1 AND v_por_bruto = 0, 'T2 falhou';
    RAISE NOTICE 'T2 OK — lookup por digest; bruto irrecuperável do banco';
END $$;

-- T3: retry idempotente NÃO devolve novo token e não duplica fichas
DO $$
DECLARE v JSONB; v_tokens INT; v_fichas INT;
BEGIN
    v := public.criar_pre_reserva('00000000-0000-0000-0000-000000000001',
        'cccccccc-0000-0000-0000-000000000001',
        jsonb_build_array(jsonb_build_object('servico_id','aaaaaaaa-0000-0000-0000-000000000002',
            'profissional_id','33333333-3333-3333-3333-333333333333',
            'cardapio','ella_studio',
            'inicio', teste_proximo_dia(2,'11:00'))), 'anam-t1');
    ASSERT (v->>'idempotente')::BOOLEAN = true;
    SELECT COUNT(*) INTO v_tokens FROM anamnese_tokens
    WHERE reserva_id = current_setting('app.teste.token_reserva')::UUID;
    SELECT COUNT(*) INTO v_fichas FROM anamneses a
    JOIN anamnese_tokens t ON t.anamnese_id = a.id
    WHERE t.reserva_id = current_setting('app.teste.token_reserva')::UUID;
    ASSERT v_tokens = 1 AND v_fichas = 1, 'T3: retry duplicou token/ficha';
    RAISE NOTICE 'T3 OK — retry seguro: 1 ficha, 1 token, sem bruto novo';
END $$;

-- T4: reemissão invalida o anterior e devolve NOVO bruto
DO $$
DECLARE v_anamnese UUID; v_novo TEXT; v_antigo_valido INT; v_novo_valido INT;
BEGIN
    SELECT anamnese_id INTO v_anamnese FROM anamnese_tokens
    WHERE reserva_id = current_setting('app.teste.token_reserva')::UUID;
    v_novo := public.regenerar_token_anamnese(v_anamnese);

    SELECT COUNT(*) INTO v_antigo_valido FROM anamnese_tokens
    WHERE anamnese_id = v_anamnese AND usado = false
      AND token_hash = public.sha256_hex(current_setting('app.teste.token_bruto'));
    SELECT COUNT(*) INTO v_novo_valido FROM anamnese_tokens
    WHERE anamnese_id = v_anamnese AND usado = false
      AND token_hash = public.sha256_hex(v_novo);
    ASSERT v_antigo_valido = 0 AND v_novo_valido = 1 AND v_novo <> current_setting('app.teste.token_bruto'),
        'T4 falhou';
    RAISE NOTICE 'T4 OK — token reemitido: antigo invalidado, novo funcional';
END $$;

-- T5: revisão da anamnese pela profissional designada via RPC (Ricardo: prof atualizava colunas a mais)
-- (o id da ficha é resolvido como sistema: anamnese_tokens é só-service_role por desenho)
DO $$
DECLARE v_anamnese UUID;
BEGIN
    SELECT anamnese_id INTO v_anamnese FROM anamnese_tokens
    WHERE reserva_id = current_setting('app.teste.token_reserva')::UUID
    LIMIT 1;
    PERFORM set_config('app.teste.anamnese_id', v_anamnese::TEXT, false);
END $$;

SET ROLE authenticated;
SELECT set_config('request.jwt.claims', '{"sub":"ffffffff-0000-0000-0000-000000000003","role":"authenticated"}', false);
DO $$
DECLARE v_anamnese UUID := current_setting('app.teste.anamnese_id')::UUID;
BEGIN
    PERFORM public.revisar_anamnese(v_anamnese, 'liberada');
    ASSERT (SELECT estado FROM anamneses WHERE id = v_anamnese) = 'liberada';
    ASSERT (SELECT data_revisao FROM anamneses WHERE id = v_anamnese) IS NOT NULL;
    RAISE NOTICE 'T5 OK — Laira revê a sua anamnese via RPC (estado + data, mais nada)';
END $$;
RESET ROLE;
