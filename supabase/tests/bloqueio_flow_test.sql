-- bloqueio_flow_test.sql (v3.4 NOVO) — criar_bloqueio_com_conflito (regressão Ricardo):
-- bloquear a agenda em cima de horário ocupado NÃO estoura exclusion_violation crua —
-- cancela os itens afetados pelo fluxo normal (regra 16h + revisão de valores) e avisa.
SET TIME ZONE 'America/Sao_Paulo';

CREATE OR REPLACE FUNCTION teste_proximo_dia(dow INT, hora TEXT) RETURNS TIMESTAMPTZ
LANGUAGE sql STABLE AS $$
    SELECT ((CURRENT_DATE + ((dow - EXTRACT(DOW FROM CURRENT_DATE)::INT + 7) % 7 + 7))::TEXT || ' ' || hora)::TIMESTAMPTZ
$$;

INSERT INTO profissional_servicos (profissional_id, servico_id, empresa_id) VALUES
('dddddddd-0000-0000-0000-000000000001', 'aaaaaaaa-0000-0000-0000-000000000011', '00000000-0000-0000-0000-000000000001')
ON CONFLICT DO NOTHING;

-- B1: reserva confirmada paga + bloqueio por cima → cancelada com revisão CHEIA + aviso na fila
DO $$
DECLARE v_r UUID; v_inicio TIMESTAMPTZ; v_res JSONB; v_valor DECIMAL;
BEGIN
    v_r := teste_cria_reserva(5, '14:00', 'bloq-b1');
    PERFORM teste_paga_sinal(v_r, 'sinal', 30.00);
    PERFORM public.confirmar_reserva(v_r);
    v_inicio := teste_proximo_dia(5, '13:00');

    v_res := public.criar_bloqueio_com_conflito(
        '33333333-3333-3333-3333-333333333333', v_inicio, v_inicio + interval '2 hours',
        'imprevisto', 'Encanador estourou no salão');

    ASSERT (v_res->>'itens_cancelados')::INT = 1, format('B1: itens %s', v_res->>'itens_cancelados');
    ASSERT (SELECT estado FROM reservas WHERE id = v_r) = 'cancelada';
    SELECT valor_sinal INTO v_valor FROM revisoes_cancelamento WHERE reserva_id = v_r;
    ASSERT v_valor = 30.00, format('B1: revisão devia ter o sinal CHEIO (R$ 30), veio %s', v_valor);
    ASSERT EXISTS (SELECT 1 FROM agenda_ocupacoes
                   WHERE origem = 'bloqueio' AND origem_id = (v_res->>'bloqueio_id')::UUID AND estado = 'ativa'),
        'B1: ocupação do bloqueio devia estar ativa';
    ASSERT EXISTS (SELECT 1 FROM jobs WHERE tipo = 'notificar_cliente_cancelamento'
                   AND payload->>'reserva_id' = v_r::TEXT),
        'B1: aviso ao cliente devia estar enfileirado';
    RAISE NOTICE 'B1 OK — bloqueio com conflito: reserva cancelada, revisão de R$ %, cliente avisado', v_valor;
END $$;

-- B2: reserva de DOIS itens — bloqueio atinge só a Laira; o item da Prof B sobrevive
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
        'folga', 'Consulta médica da Laira');

    ASSERT (v_res->>'itens_cancelados')::INT = 1, format('B2: devia cancelar 1 item, cancelou %s', v_res->>'itens_cancelados');
    ASSERT (SELECT estado FROM reserva_itens WHERE id = v_item_laira) = 'cancelado';
    ASSERT (SELECT estado FROM reserva_itens WHERE id = v_item_profb) = 'confirmado',
        'B2: item da Prof B devia sobreviver';
    ASSERT (SELECT estado FROM reservas WHERE id = v_r) = 'confirmada';
    SELECT valor_sinal INTO v_valor FROM revisoes_cancelamento WHERE reserva_item_id = v_item_laira;
    ASSERT v_valor = 30.00, format('B2: revisão proporcional devia ser 30.00, veio %s', v_valor);
    ASSERT (SELECT COUNT(*) FROM agenda_ocupacoes WHERE reserva_item_id = v_item_profb AND estado = 'ativa') = 2;
    RAISE NOTICE 'B2 OK — bloqueio cirúrgico: só o item da Laira cai (revisão R$ %), Prof B intacta', v_valor;
END $$;

-- B3: INSERT direto de bloqueio em cima de horário ocupado CONTINUA protegido pelo EXCLUDE
-- (a RPC é o caminho certo; o banco é a rede de segurança)
DO $$
DECLARE v_inicio TIMESTAMPTZ;
BEGIN
    v_inicio := teste_proximo_dia(3, '15:00');
    BEGIN
        INSERT INTO bloqueios (empresa_id, profissional_id, inicio, fim, motivo, tipo)
        VALUES ('00000000-0000-0000-0000-000000000001', 'dddddddd-0000-0000-0000-000000000001',
                v_inicio, v_inicio + interval '1 hour', 'direto no banco', 'folga');
        RAISE EXCEPTION 'B3 FALHOU: INSERT direto passou por cima de ocupação ativa';
    EXCEPTION WHEN OTHERS THEN
        ASSERT SQLERRM LIKE '%exclude_profissional_conflito%' OR SQLERRM LIKE '%conflicting key%', format('B3 erro inesperado: %s', SQLERRM);
        RAISE NOTICE 'B3 OK — EXCLUDE continua a proteger a agenda (rede de segurança)';
    END;
END $$;

-- B4: bloqueio sem conflito nenhum → cria direto, zero cancelamentos
DO $$
DECLARE v_res JSONB; v_inicio TIMESTAMPTZ;
BEGIN
    v_inicio := teste_proximo_dia(6, '11:30');
    v_res := public.criar_bloqueio_com_conflito(
        'dddddddd-0000-0000-0000-000000000001', v_inicio, v_inicio + interval '30 minutes',
        'almoco', 'Almoço Prof B');
    ASSERT (v_res->>'itens_cancelados')::INT = 0;
    RAISE NOTICE 'B4 OK — bloqueio limpo sem efeitos colaterais';
END $$;
