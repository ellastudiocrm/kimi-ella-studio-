-- 007_rls.sql — helpers, RLS em TODAS as tabelas, policies, privilégios de coluna

-- Helpers (SECURITY DEFINER: leem usuarios_internos sem recursão de RLS)
-- v3.3 (Ricardo: segurança): search_path='' + nomes totalmente qualificados
CREATE OR REPLACE FUNCTION minha_empresa_id()
RETURNS UUID
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = '' AS $$
    SELECT empresa_id FROM public.usuarios_internos
    WHERE auth_user_id = auth.uid() AND ativo = true LIMIT 1;
$$;

CREATE OR REPLACE FUNCTION meu_perfil()
RETURNS TEXT
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = '' AS $$
    SELECT perfil FROM public.usuarios_internos
    WHERE auth_user_id = auth.uid() AND ativo = true LIMIT 1;
$$;

CREATE OR REPLACE FUNCTION meu_usuario_id()
RETURNS UUID
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = '' AS $$
    SELECT id FROM public.usuarios_internos
    WHERE auth_user_id = auth.uid() AND ativo = true LIMIT 1;
$$;

CREATE OR REPLACE FUNCTION meu_profissional_id()
RETURNS UUID
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = '' AS $$
    SELECT up.profissional_id
    FROM public.usuarios_internos u
    JOIN public.usuario_profissional up ON up.usuario_id = u.id
    WHERE u.auth_user_id = auth.uid() AND u.ativo = true LIMIT 1;
$$;

-- RLS em TODAS as tabelas
ALTER TABLE empresas ENABLE ROW LEVEL SECURITY;
ALTER TABLE tipos_recurso ENABLE ROW LEVEL SECURITY;
ALTER TABLE recursos ENABLE ROW LEVEL SECURITY;
ALTER TABLE profissionais ENABLE ROW LEVEL SECURITY;
ALTER TABLE usuarios_internos ENABLE ROW LEVEL SECURITY;
ALTER TABLE usuario_profissional ENABLE ROW LEVEL SECURITY;
ALTER TABLE log_acoes ENABLE ROW LEVEL SECURITY;
ALTER TABLE log_acoes_sensiveis ENABLE ROW LEVEL SECURITY;
ALTER TABLE templates_mensagem ENABLE ROW LEVEL SECURITY;
ALTER TABLE conversas ENABLE ROW LEVEL SECURITY;
ALTER TABLE mensagens ENABLE ROW LEVEL SECURITY;
ALTER TABLE transbordos ENABLE ROW LEVEL SECURITY;
ALTER TABLE clientes ENABLE ROW LEVEL SECURITY;
ALTER TABLE modelos_anamnese ENABLE ROW LEVEL SECURITY;
ALTER TABLE modelo_perguntas ENABLE ROW LEVEL SECURITY;
ALTER TABLE servicos ENABLE ROW LEVEL SECURITY;
ALTER TABLE servico_cardapios ENABLE ROW LEVEL SECURITY;
ALTER TABLE profissional_servicos ENABLE ROW LEVEL SECURITY;
ALTER TABLE modelos_pacote ENABLE ROW LEVEL SECURITY;
ALTER TABLE modelo_pacote_itens ENABLE ROW LEVEL SECURITY;
ALTER TABLE horarios_empresa ENABLE ROW LEVEL SECURITY;
ALTER TABLE horarios_profissional ENABLE ROW LEVEL SECURITY;
ALTER TABLE excecoes_calendario ENABLE ROW LEVEL SECURITY;
ALTER TABLE agenda_ocupacoes ENABLE ROW LEVEL SECURITY;
ALTER TABLE bloqueios ENABLE ROW LEVEL SECURITY;
ALTER TABLE anamneses ENABLE ROW LEVEL SECURITY;
ALTER TABLE anamnese_respostas ENABLE ROW LEVEL SECURITY;
ALTER TABLE reservas ENABLE ROW LEVEL SECURITY;
ALTER TABLE reserva_itens ENABLE ROW LEVEL SECURITY;
ALTER TABLE cobrancas ENABLE ROW LEVEL SECURITY;
ALTER TABLE transacoes ENABLE ROW LEVEL SECURITY;
ALTER TABLE eventos_pagamento ENABLE ROW LEVEL SECURITY;
ALTER TABLE alocacoes_pagamento ENABLE ROW LEVEL SECURITY;
ALTER TABLE contas_creditos ENABLE ROW LEVEL SECURITY;
ALTER TABLE lancamentos_creditos ENABLE ROW LEVEL SECURITY;
ALTER TABLE credito_servicos_permitidos ENABLE ROW LEVEL SECURITY;
ALTER TABLE compras_pacote ENABLE ROW LEVEL SECURITY;
ALTER TABLE compra_pacote_itens ENABLE ROW LEVEL SECURITY;
ALTER TABLE pacote_utilizacoes ENABLE ROW LEVEL SECURITY;
ALTER TABLE cartoes_presente ENABLE ROW LEVEL SECURITY;
ALTER TABLE cartao_presente_lancamentos ENABLE ROW LEVEL SECURITY;
ALTER TABLE revisoes_cancelamento ENABLE ROW LEVEL SECURITY;
ALTER TABLE anamnese_tokens ENABLE ROW LEVEL SECURITY;
ALTER TABLE webhook_inbox ENABLE ROW LEVEL SECURITY;
ALTER TABLE jobs ENABLE ROW LEVEL SECURITY;
ALTER TABLE job_tentativas ENABLE ROW LEVEL SECURITY;
ALTER TABLE dead_letter_jobs ENABLE ROW LEVEL SECURITY;
ALTER TABLE notificacoes_internas ENABLE ROW LEVEL SECURITY;

