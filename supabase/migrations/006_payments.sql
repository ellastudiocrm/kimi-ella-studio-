-- 006_payments.sql — reservas, itens, pagamentos, créditos, pacotes, cartões, tokens, infra

-- v3.3 (Ricardo #3): idempotência POR EMPRESA — a mesma chave nunca devolve reserva de outra empresa
CREATE TABLE reservas (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    empresa_id UUID NOT NULL REFERENCES empresas(id),
    cliente_id UUID NOT NULL REFERENCES clientes(id),
    -- v3.4: 'expirada' — pré-reserva cujo prazo de 30 min passou sem pagamento (Ricardo/Carlos)
    estado TEXT NOT NULL CHECK (estado IN ('pre_reserva', 'expirada', 'pagamento_em_revisao', 'confirmada', 'realizada', 'cancelada', 'no_show')) DEFAULT 'pre_reserva',
    valor_total DECIMAL(10,2),
    percentual_sinal INT NOT NULL DEFAULT 30,
    valor_sinal_total DECIMAL(10,2),
    idempotencia_key TEXT NOT NULL,
    created_at TIMESTAMPTZ DEFAULT now(),
    updated_at TIMESTAMPTZ DEFAULT now(),
    UNIQUE(id, empresa_id),
    UNIQUE(empresa_id, idempotencia_key),
    FOREIGN KEY (cliente_id, empresa_id) REFERENCES clientes(id, empresa_id)
);

CREATE TRIGGER trg_reservas_updated_at BEFORE UPDATE ON reservas
FOR EACH ROW EXECUTE FUNCTION set_updated_at();

CREATE TABLE reserva_itens (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    reserva_id UUID NOT NULL REFERENCES reservas(id),
    empresa_id UUID NOT NULL REFERENCES empresas(id),
    nome_servico TEXT NOT NULL,
    preco_base_utilizado DECIMAL(10,2) NOT NULL,
    preco_final DECIMAL(10,2),
    duracao_reservada INT NOT NULL CHECK (duracao_reservada > 0),
    percentual_sinal INT NOT NULL DEFAULT 30,
    valor_sinal DECIMAL(10,2) NOT NULL,
    servico_id UUID REFERENCES servicos(id),
    profissional_id UUID NOT NULL REFERENCES profissionais(id),
    recurso_id UUID NOT NULL REFERENCES recursos(id),
    inicio TIMESTAMPTZ NOT NULL,
    fim TIMESTAMPTZ NOT NULL,
    estado TEXT NOT NULL CHECK (estado IN ('pendente', 'confirmado', 'realizado', 'cancelado')) DEFAULT 'pendente',
    observacoes TEXT,
    created_at TIMESTAMPTZ DEFAULT now(),
    CHECK (inicio < fim),
    FOREIGN KEY (reserva_id, empresa_id) REFERENCES reservas(id, empresa_id),
    FOREIGN KEY (servico_id, empresa_id) REFERENCES servicos(id, empresa_id),
    FOREIGN KEY (profissional_id, empresa_id) REFERENCES profissionais(id, empresa_id),
    FOREIGN KEY (recurso_id, empresa_id) REFERENCES recursos(id, empresa_id)
);

-- Validação recurso×serviço via trigger (subquery em CHECK não existe em PostgreSQL)
CREATE OR REPLACE FUNCTION validar_recurso_compativel()
RETURNS TRIGGER AS $$
BEGIN
    IF NEW.servico_id IS NOT NULL AND NOT EXISTS (
        SELECT 1 FROM public.servicos s
        JOIN public.recursos r ON r.id = NEW.recurso_id
        WHERE s.id = NEW.servico_id AND r.tipo_recurso_id = s.tipo_recurso_id
    ) THEN
        RAISE EXCEPTION 'Recurso % não é do tipo exigido pelo serviço %', NEW.recurso_id, NEW.servico_id;
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_valida_recurso_compativel
BEFORE INSERT OR UPDATE ON reserva_itens
FOR EACH ROW EXECUTE FUNCTION validar_recurso_compativel();

-- v3.3 (Ricardo #11): FK da ocupação → item da reserva (cancelamento individual)
ALTER TABLE agenda_ocupacoes
ADD CONSTRAINT fk_ocupacao_reserva_item
FOREIGN KEY (reserva_item_id) REFERENCES reserva_itens(id);

-- v3.4 (Carlos #11): a ficha de anamnese sabe QUAL o item de reserva que a originou
ALTER TABLE anamneses
ADD CONSTRAINT fk_anamnese_reserva_item
FOREIGN KEY (reserva_item_id) REFERENCES reserva_itens(id);

-- Máquina de estados enforced por trigger
CREATE OR REPLACE FUNCTION validar_transicao_reserva()
RETURNS TRIGGER AS $$
BEGIN
    IF OLD.estado IS NOT DISTINCT FROM NEW.estado THEN RETURN NEW; END IF;
    IF NOT (
        (OLD.estado = 'pre_reserva' AND NEW.estado IN ('confirmada', 'cancelada', 'pagamento_em_revisao', 'expirada')) OR
        (OLD.estado = 'expirada' AND NEW.estado IN ('pagamento_em_revisao', 'cancelada')) OR
        (OLD.estado = 'pagamento_em_revisao' AND NEW.estado IN ('confirmada', 'cancelada')) OR
        (OLD.estado = 'confirmada' AND NEW.estado IN ('realizada', 'cancelada', 'no_show'))
    ) THEN
        RAISE EXCEPTION 'Transição inválida em reservas: % → %', OLD.estado, NEW.estado;
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_reservas_estado BEFORE UPDATE OF estado ON reservas
FOR EACH ROW EXECUTE FUNCTION validar_transicao_reserva();

CREATE OR REPLACE FUNCTION validar_transicao_reserva_item()
RETURNS TRIGGER AS $$
BEGIN
    IF OLD.estado IS NOT DISTINCT FROM NEW.estado THEN RETURN NEW; END IF;
    IF NOT (
        (OLD.estado = 'pendente' AND NEW.estado IN ('confirmado', 'cancelado')) OR
        (OLD.estado = 'confirmado' AND NEW.estado IN ('realizado', 'cancelado')) OR
        -- v3.4.1: resolver_revisao('confirmar') revive itens cancelados pelo cron
        (OLD.estado = 'cancelado' AND NEW.estado = 'confirmado')
    ) THEN
        RAISE EXCEPTION 'Transição inválida em reserva_itens: % → %', OLD.estado, NEW.estado;
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_reserva_itens_estado BEFORE UPDATE OF estado ON reserva_itens
FOR EACH ROW EXECUTE FUNCTION validar_transicao_reserva_item();

CREATE OR REPLACE FUNCTION validar_transicao_ocupacao()
RETURNS TRIGGER AS $$
BEGIN
    IF OLD.estado IS NOT DISTINCT FROM NEW.estado THEN RETURN NEW; END IF;
    IF NOT (OLD.estado = 'ativa' AND NEW.estado IN ('cancelada', 'expirada')) THEN
        RAISE EXCEPTION 'Transição inválida em agenda_ocupacoes: % → %', OLD.estado, NEW.estado;
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_ocupacoes_estado BEFORE UPDATE OF estado ON agenda_ocupacoes
FOR EACH ROW EXECUTE FUNCTION validar_transicao_ocupacao();

CREATE TABLE cobrancas (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    reserva_id UUID NOT NULL REFERENCES reservas(id),
    empresa_id UUID NOT NULL REFERENCES empresas(id),
    valor_total DECIMAL(10,2) NOT NULL CHECK (valor_total >= 0),
    percentual_sinal INT NOT NULL DEFAULT 30,
    valor_sinal DECIMAL(10,2) NOT NULL CHECK (valor_sinal >= 0),
    UNIQUE(reserva_id),
    estado TEXT NOT NULL CHECK (estado IN ('pendente', 'sinal_pago', 'total_pago', 'cancelada')) DEFAULT 'pendente',
    created_at TIMESTAMPTZ DEFAULT now(),
    UNIQUE(id, empresa_id),
    FOREIGN KEY (reserva_id, empresa_id) REFERENCES reservas(id, empresa_id)
);

CREATE TABLE transacoes (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    cobranca_id UUID NOT NULL REFERENCES cobrancas(id),
    empresa_id UUID NOT NULL REFERENCES empresas(id),
    mp_idempotency_key TEXT NOT NULL UNIQUE,
    mp_transaction_id TEXT UNIQUE,
    valor DECIMAL(10,2) NOT NULL CHECK (valor > 0),
    meio TEXT NOT NULL CHECK (meio IN ('pix', 'dinheiro', 'cartao_debito', 'cartao_credito')),
    finalidade TEXT NOT NULL CHECK (finalidade IN ('sinal', 'saldo', 'pagamento_total', 'estorno')),
    estado TEXT NOT NULL CHECK (estado IN ('pendente', 'pago', 'expirado', 'estornado')) DEFAULT 'pendente',
    payload_webhook JSONB,
    created_at TIMESTAMPTZ DEFAULT now(),
    FOREIGN KEY (cobranca_id, empresa_id) REFERENCES cobrancas(id, empresa_id)
);

CREATE UNIQUE INDEX idx_transacao_sinal_pago_unico
ON transacoes (cobranca_id)
WHERE finalidade = 'sinal' AND estado = 'pago';

CREATE TABLE eventos_pagamento (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    transacao_id UUID REFERENCES transacoes(id),
    mp_event_id TEXT NOT NULL UNIQUE,
    tipo_evento TEXT NOT NULL,
    payload JSONB NOT NULL,
    processado BOOLEAN DEFAULT false,
    created_at TIMESTAMPTZ DEFAULT now()
);

CREATE TABLE alocacoes_pagamento (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    transacao_id UUID NOT NULL REFERENCES transacoes(id),
    reserva_item_id UUID NOT NULL REFERENCES reserva_itens(id),
    valor_alocado DECIMAL(10,2) NOT NULL CHECK (valor_alocado > 0)
);

-- v3.3: alocação não pode cruzar empresas
CREATE OR REPLACE FUNCTION validar_alocacao_mesma_empresa()
RETURNS TRIGGER AS $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM public.transacoes t
        JOIN public.reserva_itens ri ON ri.empresa_id = t.empresa_id
        WHERE t.id = NEW.transacao_id AND ri.id = NEW.reserva_item_id
    ) THEN
        RAISE EXCEPTION 'Transação e item pertencem a empresas diferentes';
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_alocacao_mesma_empresa
BEFORE INSERT OR UPDATE ON alocacoes_pagamento
FOR EACH ROW EXECUTE FUNCTION validar_alocacao_mesma_empresa();

-- Créditos
CREATE TABLE contas_creditos (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    cliente_id UUID NOT NULL REFERENCES clientes(id),
    empresa_id UUID NOT NULL REFERENCES empresas(id),
    tipo TEXT NOT NULL CHECK (tipo IN ('pago', 'promocional')),
    created_at TIMESTAMPTZ DEFAULT now(),
    UNIQUE(id, empresa_id),
    UNIQUE(cliente_id, empresa_id, tipo),
    FOREIGN KEY (cliente_id, empresa_id) REFERENCES clientes(id, empresa_id)
);

CREATE TABLE lancamentos_creditos (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    conta_id UUID NOT NULL REFERENCES contas_creditos(id),
    tipo_lancamento TEXT NOT NULL CHECK (tipo_lancamento IN (
        'emissao_pacote', 'credito_cancelamento', 'beneficio_promocional',
        'consumo', 'expiracao', 'ajuste_admin', 'estorno'
    )),
    valor DECIMAL(10,2) NOT NULL,
    saldo_apos DECIMAL(10,2) NOT NULL,
    idempotencia_key TEXT NOT NULL UNIQUE,
    origem_id UUID,
    origem_tipo TEXT,
    validade DATE,
    observacoes TEXT,
    created_at TIMESTAMPTZ DEFAULT now()
);

CREATE TABLE credito_servicos_permitidos (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    lancamento_id UUID NOT NULL REFERENCES lancamentos_creditos(id),
    servico_id UUID NOT NULL REFERENCES servicos(id),
    UNIQUE(lancamento_id, servico_id)
);

-- v3.3: serviço permitido tem de ser da empresa da conta de crédito
CREATE OR REPLACE FUNCTION validar_credito_servico_mesma_empresa()
RETURNS TRIGGER AS $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM public.lancamentos_creditos l
        JOIN public.contas_creditos c ON c.id = l.conta_id
        JOIN public.servicos s ON s.empresa_id = c.empresa_id
        WHERE l.id = NEW.lancamento_id AND s.id = NEW.servico_id
    ) THEN
        RAISE EXCEPTION 'Serviço e lançamento pertencem a empresas diferentes';
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_credito_servico_mesma_empresa
BEFORE INSERT OR UPDATE ON credito_servicos_permitidos
FOR EACH ROW EXECUTE FUNCTION validar_credito_servico_mesma_empresa();

-- Pacotes (compras — modelos estão em 003)
CREATE TABLE compras_pacote (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    empresa_id UUID NOT NULL REFERENCES empresas(id),
    cliente_id UUID NOT NULL REFERENCES clientes(id),
    modelo_id UUID NOT NULL REFERENCES modelos_pacote(id),
    preco_pago DECIMAL(10,2) NOT NULL,
    validade DATE NOT NULL,
    estado TEXT NOT NULL CHECK (estado IN ('ativo', 'expirado', 'cancelado')) DEFAULT 'ativo',
    created_at TIMESTAMPTZ DEFAULT now(),
    UNIQUE(id, empresa_id),
    FOREIGN KEY (cliente_id, empresa_id) REFERENCES clientes(id, empresa_id),
    FOREIGN KEY (modelo_id, empresa_id) REFERENCES modelos_pacote(id, empresa_id)
);

CREATE TABLE compra_pacote_itens (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    compra_id UUID NOT NULL REFERENCES compras_pacote(id),
    servico_id UUID NOT NULL REFERENCES servicos(id),
    nome_servico TEXT NOT NULL,
    quantidade_total INT NOT NULL,
    quantidade_utilizada INT NOT NULL DEFAULT 0,
    UNIQUE(compra_id, servico_id)
);

CREATE OR REPLACE FUNCTION validar_compra_item_mesma_empresa()
RETURNS TRIGGER AS $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM public.compras_pacote cp
        JOIN public.servicos s ON s.empresa_id = cp.empresa_id
        WHERE cp.id = NEW.compra_id AND s.id = NEW.servico_id
    ) THEN
        RAISE EXCEPTION 'Serviço e compra pertencem a empresas diferentes';
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_compra_item_mesma_empresa
BEFORE INSERT OR UPDATE ON compra_pacote_itens
FOR EACH ROW EXECUTE FUNCTION validar_compra_item_mesma_empresa();

