-- 002_core.sql — empresas, recursos físicos, profissionais, usuários, logs e comunicação

CREATE TABLE empresas (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    nome TEXT NOT NULL,
    cnpj TEXT UNIQUE,              -- TODO: substituir placeholder pelo CNPJ real
    telefone TEXT,
    endereco TEXT,
    created_at TIMESTAMPTZ DEFAULT now()
);

CREATE TABLE tipos_recurso (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    empresa_id UUID NOT NULL REFERENCES empresas(id),
    nome TEXT NOT NULL,
    descricao TEXT,
    created_at TIMESTAMPTZ DEFAULT now(),
    UNIQUE(id, empresa_id),
    UNIQUE(empresa_id, nome)
);

CREATE TABLE recursos (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    empresa_id UUID NOT NULL REFERENCES empresas(id),
    tipo_recurso_id UUID NOT NULL REFERENCES tipos_recurso(id),
    nome TEXT NOT NULL,
    ativo BOOLEAN DEFAULT true,
    created_at TIMESTAMPTZ DEFAULT now(),
    UNIQUE(id, empresa_id),
    FOREIGN KEY (tipo_recurso_id, empresa_id) REFERENCES tipos_recurso(id, empresa_id)
);

CREATE TABLE profissionais (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    empresa_id UUID NOT NULL REFERENCES empresas(id),
    nome TEXT NOT NULL,
    foto_url TEXT,
    bio TEXT,
    ativo BOOLEAN DEFAULT true,
    created_at TIMESTAMPTZ DEFAULT now(),
    UNIQUE(id, empresa_id)
);

-- UNIQUE(id, empresa_id) permite FKs compostas de inquilino (Ricardo: cruzamento entre empresas)
CREATE TABLE usuarios_internos (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    auth_user_id UUID NOT NULL UNIQUE REFERENCES auth.users(id),
    empresa_id UUID NOT NULL REFERENCES empresas(id),
    email TEXT NOT NULL,
    nome TEXT NOT NULL,
    perfil TEXT NOT NULL CHECK (perfil IN ('admin', 'gestor', 'recepcao', 'profissional')),
    ativo BOOLEAN DEFAULT true,
    mfa_ativado BOOLEAN DEFAULT false,
    convite_por UUID REFERENCES usuarios_internos(id),
    created_at TIMESTAMPTZ DEFAULT now(),
    UNIQUE(id, empresa_id)
);

CREATE TABLE usuario_profissional (
    usuario_id UUID PRIMARY KEY REFERENCES usuarios_internos(id),
    profissional_id UUID UNIQUE REFERENCES profissionais(id)
);

-- v3.3: impede ligar usuário da empresa A a profissional da empresa B
CREATE OR REPLACE FUNCTION validar_usuario_profissional_mesma_empresa()
RETURNS TRIGGER AS $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM public.usuarios_internos u
        JOIN public.profissionais p ON p.empresa_id = u.empresa_id
        WHERE u.id = NEW.usuario_id AND p.id = NEW.profissional_id
    ) THEN
        RAISE EXCEPTION 'Usuário e profissional pertencem a empresas diferentes';
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_up_mesma_empresa
BEFORE INSERT OR UPDATE ON usuario_profissional
FOR EACH ROW EXECUTE FUNCTION validar_usuario_profissional_mesma_empresa();

CREATE TABLE log_acoes (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    empresa_id UUID NOT NULL REFERENCES empresas(id),
    tabela TEXT NOT NULL,
    registro_id UUID NOT NULL,
    acao TEXT NOT NULL CHECK (acao IN ('INSERT', 'UPDATE', 'DELETE')),
    usuario_id UUID REFERENCES usuarios_internos(id),
    perfil TEXT,
    campos_alterados JSONB,
    motivo TEXT,
    created_at TIMESTAMPTZ DEFAULT now()
);

CREATE TABLE log_acoes_sensiveis (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    empresa_id UUID NOT NULL REFERENCES empresas(id),
    tabela TEXT NOT NULL,
    registro_id UUID NOT NULL,
    acao TEXT NOT NULL,
    usuario_id UUID REFERENCES usuarios_internos(id),
    apenas_metadados JSONB,
    created_at TIMESTAMPTZ DEFAULT now()
);

CREATE TABLE templates_mensagem (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    empresa_id UUID NOT NULL REFERENCES empresas(id),
    canal TEXT NOT NULL CHECK (canal IN ('whatsapp', 'email', 'sms')),
    tipo TEXT NOT NULL,
    segmento TEXT CHECK (segmento IN ('feminino', 'masculino', 'todos')),
    assunto TEXT,
    corpo TEXT NOT NULL,
    ativo BOOLEAN DEFAULT true,
    created_at TIMESTAMPTZ DEFAULT now()
);

CREATE TABLE conversas (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    empresa_id UUID NOT NULL REFERENCES empresas(id),
    cliente_id UUID NOT NULL,
    canal TEXT NOT NULL CHECK (canal IN ('whatsapp', 'instagram', 'messenger')),
    estado TEXT NOT NULL CHECK (estado IN ('ativa', 'transbordada', 'fechada')) DEFAULT 'ativa',
    transbordada_para UUID REFERENCES usuarios_internos(id),
    motivo_transbordo TEXT,
    created_at TIMESTAMPTZ DEFAULT now(),
    UNIQUE(id, empresa_id)
);
-- FK de clientes adicionada em 006 (clientes nasce em 003 dependências circulares evitadas via ALTER)

CREATE TABLE mensagens (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    conversa_id UUID NOT NULL REFERENCES conversas(id),
    origem TEXT NOT NULL CHECK (origem IN ('cliente', 'bot', 'humano')),
    conteudo TEXT NOT NULL,
    metadata JSONB,
    created_at TIMESTAMPTZ DEFAULT now()
);

CREATE TABLE transbordos (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    conversa_id UUID NOT NULL REFERENCES conversas(id),
    empresa_id UUID NOT NULL REFERENCES empresas(id),
    motivo TEXT NOT NULL,
    resumo_conversa TEXT NOT NULL,
    ponto_trava TEXT NOT NULL,
    profissional_id UUID NOT NULL REFERENCES profissionais(id),
    atendido BOOLEAN DEFAULT false,
    created_at TIMESTAMPTZ DEFAULT now(),
    FOREIGN KEY (conversa_id, empresa_id) REFERENCES conversas(id, empresa_id),
    FOREIGN KEY (profissional_id, empresa_id) REFERENCES profissionais(id, empresa_id)
);
