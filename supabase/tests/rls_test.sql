-- rls_test.sql — isolamento multi-inquilino, privilégios de coluna, EXECUTE de funções
SET TIME ZONE 'America/Sao_Paulo';

-- Fixtures: utilizadores (stub auth.users local; no Supabase vêm do signup)
INSERT INTO auth.users (id) VALUES
('ffffffff-0000-0000-0000-000000000001'),
('ffffffff-0000-0000-0000-000000000002'),
('ffffffff-0000-0000-0000-000000000003')
ON CONFLICT (id) DO NOTHING;

INSERT INTO empresas (id, nome) VALUES ('eeeeeeee-0000-0000-0000-00000000000b', 'Empresa B Teste')
ON CONFLICT (id) DO NOTHING;

-- Fixture defensiva: cliente da ELLA usado no teste T1
INSERT INTO clientes (id, empresa_id, nome, telefone_normalizado) VALUES
('cccccccc-0000-0000-0000-000000000001', '00000000-0000-0000-0000-000000000001', 'Cliente Teste', '5519999990001')
ON CONFLICT (id) DO NOTHING;

INSERT INTO usuarios_internos (id, auth_user_id, empresa_id, email, nome, perfil) VALUES
('99999999-0000-0000-0000-000000000001', 'ffffffff-0000-0000-0000-000000000001', '00000000-0000-0000-0000-000000000001', 'admin@ella.test', 'Admin ELLA', 'admin'),
('99999999-0000-0000-0000-000000000002', 'ffffffff-0000-0000-0000-000000000002', 'eeeeeeee-0000-0000-0000-00000000000b', 'recepcao@b.test', 'Receção B', 'recepcao'),
('99999999-0000-0000-0000-000000000003', 'ffffffff-0000-0000-0000-000000000003', '00000000-0000-0000-0000-000000000001', 'laira@ella.test', 'Laira', 'profissional')
ON CONFLICT (auth_user_id) DO NOTHING;

INSERT INTO usuario_profissional (usuario_id, profissional_id) VALUES
('99999999-0000-0000-0000-000000000003', '33333333-3333-3333-3333-333333333333')
ON CONFLICT (usuario_id) DO NOTHING;

INSERT INTO clientes (id, empresa_id, nome, telefone_normalizado) VALUES
('cccccccc-0000-0000-0000-0000000000b1', 'eeeeeeee-0000-0000-0000-00000000000b', 'Cliente B', '55199999900b1')
ON CONFLICT (empresa_id, telefone_normalizado) DO NOTHING;

-- Uma reserva da ELLA para os testes (criada como sistema)
CREATE OR REPLACE FUNCTION teste_proximo_dia(dow INT, hora TEXT) RETURNS TIMESTAMPTZ
LANGUAGE sql STABLE AS $$
    SELECT ((CURRENT_DATE + ((dow - EXTRACT(DOW FROM CURRENT_DATE)::INT + 7) % 7 + 7))::TEXT || ' ' || hora)::TIMESTAMPTZ
$$;

INSERT INTO servicos (id, empresa_id, nome_tecnico, tipo_recurso_id, duracao_minutos, preco_base, anamnese_obrigatoria) VALUES
('aaaaaaaa-0000-0000-0000-000000000021', '00000000-0000-0000-0000-000000000001', 'teste_rls', '11111111-1111-1111-1111-111111111111', 60, 80.00, false)
ON CONFLICT (empresa_id, nome_tecnico) DO NOTHING;
INSERT INTO profissional_servicos (profissional_id, servico_id, empresa_id) VALUES
('33333333-3333-3333-3333-333333333333', 'aaaaaaaa-0000-0000-0000-000000000021', '00000000-0000-0000-0000-000000000001')
ON CONFLICT DO NOTHING;