CREATE TABLE pacote_utilizacoes (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    compra_id UUID NOT NULL REFERENCES compras_pacote(id),
    reserva_item_id UUID REFERENCES reserva_itens(id),
    servico_id UUID NOT NULL REFERENCES servicos(id),
    created_at TIMESTAMPTZ DEFAULT now()
);

CREATE OR REPLACE FUNCTION validar_utilizacao_mesma_empresa()
RETURNS TRIGGER AS $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM public.compras_pacote cp
        JOIN public.servicos s ON s.empresa_id = cp.empresa_id
        WHERE cp.id = NEW.compra_id AND s.id = NEW.servico_id
    ) THEN
        RAISE EXCEPTION 'Serviço e compra pertencem a empresas diferentes';
    END IF;
    IF NEW.reserva_item_id IS NOT NULL AND NOT EXISTS (
        SELECT 1 FROM public.compras_pacote cp
        JOIN public.reserva_itens ri ON ri.empresa_id = cp.empresa_id
        WHERE cp.id = NEW.compra_id AND ri.id = NEW.reserva_item_id
    ) THEN
        RAISE EXCEPTION 'Item de reserva e compra pertencem a empresas diferentes';
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_utilizacao_mesma_empresa
BEFORE INSERT OR UPDATE ON pacote_utilizacoes
FOR EACH ROW EXECUTE FUNCTION validar_utilizacao_mesma_empresa();

