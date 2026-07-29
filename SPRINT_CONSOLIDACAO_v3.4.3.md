# SPRINT DE CONSOLIDAÇÃO — CRM ELLA Studio v3.4.3

> **Objetivo:** Selar o backend antes de avançar para frontend.
> **Autor:** Auditoria conjunta Kimi Work + Kimi Code
> **Data:** 2026-07-28
> **Aplicação:** staging `crmellastudioblz`

---

## 📋 ORDEM DE EXECUÇÃO (não saltar etapas)

| Ordem | Tarefa | Ficheiro(s) | Tipo |
|---|---|---|---|
| 1 | Revogar funções de teste e helpers | Banco (migration 016) | Segurança |
| 2 | MFA em `cancelar_item_reserva` + validação webhook | Banco (migration 016) | Segurança |
| 3 | Seed.sql completo | `supabase/seed.sql` | Dados |
| 4 | AGENTS.md reescrito | `AGENTS.md` | Documentação |
| 5 | Limpar ficheiros temporários | Raiz do projeto | Housekeeping |
| 6 | Isolar testes (fixtures + limpeza) | `tests/*.sql` | Testes |
| 7 | Corrigir colisões de horário | `decisoes_test.sql`, `auditoria2_test.sql` | Testes |

---

## ETAPA 1 — Revogar funções de teste e helpers (SQL)

**Problema:** Funções de teste (`teste_paga_sinal`, `teste_cria_reserva`, etc.) e helpers (`notificar_staff`, `validar_*`, triggers) estão acessíveis a `anon` e `authenticated`.

**Ação:** Criar migration `016_consolidacao_seguranca.sql` com os REVOKEs.

```sql
-- 016_consolidacao_seguranca.sql (v3.4.3-patch2)
-- ETAPA 1: Revogar funções de teste e helpers do público

-- Funções de teste (nenhuma deve ser pública)
REVOKE ALL ON FUNCTION teste_paga_sinal(UUID, TEXT, NUMERIC) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION teste_cria_reserva(INT, TEXT, TEXT) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION teste_agenda_com_anamnese(TEXT, INT, TEXT, TEXT) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION teste_cria_revisao_atrasada(INT, TEXT, TEXT, NUMERIC) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION teste_proximo_dia(INT, TEXT) FROM PUBLIC, anon, authenticated;

-- Helpers internos (só o sistema/triggers usam)
REVOKE ALL ON FUNCTION validar_transicao_reserva() FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION validar_transicao_reserva_item() FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION validar_transicao_ocupacao() FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION validar_recurso_compativel() FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION validar_alocacao_mesma_empresa() FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION validar_credito_servico_mesma_empresa() FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION validar_compra_item_mesma_empresa() FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION validar_utilizacao_mesma_empresa() FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION validar_resposta_mesma_empresa() FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION validar_usuario_profissional_mesma_empresa() FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION set_updated_at() FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION sincronizar_bloqueio_ocupacoes() FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION atualizar_bloqueio_ocupacoes() FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION remover_bloqueio_ocupacoes() FROM PUBLIC, anon, authenticated;

-- notificar_staff: só service_role e authenticated (nunca anon)
REVOKE ALL ON FUNCTION notificar_staff(UUID, TEXT, TEXT, TEXT[]) FROM anon;
```

**Verificação após ETAPA 1:**
```sql
SELECT p.proname, array_agg(r.rolname) as granted_to
FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
LEFT JOIN aclexplode(COALESCE(p.proacl, acldefault('f', p.proowner))) a ON a.privilege_type = 'EXECUTE'
LEFT JOIN pg_roles r ON r.oid = a.grantee
WHERE n.nspname = 'public' AND p.proname LIKE 'teste_%'
GROUP BY p.proname;
-- Resultado esperado: nenhuma função teste_* com anon ou authenticated
```

---

## ETAPA 2 — MFA em cancelar_item_reserva + validação webhook (SQL)

**Problema:** `cancelar_item_reserva` permite exceção financeira sem MFA. Webhook não valida valor defensivamente.

**Ação:** Adicionar na mesma migration 016.

