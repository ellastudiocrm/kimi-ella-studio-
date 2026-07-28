-- 003_catalog.sql — clientes, anamnese (modelos), serviços, cardápios, habilitações, pacotes (modelos)

CREATE TABLE clientes (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    empresa_id UUID NOT NULL REFERENCES empresas(id),
    nome TEXT NOT NULL,
    telefone_normalizado TEXT NOT NULL,
    email TEXT,
    data_nascimento DATE,
    cidade TEXT,
    como_conheceu TEXT,
    segmento_preferido TEXT CHECK (segmento_preferido IN ('feminino', 'masculino', 'nao_definido')) DEFAULT 'nao_definido',
    created_at TIMESTAMPTZ DEFAULT now(),
    UNIQUE(id, empresa_id),
    UNIQUE(empresa_id, telefone_normalizado)
);

-- FK adiada de 002 (conversas → clientes)
ALTER TABLE conversas
ADD CONSTRAINT fk_conversas_cliente_empresa
FOREIGN KEY (cliente_id, empresa_id) REFERENCES clientes(id, empresa_id);

CREATE TABLE modelos_anamnese (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    empresa_id UUID NOT NULL REFERENCES empresas(id),
    nome TEXT NOT NULL,
    versao INT NOT NULL DEFAULT 1,
    ativo BOOLEAN DEFAULT true,
    created_at TIMESTAMPTZ DEFAULT now(),
    UNIQUE(id, empresa_id)
);

CREATE TABLE modelo_perguntas (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    modelo_id UUID NOT NULL REFERENCES modelos_anamnese(id),
    ordem INT NOT NULL,
    pergunta TEXT NOT NULL,
    tipo_resposta TEXT NOT NULL CHECK (tipo_resposta IN ('sim_nao', 'texto', 'multipla_escolha', 'numero')),
    opcoes JSONB,
    obrigatoria BOOLEAN DEFAULT true,
    operador TEXT CHECK (operador IN ('igual', 'diferente', 'contem', 'maior_que', 'menor_que')),
    valor_disparador TEXT,
    resultado_estado TEXT CHECK (resultado_estado IN ('liberada', 'requer_avaliacao')),
    UNIQUE(modelo_id, ordem)
);

CREATE TABLE servicos (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    empresa_id UUID NOT NULL REFERENCES empresas(id),
    nome_tecnico TEXT NOT NULL,
    tipo_recurso_id UUID NOT NULL REFERENCES tipos_recurso(id),
    duracao_minutos INT NOT NULL CHECK (duracao_minutos > 0),
    preco_base DECIMAL(10,2) NOT NULL CHECK (preco_base >= 0),
    percentual_sinal INT NOT NULL DEFAULT 30 CHECK (percentual_sinal BETWEEN 0 AND 100),
    anamnese_obrigatoria BOOLEAN DEFAULT true,
    modelo_anamnese_id UUID REFERENCES modelos_anamnese(id),
    ativo BOOLEAN DEFAULT true,
    created_at TIMESTAMPTZ DEFAULT now(),
    UNIQUE(id, empresa_id),
    FOREIGN KEY (tipo_recurso_id, empresa_id) REFERENCES tipos_recurso(id, empresa_id),
    -- v3.3: modelo de anamnese tem de ser da mesma empresa
    FOREIGN KEY (modelo_anamnese_id, empresa_id) REFERENCES modelos_anamnese(id, empresa_id),
    UNIQUE(empresa_id, nome_tecnico)
);

CREATE TABLE servico_cardapios (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    servico_id UUID NOT NULL REFERENCES servicos(id),
    cardapio TEXT NOT NULL CHECK (cardapio IN ('feminino', 'masculino')),
    nome_comercial TEXT NOT NULL,
    descricao TEXT,
    preco_final DECIMAL(10,2),
    ativo BOOLEAN DEFAULT true,
    UNIQUE(servico_id, cardapio)
);

-- v3.3: empresa_id explícito — impedia-se habilitação cruzada entre empresas
CREATE TABLE profissional_servicos (
    profissional_id UUID NOT NULL REFERENCES profissionais(id),
    servico_id UUID NOT NULL REFERENCES servicos(id),
    empresa_id UUID NOT NULL REFERENCES empresas(id),
    PRIMARY KEY (profissional_id, servico_id),
    FOREIGN KEY (profissional_id, empresa_id) REFERENCES profissionais(id, empresa_id),
    FOREIGN KEY (servico_id, empresa_id) REFERENCES servicos(id, empresa_id)
);

CREATE TABLE modelos_pacote (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    empresa_id UUID NOT NULL REFERENCES empresas(id),
    nome TEXT NOT NULL,
    descricao TEXT,
    preco DECIMAL(10,2) NOT NULL,
    validade_dias INT NOT NULL,
    ativo BOOLEAN DEFAULT true,
    created_at TIMESTAMPTZ DEFAULT now(),
    UNIQUE(id, empresa_id)
);

-- v3.3: empresa_id explícito + FKs compostas
CREATE TABLE modelo_pacote_itens (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    pacote_id UUID NOT NULL REFERENCES modelos_pacote(id),
    servico_id UUID NOT NULL REFERENCES servicos(id),
    empresa_id UUID NOT NULL REFERENCES empresas(id),
    quantidade INT NOT NULL CHECK (quantidade > 0),
    UNIQUE(pacote_id, servico_id),
    FOREIGN KEY (pacote_id, empresa_id) REFERENCES modelos_pacote(id, empresa_id),
    FOREIGN KEY (servico_id, empresa_id) REFERENCES servicos(id, empresa_id)
);
