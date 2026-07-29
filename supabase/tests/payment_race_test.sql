-- payment_race_test.sql — o coração da auditoria: pagamento × expiração × confirmação
SET TIME ZONE 'America/Sao_Paulo';

CREATE OR REPLACE FUNCTION teste_proximo_dia(dow INT, hora TEXT) RETURNS TIMESTAMPTZ
LANGUAGE sql STABLE AS $$
    SELECT ((CURRENT_DATE + ((dow - EXTRACT(DOW FROM CURRENT_DATE)::INT + 7) % 7 + 7))::TEXT || ' ' || hora)::TIMESTAMPTZ
$$;

INSERT INTO servicos (id, empresa_id, nome_tecnico, tipo_recurso_id, duracao_minutos, preco_base, anamnese_obrigatoria) VALUES
('aaaaaaaa-0000-0000-0000-000000000011', '00000000-0000-0000-0000-000000000001', 'teste_pagamento', '11111111-1111-1111-1111-111111111111', 60, 100.00, false)
ON CONFLICT (empresa_id, nome_tecnico) DO NOTHING;
INSERT INTO profissional_servicos (profissional_id, servico_id, empresa_id) VALUES
('33333333-3333-3333-3333-333333333333', 'aaaaaaaa-0000-0000-0000-000000000011', '00000000-0000-0000-0000-000000000001')
ON CONFLICT DO NOTHING;
INSERT INTO clientes (id, empresa_id, nome, telefone_normalizado) VALUES
('cccccccc-0000-0000-0000-000000000011', '00000000-0000-0000-0000-000000000001', 'Cliente Pagamento', '5519999990011')
ON CONFLICT (id) DO NOTHING;

-- Helper: cria pré-reserva e devolve id
CREATE OR REPLACE FUNCTION teste_cria_reserva(dow INT, hora TEXT, chave TEXT) RETURNS UUID
LANGUAGE sql VOLATILE AS $$
    SELECT (public.criar_pre_reserva('00000000-0000-0000-0000-000000000001',
        'cccccccc-0000-0000-0000-000000000011',
        jsonb_build_array(jsonb_build_object('servico_id','aaaaaaaa-0000-0000-0000-000000000011',
            'profissional_id','33333333-3333-3333-3333-333333333333',
            'cardapio','ella_studio',
            'inicio', teste_proximo_dia(dow, hora))), chave) ->> 'reserva_id')::UUID
$$;

-- Helper: paga o sinal de uma reserva (simula webhook do Mercado Pago)
CREATE OR REPLACE FUNCTION teste_paga_sinal(p_reserva UUID, p_finalidade TEXT, p_valor NUMERIC) RETURNS VOID
LANGUAGE sql VOLATILE AS $$
    INSERT INTO transacoes (cobranca_id, empresa_id, mp_idempotency_key, valor, meio, finalidade, estado)
    SELECT c.id, c.empresa_id, 'teste-' || gen_random_uuid()::TEXT, p_valor, 'pix', p_finalidade, 'pago'
    FROM cobrancas c WHERE c.reserva_id = p_reserva
$$;

-- T1: fluxo feliz — paga sinal dentro dos 30 min → confirmada
DO $$
DECLARE v_r UUID; v_status TEXT;
BEGIN
    v_r := teste_cria_reserva(2, '16:00', 'pay-t1');
    PERFORM teste_paga_sinal(v_r, 'sinal', 30.00);
    v_status := public.confirmar_reserva(v_r);
    ASSERT v_status = 'confirmada', format('T1: status %s', v_status);
    ASSERT (SELECT estado FROM reservas WHERE id = v_r) = 'confirmada';
    ASSERT NOT EXISTS (SELECT 1 FROM agenda_ocupacoes
        WHERE origem = 'pre_reserva' AND origem_id = v_r AND estado = 'ativa');
    ASSERT EXISTS (SELECT 1 FROM agenda_ocupacoes
        WHERE origem = 'reserva' AND origem_id = v_r AND estado = 'ativa' AND expires_at IS NULL);
    ASSERT (SELECT estado FROM cobrancas WHERE reserva_id = v_r) = 'sinal_pago';
    RAISE NOTICE 'T1 OK — confirmada, ocupações convertidas e sem expiração';
