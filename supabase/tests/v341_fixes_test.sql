-- v341_fixes_test.sql — provas das 9 correções da auditoria v3.4 → v3.4.1
-- Corre DEPOIS das 8 suítes anteriores (usa as fixtures delas).
SET TIME ZONE 'America/Sao_Paulo';

CREATE OR REPLACE FUNCTION teste_proximo_dia(dow INT, hora TEXT) RETURNS TIMESTAMPTZ
LANGUAGE sql STABLE AS $$
    SELECT ((CURRENT_DATE + ((dow - EXTRACT(DOW FROM CURRENT_DATE)::INT + 7) % 7 + 7))::TEXT || ' ' || hora)::TIMESTAMPTZ
$$;

-- Fixtures defensivas
INSERT INTO clientes (id, empresa_id, nome, telefone_normalizado) VALUES
('cccccccc-0000-0000-0000-000000000011', '00000000-0000-0000-0000-000000000001', 'Cliente Pagamento', '5519999990011')
ON CONFLICT (id) DO NOTHING;

-- Fixture defensiva: admin autenticado usado em F4 e F5
INSERT INTO auth.users (id) VALUES ('ffffffff-0000-0000-0000-000000000001') ON CONFLICT (id) DO NOTHING;
INSERT INTO usuarios_internos (id, auth_user_id, empresa_id, email, nome, perfil) VALUES
('99999999-0000-0000-0000-000000000001', 'ffffffff-0000-0000-0000-000000000001', '00000000-0000-0000-0000-000000000001', 'admin@ella.test', 'Admin ELLA', 'admin')
ON CONFLICT (auth_user_id) DO NOTHING;

INSERT INTO servicos (id, empresa_id, nome_tecnico, tipo_recurso_id, duracao_minutos, preco_base, anamnese_obrigatoria) VALUES
('aaaaaaaa-0000-0000-0000-000000000011', '00000000-0000-0000-0000-000000000001', 'teste_pagamento', '11111111-1111-1111-1111-111111111111', 60, 100.00, false),
('aaaaaaaa-0000-0000-0000-000000000031', '00000000-0000-0000-0000-000000000001', 'teste_concorrencia', '11111111-1111-1111-1111-111111111111', 60, 100.00, false)
ON CONFLICT (empresa_id, nome_tecnico) DO NOTHING;

-- Prof C (terceira profissional) — usada para não colidir com os slots das suites anteriores
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
('33333333-3333-3333-3333-333333333333', 'aaaaaaaa-0000-0000-0000-000000000011', '00000000-0000-0000-0000-000000000001'),
('dddddddd-0000-0000-0000-00000000000c', 'aaaaaaaa-0000-0000-0000-000000000011', '00000000-0000-0000-0000-000000000001'),
('dddddddd-0000-0000-0000-00000000000c', 'aaaaaaaa-0000-0000-0000-000000000031', '00000000-0000-0000-0000-000000000001')
ON CONFLICT DO NOTHING;

-- Fixture defensiva: modelo de anamnese e serviço com anamnese (usado em F8)
INSERT INTO modelos_anamnese (id, empresa_id, nome, versao) VALUES
('bbbbbbbb-0000-0000-0000-000000000002', '00000000-0000-0000-0000-000000000001', 'Modelo Regras', 1)
ON CONFLICT (id) DO NOTHING;
INSERT INTO modelo_perguntas (id, modelo_id, ordem, pergunta, tipo_resposta, obrigatoria, operador, valor_disparador, resultado_estado) VALUES
('bbbbbbbb-0000-0000-0000-0000000000a1', 'bbbbbbbb-0000-0000-0000-000000000002', 1, 'Tem alergia a esmalte?', 'sim_nao', true, 'igual', 'sim', 'requer_avaliacao')
ON CONFLICT (id) DO NOTHING;
INSERT INTO servicos (id, empresa_id, nome_tecnico, tipo_recurso_id, duracao_minutos, preco_base, anamnese_obrigatoria, modelo_anamnese_id) VALUES
('aaaaaaaa-0000-0000-0000-000000000041', '00000000-0000-0000-0000-000000000001', 'teste_regras_anamnese', '11111111-1111-1111-1111-111111111111', 60, 80.00, true, 'bbbbbbbb-0000-0000-0000-000000000002')
ON CONFLICT (empresa_id, nome_tecnico) DO NOTHING;
INSERT INTO profissional_servicos (profissional_id, servico_id, empresa_id) VALUES
('dddddddd-0000-0000-0000-00000000000c', 'aaaaaaaa-0000-0000-0000-000000000041', '00000000-0000-0000-0000-000000000001')
ON CONFLICT DO NOTHING;