-- Cartões-presente (v3.3: FKs compostas de comprador/beneficiário)
CREATE TABLE cartoes_presente (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    empresa_id UUID NOT NULL REFERENCES empresas(id),
    codigo TEXT NOT NULL UNIQUE,
    valor_original DECIMAL(10,2) NOT NULL,
    saldo DECIMAL(10,2) NOT NULL,
    comprador_id UUID REFERENCES clientes(id),
    beneficiario_id UUID REFERENCES clientes(id),
    validade DATE NOT NULL,
    estado TEXT NOT NULL CHECK (estado IN ('ativo', 'utilizado', 'expirado', 'cancelado')) DEFAULT 'ativo',
    created_at TIMESTAMPTZ DEFAULT now(),
    FOREIGN KEY (comprador_id, empresa_id) REFERENCES clientes(id, empresa_id),
    FOREIGN KEY (beneficiario_id, empresa_id) REFERENCES clientes(id, empresa_id)
);

CREATE TABLE cartao_presente_lancamentos (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    cartao_id UUID NOT NULL REFERENCES cartoes_presente(id),
    tipo TEXT NOT NULL CHECK (tipo IN ('compra', 'utilizacao', 'expiracao', 'cancelamento')),
    valor DECIMAL(10,2) NOT NULL,
    saldo_apos DECIMAL(10,2) NOT NULL,
    reserva_id UUID REFERENCES reservas(id),
    created_at TIMESTAMPTZ DEFAULT now()
);