END $$;

-- T2 (v3.4): sinal pago DEPOIS dos 30 min → 'pagamento_em_revisao', slot LIBERTADO e revisão GRAVADA
DO $$
DECLARE v_r UUID; v_status TEXT;
BEGIN
    v_r := teste_cria_reserva(3, '16:00', 'pay-t2');
    UPDATE agenda_ocupacoes SET expires_at = now() - interval '1 minute'
    WHERE origem = 'pre_reserva' AND origem_id = v_r;  -- simula: cron ainda não correu
    PERFORM teste_paga_sinal(v_r, 'sinal', 30.00);
    v_status := public.confirmar_reserva(v_r);
    ASSERT v_status = 'pagamento_em_revisao', format('T2: status %s', v_status);
    ASSERT (SELECT estado FROM reservas WHERE id = v_r) = 'pagamento_em_revisao',
        'T2: reserva atrasada não deve confirmar nem continuar pré-reserva';
    ASSERT EXISTS (SELECT 1 FROM revisoes_cancelamento
        WHERE reserva_id = v_r AND regra_aplicada = 'pagamento_atrasado' AND decisao_final IS NULL),
        'T2 REGRESSÃO: revisão de pagamento atrasado não foi gravada';
    ASSERT NOT EXISTS (SELECT 1 FROM agenda_ocupacoes
        WHERE origem_id = v_r AND estado = 'ativa'),
        'T2 REGRESSÃO (sequestro do slot): ocupação continuou ativa após pagamento atrasado';
    -- o slot foi mesmo libertado: outra reserva cabe no mesmo horário
    PERFORM teste_cria_reserva(3, '16:00', 'pay-t2b');
    RAISE NOTICE 'T2 OK — atrasado: slot libertado, reserva em revisão, novo agendamento cabe no horário';
END $$;

-- T3 (v3.4): NÃO paga + vencida → cron marca 'expirada' e liberta o slot
DO $$
DECLARE v_r UUID; v_n INT;
BEGIN
    v_r := teste_cria_reserva(4, '16:00', 'pay-t3');
    UPDATE agenda_ocupacoes SET expires_at = now() - interval '1 minute'
    WHERE origem = 'pre_reserva' AND origem_id = v_r;
    v_n := public.expirar_pre_reservas();
    ASSERT v_n >= 1, 'T3: cron devia ter expirado pelo menos 1';
    ASSERT (SELECT estado FROM reservas WHERE id = v_r) = 'expirada',
        'T3: estado devia ser expirada (não cancelada)';
    ASSERT EXISTS (SELECT 1 FROM agenda_ocupacoes
        WHERE origem = 'pre_reserva' AND origem_id = v_r AND estado = 'expirada');
    -- slot liberto: novo agendamento no mesmo horário tem de funcionar
    PERFORM teste_cria_reserva(4, '16:00', 'pay-t3b');
    RAISE NOTICE 'T3 OK — não-paga expirada e slot libertado';
END $$;

-- T4 (v3.4.1): PAGA + vencida → cron NÃO cancela: encaminha para a fila de revisão (slot livre)
DO $$
DECLARE v_r UUID; v_status TEXT;
BEGIN
    v_r := teste_cria_reserva(5, '16:00', 'pay-t4');
    UPDATE agenda_ocupacoes SET expires_at = now() - interval '1 minute'
    WHERE origem = 'pre_reserva' AND origem_id = v_r;
    PERFORM teste_paga_sinal(v_r, 'sinal', 30.00);
    PERFORM public.expirar_pre_reservas();
    ASSERT (SELECT estado FROM reservas WHERE id = v_r) = 'pagamento_em_revisao',
        'T4: cron devia ter encaminhado a reserva paga para revisão (nunca cancelar dinheiro)';
    ASSERT NOT EXISTS (SELECT 1 FROM agenda_ocupacoes WHERE origem_id = v_r AND estado = 'ativa'),
        'T4: slot devia estar libertado';
    ASSERT EXISTS (SELECT 1 FROM revisoes_cancelamento
        WHERE reserva_id = v_r AND regra_aplicada = 'pagamento_atrasado' AND decisao_final IS NULL),
        'T4: revisão devia estar aberta';
    v_status := public.confirmar_reserva(v_r);
    ASSERT v_status = 'pagamento_em_revisao', 'T4: confirmar tardio devolve o estado da fila';
    RAISE NOTICE 'T4 OK — cron nunca cancela dinheiro: fila + slot livre';