-- Policies
-- NOTA: o agendamento público corre em Edge Functions com service_role (contorna RLS).
-- Não há policies anon: nenhum dado exposto ao público direto pela API.

CREATE POLICY "usuarios_proprio" ON usuarios_internos FOR SELECT TO authenticated
USING (auth_user_id = auth.uid());
CREATE POLICY "usuarios_admin" ON usuarios_internos FOR ALL TO authenticated
USING (empresa_id = minha_empresa_id() AND meu_perfil() = 'admin');
CREATE POLICY "up_proprio" ON usuario_profissional FOR SELECT TO authenticated
USING (usuario_id = meu_usuario_id());
CREATE POLICY "up_admin" ON usuario_profissional FOR ALL TO authenticated
USING (EXISTS (SELECT 1 FROM usuarios_internos u WHERE u.id = usuario_id
       AND u.empresa_id = minha_empresa_id()) AND meu_perfil() = 'admin');

CREATE POLICY "empresas_staff" ON empresas FOR SELECT TO authenticated
USING (id = minha_empresa_id());

CREATE POLICY "tipos_recurso_ler" ON tipos_recurso FOR SELECT TO authenticated
USING (empresa_id = minha_empresa_id());
CREATE POLICY "tipos_recurso_admin" ON tipos_recurso FOR ALL TO authenticated
USING (empresa_id = minha_empresa_id() AND meu_perfil() IN ('admin','gestor'));

CREATE POLICY "recursos_ler" ON recursos FOR SELECT TO authenticated
USING (empresa_id = minha_empresa_id());
CREATE POLICY "recursos_admin" ON recursos FOR ALL TO authenticated
USING (empresa_id = minha_empresa_id() AND meu_perfil() IN ('admin','gestor'));

CREATE POLICY "profissionais_ler" ON profissionais FOR SELECT TO authenticated
USING (empresa_id = minha_empresa_id());
CREATE POLICY "profissionais_admin" ON profissionais FOR ALL TO authenticated
USING (empresa_id = minha_empresa_id() AND meu_perfil() IN ('admin','gestor'));

CREATE POLICY "servicos_ler" ON servicos FOR SELECT TO authenticated
USING (empresa_id = minha_empresa_id());
CREATE POLICY "servicos_admin" ON servicos FOR ALL TO authenticated
USING (empresa_id = minha_empresa_id() AND meu_perfil() IN ('admin','gestor'));

CREATE POLICY "cardapios_ler" ON servico_cardapios FOR SELECT TO authenticated
USING (EXISTS (SELECT 1 FROM servicos s WHERE s.id = servico_id AND s.empresa_id = minha_empresa_id()));
CREATE POLICY "cardapios_admin" ON servico_cardapios FOR ALL TO authenticated
USING (EXISTS (SELECT 1 FROM servicos s WHERE s.id = servico_id AND s.empresa_id = minha_empresa_id())
       AND meu_perfil() IN ('admin','gestor'));

