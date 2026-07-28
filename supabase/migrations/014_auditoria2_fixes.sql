-- 014_auditoria2_fixes.sql (v3.4.3) — correções da 2ª auditoria independente
--
-- 1. GRAVE #2: confirmar_reserva, cancelar_reserva, cancelar_pre_reserva — verificação
--    de perfil (não só empresa). Padrão: admin/gestor/recepcao tudo; profissional só
--    quando o item/reserva lhe pertence. service_role passa.
-- 2. MÉDIO #3: resolver_revisao — cobrança fica em estado terminal 'cancelada' em
--    TODOS os ramos (credito, estorno, perdido). Antes o ramo 'perdido' deixava
--    'sinal_pago' (estado não-terminal que mente sobre o negócio).
-- 3. MENOR #4: log_acoes_sensiveis.acao — CHECK ('INSERT','UPDATE','DELETE').
-- 4. MENOR #5: submeter_anamnese — validação de formato: numero numérico,
--    multipla_escolha dentro das opções do modelo.
-- 5. ITEM 7: servico_cardapios — valores oficiais passam a ser 'ella_studio' e
--    'ella_men' (decisão de negócio: o estúdio pensa em marcas).
--
-- Regra permanente: migration nova, imutável. Aplica-se DEPOIS da 013.

-- =====================================================================
-- ITEM 7: Cardápio oficial ('ella_studio' / 'ella_men')
-- =====================================================================

-- Migra dados antigos ANTES de alterar a constraint
UPDATE public.servico_cardapios SET cardapio = 'ella_studio' WHERE cardapio = 'feminino';
UPDATE public.servico_cardapios SET cardapio = 'ella_men' WHERE cardapio = 'masculino';

-- Atualiza o CHECK constraint
ALTER TABLE public.servico_cardapios
DROP CONSTRAINT IF EXISTS servico_cardapios_cardapio_check;

ALTER TABLE public.servico_cardapios
ADD CONSTRAINT servico_cardapios_cardapio_check
CHECK (cardapio IN ('ella_studio', 'ella_men'));

