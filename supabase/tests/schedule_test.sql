-- schedule_test.sql — horários, almoço, bloqueios, exceções, anamnese sem modelo
-- Corre como superuser (as RPCs são SECURITY DEFINER).
SET TIME ZONE 'America/Sao_Paulo';

-- Fixtures
INSERT INTO servicos (id, empresa_id, nome_tecnico, tipo_recurso_id, duracao_minutos, preco_base, anamnese_obrigatoria) VALUES
('aaaaaaaa-0000-0000-0000-000000000001', '00000000-0000-0000-0000-000000000001', 'teste_manicure', '11111111-1111-1111-1111-111111111111', 60, 50.00, false),
('aaaaaaaa-0000-0000-0000-000000000003', '00000000-0000-0000-0000-000000000001', 'teste_sem_modelo', '11111111-1111-1111-1111-111111111111', 60, 50.00, true);

INSERT INTO profissionais (id, empresa_id, nome) VALUES
('dddddddd-0000-0000-0000-000000000001', '00000000-0000-0000-0000-000000000001', 'Prof B Teste');

INSERT INTO profissional_servicos (profissional_id, servico_id, empresa_id) VALUES
('33333333-3333-3333-3333-333333333333', 'aaaaaaaa-0000-0000-0000-000000000001', '00000000-0000-0000-0000-000000000001'),
('33333333-3333-3333-3333-333333333333', 'aaaaaaaa-0000-0000-0000-000000000003', '00000000-0000-0000-0000-000000000001'),
('dddddddd-0000-0000-0000-000000000001', 'aaaaaaaa-0000-0000-0000-000000000001', '00000000-0000-0000-0000-000000000001');

INSERT INTO horarios_profissional (profissional_id, dia_semana, abertura, fechamento) VALUES
('dddddddd-0000-0000-0000-000000000001', 2, '09:00', '17:00'),
('dddddddd-0000-0000-0000-000000000001', 3, '09:00', '17:00'),
('dddddddd-0000-0000-0000-000000000001', 4, '09:00', '17:00'),
('dddddddd-0000-0000-0000-000000000001', 5, '09:00', '17:00'),
('dddddddd-0000-0000-0000-000000000001', 6, '09:00', '13:00'); -- v3.4.2: sábado p/ testar última entrada de 13h

INSERT INTO clientes (id, empresa_id, nome, telefone_normalizado) VALUES
('cccccccc-0000-0000-0000-000000000001', '00000000-0000-0000-0000-000000000001', 'Cliente Teste', '5519999990001');

-- Helper: próxima data com dado dia da semana (2=terça ... 5=sexta), sempre no futuro
CREATE OR REPLACE FUNCTION teste_proximo_dia(dow INT, hora TEXT) RETURNS TIMESTAMPTZ
LANGUAGE sql STABLE AS $$
    SELECT ((CURRENT_DATE + ((dow - EXTRACT(DOW FROM CURRENT_DATE)::INT + 7) % 7 + 7))::TEXT || ' ' || hora)::TIMESTAMPTZ
$$;

-- T1: agendamento válido terça 10:00 → cria
DO $$
DECLARE v JSONB;
BEGIN
    v := public.criar_pre_reserva('00000000-0000-0000-0000-000000000001',
        'cccccccc-0000-0000-0000-000000000001',
        jsonb_build_array(jsonb_build_object('servico_id','aaaaaaaa-0000-0000-0000-000000000001',
            'profissional_id','33333333-3333-3333-3333-333333333333',
            'cardapio','ella_studio',
            'inicio', teste_proximo_dia(2,'10:00'))),
        'sched-t1');
    ASSERT (v->>'idempotente')::BOOLEAN = false, 'T1: devia ser novo';
    RAISE NOTICE 'T1 OK — pré-reserva criada %', v->>'reserva_id';
END $$;

