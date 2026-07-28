-- 005_anamnesis.sql — fichas de anamnese e respostas
-- (anamnese_tokens nasce em 006 porque referencia reservas)

CREATE TABLE anamneses (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    empresa_id UUID NOT NULL REFERENCES empresas(id),
    cliente_id UUID NOT NULL REFERENCES clientes(id),
    servico_id UUID NOT NULL REFERENCES servicos(id),
    modelo_id UUID NOT NULL REFERENCES modelos_anamnese(id),
    versao_modelo INT NOT NULL,
    estado TEXT NOT NULL CHECK (estado IN ('pendente', 'liberada', 'requer_avaliacao')) DEFAULT 'pendente',
    reserva_item_id UUID,               -- FK adicionada em 006 (reserva_itens nasce lá)
    profissional_revisora_id UUID REFERENCES profissionais(id),
    data_revisao TIMESTAMPTZ,
    consentimento_lgpd BOOLEAN DEFAULT false,
    texto_consentimento_aceito TEXT,
    created_at TIMESTAMPTZ DEFAULT now(),
    updated_at TIMESTAMPTZ DEFAULT now(),
    UNIQUE(id, empresa_id),
    FOREIGN KEY (cliente_id, empresa_id) REFERENCES clientes(id, empresa_id),
    FOREIGN KEY (servico_id, empresa_id) REFERENCES servicos(id, empresa_id),
    FOREIGN KEY (modelo_id, empresa_id) REFERENCES modelos_anamnese(id, empresa_id),
    FOREIGN KEY (profissional_revisora_id, empresa_id) REFERENCES profissionais(id, empresa_id)
);

CREATE TABLE anamnese_respostas (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    anamnese_id UUID NOT NULL REFERENCES anamneses(id),
    pergunta_id UUID NOT NULL REFERENCES modelo_perguntas(id),
    resposta TEXT NOT NULL,
    created_at TIMESTAMPTZ DEFAULT now(),
    UNIQUE(anamnese_id, pergunta_id)
);

-- v3.3: resposta não pode ligar anamnese da empresa A com pergunta de modelo da empresa B
CREATE OR REPLACE FUNCTION validar_resposta_mesma_empresa()
RETURNS TRIGGER AS $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM public.anamneses a
        JOIN public.modelo_perguntas mp ON mp.id = NEW.pergunta_id
        JOIN public.modelos_anamnese m ON m.id = mp.modelo_id AND m.empresa_id = a.empresa_id
        WHERE a.id = NEW.anamnese_id
    ) THEN
        RAISE EXCEPTION 'Pergunta e anamnese pertencem a empresas diferentes';
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_resposta_mesma_empresa
BEFORE INSERT OR UPDATE ON anamnese_respostas
FOR EACH ROW EXECUTE FUNCTION validar_resposta_mesma_empresa();

CREATE OR REPLACE FUNCTION set_updated_at()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at := now();
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_anamneses_updated_at BEFORE UPDATE ON anamneses
FOR EACH ROW EXECUTE FUNCTION set_updated_at();