-- =====================================================================
-- ITEM 1: Verificação de perfil nas 3 RPCs (GRAVE #2)
-- =====================================================================

-- -------------------------------------------------------------- confirmar_reserva
CREATE OR REPLACE FUNCTION confirmar_reserva(p_reserva_id UUID)
RETURNS TEXT
LANGUAGE plpgsql
SECURITY DEFINER SET search_path = ''
AS $$
DECLARE
    v_reserva RECORD;
    v_pago DECIMAL(10,2);
    v_atrasado BOOLEAN;
BEGIN
    SELECT * INTO v_reserva FROM public.reservas WHERE id = p_reserva_id FOR UPDATE;
    IF NOT FOUND THEN RAISE EXCEPTION 'Reserva não encontrada'; END IF;

    IF auth.role() = 'authenticated' THEN
        IF v_reserva.empresa_id IS DISTINCT FROM public.minha_empresa_id() THEN
            RAISE EXCEPTION 'Sem permissão para esta empresa';
        END IF;
        -- v3.4.3 (auditoria 2): perfil verificado — não basta ser da empresa
        IF public.meu_perfil() NOT IN ('admin','gestor','recepcao')
           AND NOT (public.meu_perfil() = 'profissional'
                    AND EXISTS (SELECT 1 FROM public.reserva_itens
                                WHERE reserva_id = p_reserva_id
                                  AND profissional_id = public.meu_profissional_id())) THEN
            RAISE EXCEPTION 'Sem permissão para confirmar esta reserva';
        END IF;
    END IF;

    IF v_reserva.estado = 'confirmada' THEN RETURN 'ja_confirmada'; END IF;
    IF v_reserva.estado = 'pagamento_em_revisao' THEN RETURN 'pagamento_em_revisao'; END IF;
    IF v_reserva.estado <> 'pre_reserva' THEN
        RAISE EXCEPTION 'Reserva não está em pré-reserva (estado: %)', v_reserva.estado;
    END IF;

    SELECT COALESCE(SUM(t.valor), 0) INTO v_pago
    FROM public.cobrancas c
    JOIN public.transacoes t ON t.cobranca_id = c.id
    WHERE c.reserva_id = p_reserva_id
      AND t.finalidade IN ('sinal', 'saldo', 'pagamento_total')
      AND t.estado = 'pago';

    IF v_pago < COALESCE(v_reserva.valor_sinal_total, 0) THEN
        RAISE EXCEPTION 'Sinal não pago (pago: %, exigido: %)', v_pago, v_reserva.valor_sinal_total;
    END IF;

    SELECT EXISTS (
        SELECT 1 FROM public.agenda_ocupacoes
        WHERE origem = 'pre_reserva' AND origem_id = p_reserva_id
          AND (estado = 'expirada' OR (estado = 'ativa' AND expires_at <= now()))
    ) INTO v_atrasado;

    IF v_atrasado THEN
        UPDATE public.agenda_ocupacoes SET estado = 'expirada'
        WHERE origem = 'pre_reserva' AND origem_id = p_reserva_id AND estado = 'ativa';
        UPDATE public.reservas SET estado = 'pagamento_em_revisao' WHERE id = p_reserva_id;
        INSERT INTO public.revisoes_cancelamento (reserva_id, empresa_id, valor_sinal, regra_aplicada, motivo_decisao)
        VALUES (p_reserva_id, v_reserva.empresa_id, v_pago, 'pagamento_atrasado',
                'Sinal pago após o prazo da pré-reserva — confirmar (se o horário ainda estiver livre), estornar ou dar crédito')
        ON CONFLICT DO NOTHING;
        PERFORM public.notificar_staff(v_reserva.empresa_id, 'pagamento_em_revisao',
            'Pagamento atrasado na reserva ' || p_reserva_id::text || ' (R$ ' ||
            trim(to_char(v_pago, '999990D00')) || '). O horário foi liberado. Decida: confirmar, estornar, crédito ou perdido.');
        RETURN 'pagamento_em_revisao';
    END IF;

    UPDATE public.reservas SET estado = 'confirmada' WHERE id = p_reserva_id;
    UPDATE public.reserva_itens SET estado = 'confirmado'
    WHERE reserva_id = p_reserva_id AND estado = 'pendente';
    UPDATE public.agenda_ocupacoes
    SET origem = 'reserva', expires_at = NULL
    WHERE origem = 'pre_reserva' AND origem_id = p_reserva_id AND estado = 'ativa';
    UPDATE public.cobrancas
    SET estado = CASE WHEN v_pago >= v_reserva.valor_total THEN 'total_pago' ELSE 'sinal_pago' END
    WHERE reserva_id = p_reserva_id AND estado = 'pendente';
    RETURN 'confirmada';
END;
$$;

-- ---------------------------------------------------------------- cancelar_reserva
CREATE OR REPLACE FUNCTION cancelar_reserva(
    p_reserva_id UUID,
    p_excecao TEXT DEFAULT NULL,
    p_motivo TEXT DEFAULT NULL
)
RETURNS TEXT
LANGUAGE plpgsql
SECURITY DEFINER SET search_path = ''
AS $$
DECLARE
    v_reserva RECORD;
    v_limite TIMESTAMP;
    v_regra TEXT;
    v_usuario UUID;
    v_pago DECIMAL(10,2);
BEGIN
    SELECT * INTO v_reserva FROM public.reservas WHERE id = p_reserva_id FOR UPDATE;
    IF NOT FOUND THEN RAISE EXCEPTION 'Reserva não encontrada'; END IF;

    IF auth.role() = 'authenticated' THEN
        IF v_reserva.empresa_id IS DISTINCT FROM public.minha_empresa_id() THEN
            RAISE EXCEPTION 'Sem permissão para esta empresa';
        END IF;
        -- v3.4.3 (auditoria 2): perfil verificado
        IF public.meu_perfil() NOT IN ('admin','gestor','recepcao')
           AND NOT (public.meu_perfil() = 'profissional'
                    AND EXISTS (SELECT 1 FROM public.reserva_itens
                                WHERE reserva_id = p_reserva_id
                                  AND profissional_id = public.meu_profissional_id())) THEN
            RAISE EXCEPTION 'Sem permissão para cancelar esta reserva';
        END IF;
    END IF;

    IF v_reserva.estado = 'pagamento_em_revisao' THEN
        RAISE EXCEPTION 'Reserva em revisão de pagamento — decida pela RPC resolver_revisao';
    END IF;

    IF p_excecao IS NOT NULL THEN
        IF p_excecao NOT IN ('credito', 'estorno', 'perdido') THEN
            RAISE EXCEPTION 'Exceção inválida: %', p_excecao;
        END IF;
        IF auth.role() = 'authenticated' THEN
            IF public.meu_perfil() <> 'admin' THEN
                RAISE EXCEPTION 'Exceção de cancelamento exige perfil admin';
            END IF;
            IF COALESCE(auth.jwt() ->> 'aal', 'aal1') <> 'aal2' THEN
                RAISE EXCEPTION 'Exceção de cancelamento exige verificação em duas etapas (MFA)';
            END IF;
        END IF;
        IF p_motivo IS NULL OR length(trim(p_motivo)) = 0 THEN
            RAISE EXCEPTION 'Exceção de cancelamento exige motivo';
        END IF;
    END IF;

    SELECT ((MIN(ri.inicio) AT TIME ZONE 'America/Sao_Paulo')::DATE - 1) + interval '16 hours' INTO v_limite
    FROM public.reserva_itens ri
    WHERE ri.reserva_id = p_reserva_id AND ri.estado NOT IN ('cancelado');

    v_regra := CASE WHEN (now() AT TIME ZONE 'America/Sao_Paulo') <= v_limite
                    THEN 'credito_automatico' ELSE 'perda_automatica' END;
    v_usuario := public.meu_usuario_id();

    UPDATE public.reservas SET estado = 'cancelada'
    WHERE id = p_reserva_id AND estado IN ('pre_reserva', 'confirmada');
    IF NOT FOUND THEN RAISE EXCEPTION 'Reserva não pode ser cancelada no estado atual'; END IF;

    UPDATE public.reserva_itens SET estado = 'cancelado'
    WHERE reserva_id = p_reserva_id AND estado IN ('pendente', 'confirmado');
    UPDATE public.agenda_ocupacoes SET estado = 'cancelada'
    WHERE origem IN ('pre_reserva', 'reserva') AND origem_id = p_reserva_id AND estado = 'ativa';
    UPDATE public.cobrancas SET estado = 'cancelada'
    WHERE reserva_id = p_reserva_id AND estado = 'pendente';

    SELECT COALESCE(SUM(t.valor), 0) INTO v_pago
    FROM public.cobrancas c
    JOIN public.transacoes t ON t.cobranca_id = c.id
    WHERE c.reserva_id = p_reserva_id
      AND t.finalidade IN ('sinal', 'saldo', 'pagamento_total')
      AND t.estado = 'pago';

    v_pago := v_pago - COALESCE((SELECT SUM(rev.valor_sinal) FROM public.revisoes_cancelamento rev
                                 WHERE rev.reserva_id = p_reserva_id
                                   AND rev.decisao_final IS DISTINCT FROM 'confirmar'), 0);

    IF v_pago > 0 THEN
        INSERT INTO public.revisoes_cancelamento
            (reserva_id, empresa_id, valor_sinal, regra_aplicada, decisao_final, decidido_por, motivo_decisao)
        VALUES
            (p_reserva_id, v_reserva.empresa_id, v_pago, v_regra, p_excecao, v_usuario, p_motivo)
        ON CONFLICT DO NOTHING;
        IF p_excecao IS NULL THEN
            PERFORM public.notificar_staff(v_reserva.empresa_id, 'revisao_cancelamento',
                'Cancelamento com R$ ' || trim(to_char(v_pago, '999990D00')) || ' pago — regra ' ||
                v_regra || '. Confirme a decisão na fila de revisões.');
        END IF;
    END IF;

    IF p_excecao IS NOT NULL THEN
        INSERT INTO public.log_acoes (empresa_id, tabela, registro_id, acao, usuario_id, perfil, motivo)
        VALUES (v_reserva.empresa_id, 'reservas', p_reserva_id, 'UPDATE', v_usuario,
                public.meu_perfil(), 'excecao_cancelamento=' || p_excecao || ': ' || p_motivo);
    END IF;
    RETURN v_regra;
END;
$$;

-- ---------------------------------------------------------- cancelar_pre_reserva
CREATE OR REPLACE FUNCTION cancelar_pre_reserva(p_reserva_id UUID)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER SET search_path = ''
AS $$
DECLARE
    v_reserva RECORD;
BEGIN
    SELECT * INTO v_reserva FROM public.reservas WHERE id = p_reserva_id FOR UPDATE;
    IF NOT FOUND THEN RAISE EXCEPTION 'Reserva não encontrada'; END IF;

    IF auth.role() = 'authenticated' THEN
        IF v_reserva.empresa_id IS DISTINCT FROM public.minha_empresa_id() THEN
            RAISE EXCEPTION 'Sem permissão para esta empresa';
        END IF;
        -- v3.4.3 (auditoria 2): perfil verificado
        IF public.meu_perfil() NOT IN ('admin','gestor','recepcao')
           AND NOT (public.meu_perfil() = 'profissional'
                    AND EXISTS (SELECT 1 FROM public.reserva_itens
                                WHERE reserva_id = p_reserva_id
                                  AND profissional_id = public.meu_profissional_id())) THEN
            RAISE EXCEPTION 'Sem permissão para cancelar esta pré-reserva';
        END IF;
    END IF;

    IF v_reserva.estado NOT IN ('pre_reserva', 'expirada') THEN
        RAISE EXCEPTION 'Reserva não é uma pré-reserva (estado: %)', v_reserva.estado;
    END IF;

    UPDATE public.agenda_ocupacoes SET estado = 'cancelada'
    WHERE origem = 'pre_reserva' AND origem_id = p_reserva_id AND estado = 'ativa';
    UPDATE public.reserva_itens SET estado = 'cancelado'
    WHERE reserva_id = p_reserva_id AND estado = 'pendente';
    UPDATE public.cobrancas SET estado = 'cancelada'
    WHERE reserva_id = p_reserva_id AND estado = 'pendente';
    UPDATE public.reservas SET estado = 'cancelada' WHERE id = p_reserva_id;
END;
$$;

-- =====================================================================
-- ITEM 2: resolver_revisao — cobrança terminal 'cancelada' (MÉDIO #3)
-- =====================================================================

CREATE OR REPLACE FUNCTION resolver_revisao(
    p_revisao_id UUID,
    p_decisao TEXT,
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

    -- ===================== CONFIRMAR =====================
    IF p_decisao = 'confirmar' THEN
        IF v_reserva.estado <> 'pagamento_em_revisao' THEN
            RAISE EXCEPTION 'Só se pode confirmar reserva em pagamento_em_revisao (estado: %)', v_reserva.estado;
        END IF;
        IF EXISTS (SELECT 1 FROM public.reserva_itens ri
                   WHERE ri.reserva_id = v_reserva.id AND ri.inicio <= now()) THEN
            RAISE EXCEPTION 'O horário desta reserva já passou — escolha estorno ou crédito';
        END IF;
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
            -- v3.4.3: cobrança sempre terminal 'cancelada'
            UPDATE public.cobrancas SET estado = 'cancelada'
            WHERE reserva_id = v_reserva.id;
        END IF;

    -- ===================== ESTORNO =====================
    ELSIF p_decisao = 'estorno' THEN
        UPDATE public.transacoes t SET estado = 'estornado'
        FROM public.cobrancas c
        WHERE t.cobranca_id = c.id AND c.reserva_id = v_reserva.id
          AND t.finalidade IN ('sinal', 'saldo', 'pagamento_total') AND t.estado = 'pago';
        INSERT INTO public.jobs (empresa_id, tipo, payload)
        VALUES (v_reserva.empresa_id, 'estorno_mercado_pago',
                jsonb_build_object('reserva_id', v_reserva.id, 'revisao_id', v_rev.id,
                                   'valor', v_rev.valor_sinal, 'motivo', p_motivo));
        IF v_reserva.estado = 'pagamento_em_revisao' THEN
            UPDATE public.reservas SET estado = 'cancelada' WHERE id = v_reserva.id;
            UPDATE public.reserva_itens SET estado = 'cancelado'
            WHERE reserva_id = v_reserva.id AND estado = 'pendente';
            -- v3.4.3: cobrança sempre terminal 'cancelada'
            UPDATE public.cobrancas SET estado = 'cancelada'
            WHERE reserva_id = v_reserva.id;
        END IF;

    -- ===================== PERDIDO =====================
    ELSE
        IF v_reserva.estado = 'pagamento_em_revisao' THEN
            UPDATE public.reservas SET estado = 'cancelada' WHERE id = v_reserva.id;
            UPDATE public.reserva_itens SET estado = 'cancelado'
            WHERE reserva_id = v_reserva.id AND estado = 'pendente';
            -- v3.4.3 (auditoria 2): 'perdido' também fecha a cobrança como 'cancelada'.
            -- 'sinal_pago' não é terminal e mente (a reserva foi cancelada/perdida).
            UPDATE public.cobrancas SET estado = 'cancelada'
            WHERE reserva_id = v_reserva.id;
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

-- =====================================================================
-- ITEM 3: CHECK em log_acoes_sensiveis.acao (MENOR #4)
-- =====================================================================

ALTER TABLE public.log_acoes_sensiveis
DROP CONSTRAINT IF EXISTS log_acoes_sensiveis_acao_check;

ALTER TABLE public.log_acoes_sensiveis
ADD CONSTRAINT log_acoes_sensiveis_acao_check
CHECK (acao IN ('INSERT', 'UPDATE', 'DELETE'));

-- =====================================================================
-- ITEM 4: Validação em submeter_anamnese (MENOR #5)
-- =====================================================================

CREATE OR REPLACE FUNCTION submeter_anamnese(
    p_token TEXT,
    p_respostas JSONB,
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
    v_pergunta RECORD;
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

    IF v_tok.reserva_item_id IS NOT NULL AND EXISTS (
        SELECT 1 FROM public.reserva_itens ri
        JOIN public.reservas r ON r.id = ri.reserva_id
        WHERE ri.id = v_tok.reserva_item_id AND r.estado IN ('cancelada', 'expirada')
    ) THEN
        RAISE EXCEPTION 'O agendamento ligado a esta ficha já não está ativo — fala com o estúdio';
    END IF;

    -- Todas as perguntas respondidas pertencem ao modelo desta ficha
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

    -- v3.4.3 (auditoria 2): validação de formato — numero numérico, multipla_escolha dentro das opções
    FOR v_resp IN SELECT * FROM jsonb_array_elements(p_respostas) LOOP
        SELECT * INTO v_pergunta FROM public.modelo_perguntas
        WHERE id = (v_resp->>'pergunta_id')::UUID AND modelo_id = v_tok.modelo_id;

        IF v_pergunta.tipo_resposta = 'numero' THEN
            IF NOT (v_resp->>'resposta' ~ '^-?\d+(\.\d+)?$') THEN
                RAISE EXCEPTION 'A resposta para "%" deve ser um número', v_pergunta.pergunta;
            END IF;
        END IF;

        IF v_pergunta.tipo_resposta = 'multipla_escolha' THEN
            IF v_pergunta.opcoes IS NULL
               OR NOT (v_resp->>'resposta' = ANY (ARRAY(SELECT jsonb_array_elements_text(v_pergunta.opcoes)))) THEN
                RAISE EXCEPTION 'A resposta para "%" deve ser uma das opções: %',
                    v_pergunta.pergunta, COALESCE(v_pergunta.opcoes::TEXT, '(nenhuma)');
            END IF;
        END IF;
    END LOOP;

    INSERT INTO public.anamnese_respostas (anamnese_id, pergunta_id, resposta)
    SELECT v_tok.id, (r->>'pergunta_id')::UUID, r->>'resposta'
    FROM jsonb_array_elements(p_respostas) r;

    -- Regras do modelo
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

-- =====================================================================
-- Permissões preservadas (CREATE OR REPLACE mantém o dono, mas os
-- REVOKE/GRANT já existem nas migrations originais; repetimos por
-- segurança caso algum tenha sido alterado manualmente)
-- =====================================================================

REVOKE ALL ON FUNCTION public.confirmar_reserva(UUID) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.confirmar_reserva(UUID) TO authenticated, service_role;

REVOKE ALL ON FUNCTION public.cancelar_reserva(UUID, TEXT, TEXT) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.cancelar_reserva(UUID, TEXT, TEXT) TO authenticated, service_role;

REVOKE ALL ON FUNCTION public.cancelar_pre_reserva(UUID) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.cancelar_pre_reserva(UUID) TO authenticated, service_role;

REVOKE ALL ON FUNCTION public.resolver_revisao(UUID, TEXT, TEXT) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.resolver_revisao(UUID, TEXT, TEXT) TO authenticated, service_role;

REVOKE ALL ON FUNCTION public.submeter_anamnese(TEXT, JSONB, BOOLEAN, TEXT) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.submeter_anamnese(TEXT, JSONB, BOOLEAN, TEXT) TO anon, authenticated, service_role;