-- Helper: paga o sinal de uma reserva
CREATE OR REPLACE FUNCTION teste_paga_sinal(p_reserva UUID, p_finalidade TEXT, p_valor NUMERIC) RETURNS VOID
LANGUAGE sql VOLATILE AS $$
    INSERT INTO transacoes (cobranca_id, empresa_id, mp_idempotency_key, valor, meio, finalidade, estado)
    SELECT c.id, c.empresa_id, 'teste-' || gen_random_uuid()::TEXT, p_valor, 'pix', p_finalidade, 'pago'
    FROM cobrancas c WHERE c.reserva_id = p_reserva
$$;

-- Helper: cria pré-reserva e devolve id
CREATE OR REPLACE FUNCTION teste_cria_reserva(dow INT, hora TEXT, chave TEXT) RETURNS UUID
LANGUAGE sql VOLATILE AS $$
    SELECT (public.criar_pre_reserva('00000000-0000-0000-0000-000000000001',
        'cccccccc-0000-0000-0000-000000000011',
        jsonb_build_array(jsonb_build_object('servico_id','aaaaaaaa-0000-0000-0000-000000000011',
            'profissional_id','dddddddd-0000-0000-0000-00000000000c',
            'cardapio','ella_studio',
            'inicio', teste_proximo_dia(dow, hora))), chave) ->> 'reserva_id')::UUID
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

-- Helper: agenda com anamnese e devolve {reserva_id, token, anamnese_id}
CREATE OR REPLACE FUNCTION teste_agenda_com_anamnese(p_servico TEXT, dow INT, hora TEXT, chave TEXT)
RETURNS JSONB
LANGUAGE plpgsql VOLATILE AS $$
DECLARE v JSONB;
BEGIN
    v := public.criar_pre_reserva('00000000-0000-0000-0000-000000000001',
        'cccccccc-0000-0000-0000-000000000011',
        jsonb_build_array(jsonb_build_object('servico_id', p_servico,
            'profissional_id', 'dddddddd-0000-0000-0000-00000000000c',
            'cardapio', 'ella_studio',
            'inicio', teste_proximo_dia(dow, hora))), chave);
    RETURN jsonb_build_object(
        'reserva_id', v->>'reserva_id',
        'anamnese_id', v->'anamneses'->0->>'anamnese_id',
        'token', v->'anamneses'->0->>'token');
END $$;