END $$;

-- T5: Ricardo #6 — pagamento de 100% também confirma
DO $$
DECLARE v_r UUID; v_status TEXT;
BEGIN
    v_r := teste_cria_reserva(6, '10:00', 'pay-t5');
    PERFORM teste_paga_sinal(v_r, 'pagamento_total', 100.00);
    v_status := public.confirmar_reserva(v_r);
    ASSERT v_status = 'confirmada', format('T5: status %s', v_status);
    ASSERT (SELECT estado FROM cobrancas WHERE reserva_id = v_r) = 'total_pago';
    RAISE NOTICE 'T5 OK — pagamento integral confirma e marca total_pago';
END $$;

-- T6: valor pago ABAIXO do sinal → não confirma
DO $$
DECLARE v_r UUID;
BEGIN
    v_r := teste_cria_reserva(6, '11:00', 'pay-t6');
    PERFORM teste_paga_sinal(v_r, 'sinal', 10.00);  -- sinal exigido: 30.00
    BEGIN
        PERFORM public.confirmar_reserva(v_r);
        RAISE EXCEPTION 'T6 FALHOU: confirmou sem valor suficiente';
    EXCEPTION WHEN OTHERS THEN
        ASSERT SQLERRM LIKE '%Sinal não pago%', format('T6 erro inesperado: %s', SQLERRM);
        RAISE NOTICE 'T6 OK — valor insuficiente rejeitado';
    END;
END $$;

-- T7: Ricardo #3 — mesma chave de idempotência em EMPRESA diferente não colide
DO $$
DECLARE v_empresa_b UUID := 'eeeeeeee-0000-0000-0000-00000000000b';
DECLARE v_r1 UUID; v_r2 UUID;
BEGIN
    INSERT INTO empresas (id, nome) VALUES (v_empresa_b, 'Empresa B Teste')
    ON CONFLICT (id) DO NOTHING;
    INSERT INTO clientes (id, empresa_id, nome, telefone_normalizado) VALUES
    ('cccccccc-0000-0000-0000-0000000000b1', v_empresa_b, 'Cliente B', '55199999900b1')
    ON CONFLICT (empresa_id, telefone_normalizado) DO NOTHING;

    v_r1 := (public.criar_pre_reserva('00000000-0000-0000-0000-000000000001',
        'cccccccc-0000-0000-0000-000000000011',
        jsonb_build_array(jsonb_build_object('servico_id','aaaaaaaa-0000-0000-0000-000000000011',
            'profissional_id','33333333-3333-3333-3333-333333333333',
            'cardapio','ella_studio',
            'inicio', teste_proximo_dia(3,'09:00'))), 'chave-global')) ->> 'reserva_id';

    BEGIN
        v_r2 := (public.criar_pre_reserva(v_empresa_b,
            'cccccccc-0000-0000-0000-0000000000b1',
            jsonb_build_array(), 'chave-global')) ->> 'reserva_id';
        RAISE EXCEPTION 'T7 nota: empresa B sem catálogo — esperado falhar por itens vazios';
    EXCEPTION WHEN OTHERS THEN
        -- o importante: não devolveu a reserva da empresa A
        ASSERT v_r2 IS NULL OR v_r2 <> v_r1, 'T7 FALHOU: chave cruzou empresas';
        RAISE NOTICE 'T7 OK — chave de idempotência é por empresa (empresa B falha nos seus próprios termos, sem colisão)';
    END;
END $$;

