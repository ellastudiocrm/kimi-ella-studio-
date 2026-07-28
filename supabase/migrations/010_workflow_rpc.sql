-- 010_workflow_rpc.sql (v3.4 — NOVO) — o fechamento dos fluxos que as auditorias
-- apontaram como impeditivos de produção:
--
--  1. processar_pagamento_webhook  — pagamento processado NUM SÓ LUGAR ATÔMICO:
--     dedupe pela caixa de entrada, lock da reserva ANTES de gravar a transação
--     e decisão (confirma OU revisão) na mesma transação. Acaba a janela de
--     corrida webhook×cron (Ricardo/Carlos — impeditivo #1).
--  2. resolver_revisao             — a fila de revisões ganha SAÍDA: credito /
--     estorno / perdido / confirmar (com re-verificação de disponibilidade).
--  3. criar_bloqueio_com_conflito  — bloqueio que cancela os agendamentos
--     afetados (com revisão de valores) em vez de estourar exclusion_violation
--     (regressão apontada pelo Ricardo).
--  4. submeter_anamnese            — o CLIENTE entrega a ficha pelo link (token é
--     a credencial); regras do modelo decidem liberada × requer_avaliacao.

-- ------------------------------------------------- processar_pagamento_webhook
CREATE OR REPLACE FUNCTION processar_pagamento_webhook(
    p_origem TEXT,                        -- 'mercado_pago'
    p_external_event_id TEXT,             -- id único do evento (dedupe)
    p_valor DECIMAL,
    p_transacao_id UUID DEFAULT NULL,     -- transação pendente criada ao gerar o PIX
    p_cobranca_id UUID DEFAULT NULL,      -- fallback: referência externa
    p_mp_transaction_id TEXT DEFAULT NULL,
    p_payload JSONB DEFAULT '{}'::JSONB,
    p_assinatura_verificada BOOLEAN DEFAULT false
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER SET search_path = ''
AS $$
DECLARE
    v_inbox UUID;
    v_tx RECORD;
    v_cobranca RECORD;
    v_reserva RECORD;
    v_tx_id UUID;
    v_pago DECIMAL(10,2);
    v_atrasado BOOLEAN := false;
    v_reserva_id_lookup UUID;
BEGIN
    -- 1) Dedupe pela caixa de entrada — o MESMO evento nunca processa duas vezes
    INSERT INTO public.webhook_inbox (empresa_id, origem, external_event_id, payload, assinatura_verificada)
    SELECT c.empresa_id, p_origem, p_external_event_id, p_payload, p_assinatura_verificada
    FROM public.cobrancas c
    WHERE c.id = p_cobranca_id
       OR c.id = (SELECT t.cobranca_id FROM public.transacoes t WHERE t.id = p_transacao_id)
    ON CONFLICT (origem, external_event_id) DO NOTHING
    RETURNING id INTO v_inbox;

    IF v_inbox IS NULL THEN
        IF EXISTS (SELECT 1 FROM public.webhook_inbox WHERE origem = p_origem AND external_event_id = p_external_event_id) THEN
            RETURN jsonb_build_object('status', 'duplicado', 'external_event_id', p_external_event_id);
        END IF;
        RAISE EXCEPTION 'Cobrança/transação não encontrada para o webhook';
    END IF;

    -- 2) Assinatura: RAISE faz rollback de TUDO (inclusive a inbox) → o provedor reenvia
    IF NOT p_assinatura_verificada THEN
        RAISE EXCEPTION 'Assinatura do webhook não verificada — evento rejeitado';
    END IF;

    -- 3) Resolve a cobrança SEM lock e trava na ordem global anti-deadlock:
    --    RESERVA → COBRANÇA → TRANSAÇÃO (a mesma de cancelar_reserva e cia.)
    IF p_cobranca_id IS NULL AND p_transacao_id IS NOT NULL THEN
        SELECT t.cobranca_id INTO p_cobranca_id FROM public.transacoes t WHERE t.id = p_transacao_id;
    END IF;
    IF p_cobranca_id IS NULL THEN
        RAISE EXCEPTION 'Webhook sem transação nem cobrança identificada';
    END IF;

    SELECT c.reserva_id INTO v_reserva_id_lookup FROM public.cobrancas c WHERE c.id = p_cobranca_id;
    IF v_reserva_id_lookup IS NULL THEN RAISE EXCEPTION 'Cobrança % não encontrada', p_cobranca_id; END IF;

    -- Trava a reserva ANTES de qualquer decisão — o cron (SKIP LOCKED) passa
    -- direto e re-tenta no próximo ciclo, quando o estado final já estiver gravado
    SELECT * INTO v_reserva FROM public.reservas WHERE id = v_reserva_id_lookup FOR UPDATE;
    SELECT * INTO v_cobranca FROM public.cobrancas WHERE id = p_cobranca_id FOR UPDATE;

    -- 4) Liquida a transação pendente (fluxo PIX da Edge) ou insere a nova
    v_tx_id := NULL;
    IF p_transacao_id IS NOT NULL THEN
        SELECT * INTO v_tx FROM public.transacoes t WHERE t.id = p_transacao_id FOR UPDATE;
        IF FOUND THEN
            IF v_tx.cobranca_id <> p_cobranca_id THEN
                RAISE EXCEPTION 'Transação % não pertence à cobrança %', p_transacao_id, p_cobranca_id;
            END IF;
            IF v_tx.estado = 'pago' THEN
                UPDATE public.webhook_inbox SET processado = true WHERE id = v_inbox;
                RETURN jsonb_build_object('status', 'ja_processado', 'transacao_id', v_tx.id);
            END IF;
            UPDATE public.transacoes
            SET estado = 'pago', mp_transaction_id = COALESCE(p_mp_transaction_id, mp_transaction_id),
                payload_webhook = p_payload
            WHERE id = v_tx.id;
            v_tx_id := v_tx.id;
        END IF;
    END IF;

    IF v_tx_id IS NULL THEN
        INSERT INTO public.transacoes (cobranca_id, empresa_id, mp_idempotency_key, mp_transaction_id, valor, meio, finalidade, estado, payload_webhook)
        SELECT p_cobranca_id, c.empresa_id, 'mp-' || p_external_event_id, p_mp_transaction_id,
               p_valor, 'pix',
               -- índice idx_transacao_sinal_pago_unico: UM sinal pago por cobrança.
               -- Sinal já pago (ou parcela de sinal) → 'saldo'; 100% → 'pagamento_total'.
               CASE
                   WHEN EXISTS (SELECT 1 FROM public.transacoes t
                                WHERE t.cobranca_id = c.id AND t.finalidade = 'sinal' AND t.estado = 'pago')
                        OR p_valor < c.valor_sinal THEN 'saldo'
                   WHEN p_valor >= c.valor_total THEN 'pagamento_total'
                   ELSE 'sinal'
               END,
               'pago', p_payload
        FROM public.cobrancas c WHERE c.id = p_cobranca_id
        RETURNING id INTO v_tx_id;
    END IF;

    INSERT INTO public.eventos_pagamento (transacao_id, mp_event_id, tipo_evento, payload, processado)
    VALUES (v_tx_id, p_external_event_id, 'payment.updated', p_payload, true)
    ON CONFLICT (mp_event_id) DO NOTHING;

    SELECT COALESCE(SUM(t.valor), 0) INTO v_pago
    FROM public.transacoes t
    WHERE t.cobranca_id = p_cobranca_id AND t.estado = 'pago'
      AND t.finalidade IN ('sinal', 'saldo', 'pagamento_total');

    -- 5) Decisão pelo estado atual da reserva
    IF v_reserva.estado = 'pre_reserva' THEN
        SELECT EXISTS (
            SELECT 1 FROM public.agenda_ocupacoes
            WHERE origem = 'pre_reserva' AND origem_id = v_reserva.id
              AND (estado = 'expirada' OR (estado = 'ativa' AND expires_at <= now()))
        ) INTO v_atrasado;

        IF NOT v_atrasado AND v_pago >= COALESCE(v_reserva.valor_sinal_total, 0) THEN
            -- No prazo: confirma tudo aqui mesmo (mesma transação do webhook)
            UPDATE public.reservas SET estado = 'confirmada' WHERE id = v_reserva.id;
            UPDATE public.reserva_itens SET estado = 'confirmado'
            WHERE reserva_id = v_reserva.id AND estado = 'pendente';
            UPDATE public.agenda_ocupacoes SET origem = 'reserva', expires_at = NULL
            WHERE origem = 'pre_reserva' AND origem_id = v_reserva.id AND estado = 'ativa';
            UPDATE public.cobrancas
            SET estado = CASE WHEN v_pago >= valor_total THEN 'total_pago' ELSE 'sinal_pago' END
            WHERE id = p_cobranca_id;

            UPDATE public.webhook_inbox SET processado = true WHERE id = v_inbox;
            RETURN jsonb_build_object('status', 'confirmada', 'reserva_id', v_reserva.id, 'transacao_id', v_tx_id);
        END IF;

        IF NOT v_atrasado THEN
            -- Pagamento PARCIAL no prazo: fica registado; o restante vem noutro evento
            UPDATE public.webhook_inbox SET processado = true WHERE id = v_inbox;
            RETURN jsonb_build_object('status', 'parcial_registrado', 'reserva_id', v_reserva.id,
                                      'transacao_id', v_tx_id, 'pago_ate_agora', v_pago);
        END IF;
        -- Atrasado: cai no fluxo de revisão abaixo
    END IF;

    IF (v_reserva.estado = 'expirada' OR (v_reserva.estado = 'pre_reserva' AND v_atrasado)) AND v_pago > 0 THEN
        -- ATRASADO: slot livre, dinheiro na fila de revisão
        UPDATE public.agenda_ocupacoes SET estado = 'expirada'
        WHERE origem = 'pre_reserva' AND origem_id = v_reserva.id AND estado = 'ativa';
        UPDATE public.reservas SET estado = 'pagamento_em_revisao' WHERE id = v_reserva.id;

        -- v3.4.1b: fila completada pelo helper (líquido do que já está na fila por item)
        PERFORM public.revisao_completar_fila(v_reserva.id, 'pagamento_atrasado',
            'Pagamento identificado após o prazo — confirmar (se o horário estiver livre), estornar, dar crédito ou marcar perdido');

        PERFORM public.notificar_staff(v_reserva.empresa_id, 'pagamento_em_revisao',
            'Pagamento atrasado na reserva ' || v_reserva.id::text || ' (R$ ' ||
            trim(to_char(v_pago, '999990D00')) || '). O horário foi liberado. Decida na fila de revisões.');

        UPDATE public.webhook_inbox SET processado = true WHERE id = v_inbox;
        RETURN jsonb_build_object('status', 'pagamento_em_revisao', 'reserva_id', v_reserva.id, 'transacao_id', v_tx_id);
    END IF;

    IF v_reserva.estado = 'confirmada' THEN
        -- Pagamento de saldo de reserva já confirmada
        UPDATE public.cobrancas
        SET estado = CASE WHEN v_pago >= valor_total THEN 'total_pago' ELSE 'sinal_pago' END
        WHERE id = p_cobranca_id;
        UPDATE public.webhook_inbox SET processado = true WHERE id = v_inbox;
        RETURN jsonb_build_object('status', 'saldo_registrado', 'reserva_id', v_reserva.id, 'transacao_id', v_tx_id);
    END IF;

    IF v_reserva.estado = 'pagamento_em_revisao' THEN
        -- v3.4.1b: dinheiro novo em revisão também ENTRA na fila (antes só notificava)
        PERFORM public.revisao_completar_fila(v_reserva.id, 'pagamento_atrasado',
            'Novo pagamento com a reserva em revisão — fila completada');
        PERFORM public.notificar_staff(v_reserva.empresa_id, 'pagamento_em_revisao',
            'Novo pagamento (R$ ' || trim(to_char(p_valor, '999990D00')) || ') em reserva já em revisão: ' || v_reserva.id::text);
        UPDATE public.webhook_inbox SET processado = true WHERE id = v_inbox;
        RETURN jsonb_build_object('status', 'pagamento_em_revisao', 'reserva_id', v_reserva.id, 'transacao_id', v_tx_id);
    END IF;

    -- cancelada/realizada/no_show com dinheiro chegando: registra e alerta.
    -- v3.4.1b (achado F9): o INSERT bruto era engolido pelo índice único quando já
    -- havia revisão aberta (dinheiro sem rasto) — o helper completa a fila aberta.
    PERFORM public.revisao_completar_fila(v_reserva.id, 'pagamento_atrasado',
            'Pagamento recebido com a reserva em estado ' || v_reserva.estado || ' — avaliar estorno/crédito');
    PERFORM public.notificar_staff(v_reserva.empresa_id, 'pagamento_inesperado',
        'Pagamento de R$ ' || trim(to_char(p_valor, '999990D00')) || ' em reserva ' || v_reserva.estado || ': ' || v_reserva.id::text);
    UPDATE public.webhook_inbox SET processado = true WHERE id = v_inbox;
    RETURN jsonb_build_object('status', 'revisao_manual', 'reserva_id', v_reserva.id, 'transacao_id', v_tx_id);
