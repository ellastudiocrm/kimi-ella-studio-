-- frontend_ready_test.sql (v3.4.4) — RLS anon + RPC listar_horarios_disponiveis
-- Corre como superuser. 20 asserts novos.
--
-- Critério de aceite: 238/238 antigos + 20/20 novos verdes.

SET TIME ZONE 'America/Sao_Paulo';

-- =====================================================================
-- FIXTURES
-- =====================================================================

-- Serviço de teste (duracao 65 min simula sala)
INSERT INTO public.servicos (
    id, empresa_id, nome_tecnico, tipo_recurso_id, duracao_minutos,
    preco_base, percentual_sinal, anamnese_obrigatoria, ativo, foto_url
) VALUES (
    'bbbbbbbb-0000-0000-0000-000000000001',
    '00000000-0000-0000-0000-000000000001',
    'teste_sala',
    '11111111-1111-1111-1111-111111111111',
    65, 80.00, 30, false, true, 'https://exemplo.com/foto.jpg'
) ON CONFLICT (id) DO NOTHING;

-- Cardápio ella_studio (OBRIGATÓRIO)
INSERT INTO public.servico_cardapios (
    id, servico_id, cardapio, nome_comercial, descricao, preco_final, ativo
) VALUES (
    'bbbbbbbb-0000-0000-0000-000000000002',
    'bbbbbbbb-0000-0000-0000-000000000001',
    'ella_studio',
    'Teste Sala',
    'Descrição',
    80.00,
    true
) ON CONFLICT (id) DO NOTHING;

-- Profissional de teste
INSERT INTO public.profissionais (
    id, empresa_id, nome, foto_url, bio, especialidades, ativo
) VALUES (
    'eeeeeeee-0000-0000-0000-000000000001',
    '00000000-0000-0000-0000-000000000001',
    'Prof Frontend',
    'https://exemplo.com/prof.jpg',
    'Bio teste',
    ARRAY['unhas', 'pele'],
    true
) ON CONFLICT (id) DO NOTHING;

-- Habilitação
INSERT INTO public.profissional_servicos (profissional_id, servico_id, empresa_id)
VALUES (
    'eeeeeeee-0000-0000-0000-000000000001',
    'bbbbbbbb-0000-0000-0000-000000000001',
    '00000000-0000-0000-0000-000000000001'
) ON CONFLICT DO NOTHING;

-- Recurso específico para este serviço
INSERT INTO public.recursos (
    id, empresa_id, tipo_recurso_id, nome, ativo
) VALUES (
    'ffffffff-0000-0000-0000-000000000001',
    '00000000-0000-0000-0000-000000000001',
    '11111111-1111-1111-1111-111111111111',
    'Sala Frontend',
    true
) ON CONFLICT (id) DO NOTHING;

-- Horários de empresa: domingo 09:00–12:30 e 13:30–18:00
INSERT INTO public.horarios_empresa (empresa_id, dia_semana, abertura, fechamento, ativo) VALUES
('00000000-0000-0000-0000-000000000001', 0, '09:00', '12:30', true),
('00000000-0000-0000-0000-000000000001', 0, '13:30', '18:00', true)
ON CONFLICT DO NOTHING;

-- Horários da profissional: domingo 09:00–12:00 e 14:00–18:00
-- (interseção com empresa: 09:00–12:00 e 14:00–18:00)
INSERT INTO public.horarios_profissional (profissional_id, dia_semana, abertura, fechamento, ativo) VALUES
('eeeeeeee-0000-0000-0000-000000000001', 0, '09:00', '12:00', true),
('eeeeeeee-0000-0000-0000-000000000001', 0, '14:00', '18:00', true)
ON CONFLICT DO NOTHING;

-- Helper: próxima data com dado dia da semana, sempre no futuro
CREATE OR REPLACE FUNCTION teste_frontend_proximo_dia(dow INT, hora TEXT) RETURNS TIMESTAMPTZ
LANGUAGE sql STABLE AS $$
    SELECT ((CURRENT_DATE + ((dow - EXTRACT(DOW FROM CURRENT_DATE)::INT + 7) % 7 + 7))::TEXT || ' ' || hora)::TIMESTAMPTZ
$$;

-- Data de teste: próximo domingo (0)
CREATE OR REPLACE FUNCTION teste_frontend_data(dow INT) RETURNS DATE
LANGUAGE sql STABLE AS $$
    SELECT (CURRENT_DATE + ((dow - EXTRACT(DOW FROM CURRENT_DATE)::INT + 7) % 7 + 7))::DATE