-- T2: mesma chave → idempotente, mesma reserva
DO $$
DECLARE v1 JSONB; v2 JSONB;
BEGIN
    SELECT (public.criar_pre_reserva('00000000-0000-0000-0000-000000000001',
        'cccccccc-0000-0000-0000-000000000001',
        jsonb_build_array(jsonb_build_object('servico_id','aaaaaaaa-0000-0000-0000-000000000001',
            'profissional_id','33333333-3333-3333-3333-333333333333',
            'cardapio','ella_studio',
            'inicio', teste_proximo_dia(2,'14:00'))), 'sched-t2a')) INTO v1;
    SELECT (public.criar_pre_reserva('00000000-0000-0000-0000-000000000001',
        'cccccccc-0000-0000-0000-000000000001',
        jsonb_build_array(jsonb_build_object('servico_id','aaaaaaaa-0000-0000-0000-000000000001',
            'profissional_id','33333333-3333-3333-3333-333333333333',
            'cardapio','ella_studio',
            'inicio', teste_proximo_dia(2,'14:00'))), 'sched-t2a')) INTO v2;
    ASSERT v1->>'reserva_id' = v2->>'reserva_id' AND (v2->>'idempotente')::BOOLEAN = true, 'T2 falhou';
    RAISE NOTICE 'T2 OK — idempotência devolveu a mesma reserva';
END $$;

-- T3: conflito de profissional (10:30 sobrepõe 10:00–11:00) → falha
DO $$
BEGIN
    BEGIN
        PERFORM public.criar_pre_reserva('00000000-0000-0000-0000-000000000001',
            'cccccccc-0000-0000-0000-000000000001',
            jsonb_build_array(jsonb_build_object('servico_id','aaaaaaaa-0000-0000-0000-000000000001',
                'profissional_id','33333333-3333-3333-3333-333333333333',
                'cardapio','ella_studio',
            'inicio', teste_proximo_dia(2,'10:30'))), 'sched-t3');
        RAISE EXCEPTION 'T3 FALHOU: conflito aceite';
    EXCEPTION WHEN OTHERS THEN
        ASSERT SQLERRM LIKE '%indisponível%', format('T3 erro inesperado: %s', SQLERRM);
        RAISE NOTICE 'T3 OK — conflito de profissional rejeitado';
    END;
END $$;