```sql
-- 016_consolidacao_seguranca.sql (continuação)
-- ETAPA 2a: MFA em cancelar_item_reserva quando p_excecao IS NOT NULL

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
        -- v3.4.3-patch2: MFA obrigatório para exceção financeira (alinhado com cancelar_reserva)
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

    PERFORM 1 FROM public.reservas WHERE id = v_item.reserva_id FOR UPDATE;
    SELECT ri.*, r.empresa_id AS r_empresa_id, r.estado AS r_estado INTO v_item
    FROM public.reserva_itens ri
    JOIN public.reservas r ON r.id = ri.reserva_id
    WHERE ri.id = p_reserva_item_id FOR UPDATE OF ri;

    IF v_item.r_estado = 'pagamento_em_revisao' THEN
        RAISE EXCEPTION 'Reserva em revisão de pagamento — decida pela RPC resolver_revisao';
    END IF;

    IF v_item.estado NOT IN ('pendente', 'confirmado') THEN
        RAISE EXCEPTION 'Item não pode ser cancelado no estado atual';
    END IF;

    SELECT COUNT(*) INTO v_restantes
    FROM public.reserva_itens
    WHERE reserva_id = v_item.reserva_id AND estado IN ('pendente', 'confirmado') AND id <> p_reserva_item_id;

    IF v_restantes = 0 THEN
        PERFORM public.cancelar_reserva(v_item.reserva_id, p_excecao, p_motivo);
        RETURN 'reserva_cancelada';
    END IF;

    v_limite := ((v_item.inicio AT TIME ZONE 'America/Sao_Paulo')::DATE - 1) + interval '16 hours';
    v_regra := CASE WHEN (now() AT TIME ZONE 'America/Sao_Paulo') <= v_limite
                    THEN 'credito_automatico' ELSE 'perda_automatica' END;

    UPDATE public.reserva_itens SET estado = 'cancelado' WHERE id = p_reserva_item_id;
    UPDATE public.agenda_ocupacoes SET estado = 'cancelada'
    WHERE reserva_item_id = p_reserva_item_id AND estado = 'ativa';

    SELECT COALESCE(SUM(t.valor), 0) INTO v_pago_reserva
    FROM public.cobrancas c
    JOIN public.transacoes t ON t.cobranca_id = c.id
    WHERE c.reserva_id = v_item.reserva_id AND t.estado = 'pago'
      AND t.finalidade IN ('sinal', 'saldo', 'pagamento_total');

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

REVOKE ALL ON FUNCTION public.cancelar_item_reserva(UUID, TEXT, TEXT) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.cancelar_item_reserva(UUID, TEXT, TEXT) TO authenticated, service_role;
```

```sql
-- ETAPA 2b: Validação defensiva no webhook
-- NOTA: NÃO recriar a função inteira — apenas adicionar validação no início via CREATE OR REPLACE

CREATE OR REPLACE FUNCTION processar_pagamento_webhook(
    p_origem TEXT,
    p_external_event_id TEXT,
    p_valor DECIMAL,
    p_transacao_id UUID DEFAULT NULL,
    p_cobranca_id UUID DEFAULT NULL,
    p_mp_transaction_id TEXT DEFAULT NULL,
    p_payload JSONB DEFAULT '{}'::JSONB,
    p_assinatura_verificada BOOLEAN DEFAULT false
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER SET search_path = ''
AS $$
DECLARE
    v_inbox UUID;
    v_tx RECORD;
    v_cobranca RECORD;
    v_reserva RECORD;
    v_tx_id UUID;
    v_pago DECIMAL(10,2);
    v_atrasado BOOLEAN := false;
    v_reserva_id_lookup UUID;
BEGIN
    -- v3.4.3-patch2: validação defensiva do valor
    IF p_valor IS NULL OR p_valor <= 0 THEN
        RAISE EXCEPTION 'Valor de pagamento inválido: % (deve ser > 0)', p_valor;
    END IF;

    -- (resto da função mantém-se igual — não alterar lógica)
    INSERT INTO public.webhook_inbox ...
    -- [código existente da função]
```

> **Nota:** Se preferires NÃO recriar `processar_pagamento_webhook` inteiramente (é grande), podes simplesmente documentar a validação para ser feita na **Edge Function** que chama a RPC.

