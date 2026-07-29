-- 017_frontend_ready.sql (v3.4.4) — preparação do backend para o frontend público
--
-- Alterações:
--   1. Schema: foto_url em servicos; especialidades em profissionais; nova tabela
--      profissional_fotos.
--   2. Leitura pública (anon) via RLS de linha + GRANT de coluna: servicos,
--      servico_cardapios, profissionais, profissional_fotos.
--   3. RPC listar_horarios_disponiveis: pública (anon + authenticated),
--      SECURITY DEFINER, search_path=''. Devolve slots respeitando duração do
--      serviço, bloqueios/ocupações, horários de empresa/profissional, exceções
--      e a regra de "última entrada" da migração 012.
--   4. criar_pre_reserva NÃO ganha GRANT a anon (agendamento público passa pela
--      API route server-side com service_role).
--   5. Buckets storage servicos e profissionais: leitura pública, escrita
--      autenticada (validação de empresa fica na API route).
--
-- Decisões aprovadas:
--   - Cardápio é OBRIGATÓRIO: sem fallback para preço/duração do serviço base.
--   - Janela efetiva do dia é a INTERSEÇÃO dos intervalos da empresa com os da
--     profissional.
--   - Massagens/limpezas de pele já têm duracao_minutos=65 no seed; a RPC usa a
--     duração do serviço diretamente.

-- =====================================================================
-- 1. SCHEMA CHANGES
-- =====================================================================

ALTER TABLE public.servicos
ADD COLUMN IF NOT EXISTS foto_url TEXT;

ALTER TABLE public.profissionais
ADD COLUMN IF NOT EXISTS especialidades TEXT[] DEFAULT '{}';

CREATE TABLE IF NOT EXISTS public.profissional_fotos (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    profissional_id UUID NOT NULL REFERENCES public.profissionais(id),
    url TEXT NOT NULL,
    ordem INT NOT NULL DEFAULT 0,
    created_at TIMESTAMPTZ DEFAULT now()
);

-- =====================================================================
-- 2. RLS + GRANT DE COLUNA PARA ANON
-- =====================================================================

-- servicos: anon só lê linhas ativas e colunas públicas
ALTER TABLE public.servicos ENABLE ROW LEVEL SECURITY;

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_policies
        WHERE schemaname = 'public' AND tablename = 'servicos' AND policyname = 'servicos_public_read'
    ) THEN
        CREATE POLICY "servicos_public_read" ON public.servicos FOR SELECT TO anon
        USING (ativo = true);
    END IF;
END $$;

REVOKE SELECT ON public.servicos FROM anon;
GRANT SELECT (
    id, nome_tecnico, tipo_recurso_id, duracao_minutos, preco_base,
    percentual_sinal, anamnese_obrigatoria, ativo, foto_url
) ON public.servicos TO anon;

-- servico_cardapios: anon só lê linhas ativas e colunas públicas
ALTER TABLE public.servico_cardapios ENABLE ROW LEVEL SECURITY;

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_policies
        WHERE schemaname = 'public' AND tablename = 'servico_cardapios' AND policyname = 'cardapios_public_read'
    ) THEN
        CREATE POLICY "cardapios_public_read" ON public.servico_cardapios FOR SELECT TO anon
        USING (ativo = true);
    END IF;
END $$;

REVOKE SELECT ON public.servico_cardapios FROM anon;
GRANT SELECT (
    id, servico_id, cardapio, nome_comercial, descricao, preco_final, ativo
) ON public.servico_cardapios TO anon;

-- profissionais: anon só lê profissionais ativos e colunas públicas
ALTER TABLE public.profissionais ENABLE ROW LEVEL SECURITY;

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_policies
        WHERE schemaname = 'public' AND tablename = 'profissionais' AND policyname = 'profissionais_public_read'
    ) THEN
        CREATE POLICY "profissionais_public_read" ON public.profissionais FOR SELECT TO anon
        USING (ativo = true);
    END IF;
END $$;

REVOKE SELECT ON public.profissionais FROM anon;
GRANT SELECT (
    id, nome, foto_url, bio, especialidades, ativo
) ON public.profissionais TO anon;