$$;

-- =====================================================================
-- T1–T8: RLS anon — colunas públicas vs restritas
-- =====================================================================

-- T1: anon lê colunas públicas de servicos
DO $$
DECLARE v_count INT;
BEGIN
    SET ROLE anon;
    SELECT COUNT(*) INTO v_count FROM public.servicos
    WHERE id = 'bbbbbbbb-0000-0000-0000-000000000001' AND ativo = true;
    RESET ROLE;
    ASSERT v_count = 1, 'T1 falhou: anon não leu serviço ativo';
    RAISE NOTICE 'T1 OK — anon lê servicos (colunas públicas)';
END $$;

-- T2: anon NÃO lê coluna restrita (empresa_id) de servicos
DO $$
BEGIN
    SET ROLE anon;
    BEGIN
        PERFORM empresa_id FROM public.servicos LIMIT 1;
        RESET ROLE;
        RAISE EXCEPTION 'T2 falhou: anon leu empresa_id';
    EXCEPTION WHEN insufficient_privilege THEN
        RESET ROLE;
        RAISE NOTICE 'T2 OK — anon não lê empresa_id de servicos';
    END;
END $$;

-- T3: anon lê servico_cardapios
DO $$
DECLARE v_count INT; v_preco NUMERIC;
BEGIN
    SET ROLE anon;
    SELECT COUNT(*), MAX(preco_final) INTO v_count, v_preco FROM public.servico_cardapios
    WHERE servico_id = 'bbbbbbbb-0000-0000-0000-000000000001' AND cardapio = 'ella_studio' AND ativo = true;
    RESET ROLE;
    ASSERT v_count = 1, 'T3 falhou: anon não leu cardápio';
    ASSERT v_preco = 80.00, 'T3 falhou: preço do cardápio incorreto';
    RAISE NOTICE 'T3 OK — anon lê servico_cardapios';
END $$;

-- T4: anon NÃO lê modelo_anamnese_id de servicos
DO $$
BEGIN
    SET ROLE anon;
    BEGIN
        PERFORM modelo_anamnese_id FROM public.servicos LIMIT 1;
        RESET ROLE;
        RAISE EXCEPTION 'T4 falhou: anon leu modelo_anamnese_id de servicos';
    EXCEPTION WHEN insufficient_privilege THEN
        RESET ROLE;
        RAISE NOTICE 'T4 OK — anon não lê modelo_anamnese_id de servicos';
    END;
END $$;

-- T5: anon lê profissionais
DO $$
DECLARE v_count INT; v_espec TEXT[];
BEGIN
    SET ROLE anon;
    SELECT COUNT(*), array_agg(especialidades) INTO v_count, v_espec FROM public.profissionais
    WHERE id = 'eeeeeeee-0000-0000-0000-000000000001' AND ativo = true;
    RESET ROLE;
    ASSERT v_count = 1, 'T5 falhou: anon não leu profissional';
    ASSERT v_espec @> ARRAY['unhas'::TEXT], 'T5 falhou: especialidades não visíveis';
    RAISE NOTICE 'T5 OK — anon lê profissionais';
END $$;

-- T6: anon NÃO lê created_at de profissionais
DO $$
BEGIN
    SET ROLE anon;
    BEGIN
        PERFORM created_at FROM public.profissionais LIMIT 1;
        RESET ROLE;
        RAISE EXCEPTION 'T6 falhou: anon leu created_at de profissionais';
    EXCEPTION WHEN insufficient_privilege THEN
        RESET ROLE;
        RAISE NOTICE 'T6 OK — anon não lê created_at de profissionais';
    END;
END $$;

-- T7: anon lê profissional_fotos
DO $$
DECLARE v_count INT;
BEGIN
    INSERT INTO public.profissional_fotos (id, profissional_id, url, ordem)
    VALUES ('aaaaaaaa-0000-0000-0000-000000000099', 'eeeeeeee-0000-0000-0000-000000000001', 'https://exemplo.com/galeria.jpg', 1)
    ON CONFLICT (id) DO NOTHING;

    SET ROLE anon;
    SELECT COUNT(*) INTO v_count FROM public.profissional_fotos
    WHERE profissional_id = 'eeeeeeee-0000-0000-0000-000000000001';
    RESET ROLE;
    ASSERT v_count >= 1, 'T7 falhou: anon não leu profissional_fotos';
    RAISE NOTICE 'T7 OK — anon lê profissional_fotos';