---

## ETAPA 3 — Seed.sql completo

**Problema:** Seed só tem empresa, recursos e Laira. Falta tudo o resto.

**Substituir o conteúdo de `supabase/seed.sql` por:**

```sql
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
('aaaaaaaa-0000-0000-0000-0000000000s1', '00000000-0000-0000-0000-000000000001', 'manicure', '11111111-1111-1111-1111-111111111111', 60, 50.00, 30, false),
('aaaaaaaa-0000-0000-0000-0000000000s2', '00000000-0000-0000-0000-000000000001', 'pedicure', '11111111-1111-1111-1111-111111111112', 60, 60.00, 30, false),
('aaaaaaaa-0000-0000-0000-0000000000s3', '00000000-0000-0000-0000-000000000001', 'avaliacao', '11111111-1111-1111-1111-111111111114', 30, 0.00, 30, false);

-- Cardápios
INSERT INTO servico_cardapios (servico_id, cardapio, nome_comercial, preco_final) VALUES
('aaaaaaaa-0000-0000-0000-0000000000s1', 'ella_studio', 'Manicure Ella Studio', 50.00),
('aaaaaaaa-0000-0000-0000-0000000000s1', 'ella_men', 'Manicure Ella Men', 45.00),
('aaaaaaaa-0000-0000-0000-0000000000s2', 'ella_studio', 'Pedicure Ella Studio', 60.00),
('aaaaaaaa-0000-0000-0000-0000000000s2', 'ella_men', 'Pedicure Ella Men', 55.00);

-- Habilidade da Laira
INSERT INTO profissional_servicos (profissional_id, servico_id, empresa_id) VALUES
('33333333-3333-3333-3333-333333333333', 'aaaaaaaa-0000-0000-0000-0000000000s1', '00000000-0000-0000-0000-000000000001'),
('33333333-3333-3333-3333-333333333333', 'aaaaaaaa-0000-0000-0000-0000000000s2', '00000000-0000-0000-0000-000000000001');

-- Cliente de exemplo
INSERT INTO clientes (id, empresa_id, nome, telefone_normalizado) VALUES
('cccccccc-0000-0000-0000-0000000000ex', '00000000-0000-0000-0000-000000000001', 'Maria Exemplo', '5519999999999');
```

---

## ETAPA 4 — AGENTS.md reescrito

**Problema:** Conteúdo duplicado, menciona 014 como última migration, lista 10 suítes em vez de 11.

**Ação:** Sobrescrever `AGENTS.md` inteiramente. Não editar — reescrever do zero.

Ver modelo em `docs/AGENTS_MODELO.md` (se criado) ou usar a versão que o Kimi Code gerar.

---

## ETAPA 5 — Limpar ficheiros temporários

**Ficheiros a apagar da raiz do projeto:**

```bash
# Windows PowerShell (com auto-aprovação completa)
cd C:/Users/ricar/Documents/crm-ella
kimi -y "Executa a sprint de consolidação do CRM ELLA Studio v3.4.3. O ficheiro de instruções completo está em C:/Users/ricar/Documents/crm-ella/SPRINT_CONSOLIDACAO_v3.4.3.md. Segue as 7 etapas na ordem indicada. Aplica as migrations via supabase-cli db query --linked. Reporta o resultado de cada etapa no final."
```

