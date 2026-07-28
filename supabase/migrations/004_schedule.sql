-- 004_schedule.sql — horários multi-intervalo (almoço!), exceções, ocupações e bloqueios

-- v3.3 (Ricardo #7): vários intervalos por dia — 09:00–12:30 e 13:30–17:00.
-- O UNIQUE(profissional_id, dia_semana) foi substituído por EXCLUDE de sobreposição.
CREATE TABLE horarios_empresa (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    empresa_id UUID NOT NULL REFERENCES empresas(id),
    dia_semana INT NOT NULL CHECK (dia_semana BETWEEN 0 AND 6), -- 0=domingo
    abertura TIME NOT NULL,
    fechamento TIME NOT NULL,
    ativo BOOLEAN DEFAULT true,
    intervalo INT4RANGE GENERATED ALWAYS AS (
        int4range((EXTRACT(EPOCH FROM abertura)/60)::INT, (EXTRACT(EPOCH FROM fechamento)/60)::INT, '[)')
    ) STORED,
    CHECK (abertura < fechamento)
);

ALTER TABLE horarios_empresa
ADD CONSTRAINT excl_hor_empresa_overlap
EXCLUDE USING gist (empresa_id WITH =, dia_semana WITH =, intervalo WITH &&)
WHERE (ativo = true);

CREATE TABLE horarios_profissional (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    profissional_id UUID NOT NULL REFERENCES profissionais(id),
    dia_semana INT NOT NULL CHECK (dia_semana BETWEEN 0 AND 6),
    abertura TIME NOT NULL,
    fechamento TIME NOT NULL,
    ativo BOOLEAN DEFAULT true,
    intervalo INT4RANGE GENERATED ALWAYS AS (
        int4range((EXTRACT(EPOCH FROM abertura)/60)::INT, (EXTRACT(EPOCH FROM fechamento)/60)::INT, '[)')
    ) STORED,
    CHECK (abertura < fechamento)
);

ALTER TABLE horarios_profissional
ADD CONSTRAINT excl_hor_prof_overlap
EXCLUDE USING gist (profissional_id WITH =, dia_semana WITH =, intervalo WITH &&)
WHERE (ativo = true);

CREATE TABLE excecoes_calendario (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    empresa_id UUID NOT NULL REFERENCES empresas(id),
    profissional_id UUID REFERENCES profissionais(id), -- NULL = toda a empresa
    data DATE NOT NULL,
    tipo TEXT NOT NULL CHECK (tipo IN ('folga', 'feriado', 'ajuste')),
    abertura TIME,
    fechamento TIME,
    motivo TEXT,
    FOREIGN KEY (profissional_id, empresa_id) REFERENCES profissionais(id, empresa_id)
);

CREATE UNIQUE INDEX uq_excecao_profissional_data
    ON excecoes_calendario (profissional_id, data) WHERE profissional_id IS NOT NULL;
CREATE UNIQUE INDEX uq_excecao_empresa_data
    ON excecoes_calendario (empresa_id, data) WHERE profissional_id IS NULL;

-- Ocupações. v3.3 (Ricardo #11): reserva_item_id identifica qual serviço ocupa o slot
-- (FK adicionada em 006, quando reserva_itens já existe)
CREATE TABLE agenda_ocupacoes (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    empresa_id UUID NOT NULL REFERENCES empresas(id),
    tipo_ocupacao TEXT NOT NULL CHECK (tipo_ocupacao IN ('profissional', 'recurso')),
    profissional_id UUID REFERENCES profissionais(id),
    recurso_id UUID REFERENCES recursos(id),
    reserva_item_id UUID,                     -- NOVO v3.3
    inicio TIMESTAMPTZ NOT NULL,
    fim TIMESTAMPTZ NOT NULL,
    periodo TSTZRANGE GENERATED ALWAYS AS (tstzrange(inicio, fim, '[)')) STORED,
    origem TEXT NOT NULL CHECK (origem IN ('reserva', 'bloqueio', 'pre_reserva')),
    origem_id UUID,
    estado TEXT NOT NULL CHECK (estado IN ('ativa', 'cancelada', 'expirada')) DEFAULT 'ativa',
    expires_at TIMESTAMPTZ,
    created_at TIMESTAMPTZ DEFAULT now(),
    CHECK (inicio < fim),
    CHECK (
        (tipo_ocupacao = 'profissional' AND profissional_id IS NOT NULL AND recurso_id IS NULL) OR
        (tipo_ocupacao = 'recurso' AND recurso_id IS NOT NULL AND profissional_id IS NULL)
    ),
    FOREIGN KEY (profissional_id, empresa_id) REFERENCES profissionais(id, empresa_id),
    FOREIGN KEY (recurso_id, empresa_id) REFERENCES recursos(id, empresa_id)
);

CREATE INDEX idx_ocupacoes_empresa ON agenda_ocupacoes(empresa_id);
CREATE INDEX idx_ocupacoes_origem ON agenda_ocupacoes(origem, origem_id);
CREATE INDEX idx_ocupacoes_item ON agenda_ocupacoes(reserva_item_id);

ALTER TABLE agenda_ocupacoes
ADD CONSTRAINT exclude_profissional_conflito
EXCLUDE USING gist (profissional_id WITH =, periodo WITH &&)
WHERE (estado = 'ativa' AND profissional_id IS NOT NULL);

ALTER TABLE agenda_ocupacoes
ADD CONSTRAINT exclude_recurso_conflito
EXCLUDE USING gist (recurso_id WITH =, periodo WITH &&)
WHERE (estado = 'ativa' AND recurso_id IS NOT NULL);

-- Bloqueios. v3.3: triggers SECURITY DEFINER — sobrevivem ao REVOKE de UPDATE(estado) (007)
CREATE TABLE bloqueios (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    empresa_id UUID NOT NULL REFERENCES empresas(id),
    profissional_id UUID NOT NULL REFERENCES profissionais(id),
    recurso_id UUID REFERENCES recursos(id),
    inicio TIMESTAMPTZ NOT NULL,
    fim TIMESTAMPTZ NOT NULL,
    motivo TEXT NOT NULL,
    tipo TEXT NOT NULL CHECK (tipo IN ('almoco', 'folga', 'imprevisto')),
    created_at TIMESTAMPTZ DEFAULT now(),
    CHECK (inicio < fim),
    FOREIGN KEY (profissional_id, empresa_id) REFERENCES profissionais(id, empresa_id),
    FOREIGN KEY (recurso_id, empresa_id) REFERENCES recursos(id, empresa_id)
);

CREATE OR REPLACE FUNCTION sincronizar_bloqueio_ocupacoes()
RETURNS TRIGGER
SECURITY DEFINER SET search_path = ''
AS $$
BEGIN
    INSERT INTO public.agenda_ocupacoes (empresa_id, tipo_ocupacao, profissional_id, inicio, fim, origem, origem_id, estado)
    VALUES (NEW.empresa_id, 'profissional', NEW.profissional_id, NEW.inicio, NEW.fim, 'bloqueio', NEW.id, 'ativa');

    IF NEW.recurso_id IS NOT NULL THEN
        INSERT INTO public.agenda_ocupacoes (empresa_id, tipo_ocupacao, recurso_id, inicio, fim, origem, origem_id, estado)
        VALUES (NEW.empresa_id, 'recurso', NEW.recurso_id, NEW.inicio, NEW.fim, 'bloqueio', NEW.id, 'ativa');
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trigger_bloqueio_cria_ocupacoes
AFTER INSERT ON bloqueios
FOR EACH ROW EXECUTE FUNCTION sincronizar_bloqueio_ocupacoes();

CREATE OR REPLACE FUNCTION atualizar_bloqueio_ocupacoes()
RETURNS TRIGGER
SECURITY DEFINER SET search_path = ''
AS $$
BEGIN
    -- Mudança de profissional: cancela a ocupação antiga e cria a nova (Carlos #10)
    IF OLD.profissional_id IS DISTINCT FROM NEW.profissional_id THEN
        UPDATE public.agenda_ocupacoes SET estado = 'cancelada'
        WHERE origem = 'bloqueio' AND origem_id = NEW.id
          AND tipo_ocupacao = 'profissional' AND estado = 'ativa';
        INSERT INTO public.agenda_ocupacoes (empresa_id, tipo_ocupacao, profissional_id, inicio, fim, origem, origem_id, estado)
        VALUES (NEW.empresa_id, 'profissional', NEW.profissional_id, NEW.inicio, NEW.fim, 'bloqueio', NEW.id, 'ativa');
    ELSE
        UPDATE public.agenda_ocupacoes
        SET inicio = NEW.inicio, fim = NEW.fim
        WHERE origem = 'bloqueio' AND origem_id = NEW.id
          AND tipo_ocupacao = 'profissional' AND estado = 'ativa';
    END IF;

    IF OLD.recurso_id IS NOT NULL AND NEW.recurso_id IS NULL THEN
        UPDATE public.agenda_ocupacoes SET estado = 'cancelada'
        WHERE origem = 'bloqueio' AND origem_id = NEW.id
          AND tipo_ocupacao = 'recurso' AND estado = 'ativa';
    ELSIF OLD.recurso_id IS NULL AND NEW.recurso_id IS NOT NULL THEN
        INSERT INTO public.agenda_ocupacoes (empresa_id, tipo_ocupacao, recurso_id, inicio, fim, origem, origem_id, estado)
        VALUES (NEW.empresa_id, 'recurso', NEW.recurso_id, NEW.inicio, NEW.fim, 'bloqueio', NEW.id, 'ativa');
    ELSIF OLD.recurso_id IS NOT NULL AND NEW.recurso_id IS NOT NULL THEN
        UPDATE public.agenda_ocupacoes
        SET inicio = NEW.inicio, fim = NEW.fim, recurso_id = NEW.recurso_id
        WHERE origem = 'bloqueio' AND origem_id = NEW.id
          AND tipo_ocupacao = 'recurso' AND estado = 'ativa';
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trigger_bloqueio_atualiza_ocupacoes
AFTER UPDATE ON bloqueios
FOR EACH ROW EXECUTE FUNCTION atualizar_bloqueio_ocupacoes();

CREATE OR REPLACE FUNCTION remover_bloqueio_ocupacoes()
RETURNS TRIGGER
SECURITY DEFINER SET search_path = ''
AS $$
BEGIN
    UPDATE public.agenda_ocupacoes SET estado = 'cancelada'
    WHERE origem = 'bloqueio' AND origem_id = OLD.id AND estado = 'ativa';
    RETURN OLD;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trigger_bloqueio_remove_ocupacoes
AFTER DELETE ON bloqueios
FOR EACH ROW EXECUTE FUNCTION remover_bloqueio_ocupacoes();