END $$;

-- T8: anon NÃO lê created_at de profissional_fotos
DO $$
BEGIN
    SET ROLE anon;
    BEGIN
        PERFORM created_at FROM public.profissional_fotos LIMIT 1;
        RESET ROLE;
        RAISE EXCEPTION 'T8 falhou: anon leu created_at de profissional_fotos';
    EXCEPTION WHEN insufficient_privilege THEN
        RESET ROLE;
        RAISE NOTICE 'T8 OK — anon não lê created_at de profissional_fotos';
    END;
END $$;

-- =====================================================================
-- T9: profissional_fotos — escrita por authenticated da mesma empresa
-- =====================================================================
DO $$
DECLARE v_id UUID;
BEGIN
    -- Simula um utilizador autenticado da empresa via request.jwt.claims
    PERFORM set_config('request.jwt.claims', jsonb_build_object(
        'sub', '00000000-0000-0000-0000-000000000000',
        'role', 'authenticated',
        'aal', 'aal1'
    )::TEXT, true);

    -- Cria auth user e usuário interno de teste vinculado à empresa
    INSERT INTO auth.users (id) VALUES ('00000000-0000-0000-0000-000000000000') ON CONFLICT (id) DO NOTHING;
    INSERT INTO public.usuarios_internos (id, auth_user_id, empresa_id, email, nome, perfil, ativo)
    VALUES ('aaaaaaaa-0000-0000-0000-000000000100', '00000000-0000-0000-0000-000000000000',
            '00000000-0000-0000-0000-000000000001', 'teste@frontend.local', 'Teste Frontend', 'admin', true)
    ON CONFLICT (id) DO NOTHING;

    SET ROLE authenticated;
    INSERT INTO public.profissional_fotos (profissional_id, url, ordem)
    VALUES ('eeeeeeee-0000-0000-0000-000000000001', 'https://exemplo.com/nova.jpg', 2)
    RETURNING id INTO v_id;
    RESET ROLE;

    ASSERT v_id IS NOT NULL, 'T9 falhou: authenticated não inseriu foto';
    RAISE NOTICE 'T9 OK — authenticated insere profissional_fotos na mesma empresa';
END $$;

-- =====================================================================
-- T10–T18: listar_horarios_disponiveis
-- =====================================================================

-- T10: slots normais no domingo (interseção 09:00–12:00 e 14:00–18:00, duração 65)
-- Intervalo 09:00–12:00: slots 09:00, 09:30, 10:00, 10:30, 11:00 (11:30 acaba 12:35 > 12:00, não é último)
-- Intervalo 14:00–18:00: slots 14:00, 14:30, 15:00, 15:30, 16:00, 16:30 (17:00 acaba 18:05; último intervalo → permite)
-- Total esperado: 5 + 6 = 11
DO $$
DECLARE v_count INT;
BEGIN
    SELECT COUNT(*) INTO v_count
    FROM public.listar_horarios_disponiveis(
        '00000000-0000-0000-0000-000000000001',
        'bbbbbbbb-0000-0000-0000-000000000001',
        'eeeeeeee-0000-0000-0000-000000000001',
        teste_frontend_data(0),
        'ella_studio',
        30
    );
    ASSERT v_count = 12, format('T10 falhou: esperado 12 slots, obtido %s', v_count);
    RAISE NOTICE 'T10 OK — 12 slots gerados no domingo';
END $$;

-- T11: cardápio inexistente retorna vazio (sem fallback)
DO $$
DECLARE v_count INT;
BEGIN
    SELECT COUNT(*) INTO v_count
    FROM public.listar_horarios_disponiveis(
        '00000000-0000-0000-0000-000000000001',
        'bbbbbbbb-0000-0000-0000-000000000001',
        'eeeeeeee-0000-0000-0000-000000000001',
        teste_frontend_data(0),
        'ella_men',
        30
    );
    ASSERT v_count = 0, 'T11 falhou: cardápio inexistente devia retornar vazio';
    RAISE NOTICE 'T11 OK — cardápio inexistente retorna vazio';
END $$;