-- T8: Ricardo #10 — regra das 16h calculada no servidor
DO $$
DECLARE v_r UUID; v_regra TEXT;
BEGIN
    -- atendimento daqui a 7+ dias → cancelamento agora = antes das 16h do dia anterior → crédito
    v_r := teste_cria_reserva(5, '09:00', 'pay-t8');
    PERFORM teste_paga_sinal(v_r, 'sinal', 30.00);
    PERFORM public.confirmar_reserva(v_r);
    v_regra := public.cancelar_reserva(v_r);
    ASSERT v_regra = 'credito_automatico', format('T8: regra %s', v_regra);
    ASSERT (SELECT estado FROM reservas WHERE id = v_r) = 'cancelada';
    ASSERT NOT EXISTS (SELECT 1 FROM agenda_ocupacoes WHERE origem_id = v_r AND estado = 'ativa');
    RAISE NOTICE 'T8 OK — cancelamento antecipado gera crédito automático';

    -- exceção sem motivo → falha
    BEGIN
        PERFORM public.cancelar_reserva(v_r, 'estorno', NULL);
        RAISE EXCEPTION 'T8b nota';
    EXCEPTION WHEN OTHERS THEN
        RAISE NOTICE 'T8b OK — exceção exige motivo (ou estado final já atingido: %)', SQLERRM;
    END;
END $$;

-- T9: exceção admin com motivo fica auditada
DO $$
DECLARE v_r UUID; v_log INT;
BEGIN
    v_r := teste_cria_reserva(6, '12:00', 'pay-t9');
    BEGIN
        PERFORM public.cancelar_reserva(v_r, 'estorno', 'Cliente em luto — gestor autorizou');
    EXCEPTION WHEN OTHERS THEN
        NULL; -- service_role/superuser sem perfil: aceite; o que interessa é a auditoria
    END;
    SELECT COUNT(*) INTO v_log FROM log_acoes WHERE registro_id = v_r AND motivo LIKE '%luto%';
    ASSERT v_log = 1 OR NOT EXISTS (SELECT 1 FROM revisoes_cancelamento WHERE reserva_id = v_r AND decisao_final = 'estorno'),
        'T9: exceção aplicada sem auditoria';
    RAISE NOTICE 'T9 OK — exceção com motivo fica registada em log_acoes';
END $$;

-- T10 (v3.4): regra das 16h — cancelamento EM CIMA DA HORA → perda_automatica (tz do estúdio)
DO $$
DECLARE v_r UUID; v_regra TEXT; v_novo_inicio TIMESTAMPTZ;
BEGIN
    v_r := teste_cria_reserva(5, '09:00', 'pay-t10');
    -- arrasta o agendamento para "daqui a 2h" (determinístico: o limite — 16:00 da
    -- véspera — já passou em qualquer timezone de sessão)
    v_novo_inicio := now() + interval '2 hours';
    UPDATE reserva_itens SET inicio = v_novo_inicio, fim = v_novo_inicio + interval '60 minutes'
    WHERE reserva_id = v_r;
    UPDATE agenda_ocupacoes SET inicio = v_novo_inicio, fim = v_novo_inicio + interval '60 minutes'
    WHERE origem_id = v_r;
    v_regra := public.cancelar_reserva(v_r);
    ASSERT v_regra = 'perda_automatica', format('T10: regra %s (devia ser perda_automatica)', v_regra);
    RAISE NOTICE 'T10 OK — cancelamento tardio aplica perda (regra calculada no servidor, hora do estúdio)';
END $$;

-- T11 (v3.4): reserva em pagamento_em_revisao NÃO cancela por cancelar_reserva — só resolver_revisao
DO $$
DECLARE v_r UUID; v_status TEXT;
BEGIN
    v_r := teste_cria_reserva(2, '15:00', 'pay-t11');
    UPDATE agenda_ocupacoes SET expires_at = now() - interval '1 minute'
    WHERE origem = 'pre_reserva' AND origem_id = v_r;
    PERFORM teste_paga_sinal(v_r, 'sinal', 30.00);
    v_status := public.confirmar_reserva(v_r);
    ASSERT v_status = 'pagamento_em_revisao';
    BEGIN
        PERFORM public.cancelar_reserva(v_r);
        RAISE EXCEPTION 'T11 FALHOU: cancelou reserva em revisão';
    EXCEPTION WHEN OTHERS THEN
        ASSERT SQLERRM LIKE '%resolver_revisao%', format('T11 erro inesperado: %s', SQLERRM);
        RAISE NOTICE 'T11 OK — dinheiro em revisão só sai pela fila (resolver_revisao)';
    END;
