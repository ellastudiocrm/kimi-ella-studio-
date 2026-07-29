# AGENTS.md — CRM ELLA Studio v3.4.4

> Ficheiro orientador para agentes de código. Baseado no conteúdo real do repositório.

---

## 1. Visão geral

O **CRM ELLA Studio** é um sistema de gestão de estética/beleza (agendamentos, pagamentos, anamnese, créditos, pacotes, bloqueios de agenda).

- **Versão atual:** v3.4.4
- **Stack:** PostgreSQL 15 + Supabase (Auth, RLS, Edge Functions opcionais)
- **Linguagem do projeto:** português (nomes de tabelas, colunas, funções, comentários, documentação)
- **Project ID Supabase:** `crmellastudioblz`
- **Região:** São Paulo (sa-east-1)

### Ficheiros de verdade

- `supabase/migrations/001_extensions.sql` … `017_frontend_ready.sql`
- `supabase/seed.sql`
- `docs/CATALOGO_SERVICOS_ELLA.md` — catálogo oficial de 24 serviços (14 ELLA Studio + 10 ELLA MEN)
- `supabase/tests/*.sql`
- `docs/DECISOES.md` — decisões de negócio oficiais
- `docs/VERIFICACOES.md` — escolhas conscientes documentadas
- `CRM_ELLA_Studio_v3.4.2.md` — changelog detalhado até v3.4.2
- `AUDITORIA_KIMI_v3.4.3.md` — estado real auditado em 2026-07-28

---

## 2. Tecnologia e arquitetura

### Base de dados

- **PostgreSQL 15** validado em instância real.
- **Timezone do negócio:** `America/Sao_Paulo`.
- **Extensões:** `uuid-ossp`, `btree_gist`, `pgcrypto`, `pg_cron`.

### Modelo geral

- **Multi-inquilino (tenant):** todas as tabelas têm `empresa_id`.
- **Isolamento:** RLS ativado em **todas** as tabelas.
- **Acesso:** exclusivamente por **RPCs `SECURITY DEFINER`** com `search_path = ''`.
- **Roles:** `anon`, `authenticated`, `service_role`.

### Estados principais

- Reserva: `pre_reserva → confirmada → realizada | cancelada | no_show` (com `expirada` e `pagamento_em_revisao`).
- Itens: `pendente → confirmado → realizado`; `cancelado` = desistência deliberada.
- Ocupações: `ativa → cancelada | expirada`.

### Concorrência

- Locks explícitos `FOR UPDATE` em ordem fixa: **reserva → cobrança → transação**.
- `expirar_pre_reservas` usa `FOR UPDATE SKIP LOCKED`.
- Constraints `EXCLUDE USING gist` em `agenda_ocupacoes` para profissional e recurso.

---

## 3. Organização do código

```
crm-ella/
├── supabase/
│   ├── migrations/          # 17 migrations numeradas (imutáveis)
│   │   ├── 001_extensions.sql
│   │   ├── 002_core.sql
│   │   ├── 003_catalog.sql
│   │   ├── 004_schedule.sql
│   │   ├── 005_anamnesis.sql
│   │   ├── 006_payments.sql
│   │   ├── 007_rls.sql
│   │   ├── 008_booking_rpc.sql
│   │   ├── 009_payment_rpc.sql
│   │   ├── 010_workflow_rpc.sql
│   │   ├── 011_cron.sql
│   │   ├── 012_ultima_entrada.sql
│   │   ├── 013_decisoes_negocio.sql
│   │   ├── 014_auditoria2_fixes.sql
│   │   ├── 015_fix_cobranca_revisao.sql
│   │   ├── 016_consolidacao_seguranca.sql
│   │   └── 017_frontend_ready.sql
│   ├── seed.sql             # dados iniciais ELLA Studio (24 serviços)
│   └── tests/               # 13 suítes oficiais / 258 asserts
│       ├── 000_test_setup.sql        # AMBIENTE LOCAL APENAS
│       ├── schedule_test.sql
│       ├── payment_race_test.sql
│       ├── rls_test.sql
│       ├── anamnesis_token_test.sql
│       ├── webhook_flow_test.sql
│       ├── review_flow_test.sql
│       ├── anamnese_submit_test.sql
│       ├── bloqueio_flow_test.sql
│       ├── concurrency_test.sql
│       ├── v341_fixes_test.sql
│       ├── decisoes_test.sql
│       ├── auditoria2_test.sql
│       └── frontend_ready_test.sql   # 20 asserts — RLS anon + RPC slots
├── docs/
│   ├── DECISOES.md
│   └── VERIFICACOES.md
├── CRM_ELLA_Studio_v3.4.2.md
└── AUDITORIA_KIMI_v3.4.3.md
```