-- T12: bloqueio remove slots sobrepostos
DO $$
DECLARE v_count INT; v_bloqueio_inicio TIMESTAMPTZ;
BEGIN
    v_bloqueio_inicio := teste_frontend_proximo_dia(0, '10:00');

    INSERT INTO public.bloqueios (id, empresa_id, profissional_id, inicio, fim, motivo, tipo)
    VALUES ('aaaaaaaa-0000-0000-0000-000000000101', '00000000-0000-0000-0000-000000000001',
            'eeeeeeee-0000-0000-0000-000000000001',
            v_bloqueio_inicio, v_bloqueio_inicio + interval '60 minutes',
            'Bloqueio frontend teste', 'imprevisto')
    ON CONFLICT (id) DO NOTHING;

    SELECT COUNT(*) INTO v_count
    FROM public.listar_horarios_disponiveis(
        '00000000-0000-0000-0000-000000000001',
        'bbbbbbbb-0000-0000-0000-000000000001',
        'eeeeeeee-0000-0000-0000-000000000001',
        teste_frontend_data(0),
        'ella_studio',
        30
    );
    -- Remove 09:00 (termina 10:05), 09:30 (termina 10:35), 10:00 (termina 11:05), 10:30 (termina 11:35) → 4 slots a menos = 8
    ASSERT v_count = 8, format('T12 falhou: esperado 8 slots, obtido %s', v_count);
    RAISE NOTICE 'T12 OK — bloqueio removeu slots sobrepostos';
END $$;

-- T13: folga da empresa retorna vazio
DO $$
DECLARE v_count INT;
BEGIN
    INSERT INTO public.excecoes_calendario (id, empresa_id, data, tipo, motivo)
    VALUES ('aaaaaaaa-0000-0000-0000-000000000102', '00000000-0000-0000-0000-000000000001',
            teste_frontend_data(0), 'feriado', 'Feriado frontend teste')
    ON CONFLICT (id) DO NOTHING;

    SELECT COUNT(*) INTO v_count
    FROM public.listar_horarios_disponiveis(
        '00000000-0000-0000-0000-000000000001',
        'bbbbbbbb-0000-0000-0000-000000000001',
        'eeeeeeee-0000-0000-0000-000000000001',
        teste_frontend_data(0),
        'ella_studio',
        30
    );
    ASSERT v_count = 0, 'T13 falhou: folga da empresa devia retornar vazio';
    RAISE NOTICE 'T13 OK — folga da empresa retorna vazio';
END $$;

-- T14: ajuste da profissional — regra antiga, serviço tem de caber inteiro
DO $$
DECLARE v_count INT;
BEGIN
    -- Remove a folga do T13 para não interferir
    DELETE FROM public.excecoes_calendario WHERE id = 'aaaaaaaa-0000-0000-0000-000000000102';
    -- Remove o bloqueio do T12 para não interferir
    DELETE FROM public.bloqueios WHERE id = 'aaaaaaaa-0000-0000-0000-000000000101';

    -- Ajuste: profissional atende só 09:00–09:45 (serviço de 65 min não cabe)
    INSERT INTO public.excecoes_calendario (id, empresa_id, profissional_id, data, tipo, abertura, fechamento, motivo)
    VALUES ('aaaaaaaa-0000-0000-0000-000000000103', '00000000-0000-0000-0000-000000000001',
            'eeeeeeee-0000-0000-0000-000000000001', teste_frontend_data(0), 'ajuste',
            '09:00', '09:45', 'Ajuste frontend teste')
    ON CONFLICT (id) DO NOTHING;

    SELECT COUNT(*) INTO v_count
    FROM public.listar_horarios_disponiveis(
        '00000000-0000-0000-0000-000000000001',
        'bbbbbbbb-0000-0000-0000-000000000001',
        'eeeeeeee-0000-0000-0000-000000000001',
        teste_frontend_data(0),
        'ella_studio',
        30
    );
    ASSERT v_count = 0, format('T14 falhou: ajuste curto devia retornar vazio, obtido %s', v_count);
    RAISE NOTICE 'T14 OK — ajuste curto retorna vazio (regra antiga)';
END $$;