-- Revisões de cancelamento (v3.3: decidido_por composto — sem cruzamento)
CREATE TABLE revisoes_cancelamento (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    reserva_id UUID NOT NULL REFERENCES reservas(id),
    reserva_item_id UUID REFERENCES reserva_itens(id),
    empresa_id UUID NOT NULL REFERENCES empresas(id),
    valor_sinal DECIMAL(10,2) NOT NULL,
    -- v3.4: 'pagamento_atrasado' — sinal pago depois do prazo (Carlos #4); decisão 'confirmar' reagenda o slot
    regra_aplicada TEXT NOT NULL CHECK (regra_aplicada IN ('credito_automatico', 'perda_automatica', 'pagamento_atrasado')),
    decisao_final TEXT CHECK (decisao_final IN ('credito', 'estorno', 'perdido', 'confirmar')),
    decidido_por UUID REFERENCES usuarios_internos(id),
    motivo_decisao TEXT,
    created_at TIMESTAMPTZ DEFAULT now(),
    FOREIGN KEY (reserva_id, empresa_id) REFERENCES reservas(id, empresa_id),
    FOREIGN KEY (decidido_por, empresa_id) REFERENCES usuarios_internos(id, empresa_id)
);

-- Uma única revisão ABERTA por reserva e por item
CREATE UNIQUE INDEX uq_revisao_aberta_reserva ON revisoes_cancelamento (reserva_id)
WHERE decisao_final IS NULL AND reserva_item_id IS NULL;
CREATE UNIQUE INDEX uq_revisao_aberta_item ON revisoes_cancelamento (reserva_item_id)
WHERE decisao_final IS NULL AND reserva_item_id IS NOT NULL;

-- Tokens de anamnese (aqui porque referenciam reservas)
CREATE TABLE anamnese_tokens (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    empresa_id UUID NOT NULL REFERENCES empresas(id),
    token_hash TEXT NOT NULL UNIQUE,
    anamnese_id UUID NOT NULL REFERENCES anamneses(id),
    cliente_id UUID NOT NULL REFERENCES clientes(id),
    reserva_id UUID REFERENCES reservas(id),
    usado BOOLEAN DEFAULT false,
    usado_em TIMESTAMPTZ,
    expira_em TIMESTAMPTZ NOT NULL,
    created_at TIMESTAMPTZ DEFAULT now(),
    FOREIGN KEY (anamnese_id, empresa_id) REFERENCES anamneses(id, empresa_id),
    FOREIGN KEY (cliente_id, empresa_id) REFERENCES clientes(id, empresa_id),
    FOREIGN KEY (reserva_id, empresa_id) REFERENCES reservas(id, empresa_id)
);

CREATE UNIQUE INDEX uq_token_ativo_anamnese ON anamnese_tokens (anamnese_id) WHERE usado = false;

-- Infra: webhooks, jobs, notificações
CREATE TABLE webhook_inbox (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    empresa_id UUID NOT NULL REFERENCES empresas(id),
    origem TEXT NOT NULL CHECK (origem IN ('meta_whatsapp', 'mercado_pago')),
    external_event_id TEXT NOT NULL,
    payload JSONB NOT NULL,
    assinatura_verificada BOOLEAN DEFAULT false,
    x_request_id TEXT,
    headers JSONB,
    processado BOOLEAN DEFAULT false,
    created_at TIMESTAMPTZ DEFAULT now(),
    UNIQUE(origem, external_event_id)
);

CREATE TABLE jobs (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    empresa_id UUID NOT NULL REFERENCES empresas(id),
    tipo TEXT NOT NULL,
    payload JSONB NOT NULL,
    estado TEXT NOT NULL CHECK (estado IN ('pendente', 'processando', 'concluido', 'falhou')) DEFAULT 'pendente',
    tentativas INT NOT NULL DEFAULT 0,
    max_tentativas INT NOT NULL DEFAULT 3,
    proxima_tentativa TIMESTAMPTZ,
    created_at TIMESTAMPTZ DEFAULT now()
);

CREATE TABLE job_tentativas (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    job_id UUID NOT NULL REFERENCES jobs(id),
    resultado TEXT,
    erro_mensagem TEXT,
    created_at TIMESTAMPTZ DEFAULT now()
);

CREATE TABLE dead_letter_jobs (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    job_id UUID NOT NULL UNIQUE REFERENCES jobs(id),
    motivo TEXT NOT NULL,
    alerta_enviado BOOLEAN DEFAULT false,
    created_at TIMESTAMPTZ DEFAULT now()
);

CREATE TABLE notificacoes_internas (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    empresa_id UUID NOT NULL REFERENCES empresas(id),
    usuario_id UUID REFERENCES usuarios_internos(id),
    tipo TEXT NOT NULL,
    mensagem TEXT NOT NULL,
    lida BOOLEAN DEFAULT false,
    created_at TIMESTAMPTZ DEFAULT now(),
    FOREIGN KEY (usuario_id, empresa_id) REFERENCES usuarios_internos(id, empresa_id)
);

-- v3.4 (Ricardo: fila sem saída / Carlos #2): ponto único de notificação ao staff
CREATE OR REPLACE FUNCTION notificar_staff(
    p_empresa_id UUID,
    p_tipo TEXT,
    p_mensagem TEXT,
    p_perfis TEXT[] DEFAULT ARRAY['admin','gestor']
)
RETURNS INT
LANGUAGE plpgsql
SECURITY DEFINER SET search_path = ''
AS $$
DECLARE
    v_count INT;
BEGIN
    INSERT INTO public.notificacoes_internas (empresa_id, usuario_id, tipo, mensagem)
    SELECT p_empresa_id, u.id, p_tipo, p_mensagem
    FROM public.usuarios_internos u
    WHERE u.empresa_id = p_empresa_id AND u.ativo = true AND u.perfil = ANY(p_perfis);
    GET DIAGNOSTICS v_count = ROW_COUNT;
    RETURN v_count;
END;
$$;