CREATE POLICY "prof_servicos_ler" ON profissional_servicos FOR SELECT TO authenticated
USING (empresa_id = minha_empresa_id());
CREATE POLICY "prof_servicos_admin" ON profissional_servicos FOR ALL TO authenticated
USING (empresa_id = minha_empresa_id() AND meu_perfil() IN ('admin','gestor'));

CREATE POLICY "modelos_ler" ON modelos_anamnese FOR SELECT TO authenticated
USING (empresa_id = minha_empresa_id());
CREATE POLICY "modelos_admin" ON modelos_anamnese FOR ALL TO authenticated
USING (empresa_id = minha_empresa_id() AND meu_perfil() IN ('admin','gestor'));

CREATE POLICY "perguntas_ler" ON modelo_perguntas FOR SELECT TO authenticated
USING (EXISTS (SELECT 1 FROM modelos_anamnese m WHERE m.id = modelo_id AND m.empresa_id = minha_empresa_id()));
CREATE POLICY "perguntas_admin" ON modelo_perguntas FOR ALL TO authenticated
USING (EXISTS (SELECT 1 FROM modelos_anamnese m WHERE m.id = modelo_id AND m.empresa_id = minha_empresa_id())
       AND meu_perfil() IN ('admin','gestor'));

CREATE POLICY "hor_empresa_ler" ON horarios_empresa FOR SELECT TO authenticated
USING (empresa_id = minha_empresa_id());
CREATE POLICY "hor_empresa_admin" ON horarios_empresa FOR ALL TO authenticated
USING (empresa_id = minha_empresa_id() AND meu_perfil() IN ('admin','gestor'));

CREATE POLICY "hor_prof_ler" ON horarios_profissional FOR SELECT TO authenticated
USING (EXISTS (SELECT 1 FROM profissionais p WHERE p.id = profissional_id AND p.empresa_id = minha_empresa_id()));
CREATE POLICY "hor_prof_admin" ON horarios_profissional FOR ALL TO authenticated
USING (EXISTS (SELECT 1 FROM profissionais p WHERE p.id = profissional_id AND p.empresa_id = minha_empresa_id())
       AND meu_perfil() IN ('admin','gestor'));

CREATE POLICY "excecoes_ler" ON excecoes_calendario FOR SELECT TO authenticated
USING (empresa_id = minha_empresa_id());
CREATE POLICY "excecoes_admin" ON excecoes_calendario FOR ALL TO authenticated
USING (empresa_id = minha_empresa_id() AND meu_perfil() IN ('admin','gestor'));

-- Clientes
CREATE POLICY "clientes_staff" ON clientes FOR ALL TO authenticated
USING (empresa_id = minha_empresa_id() AND meu_perfil() IN ('admin','gestor','recepcao'));
CREATE POLICY "clientes_profissional" ON clientes FOR SELECT TO authenticated
USING (empresa_id = minha_empresa_id() AND EXISTS (
    SELECT 1 FROM reserva_itens ri
    JOIN reservas r ON r.id = ri.reserva_id
    WHERE ri.profissional_id = meu_profissional_id()
      AND r.cliente_id = clientes.id
));

-- Anamneses: admin + profissional revisora (v3.3: UPDATE da profissional sai daqui → RPC revisar_anamnese)
CREATE POLICY "anamneses_admin" ON anamneses FOR ALL TO authenticated
USING (empresa_id = minha_empresa_id() AND meu_perfil() = 'admin');
CREATE POLICY "anamneses_profissional" ON anamneses FOR SELECT TO authenticated
USING (empresa_id = minha_empresa_id() AND profissional_revisora_id = meu_profissional_id());

CREATE POLICY "resp_admin" ON anamnese_respostas FOR ALL TO authenticated
USING (EXISTS (SELECT 1 FROM anamneses a WHERE a.id = anamnese_id
       AND a.empresa_id = minha_empresa_id()) AND meu_perfil() = 'admin');
CREATE POLICY "resp_profissional" ON anamnese_respostas FOR SELECT TO authenticated
USING (EXISTS (SELECT 1 FROM anamneses a WHERE a.id = anamnese_id
       AND a.empresa_id = minha_empresa_id()
       AND a.profissional_revisora_id = meu_profissional_id()));

-- anamnese_tokens: SEM policies — tokens são segredos; só service_role (Edge Functions)