END;
$$;

-- ----------------------------------------------------------- resolver_revisao
CREATE OR REPLACE FUNCTION resolver_revisao(
    p_revisao_id UUID,
    p_decisao TEXT,               -- 'credito' | 'estorno' | 'perdido' | 'confirmar'
    p_motivo TEXT DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER SET search_path = ''
AS $$
DECLARE
    v_rev RECORD;
    v_reserva RECORD;
    v_item RECORD;
    v_conta UUID;
    v_saldo DECIMAL(10,2);
BEGIN
    IF p_decisao NOT IN ('credito', 'estorno', 'perdido', 'confirmar') THEN
        RAISE EXCEPTION 'Decisão inválida: %', p_decisao;
    END IF;

    IF auth.role() = 'authenticated' THEN
        IF public.meu_perfil() NOT IN ('admin', 'gestor') THEN
            RAISE EXCEPTION 'Apenas admin/gestor resolvem revisões';
        END IF;
        IF COALESCE(auth.jwt() ->> 'aal', 'aal1') <> 'aal2' THEN
            RAISE EXCEPTION 'Decisão financeira exige verificação em duas etapas (MFA)';
        END IF;
    END IF;

    SELECT * INTO v_rev FROM public.revisoes_cancelamento WHERE id = p_revisao_id FOR UPDATE;
    IF NOT FOUND THEN RAISE EXCEPTION 'Revisão não encontrada'; END IF;
    IF auth.role() = 'authenticated' AND v_rev.empresa_id IS DISTINCT FROM public.minha_empresa_id() THEN
        RAISE EXCEPTION 'Sem permissão para esta empresa';
    END IF;
    IF v_rev.decisao_final IS NOT NULL THEN
        RAISE EXCEPTION 'Revisão já decidida (%) — decisões são finais', v_rev.decisao_final;
    END IF;

    SELECT * INTO v_reserva FROM public.reservas WHERE id = v_rev.reserva_id FOR UPDATE;

    -- ===================== CONFIRMAR (só pagamento atrasado) =====================
    IF p_decisao = 'confirmar' THEN
        IF v_reserva.estado <> 'pagamento_em_revisao' THEN
            RAISE EXCEPTION 'Só se pode confirmar reserva em pagamento_em_revisao (estado: %)', v_reserva.estado;
        END IF;

        -- v3.4.1 (auditoria #5): PIX que cai 3 dias depois não reagenda o passado
        IF EXISTS (SELECT 1 FROM public.reserva_itens ri
                   WHERE ri.reserva_id = v_reserva.id AND ri.inicio <= now()) THEN
            RAISE EXCEPTION 'O horário desta reserva já passou — escolha estorno ou crédito';
        END IF;

        -- v3.4.1b: revive só 'pendente'. Desde que o cron deixou de cancelar itens,
        -- 'cancelado' significa SEMPRE desistência deliberada — esses NÃO voltam.
        -- Re-verifica disponibilidade do slot original (outro cliente pode ter
        -- ocupado o horário liberado — Carlos #5)
        FOR v_item IN SELECT * FROM public.reserva_itens
                      WHERE reserva_id = v_reserva.id AND estado = 'pendente' LOOP
            IF EXISTS (SELECT 1 FROM public.agenda_ocupacoes o
                       WHERE o.estado = 'ativa' AND o.profissional_id = v_item.profissional_id
                         AND o.periodo && tstzrange(v_item.inicio, v_item.fim, '[)')) THEN
                RAISE EXCEPTION 'Horário de % já foi ocupado por outro agendamento — escolha estorno ou crédito',
                    to_char(v_item.inicio AT TIME ZONE 'America/Sao_Paulo', 'DD/MM HH24:MI');
            END IF;
            IF EXISTS (SELECT 1 FROM public.agenda_ocupacoes o
                       WHERE o.estado = 'ativa' AND o.recurso_id = v_item.recurso_id
                         AND o.periodo && tstzrange(v_item.inicio, v_item.fim, '[)')) THEN
                RAISE EXCEPTION 'Recurso do horário de % ocupado — escolha estorno ou crédito',
                    to_char(v_item.inicio AT TIME ZONE 'America/Sao_Paulo', 'DD/MM HH24:MI');
            END IF;
        END LOOP;

        -- Recria as ocupações (as antigas estão 'expirada' — não conflitam)
        FOR v_item IN SELECT * FROM public.reserva_itens
                      WHERE reserva_id = v_reserva.id AND estado = 'pendente' LOOP
            INSERT INTO public.agenda_ocupacoes (empresa_id, tipo_ocupacao, recurso_id, reserva_item_id, inicio, fim, origem, origem_id, estado)
            VALUES (v_reserva.empresa_id, 'recurso', v_item.recurso_id, v_item.id, v_item.inicio, v_item.fim, 'reserva', v_reserva.id, 'ativa');
            INSERT INTO public.agenda_ocupacoes (empresa_id, tipo_ocupacao, profissional_id, reserva_item_id, inicio, fim, origem, origem_id, estado)
            VALUES (v_reserva.empresa_id, 'profissional', v_item.profissional_id, v_item.id, v_item.inicio, v_item.fim, 'reserva', v_reserva.id, 'ativa');
            UPDATE public.reserva_itens SET estado = 'confirmado' WHERE id = v_item.id;
        END LOOP;

        UPDATE public.reservas SET estado = 'confirmada' WHERE id = v_reserva.id;
        UPDATE public.cobrancas c
        SET estado = CASE WHEN (SELECT COALESCE(SUM(t.valor),0) FROM public.transacoes t
                                WHERE t.cobranca_id = c.id AND t.estado = 'pago') >= c.valor_total
                          THEN 'total_pago' ELSE 'sinal_pago' END
        WHERE c.reserva_id = v_reserva.id;

    -- ===================== CRÉDITO =====================
    ELSIF p_decisao = 'credito' THEN
        INSERT INTO public.contas_creditos (cliente_id, empresa_id, tipo)
        VALUES (v_reserva.cliente_id, v_reserva.empresa_id, 'pago')
        ON CONFLICT (cliente_id, empresa_id, tipo) DO NOTHING;

        SELECT c.id INTO v_conta FROM public.contas_creditos c
        WHERE c.cliente_id = v_reserva.cliente_id AND c.empresa_id = v_reserva.empresa_id AND c.tipo = 'pago'
        FOR UPDATE;

        SELECT COALESCE(SUM(l.valor), 0) INTO v_saldo
        FROM public.lancamentos_creditos l WHERE l.conta_id = v_conta;

        INSERT INTO public.lancamentos_creditos
            (conta_id, tipo_lancamento, valor, saldo_apos, idempotencia_key, origem_id, origem_tipo, observacoes)
        VALUES
            (v_conta, 'credito_cancelamento', v_rev.valor_sinal, v_saldo + v_rev.valor_sinal,
             'revisao-' || v_rev.id::text, v_rev.reserva_id, 'revisao_cancelamento',
             COALESCE(p_motivo, 'Revisão ' || v_rev.regra_aplicada))
        ON CONFLICT (idempotencia_key) DO NOTHING;

        IF v_reserva.estado = 'pagamento_em_revisao' THEN
            UPDATE public.reservas SET estado = 'cancelada' WHERE id = v_reserva.id;
            UPDATE public.reserva_itens SET estado = 'cancelado'
            WHERE reserva_id = v_reserva.id AND estado = 'pendente';
            UPDATE public.cobrancas SET estado = 'cancelada'
            WHERE reserva_id = v_reserva.id AND estado = 'pendente';
        END IF;

    -- ===================== ESTORNO =====================
    ELSIF p_decisao = 'estorno' THEN
        UPDATE public.transacoes t SET estado = 'estornado'
        FROM public.cobrancas c
        WHERE t.cobranca_id = c.id AND c.reserva_id = v_reserva.id
          AND t.finalidade IN ('sinal', 'saldo', 'pagamento_total') AND t.estado = 'pago';

        -- O estorno real no Mercado Pago é tarefa da Edge Function (fila interna)
        INSERT INTO public.jobs (empresa_id, tipo, payload)
        VALUES (v_reserva.empresa_id, 'estorno_mercado_pago',
                jsonb_build_object('reserva_id', v_reserva.id, 'revisao_id', v_rev.id,
                                   'valor', v_rev.valor_sinal, 'motivo', p_motivo));

        IF v_reserva.estado = 'pagamento_em_revisao' THEN
            UPDATE public.reservas SET estado = 'cancelada' WHERE id = v_reserva.id;
            UPDATE public.reserva_itens SET estado = 'cancelado'
            WHERE reserva_id = v_reserva.id AND estado = 'pendente';
            UPDATE public.cobrancas SET estado = 'cancelada'
            WHERE reserva_id = v_reserva.id AND estado = 'pendente';
        END IF;

    -- ===================== PERDIDO (o estúdio fica com o sinal) =====================
    ELSE
        IF v_reserva.estado = 'pagamento_em_revisao' THEN
            UPDATE public.reservas SET estado = 'cancelada' WHERE id = v_reserva.id;
            UPDATE public.reserva_itens SET estado = 'cancelado'
            WHERE reserva_id = v_reserva.id AND estado = 'pendente';
            UPDATE public.cobrancas SET estado = 'sinal_pago'
            WHERE reserva_id = v_reserva.id AND estado = 'pendente';
        END IF;
    END IF;

    UPDATE public.revisoes_cancelamento
    SET decisao_final = p_decisao, decidido_por = public.meu_usuario_id(), motivo_decisao = p_motivo
    WHERE id = p_revisao_id;

    INSERT INTO public.log_acoes (empresa_id, tabela, registro_id, acao, usuario_id, perfil, motivo)
    VALUES (v_rev.empresa_id, 'revisoes_cancelamento', p_revisao_id, 'UPDATE',
            public.meu_usuario_id(), public.meu_perfil(),
            'decisao=' || p_decisao || COALESCE(': ' || p_motivo, ''));

    RETURN jsonb_build_object('revisao_id', p_revisao_id, 'decisao', p_decisao,
                              'reserva_id', v_reserva.id,
                              'reserva_status', (SELECT estado FROM public.reservas WHERE id = v_reserva.id));
END;
$$;

-- -------------------------------------------------- criar_bloqueio_com_conflito
-- Ricardo: bloqueio sobre horário ocupado estourava exclusion_violation crua.
-- Agora: cancela os itens afetados (com revisão de valores pelo fluxo normal),
-- cria o bloqueio e enfileira aviso aos clientes.
CREATE OR REPLACE FUNCTION criar_bloqueio_com_conflito(
    p_profissional_id UUID,
    p_inicio TIMESTAMPTZ,
    p_fim TIMESTAMPTZ,
    p_tipo TEXT,                     -- 'almoco' | 'folga' | 'imprevisto'
    p_motivo TEXT,
    p_recurso_id UUID DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER SET search_path = ''
AS $$
DECLARE
    v_empresa UUID;
    v_bloqueio UUID;
    v_item RECORD;
    v_reservas UUID[] := '{}';
    v_count INT := 0;
BEGIN
    IF p_tipo NOT IN ('almoco', 'folga', 'imprevisto') THEN
        RAISE EXCEPTION 'Tipo de bloqueio inválido: %', p_tipo;
    END IF;
    IF p_inicio >= p_fim THEN RAISE EXCEPTION 'Início tem de ser antes do fim'; END IF;

    SELECT empresa_id INTO v_empresa FROM public.profissionais WHERE id = p_profissional_id;
    IF NOT FOUND THEN RAISE EXCEPTION 'Profissional não encontrada'; END IF;

    IF auth.role() = 'authenticated' THEN
        IF v_empresa IS DISTINCT FROM public.minha_empresa_id()
           OR public.meu_perfil() NOT IN ('admin', 'gestor', 'recepcao') THEN
            RAISE EXCEPTION 'Apenas a equipe pode criar bloqueios';
        END IF;
    END IF;

    -- Itens vivos que colidem com o bloqueio (pela ocupaçao ATIVA: real, não estimada)
    FOR v_item IN
        SELECT DISTINCT ri.id AS item_id, ri.reserva_id
        FROM public.reserva_itens ri
        JOIN public.agenda_ocupacoes o ON o.reserva_item_id = ri.id AND o.estado = 'ativa'
        JOIN public.reservas r ON r.id = ri.reserva_id
        WHERE ri.estado IN ('pendente', 'confirmado')
          AND r.estado IN ('pre_reserva', 'confirmada')
          AND o.periodo && tstzrange(p_inicio, p_fim, '[)')
          AND ((o.tipo_ocupacao = 'profissional' AND o.profissional_id = p_profissional_id)
               OR (p_recurso_id IS NOT NULL AND o.tipo_ocupacao = 'recurso' AND o.recurso_id = p_recurso_id))
        ORDER BY ri.id
    LOOP
        -- Cancela pelo fluxo normal: regra 16h + revisão com o valor pago (Carlos #3)
        PERFORM public.cancelar_item_reserva(v_item.item_id, NULL,
            'Bloqueio de agenda (' || p_tipo || '): ' || p_motivo);
        v_reservas := v_reservas || v_item.reserva_id;
        v_count := v_count + 1;
    END LOOP;

    INSERT INTO public.bloqueios (empresa_id, profissional_id, recurso_id, inicio, fim, motivo, tipo)
    VALUES (v_empresa, p_profissional_id, p_recurso_id, p_inicio, p_fim, p_motivo, p_tipo)
    RETURNING id INTO v_bloqueio;

    -- Aviso ao cliente sai pela fila (Edge Function envia o WhatsApp)
    INSERT INTO public.jobs (empresa_id, tipo, payload)
    SELECT v_empresa, 'notificar_cliente_cancelamento',
           jsonb_build_object('reserva_id', rid, 'motivo', p_motivo, 'bloqueio_id', v_bloqueio)
    FROM (SELECT DISTINCT unnest(v_reservas) AS rid) s;

    RETURN jsonb_build_object('bloqueio_id', v_bloqueio,
                              'itens_cancelados', v_count,
                              'reservas_afetadas', (SELECT COUNT(DISTINCT rid) FROM (SELECT unnest(v_reservas) AS rid) s));
END;
$$;

-- ------------------------------------------------------------ submeter_anamnese
-- O TOKEN é a credencial: o link chega ao cliente por WhatsApp e basta para
-- submeter — sem login (a política de segurança é o sigilo do link + expiração).
CREATE OR REPLACE FUNCTION submeter_anamnese(
    p_token TEXT,
    p_respostas JSONB,               -- [{"pergunta_id": "...", "resposta": "..."}]
    p_consentimento_lgpd BOOLEAN,
    p_texto_consentimento TEXT DEFAULT NULL
)
RETURNS TEXT
LANGUAGE plpgsql
SECURITY DEFINER SET search_path = ''
AS $$
DECLARE
    v_tok RECORD;
    v_resp JSONB;
    v_total INT;
    v_ok INT;
    v_faltam INT;
    v_estado TEXT := 'liberada';
    v_regra RECORD;
    v_valor TEXT;
    v_dispara BOOLEAN;
BEGIN
    IF p_consentimento_lgpd IS NOT TRUE THEN
        RAISE EXCEPTION 'É preciso aceitar o termo de consentimento (LGPD) para enviar a ficha';
    END IF;

    SELECT t.id AS token_id, t.expira_em AS token_expira_em, a.*
    INTO v_tok
    FROM public.anamnese_tokens t
    JOIN public.anamneses a ON a.id = t.anamnese_id
    WHERE t.token_hash = public.sha256_hex(p_token)
      AND t.usado = false
    FOR UPDATE OF t, a;

    IF NOT FOUND THEN RAISE EXCEPTION 'Link inválido ou já utilizado'; END IF;
    IF v_tok.token_expira_em <= now() THEN
        RAISE EXCEPTION 'Este link expirou — peça um novo ao estúdio';
    END IF;
    IF v_tok.estado <> 'pendente' THEN
        RAISE EXCEPTION 'Esta ficha já foi respondida';
    END IF;

    -- v3.4.1 (menor): ficha de agendamento cancelado/expirado não se responde
    IF v_tok.reserva_item_id IS NOT NULL AND EXISTS (
        SELECT 1 FROM public.reserva_itens ri
        JOIN public.reservas r ON r.id = ri.reserva_id
        WHERE ri.id = v_tok.reserva_item_id AND r.estado IN ('cancelada', 'expirada')
    ) THEN
        RAISE EXCEPTION 'O agendamento ligado a esta ficha já não está ativo — fala com o estúdio';
    END IF;

    -- Toda pergunta respondida tem de pertencer ao MODELO desta ficha
    SELECT COUNT(*) INTO v_total FROM jsonb_array_elements(p_respostas);
    SELECT COUNT(*) INTO v_ok
    FROM jsonb_array_elements(p_respostas) r
    JOIN public.modelo_perguntas mp ON mp.id = (r->>'pergunta_id')::UUID AND mp.modelo_id = v_tok.modelo_id;
    IF v_total IS DISTINCT FROM v_ok THEN
        RAISE EXCEPTION 'Resposta para pergunta que não pertence a esta ficha';
    END IF;

    -- Obrigatórias respondidas
    SELECT COUNT(*) INTO v_faltam
    FROM public.modelo_perguntas mp
    WHERE mp.modelo_id = v_tok.modelo_id AND mp.obrigatoria = true
      AND NOT EXISTS (
          SELECT 1 FROM jsonb_array_elements(p_respostas) r
          WHERE (r->>'pergunta_id')::UUID = mp.id AND length(trim(COALESCE(r->>'resposta',''))) > 0
      );
    IF v_faltam > 0 THEN
        RAISE EXCEPTION 'Faltam % pergunta(s) obrigatória(s)', v_faltam;
    END IF;

    INSERT INTO public.anamnese_respostas (anamnese_id, pergunta_id, resposta)
    SELECT v_tok.id, (r->>'pergunta_id')::UUID, r->>'resposta'
    FROM jsonb_array_elements(p_respostas) r;

    -- Regras do modelo: qualquer disparo de 'requer_avaliacao' manda a ficha para a profissional
    FOR v_regra IN
        SELECT mp.* FROM public.modelo_perguntas mp
        WHERE mp.modelo_id = v_tok.modelo_id AND mp.operador IS NOT NULL AND mp.resultado_estado IS NOT NULL
    LOOP
        SELECT r->>'resposta' INTO v_valor
        FROM jsonb_array_elements(p_respostas) r
        WHERE (r->>'pergunta_id')::UUID = v_regra.id;
        IF v_valor IS NULL THEN CONTINUE; END IF;

        v_dispara := CASE v_regra.operador
            WHEN 'igual'      THEN lower(trim(v_valor)) = lower(trim(v_regra.valor_disparador))
            WHEN 'diferente'  THEN lower(trim(v_valor)) <> lower(trim(v_regra.valor_disparador))
            WHEN 'contem'     THEN position(lower(trim(v_regra.valor_disparador)) in lower(v_valor)) > 0
            WHEN 'maior_que'  THEN v_valor ~ '^-?\d+(\.\d+)?$' AND v_regra.valor_disparador ~ '^-?\d+(\.\d+)?$'
                                    AND v_valor::NUMERIC > v_regra.valor_disparador::NUMERIC
            WHEN 'menor_que'  THEN v_valor ~ '^-?\d+(\.\d+)?$' AND v_regra.valor_disparador ~ '^-?\d+(\.\d+)?$'
                                    AND v_valor::NUMERIC < v_regra.valor_disparador::NUMERIC
            ELSE false END;

        IF v_dispara AND v_regra.resultado_estado = 'requer_avaliacao' THEN
            v_estado := 'requer_avaliacao';
        END IF;
    END LOOP;

    UPDATE public.anamneses
    SET estado = v_estado,
        consentimento_lgpd = true,
        texto_consentimento_aceito = p_texto_consentimento
    WHERE id = v_tok.id;

    UPDATE public.anamnese_tokens SET usado = true, usado_em = now() WHERE id = v_tok.token_id;

    IF v_estado = 'requer_avaliacao' THEN
        PERFORM public.notificar_staff(v_tok.empresa_id, 'anamnese_requer_avaliacao',
            'Ficha de anamnese ' || v_tok.id::text || ' exige avaliação da profissional.');
    END IF;

    RETURN v_estado;
END;
$$;

-- -------------------------------------------------------------- remover_bloqueio
-- v3.4.1: com o REVOKE em bloqueios (007), a remoção também passa por RPC
CREATE OR REPLACE FUNCTION remover_bloqueio(p_bloqueio_id UUID)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER SET search_path = ''
AS $$
BEGIN
    IF auth.role() = 'authenticated' THEN
        IF public.meu_perfil() NOT IN ('admin', 'gestor', 'recepcao') THEN
            RAISE EXCEPTION 'Apenas a equipe remove bloqueios';
        END IF;
    END IF;

    DELETE FROM public.bloqueios b
    WHERE b.id = p_bloqueio_id
      AND (auth.role() IS DISTINCT FROM 'authenticated' OR b.empresa_id = public.minha_empresa_id());
    -- o trigger remover_bloqueio_ocupacoes (004) liberta as ocupações

    IF NOT FOUND THEN RAISE EXCEPTION 'Bloqueio não encontrado'; END IF;
END;
$$;

-- =====================================================================
-- EXECUTE explícito
-- =====================================================================
REVOKE ALL ON FUNCTION public.processar_pagamento_webhook(TEXT, TEXT, DECIMAL, UUID, UUID, TEXT, JSONB, BOOLEAN) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.processar_pagamento_webhook(TEXT, TEXT, DECIMAL, UUID, UUID, TEXT, JSONB, BOOLEAN) TO service_role;

REVOKE ALL ON FUNCTION public.resolver_revisao(UUID, TEXT, TEXT) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.resolver_revisao(UUID, TEXT, TEXT) TO authenticated, service_role;

REVOKE ALL ON FUNCTION public.criar_bloqueio_com_conflito(UUID, TIMESTAMPTZ, TIMESTAMPTZ, TEXT, TEXT, UUID) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.criar_bloqueio_com_conflito(UUID, TIMESTAMPTZ, TIMESTAMPTZ, TEXT, TEXT, UUID) TO authenticated, service_role;

REVOKE ALL ON FUNCTION public.remover_bloqueio(UUID) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.remover_bloqueio(UUID) TO authenticated, service_role;

REVOKE ALL ON FUNCTION public.submeter_anamnese(TEXT, JSONB, BOOLEAN, TEXT) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.submeter_anamnese(TEXT, JSONB, BOOLEAN, TEXT) TO anon, authenticated, service_role;