### Superfície RPC pública

Funções expostas (16 RPCs):

- `criar_pre_reserva(empresa, cliente, itens, chave)` — **nunca `anon`**; frontend chama via API route server-side
- `confirmar_reserva(reserva)`
- `cancelar_reserva(reserva, exceção, motivo)`
- `cancelar_item_reserva(item, exceção, motivo)`
- `cancelar_pre_reserva(reserva)`
- `registrar_pagamento_presencial(cobrança, valor, meio, finalidade, chave)`
- `finalizar_atendimento(reserva)`
- `processar_pagamento_webhook(...)` — **só `service_role`**
- `resolver_revisao(revisão, decisão, motivo)`
- `criar_bloqueio_com_conflito(prof, início, fim, tipo, motivo, recurso?)`
- `remover_bloqueio(bloqueio)`
- `submeter_anamnese(token, respostas, consentimento, texto)` — também `anon`
- `revisar_anamnese(ficha, estado)`
- `regenerar_token_anamnese(ficha)`
- `expirar_pre_reservas(limite)` — **só `service_role`**
- `listar_horarios_disponiveis(empresa, serviço, profissional, data, cardápio, intervalo, limite)` — **também `anon`** (leitura pública de slots)

Helpers internos críticos (não expor):

- `revisao_completar_fila(reserva, regra, motivo)`
- `validar_*`, `atualizar_*`, `sincronizar_*`, `remover_bloqueio_ocupacoes`, `set_updated_at`

---

## 4. Convenções

### Idioma e nomenclatura

- Português para tudo.
- `snake_case` para identificadores.
- Prefixos: `v_` variáveis, `p_` parâmetros, `t_` registos temporários.
- Todas as PKs são `UUID DEFAULT gen_random_uuid()`.

### SQL / PL/pgSQL

- Toda função RPC termina com `SECURITY DEFINER SET search_path = ''`.
- Usar `IF auth.role() = 'authenticated' THEN ... END IF;` para guardas de tenant/perfil.
- Usar `IS DISTINCT FROM` em vez de `<>` quando operandos podem ser `NULL`.
- Asserts: `ASSERT cond, format('msg %s', arg)`.

### Segurança

- Sempre `empresa_id` nas tabelas e FKs compostas.
- Nunca permitir `INSERT/UPDATE/DELETE` direto em tabelas nucleares.
- Nova RPC: `SECURITY DEFINER`, `search_path=''`, validar tenant, depois `REVOKE ... FROM PUBLIC, anon; GRANT EXECUTE ... TO authenticated, service_role;`.

---

## 5. Migrations

> **Regra permanente:** Migrations aplicadas são **imutáveis**. Correções entram sempre como **migration nova numerada sequencialmente**.

### Ambiente Supabase

1. Ativar extensões: `btree_gist`, `pgcrypto`, `uuid-ossp`, `pg_cron`.
2. Aplicar `001` → `017` pela ordem.
3. Aplicar `seed.sql` em staging (não em produção sem adaptação). O seed reflete o catálogo oficial de **24 serviços** (`docs/CATALOGO_SERVICOS_ELLA.md`).
4. Verificar cron: `SELECT * FROM cron.job WHERE jobname = 'expirar-pre-reservas';`

### Ambiente local

```bash
psql -U postgres -d crm_ella -f supabase/tests/000_test_setup.sql
psql -U postgres -d crm_ella -f supabase/migrations/001_extensions.sql
# ... 002 a 017
psql -U postgres -d crm_ella -f supabase/seed.sql
```

> `000_test_setup.sql` cria schema `auth` e roles locais. **Não correr no Supabase real.**

---

## 6. Testes

Os testes são ficheiros SQL autónomos com `DO $$ ... ASSERT ... END $$;`.