-- T20: ajuste 09:00–12:00, serviço de 65 min → 10:55 aceite, 11:00/11:30 rejeitados
DO $$
DECLARE v_tem_1055 BOOLEAN; v_tem_1100 BOOLEAN; v_tem_1130 BOOLEAN;
BEGIN
    -- T20: atualiza o ajuste do T14 para 09:00–12:00 (mesma data/profissional, nao pode haver duas excecoes)
    UPDATE public.excecoes_calendario
    SET abertura = '09:00', fechamento = '12:00', motivo = 'Ajuste frontend T20'
    WHERE id = 'aaaaaaaa-0000-0000-0000-000000000103';

    SELECT EXISTS (
        SELECT 1 FROM public.listar_horarios_disponiveis(
            '00000000-0000-0000-0000-000000000001',
            'bbbbbbbb-0000-0000-0000-000000000001',
            'eeeeeeee-0000-0000-0000-000000000001',
            teste_frontend_data(0),
            'ella_studio',
            5
        )
        WHERE (inicio AT TIME ZONE 'America/Sao_Paulo')::TIME = '10:55'::TIME
    ) INTO v_tem_1055;

    SELECT EXISTS (
        SELECT 1 FROM public.listar_horarios_disponiveis(
            '00000000-0000-0000-0000-000000000001',
            'bbbbbbbb-0000-0000-0000-000000000001',
            'eeeeeeee-0000-0000-0000-000000000001',
            teste_frontend_data(0),
            'ella_studio',
            5
        )
        WHERE (inicio AT TIME ZONE 'America/Sao_Paulo')::TIME = '11:00'::TIME
    ) INTO v_tem_1100;

    SELECT EXISTS (
        SELECT 1 FROM public.listar_horarios_disponiveis(
            '00000000-0000-0000-0000-000000000001',
            'bbbbbbbb-0000-0000-0000-000000000001',
            'eeeeeeee-0000-0000-0000-000000000001',
            teste_frontend_data(0),
            'ella_studio',
            5
        )
        WHERE (inicio AT TIME ZONE 'America/Sao_Paulo')::TIME = '11:30'::TIME
    ) INTO v_tem_1130;

    ASSERT v_tem_1055, 'T20 falhou: 10:55 devia ser aceite no ajuste 09:00–12:00';
    ASSERT NOT v_tem_1100, 'T20 falhou: 11:00 devia ser rejeitado (não cabe no ajuste)';
    ASSERT NOT v_tem_1130, 'T20 falhou: 11:30 devia ser rejeitado (não cabe no ajuste)';
    RAISE NOTICE 'T20 OK — ajuste 09:00–12:00: 10:55 aceite, 11:00/11:30 rejeitados';
END $$;

-- T15: última entrada — serviço de 65 min pode começar às 17:00 no último intervalo
DO $$
DECLARE v_count INT; v_tem_17h BOOLEAN;
BEGIN
    -- Remove ajuste do T14
    DELETE FROM public.excecoes_calendario WHERE id = 'aaaaaaaa-0000-0000-0000-000000000103';

    SELECT COUNT(*) INTO v_count
    FROM public.listar_horarios_disponiveis(
        '00000000-0000-0000-0000-000000000001',
        'bbbbbbbb-0000-0000-0000-000000000001',
        'eeeeeeee-0000-0000-0000-000000000001',
        teste_frontend_data(0),
        'ella_studio',
        30
    );
    ASSERT v_count = 12, format('T15 falhou: esperado 12 slots, obtido %s', v_count);

    SELECT EXISTS (
        SELECT 1 FROM public.listar_horarios_disponiveis(
            '00000000-0000-0000-0000-000000000001',
            'bbbbbbbb-0000-0000-0000-000000000001',
            'eeeeeeee-0000-0000-0000-000000000001',
            teste_frontend_data(0),
            'ella_studio',
            30
        )
        WHERE (inicio AT TIME ZONE 'America/Sao_Paulo')::TIME = '17:00'::TIME
    ) INTO v_tem_17h;

    ASSERT v_tem_17h, 'T15 falhou: slot das 17:00 (última entrada) devia existir';
    RAISE NOTICE 'T15 OK — última entrada às 17:00 permitida';
END $$;

-- T16: slots no passado são omitidos
DO $$
DECLARE v_count INT;
BEGIN
    SELECT COUNT(*) INTO v_count
    FROM public.listar_horarios_disponiveis(
        '00000000-0000-0000-0000-000000000001',
        'bbbbbbbb-0000-0000-0000-000000000001',
        'eeeeeeee-0000-0000-0000-000000000001',
        '2020-01-01',
        'ella_studio',
        30
    );
    ASSERT v_count = 0, format('T16 falhou: hoje no passado devia retornar vazio, obtido %s', v_count);
    RAISE NOTICE 'T16 OK — slots no passado omitidos';
END $$;