-- profissional_fotos: leitura pública; escrita só staff da mesma empresa
ALTER TABLE public.profissional_fotos ENABLE ROW LEVEL SECURITY;

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_policies
        WHERE schemaname = 'public' AND tablename = 'profissional_fotos' AND policyname = 'prof_fotos_public_read'
    ) THEN
        CREATE POLICY "prof_fotos_public_read" ON public.profissional_fotos FOR SELECT TO anon
        USING (EXISTS (SELECT 1 FROM public.profissionais p WHERE p.id = profissional_id AND p.ativo = true));
    END IF;

    IF NOT EXISTS (
        SELECT 1 FROM pg_policies
        WHERE schemaname = 'public' AND tablename = 'profissional_fotos' AND policyname = 'prof_fotos_ler'
    ) THEN
        CREATE POLICY "prof_fotos_ler" ON public.profissional_fotos FOR SELECT TO authenticated
        USING (EXISTS (SELECT 1 FROM public.profissionais p WHERE p.id = profissional_id AND p.empresa_id = public.minha_empresa_id()));
    END IF;

    IF NOT EXISTS (
        SELECT 1 FROM pg_policies
        WHERE schemaname = 'public' AND tablename = 'profissional_fotos' AND policyname = 'prof_fotos_admin'
    ) THEN
        CREATE POLICY "prof_fotos_admin" ON public.profissional_fotos FOR ALL TO authenticated
        USING (EXISTS (SELECT 1 FROM public.profissionais p WHERE p.id = profissional_id AND p.empresa_id = public.minha_empresa_id())
               AND public.meu_perfil() IN ('admin','gestor'))
        WITH CHECK (EXISTS (SELECT 1 FROM public.profissionais p WHERE p.id = profissional_id AND p.empresa_id = public.minha_empresa_id())
                    AND public.meu_perfil() IN ('admin','gestor'));
    END IF;
END $$;

REVOKE SELECT ON public.profissional_fotos FROM anon;
GRANT SELECT (id, profissional_id, url, ordem) ON public.profissional_fotos TO anon;

GRANT SELECT, INSERT, UPDATE, DELETE ON public.profissional_fotos TO authenticated;

-- =====================================================================
-- 3. RPC listar_horarios_disponiveis
-- =====================================================================

CREATE OR REPLACE FUNCTION public.listar_horarios_disponiveis(
    p_empresa_id UUID,
    p_servico_id UUID,
    p_profissional_id UUID,
    p_data DATE,
    p_cardapio TEXT DEFAULT 'ella_studio',
    p_intervalo_minutos INT DEFAULT 30,
    p_limite_slots INT DEFAULT 96
)
RETURNS TABLE(inicio TIMESTAMPTZ, fim TIMESTAMPTZ)
LANGUAGE plpgsql
STABLE SECURITY DEFINER SET search_path = ''
AS $$
DECLARE
    v_servico RECORD;
    v_cardapio RECORD;
    v_duracao_min INT;
    v_tipo_recurso_id UUID;
    v_dow INT;
    v_emp_intervalos int4range[];
    v_prof_intervalos int4range[];
    v_intersecoes int4range[];
    v_inter_e_ajuste BOOLEAN[];
    v_emp_i int4range;
    v_prof_i int4range;
    v_inter int4range;
    v_e_ajuste BOOLEAN;
    v_ultimo_fim_dia INT;
    i INT;
    v_inicio_min INT;
    v_fim_min INT;
    v_now_min INT;
    v_slot_inicio TIMESTAMPTZ;
    v_slot_fim TIMESTAMPTZ;
    v_contador INT := 0;