-- Reservas e itens
CREATE POLICY "reservas_staff" ON reservas FOR ALL TO authenticated
USING (empresa_id = minha_empresa_id() AND meu_perfil() IN ('admin','gestor','recepcao'));
CREATE POLICY "reservas_profissional" ON reservas FOR SELECT TO authenticated
USING (empresa_id = minha_empresa_id() AND EXISTS (
    SELECT 1 FROM reserva_itens ri
    WHERE ri.reserva_id = reservas.id AND ri.profissional_id = meu_profissional_id()
));

CREATE POLICY "itens_staff" ON reserva_itens FOR ALL TO authenticated
USING (empresa_id = minha_empresa_id() AND meu_perfil() IN ('admin','gestor','recepcao'));
CREATE POLICY "itens_profissional" ON reserva_itens FOR SELECT TO authenticated
USING (empresa_id = minha_empresa_id() AND profissional_id = meu_profissional_id());

-- v3.3 (Ricardo: RLS não obriga RPC): ocupações passam a ser SÓ LEITURA para staff.
-- Toda a escrita acontece via triggers (bloqueios) e RPCs, ambos SECURITY DEFINER.
CREATE POLICY "ocupacoes_ler" ON agenda_ocupacoes FOR SELECT TO authenticated
USING (empresa_id = minha_empresa_id());

CREATE POLICY "bloqueios_staff" ON bloqueios FOR ALL TO authenticated
USING (empresa_id = minha_empresa_id() AND meu_perfil() IN ('admin','gestor','recepcao'));
CREATE POLICY "bloqueios_profissional" ON bloqueios FOR SELECT TO authenticated
USING (empresa_id = minha_empresa_id() AND profissional_id = meu_profissional_id());

-- Financeiro (v3.3: receção SÓ LÊ — pagamentos em dinheiro via RPC registrar_pagamento_presencial)
CREATE POLICY "cobrancas_admin" ON cobrancas FOR ALL TO authenticated
USING (empresa_id = minha_empresa_id() AND meu_perfil() IN ('admin','gestor'));
CREATE POLICY "cobrancas_ler" ON cobrancas FOR SELECT TO authenticated
USING (empresa_id = minha_empresa_id() AND meu_perfil() = 'recepcao');

CREATE POLICY "transacoes_admin" ON transacoes FOR ALL TO authenticated
USING (empresa_id = minha_empresa_id() AND meu_perfil() IN ('admin','gestor'));
CREATE POLICY "transacoes_ler" ON transacoes FOR SELECT TO authenticated
USING (empresa_id = minha_empresa_id() AND meu_perfil() = 'recepcao');

CREATE POLICY "eventos_admin" ON eventos_pagamento FOR ALL TO authenticated
USING (EXISTS (SELECT 1 FROM transacoes t WHERE t.id = transacao_id
       AND t.empresa_id = minha_empresa_id()) AND meu_perfil() IN ('admin','gestor'));
CREATE POLICY "alocacoes_admin" ON alocacoes_pagamento FOR ALL TO authenticated
USING (EXISTS (SELECT 1 FROM transacoes t WHERE t.id = transacao_id
       AND t.empresa_id = minha_empresa_id()) AND meu_perfil() IN ('admin','gestor'));

-- Créditos
CREATE POLICY "contas_cred_admin" ON contas_creditos FOR ALL TO authenticated
USING (empresa_id = minha_empresa_id() AND meu_perfil() IN ('admin','gestor'));
CREATE POLICY "contas_cred_ler" ON contas_creditos FOR SELECT TO authenticated
USING (empresa_id = minha_empresa_id() AND meu_perfil() = 'recepcao');
CREATE POLICY "lanc_cred_admin" ON lancamentos_creditos FOR ALL TO authenticated
USING (EXISTS (SELECT 1 FROM contas_creditos c WHERE c.id = conta_id
       AND c.empresa_id = minha_empresa_id()) AND meu_perfil() IN ('admin','gestor'));
CREATE POLICY "lanc_cred_ler" ON lancamentos_creditos FOR SELECT TO authenticated
USING (EXISTS (SELECT 1 FROM contas_creditos c WHERE c.id = conta_id
       AND c.empresa_id = minha_empresa_id()) AND meu_perfil() = 'recepcao');