### Ordem recomendada

1. `000_test_setup.sql` (local apenas)
2. Migrations `001` → `017`
3. `seed.sql`
4. Suítes na ordem (13 suítes / 258 asserts):
   - `schedule_test.sql`
   - `payment_race_test.sql`
   - `rls_test.sql`
   - `anamnesis_token_test.sql`
   - `webhook_flow_test.sql`
   - `review_flow_test.sql`
   - `anamnese_submit_test.sql`
   - `bloqueio_flow_test.sql`
   - `concurrency_test.sql`
   - `v341_fixes_test.sql`
   - `decisoes_test.sql`
   - `auditoria2_test.sql`
   - `frontend_ready_test.sql`

### Comando

```bash
psql -U postgres -d crm_ella -v ON_ERROR_STOP=1 -f supabase/tests/schedule_test.sql
```

> `ON_ERROR_STOP=1` é essencial.
> `concurrency_test.sql` requer orquestração manual (ver comentários no ficheiro).

---

## 7. Segurança

- **MFA (`aal2`):** exigido em `cancelar_reserva`, `cancelar_item_reserva` (exceção) e `resolver_revisao`.
- **Tokens de anamnese:** credenciais opacas de uso único.
- **Webhooks:** `processar_pagamento_webhook` é só `service_role`.
- **Deadlock:** ordem de lock `reserva → cobrança → transacao`.
- **Revisões:** no máximo uma revisão aberta por reserva/item.
- **Leitura pública (`anon`):** catálogo (`servicos`, `servico_cardapios`, `profissionais`, `profissional_fotos`) exposto via **RLS de linha + GRANT de coluna**; colunas internas (`empresa_id`, `created_at`, `modelo_anamnese_id`, etc.) nunca expostas.
- **Agendamento público:** `criar_pre_reserva` **nunca é exposta a `anon`**; a página pública chama uma API route server-side que usa `service_role`.
- **Storage:** buckets `servicos` e `profissionais` são públicos para leitura; escrita só via API route server-side (validação de empresa e perfil no backend).

---

## 8. Edge Functions esperadas

- `mercado-pago-webhook`: valida assinatura, chama `processar_pagamento_webhook(..., p_assinatura_verificada=true)`.
- Consumidor da fila `jobs`: estornos e notificações.
- Envio de link de anamnese por WhatsApp.

---

## 9. Checklist antes de entregar

- [ ] Migration nova numerada sequencialmente (não editar migrations aplicadas).
- [ ] `CREATE OR REPLACE FUNCTION` numa migration nova se alterar RPC.
- [ ] Testes SQL com `ASSERT` e `RAISE NOTICE`.
- [ ] Verificar RLS/privilégios quando adicionar tabela ou RPC.
- [ ] Correr todas as suítes com `ON_ERROR_STOP=1` e confirmar 0 falhas.
- [ ] Atualizar `AGENTS.md` se a mudança mudar arquitetura ou processo.

---

## 10. Frontend-ready (v3.4.4)

A migration `017_frontend_ready.sql` prepara o backend para a app web Next.js:

- **Schema:** `foto_url` em `servicos`; `especialidades` e `foto_url` em `profissionais`; nova tabela `profissional_fotos`.
- **Leitura pública:** `anon` lê `servicos`, `servico_cardapios`, `profissionais` e `profissional_fotos` via **RLS de linha + GRANT de coluna**; colunas internas (`empresa_id`, `created_at`, `modelo_anamnese_id`) ficam escondidas.
- **RPC pública:** `listar_horarios_disponiveis` exposta a `anon` e `authenticated`; respeita duração do serviço, bloqueios, agenda_ocupacoes, horários de empresa/profissional, exceções e a regra de "última entrada" da migração 012.
- **Cardápio obrigatório:** a RPC não faz fallback para preço/duração do serviço base; sem `servico_cardapios` ativo para o par `(servico_id, cardapio)`, retorna vazio.
- **Storage:** buckets `servicos` e `profissionais` criados; leitura pública, escrita validada em API route server-side.
- **Agendamento anónimo:** `criar_pre_reserva` permanece sem GRANT a `anon`; o browser chama `/api/pre-reserva` (Next.js) que usa `service_role`.