BEGIN
    -- 1. Validação de inputs
    IF p_empresa_id IS NULL OR p_servico_id IS NULL OR p_profissional_id IS NULL OR p_data IS NULL THEN
        RETURN;
    END IF;
    IF p_cardapio NOT IN ('ella_studio', 'ella_men') THEN
        RETURN;
    END IF;
    IF p_intervalo_minutos <= 0 OR p_limite_slots <= 0 THEN
        RETURN;
    END IF;

    -- Guarda: não listar dias no passado
    IF p_data < (now() AT TIME ZONE 'America/Sao_Paulo')::DATE THEN
        RETURN;
    END IF;

    -- 2. Serviço ativo da empresa
    SELECT * INTO v_servico
    FROM public.servicos
    WHERE id = p_servico_id AND empresa_id = p_empresa_id AND ativo = true;
    IF NOT FOUND THEN RETURN; END IF;

    -- 3. Cardápio OBRIGATÓRIO — sem fallback para o serviço base
    SELECT * INTO v_cardapio
    FROM public.servico_cardapios
    WHERE servico_id = p_servico_id AND cardapio = p_cardapio AND ativo = true;
    IF NOT FOUND THEN RETURN; END IF;

    v_duracao_min := v_servico.duracao_minutos;
    v_tipo_recurso_id := v_servico.tipo_recurso_id;

    -- 4. Profissional habilitada, ativa e da empresa
    IF NOT EXISTS (
        SELECT 1 FROM public.profissionais p
        JOIN public.profissional_servicos ps ON ps.profissional_id = p.id
        WHERE p.id = p_profissional_id
          AND p.empresa_id = p_empresa_id
          AND p.ativo = true
          AND ps.servico_id = p_servico_id
          AND ps.empresa_id = p_empresa_id
    ) THEN
        RETURN;
    END IF;

    v_dow := EXTRACT(DOW FROM p_data)::INT;

    -- 5. Exceções de calendário (mesma ordem da criar_pre_reserva)
    -- 5.1 Folga/feriado da empresa → sem slots
    IF EXISTS (
        SELECT 1 FROM public.excecoes_calendario e
        WHERE e.empresa_id = p_empresa_id AND e.data = p_data
          AND e.profissional_id IS NULL AND e.tipo IN ('folga', 'feriado')
    ) THEN
        RETURN;
    END IF;

    -- 5.2 Folga/feriado da profissional → sem slots
    IF EXISTS (
        SELECT 1 FROM public.excecoes_calendario e
        WHERE e.empresa_id = p_empresa_id AND e.data = p_data
          AND e.profissional_id = p_profissional_id AND e.tipo IN ('folga', 'feriado')
    ) THEN
        RETURN;
    END IF;

    -- 5.3 Ajuste da profissional substitui o horário dela
    v_e_ajuste := true;
    IF EXISTS (
        SELECT 1 FROM public.excecoes_calendario e
        WHERE e.empresa_id = p_empresa_id AND e.data = p_data
          AND e.profissional_id = p_profissional_id AND e.tipo = 'ajuste'
    ) THEN
        SELECT array_agg(int4range(
            (EXTRACT(EPOCH FROM e.abertura)/60)::INT,
            (EXTRACT(EPOCH FROM e.fechamento)/60)::INT,
            '[)'
        )) INTO v_prof_intervalos
        FROM public.excecoes_calendario e
        WHERE e.empresa_id = p_empresa_id AND e.data = p_data
          AND e.profissional_id = p_profissional_id AND e.tipo = 'ajuste';

        SELECT array_agg(int4range(
            (EXTRACT(EPOCH FROM h.abertura)/60)::INT,
            (EXTRACT(EPOCH FROM h.fechamento)/60)::INT,
            '[)'
        )) INTO v_emp_intervalos
        FROM public.horarios_empresa h
        WHERE h.empresa_id = p_empresa_id AND h.dia_semana = v_dow AND h.ativo = true;

    -- 5.4 Ajuste da empresa substitui o horário da empresa
    v_e_ajuste := true;
    ELSIF EXISTS (
        SELECT 1 FROM public.excecoes_calendario e
        WHERE e.empresa_id = p_empresa_id AND e.data = p_data
          AND e.profissional_id IS NULL AND e.tipo = 'ajuste'
    ) THEN
        SELECT array_agg(int4range(
            (EXTRACT(EPOCH FROM e.abertura)/60)::INT,
            (EXTRACT(EPOCH FROM e.fechamento)/60)::INT,
            '[)'
        )) INTO v_emp_intervalos
        FROM public.excecoes_calendario e
        WHERE e.empresa_id = p_empresa_id AND e.data = p_data
          AND e.profissional_id IS NULL AND e.tipo = 'ajuste';

        SELECT array_agg(int4range(
            (EXTRACT(EPOCH FROM h.abertura)/60)::INT,
            (EXTRACT(EPOCH FROM h.fechamento)/60)::INT,
            '[)'
        )) INTO v_prof_intervalos
        FROM public.horarios_profissional h
        WHERE h.profissional_id = p_profissional_id AND h.dia_semana = v_dow AND h.ativo = true;

    -- 5.5 Horários recorrentes (padrão)
    ELSE
        v_e_ajuste := false;
        SELECT array_agg(int4range(
            (EXTRACT(EPOCH FROM h.abertura)/60)::INT,
            (EXTRACT(EPOCH FROM h.fechamento)/60)::INT,
            '[)'
        )) INTO v_emp_intervalos
        FROM public.horarios_empresa h
        WHERE h.empresa_id = p_empresa_id AND h.dia_semana = v_dow AND h.ativo = true;

        SELECT array_agg(int4range(
            (EXTRACT(EPOCH FROM h.abertura)/60)::INT,
            (EXTRACT(EPOCH FROM h.fechamento)/60)::INT,
            '[)'
        )) INTO v_prof_intervalos
        FROM public.horarios_profissional h
        WHERE h.profissional_id = p_profissional_id AND h.dia_semana = v_dow AND h.ativo = true;
    END IF;

    -- 6. Janela efetiva = INTERSEÇÃO dos intervalos empresa × profissional.
    --    v_inter_e_ajuste marca quais interseções vêm de ajuste (regra antiga:
    --    serviço tem de caber inteiro), vs. recorrentes (regra de última entrada).
    v_intersecoes := '{}'::int4range[];
    v_inter_e_ajuste := '{}'::BOOLEAN[];
    IF v_emp_intervalos IS NOT NULL THEN
        FOREACH v_emp_i IN ARRAY v_emp_intervalos
        LOOP
            IF v_prof_intervalos IS NOT NULL THEN
                FOREACH v_prof_i IN ARRAY v_prof_intervalos
                LOOP
                    IF v_emp_i && v_prof_i THEN
                        v_intersecoes := array_append(v_intersecoes, v_emp_i * v_prof_i);
                        v_inter_e_ajuste := array_append(v_inter_e_ajuste, v_e_ajuste);
                    END IF;
                END LOOP;
            END IF;
        END LOOP;
    END IF;

    IF v_intersecoes IS NULL OR v_intersecoes = '{}'::int4range[] THEN
        RETURN;
    END IF;

    -- 7. Último fim do dia entre todas as interseções (regra de última entrada)
    SELECT MAX(upper(x)) INTO v_ultimo_fim_dia FROM unnest(v_intersecoes) x;

    -- 8. Gera e filtra slots
    FOR i IN 1 .. array_length(v_intersecoes, 1)
    LOOP
        v_inter := v_intersecoes[i];
        v_e_ajuste := v_inter_e_ajuste[i];
        v_inicio_min := lower(v_inter);

        -- Descarta horários no passado se o dia for hoje
        IF p_data = (now() AT TIME ZONE 'America/Sao_Paulo')::DATE THEN
            v_now_min := (EXTRACT(EPOCH FROM (now() AT TIME ZONE 'America/Sao_Paulo')::TIME)/60)::INT;
            IF v_inicio_min < v_now_min THEN
                v_inicio_min := ((v_now_min / p_intervalo_minutos) + 1) * p_intervalo_minutos;
            END IF;
        END IF;

        LOOP
            IF v_inicio_min >= upper(v_inter) THEN
                EXIT;
            END IF;

            v_fim_min := v_inicio_min + v_duracao_min;

            -- Regra da "última entrada" (v3.4.2 / migração 012):
            --   - ajustes: serviço tem de caber inteiro;
            --   - recorrentes: fim pode passar do fechamento SÓ no último intervalo do dia.
            IF v_fim_min > upper(v_inter) AND (v_e_ajuste OR upper(v_inter) <> v_ultimo_fim_dia) THEN
                EXIT;
            END IF;

            v_slot_inicio := (p_data::TEXT || ' ' ||
                make_time(v_inicio_min / 60, v_inicio_min % 60, 0))::TIMESTAMP
                AT TIME ZONE 'America/Sao_Paulo';
            v_slot_fim := v_slot_inicio + (v_duracao_min || ' minutes')::INTERVAL;

            -- Profissional livre?
            IF NOT EXISTS (
                SELECT 1 FROM public.agenda_ocupacoes o
                WHERE o.profissional_id = p_profissional_id
                  AND o.estado = 'ativa'
                  AND o.periodo && tstzrange(v_slot_inicio, v_slot_fim, '[)')
            ) THEN
                -- Pelo menos um recurso compatível livre?
                IF EXISTS (
                    SELECT 1 FROM public.recursos r
                    WHERE r.tipo_recurso_id = v_tipo_recurso_id
                      AND r.empresa_id = p_empresa_id
                      AND r.ativo = true
                      AND NOT EXISTS (
                          SELECT 1 FROM public.agenda_ocupacoes o
                          WHERE o.recurso_id = r.id
                            AND o.estado = 'ativa'
                            AND o.periodo && tstzrange(v_slot_inicio, v_slot_fim, '[)')
                      )
                ) THEN
                    inicio := v_slot_inicio;
                    fim := v_slot_fim;
                    RETURN NEXT;
                    v_contador := v_contador + 1;
                    IF v_contador >= p_limite_slots THEN
                        RETURN;
                    END IF;
                END IF;
            END IF;

            v_inicio_min := v_inicio_min + p_intervalo_minutos;
        END LOOP;
    END LOOP;

    RETURN;
