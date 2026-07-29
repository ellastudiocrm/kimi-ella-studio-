-- seed.sql — dados iniciais ELLA Studio (Valinhos) v3.4.3
-- v3.3 (Ricardo #7): horário da Laira dividido em DOIS intervalos

-- Empresa
INSERT INTO empresas (id, nome, cnpj, telefone, endereco) VALUES
('00000000-0000-0000-0000-000000000001', 'ELLA Studio', 'XX.XXX.XXX/0001-XX', '5519987480336', 'Santa Gertrudes, Valinhos - SP, CEP 13277-248');

-- Tipos de recurso
INSERT INTO tipos_recurso (id, empresa_id, nome, descricao) VALUES
('11111111-1111-1111-1111-111111111111', '00000000-0000-0000-0000-000000000001', 'mesa_manicure', 'Mesa para manicure e serviços de unhas'),
('11111111-1111-1111-1111-111111111112', '00000000-0000-0000-0000-000000000001', 'cadeira_pedicure', 'Cadeira para pedicure e spa dos pés'),
('11111111-1111-1111-1111-111111111113', '00000000-0000-0000-0000-000000000001', 'cadeira_cilios', 'Cadeira para cílios e sobrancelhas'),
('11111111-1111-1111-1111-111111111114', '00000000-0000-0000-0000-000000000001', 'sala_estetica', 'Sala com maca para massagem, depilação e limpeza de pele');

-- Recursos físicos
INSERT INTO recursos (id, empresa_id, tipo_recurso_id, nome) VALUES
('22222222-2222-2222-2222-222222222221', '00000000-0000-0000-0000-000000000001', '11111111-1111-1111-1111-111111111111', 'Mesa 1'),
('22222222-2222-2222-2222-222222222222', '00000000-0000-0000-0000-000000000001', '11111111-1111-1111-1111-111111111111', 'Mesa 2'),
('22222222-2222-2222-2222-222222222223', '00000000-0000-0000-0000-000000000001', '11111111-1111-1111-1111-111111111112', 'Cadeira Pés 1'),
('22222222-2222-2222-2222-222222222224', '00000000-0000-0000-0000-000000000001', '11111111-1111-1111-1111-111111111113', 'Cadeira Cílios 1'),
('22222222-2222-2222-2222-222222222225', '00000000-0000-0000-0000-000000000001', '11111111-1111-1111-1111-111111111114', 'Sala 1');

-- Profissional principal (Laira)
INSERT INTO profissionais (id, empresa_id, nome, bio) VALUES
('33333333-3333-3333-3333-333333333333', '00000000-0000-0000-0000-000000000001', 'Laira', 'Fundadora e profissional principal');

-- Horários da empresa: ter–sex 09:00–17:00, sáb 09:00–13:00
INSERT INTO horarios_empresa (empresa_id, dia_semana, abertura, fechamento) VALUES
('00000000-0000-0000-0000-000000000001', 2, '09:00', '17:00'),
('00000000-0000-0000-0000-000000000001', 3, '09:00', '17:00'),
('00000000-0000-0000-0000-000000000001', 4, '09:00', '17:00'),
('00000000-0000-0000-0000-000000000001', 5, '09:00', '17:00'),
('00000000-0000-0000-0000-000000000001', 6, '09:00', '13:00');

-- Laira: ter–sex em DOIS intervalos (almoço 12:30–13:30 protegido), sáb 09:00–13:00
INSERT INTO horarios_profissional (profissional_id, dia_semana, abertura, fechamento) VALUES
('33333333-3333-3333-3333-333333333333', 2, '09:00', '12:30'),
('33333333-3333-3333-3333-333333333333', 2, '13:30', '17:00'),
('33333333-3333-3333-3333-333333333333', 3, '09:00', '12:30'),
('33333333-3333-3333-3333-333333333333', 3, '13:30', '17:00'),
('33333333-3333-3333-3333-333333333333', 4, '09:00', '12:30'),
('33333333-3333-3333-3333-333333333333', 4, '13:30', '17:00'),
('33333333-3333-3333-3333-333333333333', 5, '09:00', '12:30'),
('33333333-3333-3333-3333-333333333333', 5, '13:30', '17:00'),
('33333333-3333-3333-3333-333333333333', 6, '09:00', '13:00');

-- ============================================================
-- NOVO: Serviços reais para testes de ponta a ponta
-- ============================================================
INSERT INTO servicos (id, empresa_id, nome_tecnico, tipo_recurso_id, duracao_minutos, preco_base, percentual_sinal, anamnese_obrigatoria) VALUES
('aaaaaaaa-0000-0000-0000-000000000101', '00000000-0000-0000-0000-000000000001', 'manicure', '11111111-1111-1111-1111-111111111111', 60, 50.00, 30, false),
('aaaaaaaa-0000-0000-0000-000000000102', '00000000-0000-0000-0000-000000000001', 'pedicure', '11111111-1111-1111-1111-111111111112', 60, 60.00, 30, false),
('aaaaaaaa-0000-0000-0000-000000000103', '00000000-0000-0000-0000-000000000001', 'avaliacao', '11111111-1111-1111-1111-111111111114', 30, 0.00, 30, false);

-- Cardápios
INSERT INTO servico_cardapios (servico_id, cardapio, nome_comercial, preco_final) VALUES
('aaaaaaaa-0000-0000-0000-000000000101', 'ella_studio', 'Manicure Ella Studio', 50.00),
('aaaaaaaa-0000-0000-0000-000000000101', 'ella_men', 'Manicure Ella Men', 45.00),
('aaaaaaaa-0000-0000-0000-000000000102', 'ella_studio', 'Pedicure Ella Studio', 60.00),
('aaaaaaaa-0000-0000-0000-000000000102', 'ella_men', 'Pedicure Ella Men', 55.00);

-- Habilidade da Laira
INSERT INTO profissional_servicos (profissional_id, servico_id, empresa_id) VALUES
('33333333-3333-3333-3333-333333333333', 'aaaaaaaa-0000-0000-0000-000000000101', '00000000-0000-0000-0000-000000000001'),
('33333333-3333-3333-3333-333333333333', 'aaaaaaaa-0000-0000-0000-000000000102', '00000000-0000-0000-0000-000000000001');

-- Cliente de exemplo
INSERT INTO clientes (id, empresa_id, nome, telefone_normalizado) VALUES
('cccccccc-0000-0000-0000-000000000199', '00000000-0000-0000-0000-000000000001', 'Maria Exemplo', '5519999999999');