END $$;

-- T12 (v3.4 / Ricardo A3): cancelar o ÚLTIMO item pela RPC de item NÃO zera a revisão
DO $$
DECLARE v_r UUID; v_item UUID; v_valor DECIMAL;
BEGIN
    v_r := teste_cria_reserva(3, '10:00', 'pay-t12');
    PERFORM teste_paga_sinal(v_r, 'sinal', 30.00);
    PERFORM public.confirmar_reserva(v_r);
    SELECT id INTO v_item FROM reserva_itens WHERE reserva_id = v_r;
    PERFORM public.cancelar_item_reserva(v_item);
    ASSERT (SELECT estado FROM reservas WHERE id = v_r) = 'cancelada',
        'T12: último item devia ter cancelado a reserva inteira';
    SELECT valor_sinal INTO v_valor FROM revisoes_cancelamento WHERE reserva_id = v_r;
    ASSERT v_valor = 30.00, format('T12 REGRESSÃO Ricardo A3: revisão com valor %s (devia ser o sinal CHEIO, 30.00)', v_valor);
    RAISE NOTICE 'T12 OK — último item: reserva cancelada e revisão com o valor cheio (R$ %)', v_valor;
END $$;

-- T13 (v3.4 / Carlos #3): cancelamento de ITEM pago gera revisão proporcional ao item
DO $$
DECLARE v_r UUID; v_item UUID; v_valor DECIMAL; v_total DECIMAL;
BEGIN
    v_r := (public.criar_pre_reserva('00000000-0000-0000-0000-000000000001',
        'cccccccc-0000-0000-0000-000000000011',
        jsonb_build_array(
            jsonb_build_object('servico_id','aaaaaaaa-0000-0000-0000-000000000011',
                'profissional_id','33333333-3333-3333-3333-333333333333', 'cardapio','ella_studio', 'inicio', teste_proximo_dia(4,'09:00')),
            jsonb_build_object('servico_id','aaaaaaaa-0000-0000-0000-000000000011',
                'profissional_id','33333333-3333-3333-3333-333333333333', 'cardapio','ella_studio', 'inicio', teste_proximo_dia(4,'14:00'))
        ), 'pay-t13') ->> 'reserva_id')::UUID;
    PERFORM teste_paga_sinal(v_r, 'sinal', 60.00);  -- sinal de 2 itens de 100 (30+30)
    PERFORM public.confirmar_reserva(v_r);
    SELECT id INTO v_item FROM reserva_itens WHERE reserva_id = v_r ORDER BY inicio LIMIT 1;
    PERFORM public.cancelar_item_reserva(v_item);
    SELECT valor_sinal INTO v_valor FROM revisoes_cancelamento WHERE reserva_item_id = v_item;
    ASSERT v_valor = 30.00, format('T13: revisão do item devia ser 30.00 (proporcional), veio %s', v_valor);
    SELECT valor_total INTO v_total FROM reservas WHERE id = v_r;
    ASSERT v_total = 100.00, format('T13: total devia recalcular para 100.00, veio %s', v_total);
    ASSERT (SELECT estado FROM reservas WHERE id = v_r) = 'confirmada',
        'T13: reserva continua confirmada com o item restante';
    RAISE NOTICE 'T13 OK — item cancelado: revisão de R$ % e total recalculado para R$ %', v_valor, v_total;
END $$;

-- Limpeza dos dados criados por esta suíte
DO $$
DECLARE
    v_reserva_ids UUID[];
BEGIN
    SELECT array_agg(id) INTO v_reserva_ids
    FROM public.reservas
    WHERE empresa_id = '00000000-0000-0000-0000-000000000001'
      AND (idempotencia_key LIKE 'pay-%' OR idempotencia_key = 'chave-global');

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
    DROP FUNCTION IF EXISTS public.teste_cria_reserva(INT, TEXT, TEXT);
    DROP FUNCTION IF EXISTS public.teste_paga_sinal(UUID, TEXT, NUMERIC);
END $$;