> ⚠️ **IMPORTANTE:** A flag `-y` é obrigatória. Sem ela, o CLI pede aprovação para cada ferramenta destrutiva, ignorando instruções do tipo "não peças confirmação".
# Windows (PowerShell)
Remove-Item "C:/Users/ricar/Documents/crm-ella/_d1_unico_bloco.sql" -ErrorAction SilentlyContinue
Remove-Item "C:/Users/ricar/Documents/crm-ella/_d1ab_only.sql" -ErrorAction SilentlyContinue
Remove-Item "C:/Users/ricar/Documents/crm-ella/_decisoes_min.sql" -ErrorAction SilentlyContinue
Remove-Item "C:/Users/ricar/Documents/crm-ella/_decisoes_sem_d1ab.sql" -ErrorAction SilentlyContinue
Remove-Item "C:/Users/ricar/Documents/crm-ella/master_staging_tests.sql" -ErrorAction SilentlyContinue
# gerar_master.ps1 pode manter se for útil, senão apagar também
```

---

## ETAPA 6 — Isolar testes (fixtures + limpeza)

**Problema:** Testes partilham fixtures (cliente `cccccccc...0001`, profissional `dddddddd...0001`). Corridos isolados, 7/12 falham.

**Princípio:** Cada suíte deve ser **autocontida** — criar os seus próprios fixtures e limpar no fim.

### Regra para todas as suítes:

1. **No início de cada suíte:** criar fixtures com `ON CONFLICT DO NOTHING`
2. **No fim de cada suíte:** limpar dados criados (ou usar UUIDs únicos por teste)
3. **Nunca assumir** que fixtures de outra suíte existem

### Exemplo de padrão a aplicar:

```sql
-- FIXTURES defensivas no início da suíte
INSERT INTO clientes (id, empresa_id, nome, telefone_normalizado) VALUES
('cccccccc-0000-0000-0000-000000000001', '00000000-0000-0000-0000-000000000001', 'Cliente Teste', '5519999990001')
ON CONFLICT (id) DO NOTHING;

INSERT INTO profissionais (id, empresa_id, nome) VALUES
('dddddddd-0000-0000-0000-000000000001', '00000000-0000-0000-0000-000000000001', 'Prof B Teste')
ON CONFLICT (id) DO NOTHING;

INSERT INTO horarios_profissional ... ON CONFLICT DO NOTHING;
INSERT INTO servicos ... ON CONFLICT DO NOTHING;
INSERT INTO profissional_servicos ... ON CONFLICT DO NOTHING;
```

---

## ETAPA 7 — Corrigir colisões de horário

**Problema:** `decisoes_test.sql` e `auditoria2_test.sql` usam horários que colidem com reservas de suítes anteriores.

**Solução:** Usar **dias da semana diferentes** e **horários distintos** em cada suíte. Sugestão:

| Suíte | DOW usado | Horários |
|---|---|---|
| schedule_test | 2-6 | 10:00, 14:00 |
| payment_race_test | 2-6 | 16:00, 09:00 |
| webhook_flow_test | 5 | 10:00-15:00 |
| review_flow_test | 2-6 | 09:00, 15:00 |
| **decisoes_test** | **2-5** | **10:00, 11:00, 12:00** ← já assim |
| **auditoria2_test** | **2-6** | **10:00-12:00** ← já assim |

Verificar se há sobreposição real. Se sim, usar `DELETE FROM excecoes_calendario WHERE motivo LIKE 'Teste%'` no fim de cada suíte que cria exceções.

---

## ✅ CHECKLIST DE VALIDAÇÃO FINAL

Após todas as etapas:

```sql
-- 1. Verificar funções de teste não expostas
SELECT proname FROM pg_proc
WHERE proname LIKE 'teste_%'
  AND proacl IS NOT NULL;
-- Esperado: 0 linhas

-- 2. Verificar cron ativo
SELECT jobname, schedule, active FROM cron.job WHERE jobname = 'expirar-pre-reservas';
-- Esperado: 'expirar-pre-reservas', '*/5 * * * *', true

-- 3. Verificar migrations aplicadas
SELECT filename FROM supabase_migrations.migration ORDER BY id;
-- Esperado: 001 a 016 (sem gaps)

-- 4. Contar tabelas
SELECT COUNT(*) FROM pg_tables WHERE schemaname = 'public';
-- Esperado: 48

-- 5. Contar policies
SELECT COUNT(*) FROM pg_policies WHERE schemaname = 'public';
-- Esperado: 77
```

---

## 🚀 PROMPT PARA O KIMI CODE

Copia e cola isto no PowerShell (Kimi Code):

```
Executa a sprint de consolidação do CRM ELLA Studio v3.4.3.

O ficheiro de instruções completo está em:
C:/Users/ricar/Documents/crm-ella/SPRINT_CONSOLIDACAO_v3.4.3.md

Segue as 7 etapas na ordem indicada. NÃO peças confirmação entre etapas.
Aplica as migrations via supabase-cli db query --linked.
Reporta o resultado de cada etapa (sucesso/erro) no final.
```