-- F1 (auditoria #1): cancelar os DOIS itens um a um → a fila vale EXATAMENTE o pago
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
    PERFORM public.cancelar_item_reserva(v_i2);   -- último → delega em cancelar_reserva

    SELECT COALESCE(SUM(valor_sinal),0), COUNT(*) INTO v_soma, v_n
    FROM revisoes_cancelamento WHERE reserva_id = v_r;
    ASSERT v_soma = 60.00, format('F1 REGRESSÃO (auditoria #1): fila com R$ %s por R$ 60 pagos — dinheiro contado em dobro', v_soma);
    ASSERT (SELECT estado FROM reservas WHERE id = v_r) = 'cancelada';
    RAISE NOTICE 'F1 OK — fila vale exatamente o pago (R$ % em % revisões)', v_soma, v_n;
END $$;

-- F2 (auditoria #1): bloqueio pegando DOIS itens da mesma reserva → mesma garantia
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
    ASSERT v_soma = 60.00, format('F2 REGRESSÃO (auditoria #1): bloqueio em 2 itens gerou fila de R$ %s por R$ 60 pagos', v_soma);
    ASSERT (SELECT estado FROM reservas WHERE id = v_r) = 'cancelada';
    PERFORM set_config('app.f2.bloqueio', v_res->>'bloqueio_id', false);
    RAISE NOTICE 'F2 OK — bloqueio em 2 itens: fila de R$ % (sem dupla contagem)', v_soma;
END $$;

-- F3 (auditoria #3): percentual_sinal = 0 → nasce CONFIRMADA, sem expires_at, cron não toca
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
        'F3 REGRESSÃO (auditoria #3): sinal zero não nasceu confirmada — morreria em 30 min';
    ASSERT (SELECT COUNT(*) FROM agenda_ocupacoes
            WHERE origem = 'reserva' AND origem_id = v_r AND estado = 'ativa' AND expires_at IS NULL) = 2,
        'F3: ocupações deviam ser definitivas (sem expires_at)';
    ASSERT (SELECT valor_sinal FROM cobrancas WHERE reserva_id = v_r) = 0;
    PERFORM public.expirar_pre_reservas();
    ASSERT (SELECT estado FROM reservas WHERE id = v_r) = 'confirmada', 'F3: cron mexeu em reserva sem sinal';
    RAISE NOTICE 'F3 OK — agenda vazia funciona: sinal 0 nasce confirmada e o cron ignora';
END $$;

-- F4 (auditoria #4): pagar 100% no balcão NÃO realiza; finalizar_atendimento sim — e sem MFA no caixa
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

-- caixa autenticado com aal1 (sem TOTP) — decisão de negócio: dinheiro ENTRANDO não exige MFA
SET ROLE authenticated;
SELECT set_config('request.jwt.claims', '{"sub":"ffffffff-0000-0000-0000-000000000001","role":"authenticated","aal":"aal1"}', false);
DO $$
DECLARE v_res JSONB;
BEGIN
    v_res := public.registrar_pagamento_presencial(
        current_setting('app.f4.cob')::UUID, 70.00, 'dinheiro', 'saldo', 'f4-caixa-1');
    ASSERT v_res->>'reserva_status' = 'confirmada', format('F4 REGRESSÃO (auditoria #4): pagamento marcou %s — pagar adiantado não é ter atendido', v_res->>'reserva_status');
    ASSERT (SELECT estado FROM cobrancas WHERE id = current_setting('app.f4.cob')::UUID) = 'total_pago';
    RAISE NOTICE 'F4a OK — total pago no balcão (aal1): cobrança fecha, atendimento NÃO vira realizado';
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
        RAISE EXCEPTION 'F4 FALHOU: cancelou atendimento já realizado';
    EXCEPTION WHEN OTHERS THEN
        ASSERT SQLERRM LIKE '%não pode ser cancelada%', format('F4 erro inesperado: %s', SQLERRM);
    END;
    RAISE NOTICE 'F4b OK — realizada é ação da equipe e é terminal';
END $$;

-- F5 (auditoria #5): resolver 'confirmar' não reagenda o passado; e confirmação após cron revive os itens
DO $$
DECLARE v_rev UUID; v_r UUID;
BEGIN
    v_rev := teste_cria_revisao_atrasada(3, '15:00', 'f5-passado', 30.00);
    SELECT reserva_id INTO v_r FROM revisoes_cancelamento WHERE id = v_rev;
    UPDATE reserva_itens SET inicio = now() - interval '2 days', fim = now() - interval '2 days' + interval '1 hour'
    WHERE reserva_id = v_r;
    BEGIN
        PERFORM public.resolver_revisao(v_rev, 'confirmar', 'pix caiu 3 dias depois');
        RAISE EXCEPTION 'F5 FALHOU: reagendou no passado';
    EXCEPTION WHEN OTHERS THEN
        ASSERT SQLERRM LIKE '%já passou%', format('F5 erro inesperado: %s', SQLERRM);
        RAISE NOTICE 'F5a OK — passado não se reagenda: %', SQLERRM;
    END;
    PERFORM public.resolver_revisao(v_rev, 'credito', 'horário já era');
    ASSERT (SELECT decisao_final FROM revisoes_cancelamento WHERE id = v_rev) = 'credito';
END $$;

DO $$
DECLARE v_r UUID; v_cob UUID; v_rev UUID; v_res JSONB;
BEGIN
    -- cron expira SEM pagamento (v3.4.1b: itens ficam 'pendente'), webhook chega depois → revisão → confirmar
    v_r := teste_cria_reserva(3, '15:00', 'f5b-cron-webhook');
    SELECT id INTO v_cob FROM cobrancas WHERE reserva_id = v_r;
    UPDATE agenda_ocupacoes SET expires_at = now() - interval '1 minute'
    WHERE origem = 'pre_reserva' AND origem_id = v_r;
    PERFORM public.expirar_pre_reservas();
    ASSERT (SELECT estado FROM reservas WHERE id = v_r) = 'expirada';
    ASSERT (SELECT COUNT(*) FROM reserva_itens WHERE reserva_id = v_r AND estado = 'pendente') = 1,
        'F5b: v3.4.1b — cron não-pago deixa itens pendente (cancelado = só desistência)';

    v_res := public.processar_pagamento_webhook('mercado_pago', 'evt-f5b', 30.00, NULL, v_cob, 'mp-f5b', '{}'::JSONB, true);
    ASSERT v_res->>'status' = 'pagamento_em_revisao';
    SELECT id INTO v_rev FROM revisoes_cancelamento WHERE reserva_id = v_r AND decisao_final IS NULL;

    v_res := public.resolver_revisao(v_rev, 'confirmar', 'cliente provou o pix');
    ASSERT v_res->>'reserva_status' = 'confirmada', format('F5b: status %s', v_res->>'reserva_status');
    ASSERT (SELECT COUNT(*) FROM reserva_itens WHERE reserva_id = v_r AND estado = 'confirmado') = 1,
        'F5b REGRESSÃO: reserva confirmada SEM itens (bug do cron)';
    ASSERT (SELECT COUNT(*) FROM agenda_ocupacoes
            WHERE origem = 'reserva' AND origem_id = v_r AND estado = 'ativa' AND expires_at IS NULL) = 2,
        'F5b REGRESSÃO: ocupações não foram recriadas';
    RAISE NOTICE 'F5b OK — cron→webhook→confirmar: reserva completa (item revivido + 2 ocupações)';
END $$;

-- F6 (auditoria #6): tabelas de workflow/dinheiro também são 100% RPC
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
        RAISE NOTICE 'F6a OK — bloqueios só via RPC (o frontend não consegue recriar o 23P01)';
    END;

    SELECT id INTO v_rev FROM revisoes_cancelamento WHERE decisao_final IS NULL LIMIT 1;
    IF v_rev IS NOT NULL THEN
        BEGIN
            UPDATE revisoes_cancelamento SET decisao_final = 'perdido' WHERE id = v_rev;
            RAISE EXCEPTION 'F6 FALHOU: admin decidiu revisão na mão (sem MFA, sem resolver_revisao)';
        EXCEPTION WHEN OTHERS THEN
            ASSERT SQLERRM LIKE '%permission denied%', format('F6b erro inesperado: %s', SQLERRM);
            RAISE NOTICE 'F6b OK — decisão de revisão só via resolver_revisao (com MFA)';
        END;
    END IF;

    BEGIN
        INSERT INTO lancamentos_creditos (conta_id, tipo_lancamento, valor, saldo_apos, idempotencia_key)
        SELECT conta_id, 'credito_cancelamento', 999, 999, 'fraude' FROM lancamentos_creditos LIMIT 1;
        RAISE EXCEPTION 'F6 FALHOU: admin criou crédito na mão';
    EXCEPTION WHEN OTHERS THEN
        ASSERT SQLERRM LIKE '%permission denied%' OR SQLERRM LIKE '%null value%', format('F6c erro inesperado: %s', SQLERRM);
        RAISE NOTICE 'F6c OK — créditos só via resolver_revisao';
    END;
END $$;
RESET ROLE;
SELECT set_config('request.jwt.claims', '{}', false);

-- remover_bloqueio: a saída operacional com o REVOKE em vigor
DO $$
BEGIN
    PERFORM public.remover_bloqueio(current_setting('app.f2.bloqueio')::UUID);
    ASSERT NOT EXISTS (SELECT 1 FROM bloqueios WHERE id = current_setting('app.f2.bloqueio')::UUID);
    ASSERT NOT EXISTS (SELECT 1 FROM agenda_ocupacoes
        WHERE origem = 'bloqueio' AND origem_id = current_setting('app.f2.bloqueio')::UUID AND estado = 'ativa');
    RAISE NOTICE 'F6d OK — remover_bloqueio remove e liberta as ocupações';
END $$;

-- F7 (parcial vencido): parcela de sinal SEM complemento não prende o horário — vai à fila
DO $$
DECLARE v_r UUID; v_valor DECIMAL;
BEGIN
    v_r := teste_cria_reserva(5, '16:00', 'f7-parcial');
    PERFORM teste_paga_sinal(v_r, 'saldo', 10.00);   -- parcela de 10 de um sinal de 30
    UPDATE agenda_ocupacoes SET expires_at = now() - interval '1 minute'
    WHERE origem = 'pre_reserva' AND origem_id = v_r;
    PERFORM public.expirar_pre_reservas();

    ASSERT (SELECT estado FROM reservas WHERE id = v_r) = 'pagamento_em_revisao',
        'F7 REGRESSÃO: parcial vencido ficou preso em pre_reserva';
    ASSERT NOT EXISTS (SELECT 1 FROM agenda_ocupacoes WHERE origem_id = v_r AND estado = 'ativa'),
        'F7 REGRESSÃO: parcial vencido continua a prender o slot';
    SELECT valor_sinal INTO v_valor FROM revisoes_cancelamento WHERE reserva_id = v_r;
    ASSERT v_valor = 10.00, format('F7: revisão devia ser pela parcela (10.00), veio %s', v_valor);
    PERFORM teste_cria_reserva(5, '16:00', 'f7-remarcacao');  -- o horário foi mesmo libertado
    RAISE NOTICE 'F7 OK — parcial vencido: fila de R$ % + horário re-agendável', v_valor;
END $$;

-- F8 (menor): ficha de agendamento cancelado não se responde
DO $$
DECLARE v JSONB;
BEGIN
    v := teste_agenda_com_anamnese('aaaaaaaa-0000-0000-0000-000000000041', 2, '13:30', 'f8-anamnese-morta');
    PERFORM public.cancelar_pre_reserva((v->>'reserva_id')::UUID);
    BEGIN
        PERFORM public.submeter_anamnese(v->>'token',
            jsonb_build_array(jsonb_build_object('pergunta_id','bbbbbbbb-0000-0000-0000-0000000000a1','resposta','não')),
            true, 'termo');
        RAISE EXCEPTION 'F8 FALHOU: ficha de reserva cancelada aceite';
    EXCEPTION WHEN OTHERS THEN
        ASSERT SQLERRM LIKE '%já não está ativo%', format('F8 erro inesperado: %s', SQLERRM);
        RAISE NOTICE 'F8 OK — ficha de agendamento morto rejeitada';
    END;
END $$;

-- F10 (menor): expirada tem saída — cancelar_pre_reserva limpa
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
    RAISE NOTICE 'F10 OK — expirada deixou de ser um estado sem saída';
END $$;

-- F11 (auditoria v3.4.1 — GRAVE): revisão decidida 'confirmar' NÃO pode
-- descontar da fila — o dinheiro voltou à reserva viva. Sem o filtro
-- IS DISTINCT FROM 'confirmar', um cancelamento posterior calculava 30 − 30 = 0
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
    v_res := public.resolver_revisao(v_rev, 'confirmar', 'horário livre, cliente provou o pix');
    ASSERT (SELECT estado FROM reservas WHERE id = v_r) = 'confirmada';
    ASSERT (SELECT decisao_final FROM revisoes_cancelamento WHERE id = v_rev) = 'confirmar';

    -- semanas depois a cliente cancela: a fila TEM de nascer com os R$ 30 outra vez
    PERFORM public.cancelar_reserva(v_r, NULL, 'cliente desistiu');
    SELECT COALESCE(SUM(valor_sinal), 0) INTO v_soma
    FROM revisoes_cancelamento WHERE reserva_id = v_r AND decisao_final IS NULL;
    ASSERT v_soma = 30.00, format('F11 REGRESSÃO (GRAVE): cancelamento após confirmar abriu fila de R$ %s — devia ser R$ 30.00 (o confirmar devolveu o dinheiro à reserva)', v_soma);
    ASSERT (SELECT estado FROM reservas WHERE id = v_r) = 'cancelada';
    RAISE NOTICE 'F11 OK — confirmar não desconta: cancelamento posterior reabre fila de R$ 30';
END $$;

-- F12 (auditoria v3.4.1 — MÉDIO): resolver('confirmar') NÃO ressuscita item que a
-- cliente cancelou de propósito. Pré-reserva com 2 serviços, desistência de um
-- (sem dinheiro → sem revisão), sinal atrasado, admin confirma → só o item
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

    -- cliente desiste do 2.º serviço ANTES de pagar (sem dinheiro → sem revisão)
    PERFORM public.cancelar_item_reserva(v_i2, NULL, 'cliente desistiu deste serviço');
    ASSERT (SELECT estado FROM reserva_itens WHERE id = v_i2) = 'cancelado';
    ASSERT NOT EXISTS (SELECT 1 FROM revisoes_cancelamento WHERE reserva_id = v_r);

    -- sinal chega atrasado: cron expira (v3.4.1b: itens ficam pendente), webhook, admin confirma
    UPDATE agenda_ocupacoes SET expires_at = now() - interval '1 minute'
    WHERE origem = 'pre_reserva' AND origem_id = v_r;
    PERFORM public.expirar_pre_reservas();
    v_res := public.processar_pagamento_webhook('mercado_pago', 'evt-f12', 30.00, NULL, v_cob, 'mp-f12', '{}'::JSONB, true);
    ASSERT v_res->>'status' = 'pagamento_em_revisao';
    SELECT id INTO v_rev FROM revisoes_cancelamento WHERE reserva_id = v_r AND decisao_final IS NULL;
    v_res := public.resolver_revisao(v_rev, 'confirmar', 'horário livre');

    ASSERT (SELECT estado FROM reserva_itens WHERE id = v_i1) = 'confirmado',
        'F12: item pendente devia ter sido revivido';
    ASSERT (SELECT estado FROM reserva_itens WHERE id = v_i2) = 'cancelado',
        'F12 REGRESSÃO (MÉDIO): item recusado pela cliente foi RESSUSCITADO pelo confirmar';
    ASSERT (SELECT COUNT(*) FROM agenda_ocupacoes
            WHERE origem = 'reserva' AND origem_id = v_r AND estado = 'ativa') = 2,
        'F12 REGRESSÃO: ocupações a mais — item cancelado voltou à agenda';

    -- bónus (amarra F11 ao caminho do item): cancelar o item revivido → fila com os R$ 30
    PERFORM public.cancelar_item_reserva(v_i1, NULL, 'cliente cancelou tudo');
    SELECT COALESCE(SUM(valor_sinal), 0) INTO v_soma
    FROM revisoes_cancelamento WHERE reserva_id = v_r AND decisao_final IS NULL;
    ASSERT v_soma = 30.00, format('F12/F11 REGRESSÃO: fila de R$ %s após cancelar item confirmado — devia ser R$ 30.00', v_soma);
    RAISE NOTICE 'F12 OK — confirmar revive só pendente; item recusado não volta (e cancelar depois abre fila certa)';
END $$;

-- F13 (achado da prova de corrida F9 — GRAVE): webhook de saldo chega DEPOIS do
-- cancelamento. Antes: a revisão aberta (30) fazia o índice único engolir o novo
-- INSERT (100) → R$ 70 sem rasto. Agora a fila aberta é completada para o pago total.
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

    -- o saldo (70) cai no webhook com a reserva já cancelada
    v_res := public.processar_pagamento_webhook('mercado_pago', 'evt-f13', 70.00, NULL, v_cob, 'mp-f13', '{}'::JSONB, true);
    ASSERT v_res->>'status' = 'revisao_manual', format('F13: status %s', v_res->>'status');

    SELECT COALESCE(SUM(valor_sinal),0), COUNT(*) INTO v_soma, v_n
    FROM revisoes_cancelamento WHERE reserva_id = v_r AND decisao_final IS NULL;
    ASSERT v_soma = 100.00, format('F13 REGRESSÃO (GRAVE): fila aberta de R$ %s por R$ 100 pagos — dinheiro sem rasto', v_soma);
    ASSERT v_n = 1, format('F13: devia haver UMA revisão aberta ao nível da reserva, há %s', v_n);
    RAISE NOTICE 'F13 OK — saldo pós-cancelamento: fila completada para os R$ 100 pagos';
END $$;

-- F14 (mesma família): 2.º pagamento com a reserva JÁ em revisão entra na fila
-- (antes só notificava — a fila ficava curta)
DO $$
DECLARE v_r UUID; v_cob UUID; v_res JSONB; v_soma DECIMAL; v_n INT;
BEGIN
    v_r := (public.criar_pre_reserva('00000000-0000-0000-0000-000000000001',
        'cccccccc-0000-0000-0000-000000000011',
        jsonb_build_array(jsonb_build_object('servico_id','aaaaaaaa-0000-0000-0000-000000000011',
            'profissional_id','dddddddd-0000-0000-0000-00000000000c', 'cardapio','ella_studio', 'inicio', teste_proximo_dia(4,'13:00'))),
        'f14-topup-revisao')) ->> 'reserva_id';
    SELECT id INTO v_cob FROM cobrancas WHERE reserva_id = v_r;

    -- parcial de 10 (< sinal 30) → registado; cron expira → revisão de 10
    v_res := public.processar_pagamento_webhook('mercado_pago', 'evt-f14a', 10.00, NULL, v_cob, 'mp-f14a', '{}'::JSONB, true);
    ASSERT v_res->>'status' = 'parcial_registrado', format('F14: status %s', v_res->>'status');
    UPDATE agenda_ocupacoes SET expires_at = now() - interval '1 minute'
    WHERE origem = 'pre_reserva' AND origem_id = v_r;
    PERFORM public.expirar_pre_reservas();
    ASSERT (SELECT estado FROM reservas WHERE id = v_r) = 'pagamento_em_revisao';
    ASSERT (SELECT valor_sinal FROM revisoes_cancelamento WHERE reserva_id = v_r AND decisao_final IS NULL) = 10.00;

    -- mais 20 no webhook com a reserva em revisão → fila passa a valer 30
    v_res := public.processar_pagamento_webhook('mercado_pago', 'evt-f14b', 20.00, NULL, v_cob, 'mp-f14b', '{}'::JSONB, true);
    ASSERT v_res->>'status' = 'pagamento_em_revisao';
    SELECT COALESCE(SUM(valor_sinal),0), COUNT(*) INTO v_soma, v_n
    FROM revisoes_cancelamento WHERE reserva_id = v_r AND decisao_final IS NULL;
    ASSERT v_soma = 30.00, format('F14 REGRESSÃO: fila de R$ %s por R$ 30 pagos — 2.º pagamento não entrou na fila', v_soma);
    ASSERT v_n = 1, format('F14: devia haver UMA revisão aberta ao nível da reserva, há %s', v_n);
    RAISE NOTICE 'F14 OK — pagamento em revisão entra na fila: R$ 10 + R$ 20 = R$ 30';
END $$;

-- Limpeza dos dados criados por esta suíte
DO $$
DECLARE
    v_reserva_ids UUID[];
BEGIN
    SELECT array_agg(id) INTO v_reserva_ids
    FROM public.reservas
    WHERE empresa_id = '00000000-0000-0000-0000-000000000001'
      AND idempotencia_key LIKE 'f%';

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

    DELETE FROM public.webhook_inbox WHERE external_event_id LIKE 'evt-f%';

    DELETE FROM public.bloqueios
    WHERE empresa_id = '00000000-0000-0000-0000-000000000001'
      AND motivo = 'Prof C ficou doente';

    DELETE FROM public.agenda_ocupacoes
    WHERE origem = 'bloqueio'
      AND origem_id IN (
          SELECT id FROM public.bloqueios
          WHERE empresa_id = '00000000-0000-0000-0000-000000000001'
            AND motivo = 'Prof C ficou doente'
      );

    DELETE FROM public.excecoes_calendario
    WHERE empresa_id = '00000000-0000-0000-0000-000000000001'
      AND motivo LIKE 'Teste%';

    DROP FUNCTION IF EXISTS public.teste_proximo_dia(INT, TEXT);
    DROP FUNCTION IF EXISTS public.teste_paga_sinal(UUID, TEXT, NUMERIC);
    DROP FUNCTION IF EXISTS public.teste_cria_reserva(INT, TEXT, TEXT);
    DROP FUNCTION IF EXISTS public.teste_cria_revisao_atrasada(INT, TEXT, NUMERIC);
    DROP FUNCTION IF EXISTS public.teste_agenda_com_anamnese(TEXT, INT, TEXT, TEXT);
END $$;