-- T4: ALMOÇO — 12:30 não é agendável (Ricardo #7)
DO $$
BEGIN
    BEGIN
        PERFORM public.criar_pre_reserva('00000000-0000-0000-0000-000000000001',
            'cccccccc-0000-0000-0000-000000000001',
            jsonb_build_array(jsonb_build_object('servico_id','aaaaaaaa-0000-0000-0000-000000000001',
                'profissional_id','33333333-3333-3333-3333-333333333333',
                'cardapio','ella_studio',
            'inicio', teste_proximo_dia(3,'12:30'))), 'sched-t4');
        RAISE EXCEPTION 'T4 FALHOU: agendou durante o almoço';
    EXCEPTION WHEN OTHERS THEN
        ASSERT SQLERRM LIKE '%não atende%', format('T4 erro inesperado: %s', SQLERRM);
        RAISE NOTICE 'T4 OK — almoço 12:30–13:30 protegido';
    END;
END $$;

-- T5: 13:30 (regresso do almoço) → cria
DO $$
BEGIN
    PERFORM public.criar_pre_reserva('00000000-0000-0000-0000-000000000001',
        'cccccccc-0000-0000-0000-000000000001',
        jsonb_build_array(jsonb_build_object('servico_id','aaaaaaaa-0000-0000-0000-000000000001',
            'profissional_id','33333333-3333-3333-3333-333333333333',
            'cardapio','ella_studio',
            'inicio', teste_proximo_dia(3,'13:30'))), 'sched-t5');
    RAISE NOTICE 'T5 OK — 13:30 agendável (segundo intervalo do dia)';
END $$;

-- T6: domingo → falha
DO $$
BEGIN
    BEGIN
        PERFORM public.criar_pre_reserva('00000000-0000-0000-0000-000000000001',
            'cccccccc-0000-0000-0000-000000000001',
            jsonb_build_array(jsonb_build_object('servico_id','aaaaaaaa-0000-0000-0000-000000000001',
                'profissional_id','33333333-3333-3333-3333-333333333333',
                'cardapio','ella_studio',
            'inicio', teste_proximo_dia(0,'10:00'))), 'sched-t6');
        RAISE EXCEPTION 'T6 FALHOU: domingo aceite';
    EXCEPTION WHEN OTHERS THEN
        ASSERT SQLERRM LIKE '%horário de funcionamento%', format('T6 erro inesperado: %s', SQLERRM);
        RAISE NOTICE 'T6 OK — domingo rejeitado';
    END;
END $$;

-- T7: passado → falha
DO $$
BEGIN
    BEGIN
        PERFORM public.criar_pre_reserva('00000000-0000-0000-0000-000000000001',
            'cccccccc-0000-0000-0000-000000000001',
            jsonb_build_array(jsonb_build_object('servico_id','aaaaaaaa-0000-0000-0000-000000000001',
                'profissional_id','33333333-3333-3333-3333-333333333333',
                'cardapio','ella_studio',
            'inicio', now() - interval '1 hour')), 'sched-t7');
        RAISE EXCEPTION 'T7 FALHOU: passado aceite';
    EXCEPTION WHEN OTHERS THEN
        ASSERT SQLERRM LIKE '%passado%', format('T7 erro inesperado: %s', SQLERRM);
        RAISE NOTICE 'T7 OK — passado rejeitado';
    END;
END $$;

-- T8: anamnese obrigatória SEM modelo → falha (Ricardo #8)
DO $$
BEGIN
    BEGIN
        PERFORM public.criar_pre_reserva('00000000-0000-0000-0000-000000000001',
            'cccccccc-0000-0000-0000-000000000001',
            jsonb_build_array(jsonb_build_object('servico_id','aaaaaaaa-0000-0000-0000-000000000003',
                'profissional_id','33333333-3333-3333-3333-333333333333',
                'cardapio','ella_studio',
            'inicio', teste_proximo_dia(4,'15:00'))), 'sched-t8');
        RAISE EXCEPTION 'T8 FALHOU: anamnese obrigatória ignorada';
    EXCEPTION WHEN OTHERS THEN
        ASSERT SQLERRM LIKE '%não tem modelo configurado%', format('T8 erro inesperado: %s', SQLERRM);
        RAISE NOTICE 'T8 OK — serviço sem modelo de anamnese bloqueado';
    END;
END $$;

-- T9: bloqueio de imprevisto ocupa a agenda → falha agendar no período
DO $$
DECLARE v_quinta TIMESTAMPTZ;
BEGIN
    v_quinta := teste_proximo_dia(4,'10:00');
    INSERT INTO bloqueios (empresa_id, profissional_id, inicio, fim, motivo, tipo) VALUES
    ('00000000-0000-0000-0000-000000000001', '33333333-3333-3333-3333-333333333333',
     v_quinta, v_quinta + interval '60 minutes', 'Teste imprevisto', 'imprevisto');
    BEGIN
        PERFORM public.criar_pre_reserva('00000000-0000-0000-0000-000000000001',
            'cccccccc-0000-0000-0000-000000000001',
            jsonb_build_array(jsonb_build_object('servico_id','aaaaaaaa-0000-0000-0000-000000000001',
                'profissional_id','33333333-3333-3333-3333-333333333333',
                'cardapio','ella_studio',
            'inicio', v_quinta)), 'sched-t9');
        RAISE EXCEPTION 'T9 FALHOU: bloqueio ignorado';
    EXCEPTION WHEN OTHERS THEN
        ASSERT SQLERRM LIKE '%indisponível%', format('T9 erro inesperado: %s', SQLERRM);
        RAISE NOTICE 'T9 OK — bloqueio respeitado';
    END;
END $$;

-- T10: segunda profissional usa a SEGUNDA mesa no mesmo horário (recursos independentes)
DO $$
BEGIN
    PERFORM public.criar_pre_reserva('00000000-0000-0000-0000-000000000001',
        'cccccccc-0000-0000-0000-000000000001',
        jsonb_build_array(jsonb_build_object('servico_id','aaaaaaaa-0000-0000-0000-000000000001',
            'profissional_id','dddddddd-0000-0000-0000-000000000001',
            'cardapio','ella_studio',
            'inicio', teste_proximo_dia(2,'10:00'))), 'sched-t10');
    RAISE NOTICE 'T10 OK — Prof B na Mesa 2 em simultâneo com Laira na Mesa 1';
END $$;

-- T11: sábado 14:00 (empresa fecha 13:00) → falha
DO $$
BEGIN
    BEGIN
        PERFORM public.criar_pre_reserva('00000000-0000-0000-0000-000000000001',
            'cccccccc-0000-0000-0000-000000000001',
            jsonb_build_array(jsonb_build_object('servico_id','aaaaaaaa-0000-0000-0000-000000000001',
                'profissional_id','33333333-3333-3333-3333-333333333333',
                'cardapio','ella_studio',
            'inicio', teste_proximo_dia(6,'14:00'))), 'sched-t11');
        RAISE EXCEPTION 'T11 FALHOU: sábado à tarde aceite';
    EXCEPTION WHEN OTHERS THEN
        ASSERT SQLERRM LIKE '%horário de funcionamento%' OR SQLERRM LIKE '%não atende%', format('T11 erro inesperado: %s', SQLERRM);
        RAISE NOTICE 'T11 OK — sábado à tarde rejeitado';
    END;
END $$;

-- T12: cancelamento INDIVIDUAL — reserva com 2 itens, cancela 1, o outro fica (Ricardo #11)
DO $$
DECLARE v JSONB; v_item1 UUID; v_item2 UUID; v_ativas INT;
BEGIN
    v := public.criar_pre_reserva('00000000-0000-0000-0000-000000000001',
        'cccccccc-0000-0000-0000-000000000001',
        jsonb_build_array(
            jsonb_build_object('servico_id','aaaaaaaa-0000-0000-0000-000000000001',
                'profissional_id','33333333-3333-3333-3333-333333333333', 'cardapio','ella_studio', 'inicio', teste_proximo_dia(5,'09:00')),
            jsonb_build_object('servico_id','aaaaaaaa-0000-0000-0000-000000000001',
                'profissional_id','dddddddd-0000-0000-0000-000000000001', 'cardapio','ella_studio', 'inicio', teste_proximo_dia(5,'09:00'))
        ), 'sched-t12');
    SELECT id INTO v_item1 FROM reserva_itens WHERE reserva_id = (v->>'reserva_id')::UUID
        AND profissional_id = '33333333-3333-3333-3333-333333333333';
    SELECT id INTO v_item2 FROM reserva_itens WHERE reserva_id = (v->>'reserva_id')::UUID
        AND profissional_id = 'dddddddd-0000-0000-0000-000000000001';

    PERFORM public.cancelar_item_reserva(v_item1);

    SELECT COUNT(*) INTO v_ativas FROM agenda_ocupacoes
    WHERE reserva_item_id = v_item2 AND estado = 'ativa';
    ASSERT v_ativas = 2, 'T12: ocupações do item 2 deviam continuar ativas';
    ASSERT EXISTS (SELECT 1 FROM agenda_ocupacoes WHERE reserva_item_id = v_item1 AND estado = 'cancelada'),
        'T12: ocupações do item 1 deviam estar canceladas';
    ASSERT (SELECT estado FROM reservas WHERE id = (v->>'reserva_id')::UUID) = 'pre_reserva',
        'T12: reserva devia continuar pré-reserva (ainda tem 1 item)';
    ASSERT (SELECT valor_total FROM reservas WHERE id = (v->>'reserva_id')::UUID) = 50.00,
        'T12: total devia ter sido recalculado para 1 item';
    RAISE NOTICE 'T12 OK — cancelamento individual liberta só o item cancelado';
END $$;

-- ================= v3.4.2 — regra da "última entrada" (migração 012) =================
-- 17h não é fechar o studio: é receber o ÚLTIMO cliente. O serviço pode passar da
-- hora SÓ no último intervalo do dia. Almoço e ajustes (exceções) continuam rigorosos.

-- T13: Prof B sábado 12:30 + 60 min → acaba 13:30 (passa das 13h no ÚLTIMO intervalo) → CRIA
DO $$
BEGIN
    PERFORM public.criar_pre_reserva('00000000-0000-0000-0000-000000000001',
        'cccccccc-0000-0000-0000-000000000001',
        jsonb_build_array(jsonb_build_object('servico_id','aaaaaaaa-0000-0000-0000-000000000001',
            'profissional_id','dddddddd-0000-0000-0000-000000000001',
            'cardapio','ella_studio',
            'inicio', teste_proximo_dia(6,'12:30'))), 'sched-t13');
    RAISE NOTICE 'T13 OK — cliente das 12:30 de sábado pode acabar 13:30 (última entrada)';
END $$;

-- T14: Prof B quarta 17:00 em ponto + 60 min → acaba 18:00 → CRIA (último cliente às 17h)
DO $$
BEGIN
    PERFORM public.criar_pre_reserva('00000000-0000-0000-0000-000000000001',
        'cccccccc-0000-0000-0000-000000000001',
        jsonb_build_array(jsonb_build_object('servico_id','aaaaaaaa-0000-0000-0000-000000000001',
            'profissional_id','dddddddd-0000-0000-0000-000000000001',
            'cardapio','ella_studio',
            'inicio', teste_proximo_dia(3,'17:00'))), 'sched-t14');
    RAISE NOTICE 'T14 OK — começar exatamente às 17:00 é permitido';
END $$;

-- T15: quinta 17:30 (DEPOIS da última entrada) → falha
DO $$
BEGIN
    BEGIN
        PERFORM public.criar_pre_reserva('00000000-0000-0000-0000-000000000001',
            'cccccccc-0000-0000-0000-000000000001',
            jsonb_build_array(jsonb_build_object('servico_id','aaaaaaaa-0000-0000-0000-000000000001',
                'profissional_id','33333333-3333-3333-3333-333333333333',
                'cardapio','ella_studio',
            'inicio', teste_proximo_dia(4,'17:30'))), 'sched-t15');
        RAISE EXCEPTION 'T15 FALHOU: agendou depois das 17h';
    EXCEPTION WHEN OTHERS THEN
        ASSERT SQLERRM LIKE '%horário de funcionamento%', format('T15 erro inesperado: %s', SQLERRM);
        RAISE NOTICE 'T15 OK — depois das 17:00 não entra ninguém';
    END;
END $$;

-- T16: sexta 12:00 + 60 min → atravessa o almoço (12:30 não é o último do dia) → falha
DO $$
BEGIN
    BEGIN
        PERFORM public.criar_pre_reserva('00000000-0000-0000-0000-000000000001',
            'cccccccc-0000-0000-0000-000000000001',
            jsonb_build_array(jsonb_build_object('servico_id','aaaaaaaa-0000-0000-0000-000000000001',
                'profissional_id','33333333-3333-3333-3333-333333333333',
                'cardapio','ella_studio',
            'inicio', teste_proximo_dia(5,'12:00'))), 'sched-t16');
        RAISE EXCEPTION 'T16 FALHOU: serviço atravessou o almoço';
    EXCEPTION WHEN OTHERS THEN
        ASSERT SQLERRM LIKE '%não atende%', format('T16 erro inesperado: %s', SQLERRM);
        RAISE NOTICE 'T16 OK — almoço continua protegido (só o último intervalo estica)';
    END;
END $$;

-- T17/T18: dia de AJUSTE (exceção) — regra antiga: o serviço tem de caber inteiro.
-- Cenário: sexta especial, Laira atende 09:00–15:00 (compromisso às 15h).
INSERT INTO excecoes_calendario (empresa_id, profissional_id, data, tipo, abertura, fechamento, motivo)
VALUES ('00000000-0000-0000-0000-000000000001', '33333333-3333-3333-3333-333333333333',
        teste_proximo_dia(5,'00:00')::DATE, 'ajuste', '09:00', '15:00', 'Teste v3.4.2 — saída às 15h');

-- T17: sexta 12:00 + 60 min → acaba 13:00 (cabe inteiro antes das 15h) → CRIA
DO $$
BEGIN
    PERFORM public.criar_pre_reserva('00000000-0000-0000-0000-000000000001',
        'cccccccc-0000-0000-0000-000000000001',
        jsonb_build_array(jsonb_build_object('servico_id','aaaaaaaa-0000-0000-0000-000000000001',
            'profissional_id','33333333-3333-3333-3333-333333333333',
            'cardapio','ella_studio',
            'inicio', teste_proximo_dia(5,'12:00'))), 'sched-t17');
    RAISE NOTICE 'T17 OK — em dia de ajuste, serviço que cabe inteiro entra';
END $$;

-- T18: sexta 15:00 + 60 min → acabaria 16:00, depois da saída → falha (ajuste NÃO estica)
DO $$
BEGIN
    BEGIN
        PERFORM public.criar_pre_reserva('00000000-0000-0000-0000-000000000001',
            'cccccccc-0000-0000-0000-000000000001',
            jsonb_build_array(jsonb_build_object('servico_id','aaaaaaaa-0000-0000-0000-000000000001',
                'profissional_id','33333333-3333-3333-3333-333333333333',
                'cardapio','ella_studio',
            'inicio', teste_proximo_dia(5,'15:00'))), 'sched-t18');
        RAISE EXCEPTION 'T18 FALHOU: esticou num dia de ajuste';
    EXCEPTION WHEN OTHERS THEN
        ASSERT SQLERRM LIKE '%horário especial%', format('T18 erro inesperado: %s', SQLERRM);
        RAISE NOTICE 'T18 OK — dia de ajuste não estica (saída às 15h respeitada)';
    END;
END $$;

-- Limpeza: o ajuste de teste não pode vazar para os outros ficheiros da suíte
DELETE FROM excecoes_calendario
WHERE empresa_id = '00000000-0000-0000-0000-000000000001'
  AND profissional_id = '33333333-3333-3333-3333-333333333333'
  AND tipo = 'ajuste' AND motivo = 'Teste v3.4.2 — saída às 15h';