DO $$
DECLARE v UUID;
BEGIN
    v := (public.criar_pre_reserva('00000000-0000-0000-0000-000000000001',
        'cccccccc-0000-0000-0000-000000000001',
        jsonb_build_array(jsonb_build_object('servico_id','aaaaaaaa-0000-0000-0000-000000000021',
            'profissional_id','33333333-3333-3333-3333-333333333333',
            'cardapio','ella_studio',
            'inicio', teste_proximo_dia(3,'11:00'))), 'rls-fixture')) ->> 'reserva_id';
    PERFORM set_config('app.teste.reserva_id', v::TEXT, false);
END $$;

-- T1: admin da ELLA vê os clientes da ELLA e NÃO vê a Empresa B
SET ROLE authenticated;
SELECT set_config('request.jwt.claims', '{"sub":"ffffffff-0000-0000-0000-000000000001","role":"authenticated"}', false);
DO $$
DECLARE v_ella INT; v_b INT;
BEGIN
    SELECT COUNT(*) INTO v_ella FROM clientes WHERE empresa_id = '00000000-0000-0000-0000-000000000001';
    SELECT COUNT(*) INTO v_b FROM clientes WHERE empresa_id = 'eeeeeeee-0000-0000-0000-00000000000b';
    ASSERT v_ella > 0, 'T1: admin devia ver clientes ELLA';
    ASSERT v_b = 0, format('T1 FALHOU: admin ELLA vê %s clientes da Empresa B', v_b);
    RAISE NOTICE 'T1 OK — admin ELLA: % clientes próprios, 0 alheios', v_ella;
END $$;
RESET ROLE;

-- T2: receção da Empresa B não vê clientes da ELLA
SET ROLE authenticated;
SELECT set_config('request.jwt.claims', '{"sub":"ffffffff-0000-0000-0000-000000000002","role":"authenticated"}', false);
DO $$
DECLARE v INT;
BEGIN
    SELECT COUNT(*) INTO v FROM clientes WHERE empresa_id = '00000000-0000-0000-0000-000000000001';
    ASSERT v = 0, format('T2 FALHOU: receção B vê %s clientes ELLA', v);
    RAISE NOTICE 'T2 OK — isolamento multi-inquilino confirmado';
END $$;
RESET ROLE;

-- T3: anon não vê nada
SET ROLE anon;
SELECT set_config('request.jwt.claims', '{"role":"anon"}', false);
DO $$
DECLARE v INT;
BEGIN
    SELECT COUNT(*) INTO v FROM clientes;
    ASSERT v = 0, format('T3 FALHOU: anon vê %s clientes', v);
    RAISE NOTICE 'T3 OK — anon sem qualquer acesso';
END $$;
RESET ROLE;

-- T4: admin NÃO consegue mudar estado diretamente (privilégio de coluna — Ricardo: RLS não obriga RPC)
SET ROLE authenticated;
SELECT set_config('request.jwt.claims', '{"sub":"ffffffff-0000-0000-0000-000000000001","role":"authenticated"}', false);
DO $$
BEGIN
    BEGIN
        EXECUTE format('UPDATE reservas SET estado = %L WHERE id = %L', 'cancelada', current_setting('app.teste.reserva_id'));
        RAISE EXCEPTION 'T4 FALHOU: mudou estado fora da RPC';
    EXCEPTION WHEN OTHERS THEN
        ASSERT SQLERRM LIKE '%permission denied for table reservas%', format('T4 erro inesperado (devia ser privilégio de coluna): %s', SQLERRM);
        RAISE NOTICE 'T4 OK — coluna estado protegida: só muda via RPC';
    END;
END $$;
RESET ROLE;