END;
$$;

-- =====================================================================
-- 4. PERMISSÕES DAS FUNÇÕES
-- =====================================================================

-- RPC pública de slots
REVOKE ALL ON FUNCTION public.listar_horarios_disponiveis(UUID, UUID, UUID, DATE, TEXT, INT, INT) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.listar_horarios_disponiveis(UUID, UUID, UUID, DATE, TEXT, INT, INT)
    TO anon, authenticated, service_role;

-- Garante que criar_pre_reserva NUNCA fica exposta a anon
REVOKE ALL ON FUNCTION public.criar_pre_reserva(UUID, UUID, JSONB, TEXT) FROM anon;
GRANT EXECUTE ON FUNCTION public.criar_pre_reserva(UUID, UUID, JSONB, TEXT) TO authenticated, service_role;

-- =====================================================================
-- 5. STORAGE
-- =====================================================================

INSERT INTO storage.buckets (id, name, public)
VALUES ('servicos', 'servicos', true), ('profissionais', 'profissionais', true)
ON CONFLICT (id) DO NOTHING;

-- Leitura pública
DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_policies
        WHERE schemaname = 'storage' AND tablename = 'objects' AND policyname = 'servicos_public_select'
    ) THEN
        CREATE POLICY "servicos_public_select" ON storage.objects FOR SELECT TO anon
        USING (bucket_id = 'servicos');
    END IF;

    IF NOT EXISTS (
        SELECT 1 FROM pg_policies
        WHERE schemaname = 'storage' AND tablename = 'objects' AND policyname = 'profissionais_public_select'
    ) THEN
        CREATE POLICY "profissionais_public_select" ON storage.objects FOR SELECT TO anon
        USING (bucket_id = 'profissionais');
    END IF;

    -- Escrita autenticada (validação de empresa fica na API route server-side)
    IF NOT EXISTS (
        SELECT 1 FROM pg_policies
        WHERE schemaname = 'storage' AND tablename = 'objects' AND policyname = 'servicos_authenticated_write'
    ) THEN
        CREATE POLICY "servicos_authenticated_write" ON storage.objects
        FOR ALL TO authenticated USING (bucket_id = 'servicos') WITH CHECK (bucket_id = 'servicos');
    END IF;

    IF NOT EXISTS (
        SELECT 1 FROM pg_policies
        WHERE schemaname = 'storage' AND tablename = 'objects' AND policyname = 'profissionais_authenticated_write'
    ) THEN
        CREATE POLICY "profissionais_authenticated_write" ON storage.objects
        FOR ALL TO authenticated USING (bucket_id = 'profissionais') WITH CHECK (bucket_id = 'profissionais');
    END IF;
END $$;
