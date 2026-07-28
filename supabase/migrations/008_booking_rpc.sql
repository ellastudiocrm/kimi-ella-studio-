-- 008_booking_rpc.sql (v3.4) — criação de pré-reserva e cancelamento individual de item
-- SECURITY DEFINER (contorna RLS) → guarda de inquilino + verificação de perfil; search_path=''

-- v3.4: timezone explícito (Ricardo), calendário de exceções completo (Carlos #8),
-- retry de mesa em corrida (Carlos #12), erro amigável de concorrência (Ricardo),
-- percentual de sinal por serviço (Ricardo), ficha ligada ao item (Carlos #11).
CREATE OR REPLACE FUNCTION criar_pre_reserva(
    p_empresa_id UUID,
    p_cliente_id UUID,
    p_itens JSONB,              -- [{servico_id, profissional_id, inicio, cardapio?}]
    p_idempotencia_key TEXT
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER SET search_path = ''
AS $$
DECLARE
    v_reserva_id UUID;
    v_item JSONB;
    v_servico RECORD;
    v_profissional RECORD;
    v_recurso RECORD;
    v_cand RECORD;
    v_exc RECORD;
    v_item_id UUID;
    v_inicio TIMESTAMPTZ;
    v_fim TIMESTAMPTZ;
    v_local_i TIMESTAMP;        -- horário LOCAL do studio (independe da sessão)
    v_local_f TIMESTAMP;
    v_preco DECIMAL(10,2);
    v_cardapio TEXT;
    v_dow INT;
    v_anamnese_id UUID;
    v_token TEXT;
    v_anamneses JSONB := '[]'::JSONB;
    v_total DECIMAL(10,2);
    v_sinal DECIMAL(10,2);
    v_pct_reserva INT := NULL;
    v_ok BOOLEAN;
BEGIN
    -- Guarda: autenticado tem de ter vínculo ativo com a empresa
    IF auth.role() = 'authenticated' THEN
        IF public.minha_empresa_id() IS NULL THEN
            RAISE EXCEPTION 'Utilizador sem vínculo ativo';
        END IF;
        IF p_empresa_id IS DISTINCT FROM public.minha_empresa_id() THEN
            RAISE EXCEPTION 'Sem permissão para esta empresa';
        END IF;
    END IF;

    -- Idempotência POR EMPRESA
    SELECT id INTO v_reserva_id FROM public.reservas
    WHERE empresa_id = p_empresa_id AND idempotencia_key = p_idempotencia_key;
    IF FOUND THEN
        RETURN jsonb_build_object(
            'reserva_id', v_reserva_id, 'idempotente', true,
            'valor_total', (SELECT valor_total FROM public.reservas WHERE id = v_reserva_id),
            'valor_sinal', (SELECT valor_sinal_total FROM public.reservas WHERE id = v_reserva_id),
            'anamneses', COALESCE((
                SELECT jsonb_agg(jsonb_build_object('anamnese_id', a.id))
                FROM public.anamneses a
                WHERE a.empresa_id = p_empresa_id
                  AND a.id IN (SELECT t.anamnese_id FROM public.anamnese_tokens t WHERE t.reserva_id = v_reserva_id)
            ), '[]'::JSONB)
        );
    END IF;

    IF NOT EXISTS (SELECT 1 FROM public.clientes WHERE id = p_cliente_id AND empresa_id = p_empresa_id) THEN
        RAISE EXCEPTION 'Cliente não encontrado nesta empresa';
    END IF;

    IF p_itens IS NULL OR jsonb_array_length(p_itens) = 0 THEN
        RAISE EXCEPTION 'A reserva precisa de pelo menos um serviço';
    END IF;

    INSERT INTO public.reservas (empresa_id, cliente_id, estado, percentual_sinal, idempotencia_key)
    VALUES (p_empresa_id, p_cliente_id, 'pre_reserva', 30, p_idempotencia_key)
    RETURNING id INTO v_reserva_id;

    FOR v_item IN SELECT * FROM jsonb_array_elements(p_itens)
    LOOP
        v_item_id := NULL;
        v_inicio := (v_item->>'inicio')::TIMESTAMPTZ;
        v_cardapio := COALESCE(v_item->>'cardapio', 'feminino');

        SELECT * INTO v_servico FROM public.servicos
        WHERE id = (v_item->>'servico_id')::UUID
          AND empresa_id = p_empresa_id AND ativo = true;
        IF NOT FOUND THEN RAISE EXCEPTION 'Serviço não encontrado ou inativo'; END IF;

        IF v_servico.anamnese_obrigatoria AND v_servico.modelo_anamnese_id IS NULL THEN
            RAISE EXCEPTION 'Serviço % exige anamnese, mas não tem modelo configurado', v_servico.nome_tecnico;
        END IF;

        IF v_inicio <= now() THEN
            RAISE EXCEPTION 'Não é possível agendar no passado';
        END IF;

        v_fim := v_inicio + (v_servico.duracao_minutos || ' minutes')::INTERVAL;
        v_pct_reserva := COALESCE(v_pct_reserva, v_servico.percentual_sinal);

        -- Hora LOCAL do studio: não depende do timezone da sessão (Ricardo)
        v_local_i := v_inicio AT TIME ZONE 'America/Sao_Paulo';
        v_local_f := v_fim AT TIME ZONE 'America/Sao_Paulo';
        v_dow := EXTRACT(DOW FROM v_local_i)::INT; -- 0=domingo

        -- Profissional habilitada, ativa e da empresa
        SELECT p.* INTO v_profissional
        FROM public.profissionais p
        JOIN public.profissional_servicos ps ON ps.profissional_id = p.id
        WHERE p.id = (v_item->>'profissional_id')::UUID
          AND p.empresa_id = p_empresa_id
          AND p.ativo = true
          AND ps.servico_id = v_servico.id;
        IF NOT FOUND THEN
            RAISE EXCEPTION 'Profissional não habilitada para este serviço';
        END IF;

        -- ===== Calendário de exceções na ordem correta (Carlos #8) =====
        -- 1. Fechamento GERAL (folga/feriado da empresa) bloqueia TUDO
        IF EXISTS (
            SELECT 1 FROM public.excecoes_calendario e
            WHERE e.empresa_id = p_empresa_id AND e.data = v_local_i::DATE
              AND e.profissional_id IS NULL AND e.tipo IN ('folga', 'feriado')
        ) THEN
            RAISE EXCEPTION 'Sem atendimento nesta data (folga ou feriado)';
        END IF;

        -- 2. Folga da PROFISSIONAL bloqueia só ela
        IF EXISTS (
            SELECT 1 FROM public.excecoes_calendario e
            WHERE e.empresa_id = p_empresa_id AND e.data = v_local_i::DATE
              AND e.profissional_id = v_profissional.id AND e.tipo IN ('folga', 'feriado')
        ) THEN
            RAISE EXCEPTION 'Profissional de folga nesta data';
        END IF;

        -- 3. Ajuste da profissional SUBSTITUI o horário normal dela
        SELECT e.abertura, e.fechamento INTO v_exc
        FROM public.excecoes_calendario e
        WHERE e.empresa_id = p_empresa_id AND e.data = v_local_i::DATE
          AND e.profissional_id = v_profissional.id AND e.tipo = 'ajuste'
        LIMIT 1;

        IF FOUND THEN
            IF v_exc.abertura IS NULL OR v_exc.fechamento IS NULL THEN
                RAISE EXCEPTION 'Ajuste de horário sem período definido';
            END IF;
            IF v_local_i::TIME < v_exc.abertura OR v_local_f::TIME > v_exc.fechamento THEN
                RAISE EXCEPTION 'Fora do horário especial da profissional nesta data';
            END IF;
        ELSE
            -- 4. Ajuste da empresa substitui o horário normal da empresa
            SELECT e.abertura, e.fechamento INTO v_exc
            FROM public.excecoes_calendario e
            WHERE e.empresa_id = p_empresa_id AND e.data = v_local_i::DATE
              AND e.profissional_id IS NULL AND e.tipo = 'ajuste'
            LIMIT 1;
            IF FOUND THEN
                IF v_exc.abertura IS NULL OR v_exc.fechamento IS NULL THEN
                    RAISE EXCEPTION 'Ajuste de horário da empresa sem período definido';
                END IF;
                IF v_local_i::TIME < v_exc.abertura OR v_local_f::TIME > v_exc.fechamento THEN
                    RAISE EXCEPTION 'Fora do horário especial desta data';
                END IF;
            ELSE
                -- 5. Horário recorrente da empresa
                IF NOT EXISTS (
                    SELECT 1 FROM public.horarios_empresa h
                    WHERE h.empresa_id = p_empresa_id AND h.dia_semana = v_dow AND h.ativo = true
                      AND v_local_i::TIME >= h.abertura AND v_local_f::TIME <= h.fechamento
                ) THEN
                    RAISE EXCEPTION 'Fora do horário de funcionamento';
                END IF;
            END IF;

            -- Horário recorrente da profissional (só quando não há ajuste dela)
            IF NOT EXISTS (
                SELECT 1 FROM public.horarios_profissional h
                WHERE h.profissional_id = v_profissional.id AND h.dia_semana = v_dow AND h.ativo = true
                  AND v_local_i::TIME >= h.abertura AND v_local_f::TIME <= h.fechamento
            ) THEN
                RAISE EXCEPTION 'Profissional não atende neste dia/horário';
            END IF;
        END IF;
        -- ===== fim do calendário =====

        -- Profissional livre (erro claro; EXCLUDE + retry são a rede de segurança)
        IF EXISTS (
            SELECT 1 FROM public.agenda_ocupacoes o
            WHERE o.profissional_id = v_profissional.id
              AND o.estado = 'ativa'
              AND o.periodo && tstzrange(v_inicio, v_fim, '[)')
        ) THEN
            RAISE EXCEPTION 'Profissional indisponível neste horário';
        END IF;

        SELECT COALESCE(sc.preco_final, v_servico.preco_base) INTO v_preco
        FROM public.servico_cardapios sc
        WHERE sc.servico_id = v_servico.id AND sc.cardapio = v_cardapio AND sc.ativo = true;
        v_preco := COALESCE(v_preco, v_servico.preco_base);

        -- Mesa com RETRY: se outra transação ganhar a mesa, tenta a seguinte (Carlos #12)
        v_ok := false;
        FOR v_cand IN
            SELECT r.* FROM public.recursos r
            WHERE r.tipo_recurso_id = v_servico.tipo_recurso_id
              AND r.empresa_id = p_empresa_id AND r.ativo = true
              AND NOT EXISTS (
                  SELECT 1 FROM public.agenda_ocupacoes o
                  WHERE o.recurso_id = r.id AND o.estado = 'ativa'
                    AND o.periodo && tstzrange(v_inicio, v_fim, '[)')
              )
            ORDER BY r.nome
        LOOP
            IF v_item_id IS NULL THEN
                INSERT INTO public.reserva_itens (
                    reserva_id, empresa_id, nome_servico, preco_base_utilizado,
                    preco_final, duracao_reservada, percentual_sinal, valor_sinal,
                    servico_id, profissional_id, recurso_id, inicio, fim
                ) VALUES (
                    v_reserva_id, p_empresa_id, v_servico.nome_tecnico, v_servico.preco_base,
                    v_preco, v_servico.duracao_minutos, v_servico.percentual_sinal,
                    ROUND(v_preco * v_servico.percentual_sinal / 100.0, 2),
                    v_servico.id, v_profissional.id, v_cand.id, v_inicio, v_fim
                ) RETURNING id INTO v_item_id;
            ELSE
                UPDATE public.reserva_itens SET recurso_id = v_cand.id WHERE id = v_item_id;
            END IF;

            BEGIN
                INSERT INTO public.agenda_ocupacoes (empresa_id, tipo_ocupacao, recurso_id, reserva_item_id, inicio, fim, origem, origem_id, estado, expires_at)
                VALUES (p_empresa_id, 'recurso', v_cand.id, v_item_id, v_inicio, v_fim, 'pre_reserva', v_reserva_id, 'ativa', now() + interval '30 minutes');
                v_ok := true;
                EXIT;
            EXCEPTION WHEN exclusion_violation THEN
                NULL; -- outra transação ficou com esta mesa; tentar a próxima
            END;
        END LOOP;

        IF NOT v_ok THEN
            RAISE EXCEPTION 'Nenhum recurso compatível disponível neste horário';
        END IF;

        -- Ocupação da profissional (concorrência vira mensagem clara — Ricardo)
        BEGIN
            INSERT INTO public.agenda_ocupacoes (empresa_id, tipo_ocupacao, profissional_id, reserva_item_id, inicio, fim, origem, origem_id, estado, expires_at)
            VALUES (p_empresa_id, 'profissional', v_profissional.id, v_item_id, v_inicio, v_fim, 'pre_reserva', v_reserva_id, 'ativa', now() + interval '30 minutes');
        EXCEPTION WHEN exclusion_violation THEN
            RAISE EXCEPTION 'Profissional indisponível neste horário';
        END;

        -- Anamnese: ficha ligada AO ITEM + token bruto devolvido uma única vez
        IF v_servico.anamnese_obrigatoria THEN
            INSERT INTO public.anamneses (empresa_id, cliente_id, servico_id, modelo_id, versao_modelo, estado, reserva_item_id, profissional_revisora_id)
            SELECT p_empresa_id, p_cliente_id, v_servico.id, m.id, m.versao, 'pendente', v_item_id, v_profissional.id
            FROM public.modelos_anamnese m WHERE m.id = v_servico.modelo_anamnese_id
            RETURNING id INTO v_anamnese_id;

            v_token := public.gerar_token_opaco();

            INSERT INTO public.anamnese_tokens (empresa_id, token_hash, anamnese_id, cliente_id, reserva_id, expira_em)
            VALUES (
                p_empresa_id, public.sha256_hex(v_token),
                v_anamnese_id, p_cliente_id, v_reserva_id,
                LEAST(v_inicio, now() + interval '24 hours')
            );

            v_anamneses := v_anamneses || jsonb_build_object(
                'anamnese_id', v_anamnese_id,
                'token', v_token,
                'expira_em', LEAST(v_inicio, now() + interval '24 hours')
            );
        END IF;
    END LOOP;

    UPDATE public.reservas r SET
        valor_total = t.total,
        valor_sinal_total = t.sinal,
        percentual_sinal = v_pct_reserva
    FROM (SELECT SUM(preco_final) AS total, SUM(valor_sinal) AS sinal
          FROM public.reserva_itens WHERE reserva_id = v_reserva_id) t
    WHERE r.id = v_reserva_id
    RETURNING r.valor_total, r.valor_sinal_total INTO v_total, v_sinal;

    INSERT INTO public.cobrancas (reserva_id, empresa_id, valor_total, percentual_sinal, valor_sinal)
    VALUES (v_reserva_id, p_empresa_id, v_total, v_pct_reserva, v_sinal);

    -- v3.4.1 (auditoria #3): sinal ZERO (percentual_sinal = 0 — a configuração da fase
    -- de agenda vazia) não pode morrer nos 30 min: nasce CONFIRMADA, ocupações sem
    -- expires_at, sem PIX a esperar. O saldo paga-se no estúdio.
    IF v_sinal <= 0 THEN
        UPDATE public.reservas SET estado = 'confirmada' WHERE id = v_reserva_id;
        UPDATE public.reserva_itens SET estado = 'confirmado'
        WHERE reserva_id = v_reserva_id AND estado = 'pendente';
        UPDATE public.agenda_ocupacoes SET origem = 'reserva', expires_at = NULL
        WHERE origem = 'pre_reserva' AND origem_id = v_reserva_id AND estado = 'ativa';
    END IF;

    RETURN jsonb_build_object(
        'reserva_id', v_reserva_id,
        'idempotente', false,
        'estado', CASE WHEN v_sinal <= 0 THEN 'confirmada' ELSE 'pre_reserva' END,
        'valor_total', v_total,
        'valor_sinal', v_sinal,
        'anamneses', v_anamneses
    );

EXCEPTION
    WHEN unique_violation THEN
        SELECT id INTO v_reserva_id FROM public.reservas
        WHERE empresa_id = p_empresa_id AND idempotencia_key = p_idempotencia_key;
        IF FOUND THEN
            RETURN jsonb_build_object('reserva_id', v_reserva_id, 'idempotente', true, 'anamneses', '[]'::JSONB);
        END IF;
        RAISE;
    WHEN exclusion_violation THEN
        RAISE EXCEPTION 'Esse horário acabou de ser preenchido por outro cliente. Tenta outro horário.';
END;
$$;

-- v3.4 (Ricardo: último item zerava a revisão / Carlos #3: regra 16h e valor proporcional por item)
CREATE OR REPLACE FUNCTION cancelar_item_reserva(
    p_reserva_item_id UUID,
    p_excecao TEXT DEFAULT NULL,
    p_motivo TEXT DEFAULT NULL
)
RETURNS TEXT
LANGUAGE plpgsql
SECURITY DEFINER SET search_path = ''
AS $$
DECLARE
    v_item RECORD;
    v_restantes INT;
    v_limite TIMESTAMP;
    v_regra TEXT;
    v_pago_reserva DECIMAL(10,2);
    v_valor_item DECIMAL(10,2);
BEGIN
    SELECT ri.*, r.empresa_id AS r_empresa_id INTO v_item
    FROM public.reserva_itens ri
    JOIN public.reservas r ON r.id = ri.reserva_id
    WHERE ri.id = p_reserva_item_id;
    IF NOT FOUND THEN RAISE EXCEPTION 'Item não encontrado'; END IF;

    IF auth.role() = 'authenticated' THEN
        IF v_item.r_empresa_id IS DISTINCT FROM public.minha_empresa_id() THEN
            RAISE EXCEPTION 'Sem permissão para esta empresa';
        END IF;
        IF public.meu_perfil() NOT IN ('admin','gestor','recepcao')
           AND NOT (public.meu_perfil() = 'profissional' AND v_item.profissional_id = public.meu_profissional_id()) THEN
            RAISE EXCEPTION 'Sem permissão para cancelar este item';
        END IF;
    END IF;

    IF p_excecao IS NOT NULL THEN
        IF p_excecao NOT IN ('credito', 'estorno', 'perdido') THEN
            RAISE EXCEPTION 'Exceção inválida: %', p_excecao;
        END IF;
        IF auth.role() = 'authenticated' AND public.meu_perfil() <> 'admin' THEN
            RAISE EXCEPTION 'Exceção de cancelamento exige perfil admin';
        END IF;
        IF p_motivo IS NULL OR length(trim(p_motivo)) = 0 THEN
            RAISE EXCEPTION 'Exceção de cancelamento exige motivo';
        END IF;
    END IF;

    -- Ordem de lock global (anti-deadlock): RESERVA primeiro, depois o item
    PERFORM 1 FROM public.reservas WHERE id = v_item.reserva_id FOR UPDATE;

    -- Re-lê o item já sob lock (leitura anterior era sem lock)
    SELECT ri.*, r.empresa_id AS r_empresa_id, r.estado AS r_estado INTO v_item
    FROM public.reserva_itens ri
    JOIN public.reservas r ON r.id = ri.reserva_id
    WHERE ri.id = p_reserva_item_id FOR UPDATE OF ri;

    -- v3.4.1: dinheiro em revisão só sai pela fila — cancelar item aqui
    -- contabilizaria o mesmo dinheiro duas vezes
    IF v_item.r_estado = 'pagamento_em_revisao' THEN
        RAISE EXCEPTION 'Reserva em revisão de pagamento — decida pela RPC resolver_revisao';
    END IF;

    IF v_item.estado NOT IN ('pendente', 'confirmado') THEN
        RAISE EXCEPTION 'Item não pode ser cancelado no estado atual';
    END IF;

    SELECT COUNT(*) INTO v_restantes
    FROM public.reserva_itens
    WHERE reserva_id = v_item.reserva_id AND estado IN ('pendente', 'confirmado') AND id <> p_reserva_item_id;

    -- Último item: cancela a RESERVA primeiro — a revisão fica com o valor CHEIO (Ricardo A3)
    IF v_restantes = 0 THEN
        PERFORM public.cancelar_reserva(v_item.reserva_id, p_excecao, p_motivo);
        RETURN 'reserva_cancelada';
    END IF;

    -- Regra das 16h calculada para ESTE item (Carlos #3), em hora local do studio
    v_limite := ((v_item.inicio AT TIME ZONE 'America/Sao_Paulo')::DATE - 1) + interval '16 hours';
    v_regra := CASE WHEN (now() AT TIME ZONE 'America/Sao_Paulo') <= v_limite
                    THEN 'credito_automatico' ELSE 'perda_automatica' END;

    UPDATE public.reserva_itens SET estado = 'cancelado' WHERE id = p_reserva_item_id;

    UPDATE public.agenda_ocupacoes SET estado = 'cancelada'
    WHERE reserva_item_id = p_reserva_item_id AND estado = 'ativa';

    -- Revisão só quando há DINHEIRO pago na reserva; valor proporcional a ESTE
    -- item (Carlos #3). v3.4.1 (auditoria #1): desconta o que JÁ está na fila —
    -- a fila nunca vale mais do que o dinheiro recebido
    SELECT COALESCE(SUM(t.valor), 0) INTO v_pago_reserva
    FROM public.cobrancas c
    JOIN public.transacoes t ON t.cobranca_id = c.id
    WHERE c.reserva_id = v_item.reserva_id AND t.estado = 'pago'
      AND t.finalidade IN ('sinal', 'saldo', 'pagamento_total');

    -- v3.4.1b: 'confirmar' devolve o dinheiro à reserva viva — NÃO entra no
    -- desconto (senão um cancelamento depois de um confirmar perdia o rasto do valor)
    v_valor_item := LEAST(v_item.valor_sinal,
        v_pago_reserva - COALESCE((SELECT SUM(rev.valor_sinal) FROM public.revisoes_cancelamento rev
                                   WHERE rev.reserva_id = v_item.reserva_id
                                     AND rev.decisao_final IS DISTINCT FROM 'confirmar'), 0));

    IF v_valor_item > 0 THEN
        INSERT INTO public.revisoes_cancelamento
            (reserva_id, reserva_item_id, empresa_id, valor_sinal, regra_aplicada, decisao_final, decidido_por, motivo_decisao)
        VALUES
            (v_item.reserva_id, p_reserva_item_id, v_item.r_empresa_id, v_valor_item,
             v_regra, p_excecao, public.meu_usuario_id(), p_motivo)
        ON CONFLICT DO NOTHING;

        PERFORM public.notificar_staff(v_item.r_empresa_id, 'cancelamento_item',
            'Item cancelado com R$ ' || trim(to_char(v_valor_item, '999990D00')) ||
            ' pago — ' || v_item.nome_servico || ' (' || v_regra || ')');
    END IF;

    UPDATE public.reservas r SET
        valor_total = t.total,
        valor_sinal_total = t.sinal
    FROM (SELECT COALESCE(SUM(preco_final),0) AS total, COALESCE(SUM(valor_sinal),0) AS sinal
          FROM public.reserva_itens
          WHERE reserva_id = v_item.reserva_id AND estado <> 'cancelado') t
    WHERE r.id = v_item.reserva_id;

    UPDATE public.cobrancas c SET
        valor_total = r.valor_total,
        valor_sinal = r.valor_sinal_total
    FROM public.reservas r
    WHERE c.reserva_id = r.id AND r.id = v_item.reserva_id AND c.estado = 'pendente';

    RETURN v_regra;
END;
$$;