-- T5 (v3.4 / Carlos #6): admin NÃO edita NENHUMA coluna das tabelas nucleares — só via RPC
SET ROLE authenticated;
SELECT set_config('request.jwt.claims', '{"sub":"ffffffff-0000-0000-0000-000000000001","role":"authenticated"}', false);
DO $$
BEGIN
    BEGIN
        UPDATE reservas SET percentual_sinal = 35
        WHERE id = current_setting('app.teste.reserva_id')::UUID;
        RAISE EXCEPTION 'T5 FALHOU: admin editou reservas diretamente';
    EXCEPTION WHEN OTHERS THEN
        ASSERT SQLERRM LIKE '%permission denied for table reservas%', format('T5 erro inesperado: %s', SQLERRM);
        RAISE NOTICE 'T5 OK — reservas é 100%% RPC (UPDATE revogado de authenticated)';
    END;
    BEGIN
        UPDATE cobrancas SET estado = 'total_pago';
        RAISE EXCEPTION 'T5b FALHOU: admin editou cobranças diretamente';
    EXCEPTION WHEN OTHERS THEN
        ASSERT SQLERRM LIKE '%permission denied%', format('T5b erro inesperado: %s', SQLERRM);
        RAISE NOTICE 'T5b OK — cobranças idem';
    END;
END $$;
RESET ROLE;

-- T6: profissional vê os seus itens; NÃO escreve em ocupações
SET ROLE authenticated;
SELECT set_config('request.jwt.claims', '{"sub":"ffffffff-0000-0000-0000-000000000003","role":"authenticated"}', false);
DO $$
DECLARE v INT;
BEGIN
    SELECT COUNT(*) INTO v FROM reserva_itens;
    ASSERT v > 0, 'T6: profissional devia ver os seus itens';
    BEGIN
        EXECUTE 'UPDATE agenda_ocupacoes SET estado = ''cancelada''';
        RAISE EXCEPTION 'T6 FALHOU: profissional escreveu em ocupações';
    EXCEPTION WHEN OTHERS THEN
        ASSERT SQLERRM LIKE '%permission denied%', format('T6 erro inesperado: %s', SQLERRM);
        RAISE NOTICE 'T6 OK — profissional lê itens (%), ocupações só leitura', v;
    END;
END $$;
RESET ROLE;

-- T7: receção B chama criar_pre_reserva para a ELLA → guarda de inquilino
SET ROLE authenticated;
SELECT set_config('request.jwt.claims', '{"sub":"ffffffff-0000-0000-0000-000000000002","role":"authenticated"}', false);
DO $$
BEGIN
    BEGIN
        PERFORM public.criar_pre_reserva('00000000-0000-0000-0000-000000000001',
            'cccccccc-0000-0000-0000-0000000000b1', '[]'::JSONB, 'rls-t7');
        RAISE EXCEPTION 'T7 FALHOU: guarda de inquilino não disparou';
    EXCEPTION WHEN OTHERS THEN
        ASSERT SQLERRM LIKE '%Sem permissão%', format('T7 erro inesperado: %s', SQLERRM);
        RAISE NOTICE 'T7 OK — RPC bloqueia operação noutra empresa';
    END;
END $$;
RESET ROLE;

-- T8: anon NÃO executa confirmar_reserva (Ricardo #2)
SET ROLE anon;
SELECT set_config('request.jwt.claims', '{"role":"anon"}', false);
DO $$
BEGIN
    BEGIN
        PERFORM public.confirmar_reserva(gen_random_uuid());
        RAISE EXCEPTION 'T8 FALHOU: anon executou RPC privilegiada';
    EXCEPTION WHEN OTHERS THEN
        ASSERT SQLERRM LIKE '%permission denied%', format('T8 erro inesperado: %s', SQLERRM);
        RAISE NOTICE 'T8 OK — EXECUTE revogado de anon';
    END;
END $$;
RESET ROLE;

-- T9: receção NÃO insere transação diretamente (vai pela RPC registrar_pagamento_presencial)
SET ROLE authenticated;
SELECT set_config('request.jwt.claims', '{"sub":"ffffffff-0000-0000-0000-000000000002","role":"authenticated"}', false);
DO $$
BEGIN
    BEGIN
        INSERT INTO transacoes (cobranca_id, empresa_id, mp_idempotency_key, valor, meio, finalidade)
        VALUES (gen_random_uuid(), 'eeeeeeee-0000-0000-0000-00000000000b', 'x', 10, 'pix', 'sinal');
        RAISE EXCEPTION 'T9 FALHOU: receção inseriu transação direta';
    EXCEPTION WHEN OTHERS THEN
        -- v3.4: o REVOKE de INSERT dispara ANTES da RLS — ambas as mensagens provam o bloqueio
        ASSERT SQLERRM LIKE '%permission denied%' OR SQLERRM LIKE '%row-level security%' OR SQLERRM LIKE '%row violates%', format('T9 erro inesperado: %s', SQLERRM);
        RAISE NOTICE 'T9 OK — escrita financeira só via RPC (%)', SQLERRM;
    END;
END $$;
RESET ROLE;

-- T9c (v3.4): anon EXECUTA submeter_anamnese (o token é a credencial) mas token errado não revela nada
SET ROLE anon;
SELECT set_config('request.jwt.claims', '{"role":"anon"}', false);
DO $$
BEGIN
    BEGIN
        PERFORM public.submeter_anamnese('token-inexistente', '[]'::JSONB, true, 'termo');
        RAISE EXCEPTION 'T9c FALHOU: token inválido aceite';
    EXCEPTION WHEN OTHERS THEN
        ASSERT SQLERRM LIKE '%Link inválido%' OR SQLERRM LIKE '%consentimento%', format('T9c erro inesperado (devia ser de negócio, não de permissão): %s', SQLERRM);
        RAISE NOTICE 'T9c OK — anon executa a RPC; token errado = erro genérico (%)', SQLERRM;
    END;
END $$;
RESET ROLE;

-- T9d (v3.4): anon NÃO executa as RPCs novas de workflow (service_role/authenticated only)
SET ROLE anon;
SELECT set_config('request.jwt.claims', '{"role":"anon"}', false);
DO $$
BEGIN
    BEGIN
        PERFORM public.processar_pagamento_webhook('mercado_pago', 'x', 10.00);
        RAISE EXCEPTION 'T9d FALHOU: anon chamou webhook';
    EXCEPTION WHEN OTHERS THEN
        ASSERT SQLERRM LIKE '%permission denied%', format('T9d erro inesperado: %s', SQLERRM);
        RAISE NOTICE 'T9d OK — webhook só service_role';
    END;
    BEGIN
        PERFORM public.resolver_revisao(gen_random_uuid(), 'credito');
        RAISE EXCEPTION 'T9e FALHOU: anon resolveu revisão';
    EXCEPTION WHEN OTHERS THEN
        ASSERT SQLERRM LIKE '%permission denied%', format('T9e erro inesperado: %s', SQLERRM);
        RAISE NOTICE 'T9e OK — resolver_revisao revogado de anon';
    END;
END $$;
RESET ROLE;

-- T10: FK de inquilino — item com profissional de outra empresa é impossível
DO $$
BEGIN
    BEGIN
        INSERT INTO reserva_itens (reserva_id, empresa_id, nome_servico, preco_base_utilizado,
            duracao_reservada, valor_sinal, profissional_id, recurso_id, inicio, fim)
        VALUES (current_setting('app.teste.reserva_id')::UUID,
            '00000000-0000-0000-0000-000000000001', 'x', 10, 60, 3,
            'dddddddd-0000-0000-0000-0000000000b1', -- inexistente na ELLA
            '22222222-2222-2222-2222-222222222221', now(), now() + interval '1 hour');
        RAISE EXCEPTION 'T10 FALHOU: cruzamento de inquilinos aceite';
    EXCEPTION WHEN OTHERS THEN
        ASSERT SQLERRM LIKE '%violates foreign key%', format('T10 erro inesperado: %s', SQLERRM);
        RAISE NOTICE 'T10 OK — FK composta impede cruzamento entre empresas';
    END;
END $$;

-- Limpeza dos dados criados por esta suíte
DO $$
DECLARE
    v_reserva_ids UUID[];
BEGIN
    SELECT array_agg(id) INTO v_reserva_ids
    FROM public.reservas
    WHERE empresa_id = '00000000-0000-0000-0000-000000000001'
      AND idempotencia_key LIKE 'rls-%';

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