CREATE POLICY "cred_serv_admin" ON credito_servicos_permitidos FOR ALL TO authenticated
USING (EXISTS (SELECT 1 FROM lancamentos_creditos l
       JOIN contas_creditos c ON c.id = l.conta_id
       WHERE l.id = lancamento_id AND c.empresa_id = minha_empresa_id())
       AND meu_perfil() IN ('admin','gestor'));

-- Pacotes
CREATE POLICY "modelos_pacote_ler" ON modelos_pacote FOR SELECT TO authenticated
USING (empresa_id = minha_empresa_id());
CREATE POLICY "modelos_pacote_admin" ON modelos_pacote FOR ALL TO authenticated
USING (empresa_id = minha_empresa_id() AND meu_perfil() IN ('admin','gestor'));
CREATE POLICY "modelo_pacote_itens_ler" ON modelo_pacote_itens FOR SELECT TO authenticated
USING (empresa_id = minha_empresa_id());
CREATE POLICY "modelo_pacote_itens_admin" ON modelo_pacote_itens FOR ALL TO authenticated
USING (empresa_id = minha_empresa_id() AND meu_perfil() IN ('admin','gestor'));
CREATE POLICY "compras_pacote_admin" ON compras_pacote FOR ALL TO authenticated
USING (empresa_id = minha_empresa_id() AND meu_perfil() IN ('admin','gestor'));
CREATE POLICY "compras_pacote_ler" ON compras_pacote FOR SELECT TO authenticated
USING (empresa_id = minha_empresa_id() AND meu_perfil() = 'recepcao');
CREATE POLICY "compra_itens_admin" ON compra_pacote_itens FOR ALL TO authenticated
USING (EXISTS (SELECT 1 FROM compras_pacote cp WHERE cp.id = compra_id
       AND cp.empresa_id = minha_empresa_id()) AND meu_perfil() IN ('admin','gestor'));
CREATE POLICY "compra_itens_ler" ON compra_pacote_itens FOR SELECT TO authenticated
USING (EXISTS (SELECT 1 FROM compras_pacote cp WHERE cp.id = compra_id
       AND cp.empresa_id = minha_empresa_id()) AND meu_perfil() = 'recepcao');
CREATE POLICY "pacote_util_admin" ON pacote_utilizacoes FOR ALL TO authenticated
USING (EXISTS (SELECT 1 FROM compras_pacote cp WHERE cp.id = compra_id
       AND cp.empresa_id = minha_empresa_id()) AND meu_perfil() IN ('admin','gestor'));

-- Cartões
CREATE POLICY "cartoes_admin" ON cartoes_presente FOR ALL TO authenticated
USING (empresa_id = minha_empresa_id() AND meu_perfil() IN ('admin','gestor'));
CREATE POLICY "cartoes_ler" ON cartoes_presente FOR SELECT TO authenticated
USING (empresa_id = minha_empresa_id() AND meu_perfil() = 'recepcao');
CREATE POLICY "cartao_lanc_admin" ON cartao_presente_lancamentos FOR ALL TO authenticated
USING (EXISTS (SELECT 1 FROM cartoes_presente cp WHERE cp.id = cartao_id
       AND cp.empresa_id = minha_empresa_id()) AND meu_perfil() IN ('admin','gestor'));

-- Conversas, mensagens, transbordos, templates, notificações, revisões, logs
CREATE POLICY "conversas_staff" ON conversas FOR ALL TO authenticated
USING (empresa_id = minha_empresa_id() AND meu_perfil() IN ('admin','gestor','recepcao'));
CREATE POLICY "conversas_profissional" ON conversas FOR SELECT TO authenticated
USING (empresa_id = minha_empresa_id() AND transbordada_para = meu_usuario_id());
CREATE POLICY "mensagens_staff" ON mensagens FOR ALL TO authenticated
USING (EXISTS (SELECT 1 FROM conversas c WHERE c.id = conversa_id
       AND c.empresa_id = minha_empresa_id()) AND meu_perfil() IN ('admin','gestor','recepcao'));
CREATE POLICY "mensagens_profissional" ON mensagens FOR SELECT TO authenticated
USING (EXISTS (SELECT 1 FROM conversas c WHERE c.id = conversa_id
       AND c.empresa_id = minha_empresa_id() AND c.transbordada_para = meu_usuario_id()));