-- T17: profissional não habilitada para o serviço retorna vazio
DO $$
DECLARE v_count INT;
BEGIN
    SELECT COUNT(*) INTO v_count
    FROM public.listar_horarios_disponiveis(
        '00000000-0000-0000-0000-000000000001',
        'bbbbbbbb-0000-0000-0000-000000000001',
        '33333333-3333-3333-3333-333333333333', -- Laira, habilitada para outros serviços
        teste_frontend_data(0),
        'ella_studio',
        30
    );
    ASSERT v_count = 0, 'T17 falhou: profissional não habilitada devia retornar vazio';
    RAISE NOTICE 'T17 OK — profissional não habilitada retorna vazio';
END $$;

-- T18: anon pode executar listar_horarios_disponiveis
DO $$
DECLARE v_count INT;
BEGIN
    SET ROLE anon;
    SELECT COUNT(*) INTO v_count
    FROM public.listar_horarios_disponiveis(
        '00000000-0000-0000-0000-000000000001',
        'bbbbbbbb-0000-0000-0000-000000000001',
        'eeeeeeee-0000-0000-0000-000000000001',
        teste_frontend_data(0),
        'ella_studio',
        30
    );
    RESET ROLE;
    ASSERT v_count = 12, format('T18 falhou: anon devia ver 12 slots, viu %s', v_count);
    RAISE NOTICE 'T18 OK — anon executa listar_horarios_disponiveis';
END $$;

-- T19: anon NÃO pode executar criar_pre_reserva
DO $$
BEGIN
    SET ROLE anon;
    BEGIN
        PERFORM public.criar_pre_reserva(
            '00000000-0000-0000-0000-000000000001',
            'cccccccc-0000-0000-0000-000000000001',
            jsonb_build_array(jsonb_build_object(
                'servico_id','bbbbbbbb-0000-0000-0000-000000000001',
                'profissional_id','eeeeeeee-0000-0000-0000-000000000001',
                'cardapio','ella_studio',
                'inicio', teste_frontend_proximo_dia(0,'09:00')
            )),
            'frontend-t19'
        );
        RESET ROLE;
        RAISE EXCEPTION 'T19 falhou: anon executou criar_pre_reserva';
    EXCEPTION WHEN insufficient_privilege THEN
        RESET ROLE;
        RAISE NOTICE 'T19 OK — anon não executa criar_pre_reserva';
    END;
END $$;

-- =====================================================================
-- LIMPEZA
-- =====================================================================

DO $$
BEGIN
    DELETE FROM public.profissional_fotos
    WHERE profissional_id = 'eeeeeeee-0000-0000-0000-000000000001';

    DELETE FROM public.excecoes_calendario
    WHERE id IN ('aaaaaaaa-0000-0000-0000-000000000102', 'aaaaaaaa-0000-0000-0000-000000000103');

    DELETE FROM public.bloqueios WHERE id = 'aaaaaaaa-0000-0000-0000-000000000101';

    DELETE FROM public.agenda_ocupacoes
    WHERE profissional_id = 'eeeeeeee-0000-0000-0000-000000000001'
       OR recurso_id = 'ffffffff-0000-0000-0000-000000000001';

    DELETE FROM public.horarios_empresa
    WHERE empresa_id = '00000000-0000-0000-0000-000000000001'
      AND dia_semana = 0 AND (abertura, fechamento) IN (('09:00','12:30'),('13:30','18:00'));

    DELETE FROM public.horarios_profissional
    WHERE profissional_id = 'eeeeeeee-0000-0000-0000-000000000001';

    DELETE FROM public.recursos WHERE id = 'ffffffff-0000-0000-0000-000000000001';

    DELETE FROM public.profissional_servicos
    WHERE profissional_id = 'eeeeeeee-0000-0000-0000-000000000001'
      AND servico_id = 'bbbbbbbb-0000-0000-0000-000000000001';

    DELETE FROM public.profissionais WHERE id = 'eeeeeeee-0000-0000-0000-000000000001';
    DELETE FROM public.servico_cardapios WHERE id = 'bbbbbbbb-0000-0000-0000-000000000002';
    DELETE FROM public.servicos WHERE id = 'bbbbbbbb-0000-0000-0000-000000000001';
    DELETE FROM public.usuarios_internos WHERE id = 'aaaaaaaa-0000-0000-0000-000000000100';

    DROP FUNCTION IF EXISTS public.teste_frontend_proximo_dia(INT, TEXT);
    DROP FUNCTION IF EXISTS public.teste_frontend_data(INT);
END $$;