CREATE POLICY "transbordos_staff" ON transbordos FOR ALL TO authenticated
USING (empresa_id = minha_empresa_id() AND meu_perfil() IN ('admin','gestor','recepcao'));
CREATE POLICY "transbordos_prof_ler" ON transbordos FOR SELECT TO authenticated
USING (empresa_id = minha_empresa_id() AND profissional_id = meu_profissional_id());
CREATE POLICY "transbordos_prof_update" ON transbordos FOR UPDATE TO authenticated
USING (empresa_id = minha_empresa_id() AND profissional_id = meu_profissional_id());

CREATE POLICY "templates_ler" ON templates_mensagem FOR SELECT TO authenticated
USING (empresa_id = minha_empresa_id());
CREATE POLICY "templates_admin" ON templates_mensagem FOR ALL TO authenticated
USING (empresa_id = minha_empresa_id() AND meu_perfil() IN ('admin','gestor'));

CREATE POLICY "notif_proprio" ON notificacoes_internas FOR SELECT TO authenticated
USING (empresa_id = minha_empresa_id() AND usuario_id = meu_usuario_id());
CREATE POLICY "notif_update" ON notificacoes_internas FOR UPDATE TO authenticated
USING (empresa_id = minha_empresa_id() AND usuario_id = meu_usuario_id());

CREATE POLICY "revisoes_admin" ON revisoes_cancelamento FOR ALL TO authenticated
USING (empresa_id = minha_empresa_id() AND meu_perfil() IN ('admin','gestor'));

CREATE POLICY "log_admin" ON log_acoes FOR SELECT TO authenticated
USING (empresa_id = minha_empresa_id() AND meu_perfil() = 'admin');
CREATE POLICY "log_sensivel_admin" ON log_acoes_sensiveis FOR SELECT TO authenticated
USING (empresa_id = minha_empresa_id() AND meu_perfil() = 'admin');

-- webhook_inbox, jobs, job_tentativas, dead_letter_jobs: SEM policies — só service_role.

-- =====================================================================
-- v3.4 (Carlos #6): escrita nas tabelas nucleares SÓ via RPCs (SECURITY DEFINER).
-- Staff autenticado lê (policies acima); INSERT/UPDATE/DELETE revogados.
-- =====================================================================
REVOKE INSERT, UPDATE, DELETE ON reservas FROM anon, authenticated;
REVOKE INSERT, UPDATE, DELETE ON reserva_itens FROM anon, authenticated;
REVOKE INSERT, UPDATE, DELETE ON cobrancas FROM anon, authenticated;
REVOKE INSERT, UPDATE, DELETE ON transacoes FROM anon, authenticated;
REVOKE INSERT, UPDATE, DELETE ON agenda_ocupacoes FROM anon, authenticated;

-- v3.4.1 (auditoria #6): fecha TODOS os atalhos que contornavam RPC e MFA.
-- Sem estes REVOKEs, as policies FOR ALL abaixo deixavam o staff:
--   - inserir bloqueio direto na tabela (morria no EXCLUDE 23P01 em vez de usar a RPC);
--   - DECIDIR revisão na mão (UPDATE decisao_final) — sem resolver_revisao, sem aal2, sem log;
--   - criar lançamento de crédito na mão (dinheiro inventado).
REVOKE INSERT, UPDATE, DELETE ON bloqueios FROM anon, authenticated;
REVOKE INSERT, UPDATE, DELETE ON revisoes_cancelamento FROM anon, authenticated;
REVOKE INSERT, UPDATE, DELETE ON contas_creditos FROM anon, authenticated;
REVOKE INSERT, UPDATE, DELETE ON lancamentos_creditos FROM anon, authenticated;
REVOKE INSERT, UPDATE, DELETE ON eventos_pagamento FROM anon, authenticated;
REVOKE INSERT, UPDATE, DELETE ON anamnese_tokens FROM anon, authenticated;
REVOKE INSERT, UPDATE, DELETE ON webhook_inbox FROM anon, authenticated;
REVOKE INSERT, UPDATE, DELETE ON jobs FROM anon, authenticated;
REVOKE INSERT, UPDATE, DELETE ON dead_letter_jobs FROM anon, authenticated;
-- notificacoes_internas: UPDATE continua permitido (marcar como lida); criação é só do sistema
REVOKE INSERT, DELETE ON notificacoes_internas FROM anon, authenticated;
