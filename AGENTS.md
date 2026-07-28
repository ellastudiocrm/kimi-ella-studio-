# AGENTS.md — CRM ELLA Studio v3.4.3

> Ficheiro orientador para agentes de código. Baseado no conteúdo real do repositório (`supabase/migrations/`, `supabase/tests/`, `supabase/seed.sql` e `CRM_ELLA_Studio_v3.4.2.md`).

---

## 1. Visão geral do projeto

O **CRM ELLA Studio** é um sistema de gestão de estética/beleza (agendamentos, pagamentos, anamnese, créditos, pacotes, bloqueios de agenda). A versão atual é a **v3.4.3**.

- **Stack:** PostgreSQL 15 + Supabase (Auth, RLS, Edge Functions opcionais).
- **Linguagem do projeto:** português (nomes de tabelas, colunas, funções, comentários e documentação).
- **Ficheiros de verdade:**
  - `supabase/migrations/001_extensions.sql` … `014_auditoria2_fixes.sql`
  - `supabase/seed.sql`
  - `supabase/tests/*.sql`
- **Decisões de negócio:** `docs/DECISOES.md` (fonte oficial — prioridade sobre defaults no código).
- **Verificações e observações:** `docs/VERIFICACOES.md` (escolhas conscientes documentadas).
- **Documentação detalhada:** `CRM_ELLA_Studio_v3.4.2.md` (changelog, matriz de permissões, provas de corrida).
- **Consolidações (apenas para conveniência):** `CRM_ELLA_Studio_v3.4.2_migracoes.txt` e `CRM_ELLA_Studio_v3.4.2_testes.txt`. Em caso de dúvida, mandam sempre os ficheiros individuais em `supabase/migrations/`.

- **Stack:** PostgreSQL 15 + Supabase (Auth, RLS, Edge Functions opcionais).
- **Linguagem do projeto:** português (nomes de tabelas, colunas, funções, comentários e documentação).
- **Ficheiros de verdade:**
  - `supabase/migrations/001_extensions.sql` … `012_ultima_entrada.sql`
  - `supabase/seed.sql`
  - `supabase/tests/*.sql`
- **Decisões de negócio:** `docs/DECISOES.md` (fonte oficial — prioridade sobre defaults no código).
- **Documentação detalhada:** `CRM_ELLA_Studio_v3.4.2.md` (changelog, matriz de permissões, provas de corrida).
- **Consolidações (apenas para conveniência):** `CRM_ELLA_Studio_v3.4.2_migracoes.txt` e `CRM_ELLA_Studio_v3.4.2_testes.txt`. Em caso de dúvida, mandam sempre os ficheiros individuais em `supabase/migrations/`.

O **CRM ELLA Studio** é um sistema de gestão de estética/beleza (agendamentos, pagamentos, anamnese, créditos, pacotes, bloqueios de agenda). A versão atual é a **v3.4.3**.

- **Stack:** PostgreSQL 15 + Supabase (Auth, RLS, Edge Functions opcionais).
- **Linguagem do projeto:** português (nomes de tabelas, colunas, funções, comentários e documentação).
- **Ficheiros de verdade:**
  - `supabase/migrations/001_extensions.sql` … `014_auditoria2_fixes.sql`
  - `supabase/seed.sql`
  - `supabase/tests/*.sql`
- **Decisões de negócio:** `docs/DECISOES.md` (fonte oficial — prioridade sobre defaults no código).
- **Verificações e observações:** `docs/VERIFICACOES.md` (escolhas conscientes documentadas).
- **Documentação detalhada:** `CRM_ELLA_Studio_v3.4.2.md` (changelog, matriz de permissões, provas de corrida).
- **Consolidações (apenas para conveniência):** `CRM_ELLA_Studio_v3.4.2_migracoes.txt` e `CRM_ELLA_Studio_v3.4.2_testes.txt`. Em caso de dúvida, mandam sempre os ficheiros individuais em `supabase/migrations/`.

- **Stack:** PostgreSQL 15 + Supabase (Auth, RLS, Edge Functions opcionais).
- **Linguagem do projeto:** português (nomes de tabelas, colunas, funções, comentários e documentação).
- **Ficheiros de verdade:**
  - `supabase/migrations/001_extensions.sql` … `012_ultima_entrada.sql`
  - `supabase/seed.sql`
  - `supabase/tests/*.sql`
- **Decisões de negócio:** `docs/DECISOES.md` (fonte oficial — prioridade sobre defaults no código).
- **Documentação detalhada:** `CRM_ELLA_Studio_v3.4.2.md` (changelog, matriz de permissões, provas de corrida).
- **Consolidações (apenas para conveniência):** `CRM_ELLA_Studio_v3.4.2_migracoes.txt` e `CRM_ELLA_Studio_v3.4.2_testes.txt`. Em caso de dúvida, mandam sempre os ficheiros individuais em `supabase/migrations/`.

Não existem `package.json`, `pyproject.toml`, `Cargo.toml`, `docker-compose.yml`, `Makefile`, `config.toml` nem outro manifesto de build. Tudo vive dentro de SQL puro.

---

## 2. Tecnologia e arquitetura

### Base de dados
- **PostgreSQL 15** (validado em 15.13 real).
- **Timezone do negócio:** `America/Sao_Paulo` (definido em `001_extensions.sql` e replicado nos testes).
- **Extensões usadas:** `uuid-ossp`, `btree_gist`, `pgcrypto`, `pg_cron` (este último só no Supabase gerido; `011_cron.sql` é seguro em local).

### Modelo geral
- **Multi-inquilino (tenant):** todas as tabelas têm `empresa_id`. Chaves estrangeiras compostas (`id, empresa_id`) impedem cruzamento entre empresas.
- **Isolamento:** RLS (Row Level Security) ativado em **todas** as tabelas (`007_rls.sql`).
- **Acesso à API:** feito exclusivamente por **RPCs `SECURITY DEFINER`** com `search_path = ''`. As roles `anon`/`authenticated` têm `INSERT/UPDATE/DELETE` revogados nas tabelas nucleares e de workflow (`007_rls.sql`).

### Estados principais
- Reserva: `pre_reserva → confirmada → realizada | cancelada | no_show`, com ramos intermediários `expirada` e `pagamento_em_revisao`.
- Itens: `pendente → confirmado → realizado`; `cancelado` significa **sempre** desistência deliberada.
- Ocupações (`agenda_ocupacoes`): `ativa → cancelada | expirada`.

### Concorrência
- Locks explícitos `FOR UPDATE` em ordem fixa: **reserva → cobrança → transação**.
- `expirar_pre_reservas` usa `FOR UPDATE SKIP LOCKED`.
- Existem duas restrições `EXCLUDE USING gist` em `agenda_ocupacoes` para profissional e recurso (`004_schedule.sql`).

---

## 3. Organização do código

```
crm-ella/
├── supabase/
│   ├── migrations/          # 14 migrations numeradas (aplicar em ordem)
│   │   ├── 001_extensions.sql
│   │   ├── 002_core.sql     # empresas, profissionais, recursos, usuários, logs
│   │   ├── 003_catalog.sql  # clientes, serviços, cardápios, pacotes, anamnese
│   │   ├── 004_schedule.sql # horários, exceções, ocupações, bloqueios, triggers
│   │   ├── 005_anamnesis.sql# fichas de anamnese e respostas
│   │   ├── 006_payments.sql # reservas, itens, cobranças, transações, créditos, revisões
│   │   ├── 007_rls.sql      # RLS, policies, REVOKEs nucleares
│   │   ├── 008_booking_rpc.sql  # criar_pre_reserva, cancelar_item_reserva
│   │   ├── 009_payment_rpc.sql  # pagamentos, cancelamento, expiração
│   │   ├── 010_workflow_rpc.sql # webhook, resolver revisão, bloqueios, anamnese
│   │   ├── 011_cron.sql     # job pg_cron expirar-pre-reservas
│   │   ├── 012_ultima_entrada.sql  # regra da última entrada (v3.4.2)
│   │   ├── 013_decisoes_negocio.sql   # 3 decisões: cardápio obrigatório, sinal 30%, avaliação 0 (v3.4.3)
│   │   └── 014_auditoria2_fixes.sql   # 2ª auditoria: perfis, estados terminais, validações (v3.4.3)
│   ├── seed.sql             # dados iniciais ELLA Studio (Valinhos)
│   └── tests/               # 12 suítes + setup
│       ├── 000_test_setup.sql
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
│       ├── decisoes_test.sql        # 3 decisões de negócio (v3.4.3)
│       └── auditoria2_test.sql      # 2ª auditoria: 7 itens (v3.4.3)
│   │   ├── 001_extensions.sql
│   │   ├── 002_core.sql     # empresas, profissionais, recursos, usuários, logs
│   │   ├── 003_catalog.sql  # clientes, serviços, cardápios, pacotes, anamnese
│   │   ├── 004_schedule.sql # horários, exceções, ocupações, bloqueios, triggers
│   │   ├── 005_anamnesis.sql# fichas de anamnese e respostas
│   │   ├── 006_payments.sql # reservas, itens, cobranças, transações, créditos, revisões
│   │   ├── 007_rls.sql      # RLS, policies, REVOKEs nucleares
│   │   ├── 008_booking_rpc.sql  # criar_pre_reserva, cancelar_item_reserva
│   │   ├── 009_payment_rpc.sql  # pagamentos, cancelamento, expiração
│   │   ├── 010_workflow_rpc.sql # webhook, resolver revisão, bloqueios, anamnese
│   │   ├── 011_cron.sql     # job pg_cron expirar-pre-reservas
│   │   └── 012_ultima_entrada.sql  # regra da última entrada (v3.4.2)
│   ├── seed.sql             # dados iniciais ELLA Studio (Valinhos)
│   └── tests/               # 10 suítes + setup
│       ├── 000_test_setup.sql
│       ├── schedule_test.sql
│       ├── payment_race_test.sql
│       ├── rls_test.sql
│       ├── anamnesis_token_test.sql
│       ├── webhook_flow_test.sql
│       ├── review_flow_test.sql
│       ├── anamnese_submit_test.sql
│       ├── bloqueio_flow_test.sql
│       ├── concurrency_test.sql
│       └── v341_fixes_test.sql
├── CRM_ELLA_Studio_v3.4.2.md
├── CRM_ELLA_Studio_v3.4.2_migracoes.txt
└── CRM_ELLA_Studio_v3.4.2_testes.txt
```

### Superfície RPC pública
São 15 funções expostas (autorização detalhada em `007_rls.sql` / `009_payment_rpc.sql` / `010_workflow_rpc.sql`):

- `criar_pre_reserva(empresa, cliente, itens, chave)`
- `confirmar_reserva(reserva)`
- `cancelar_reserva(reserva, exceção, motivo)`
- `cancelar_item_reserva(item, exceção, motivo)`
- `cancelar_pre_reserva(reserva)`
- `registrar_pagamento_presencial(cobrança, valor, meio, finalidade, chave)`
- `finalizar_atendimento(reserva)`
- `processar_pagamento_webhook(...)` (só `service_role`)
- `resolver_revisao(revisão, decisão, motivo)`
- `criar_bloqueio_com_conflito(prof, início, fim, tipo, motivo, recurso?)`
- `remover_bloqueio(bloqueio)`
- `submeter_anamnese(token, respostas, consentimento, texto)` (também `anon`)
- `revisar_anamnese(ficha, estado)`
- `regenerar_token_anamnese(ficha)`
- `expirar_pre_reservas(limite)` (só `service_role`, cron)

Helper interno crítico: `revisao_completar_fila(reserva, regra, motivo)` — **não** expor a `authenticated`.

---

## 4. Convenções de desenvolvimento

### Idioma e nomenclatura
- Português para tudo: tabelas, colunas, funções, mensagens de erro, comentários.
- Identificadores em `snake_case`.
- Prefixo `v_` para variáveis em PL/pgSQL; `p_` para parâmetros de função; `t_` para registos temporários.
- Todas as chaves primárias são `UUID DEFAULT gen_random_uuid()`.

### SQL / PL/pgSQL
- Toda função RPC termina com `SECURITY DEFINER SET search_path = ''`.
- Wrappers determinísticos de cripto (`gerar_token_opaco`, `sha256_hex`) em vez de chamar `pgcrypto` diretamente.
- Usar `IF auth.role() = 'authenticated' THEN ... END IF;` para guardas de tenant/perfil.
- Usar `IS DISTINCT FROM` em vez de `<>` quando os operandos podem ser `NULL`.
- Asserts de teste usam `ASSERT cond, format('msg %s', arg)` (nunca `ASSERT cond, 'msg %', arg`).

### Isolamento e segurança
- Sempre `empresa_id` nas tabelas e FKs compostas `REFERENCES tabela(id, empresa_id)`.
- Nunca permitir `INSERT/UPDATE/DELETE` direto em tabelas nucleares (`reservas`, `reserva_itens`, `cobrancas`, `transacoes`, `agenda_ocupacoes`) nem de workflow/dinheiro.
- Adicionar novas RPCs? Siga o padrão: `SECURITY DEFINER`, `search_path=''`, validar tenant, e no fim `REVOKE ... FROM PUBLIC, anon; GRANT EXECUTE ... TO authenticated, service_role;`.

---

## 5. Como aplicar migrations e seed

> **Regra permanente:** Migrations aplicadas são **imutáveis**. Nunca editar uma migration que já foi `db push`-ada em staging ou produção. Correções entram sempre como **migration nova numerada sequencialmente** (ex: `013_decisoes_negocio.sql` com `CREATE OR REPLACE`).

### Ambiente Supabase

### Ambiente Supabase
1. Ativar extensões: `btree_gist`, `pgcrypto`, `uuid-ossp`, `pg_cron`.
2. Aplicar `001_extensions.sql` → `014_auditoria2_fixes.sql` pela ordem.
3. Aplicar `seed.sql` em staging (não em produção sem adaptação).
4. Verificar o cron: `SELECT * FROM cron.job WHERE jobname = 'expirar-pre-reservas';`
3. Aplicar `seed.sql` em staging (não em produção sem adaptação).
4. Verificar o cron: `SELECT * FROM cron.job WHERE jobname = 'expirar-pre-reservas';`

### Ambiente local (PostgreSQL limpo)
```bash
psql -U postgres -d crm_ella -f supabase/tests/000_test_setup.sql
psql -U postgres -d crm_ella -f supabase/migrations/001_extensions.sql
# ... 002 a 012
psql -U postgres -d crm_ella -f supabase/seed.sql
```

> `000_test_setup.sql` cria o schema `auth`, as roles `anon`/`authenticated`/`service_role` e funções `auth.uid()`/`auth.role()`/`auth.jwt()` locais. **Não correr no Supabase real.**

---

## 6. Como correr os testes

Os testes são **ficheiros SQL autónomos** com `DO $$ ... ASSERT ... END $$;`. Cada suíte corre numa conexão própria para evitar estado de sessão contaminado.

### Ordem
1. `supabase/tests/000_test_setup.sql` (uma vez, antes das migrations)
2. Migrations `001` → `014`
3. `supabase/seed.sql`
4. Suítes na ordem sugerida (ou individualmente):
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
   - `decisoes_test.sql`      # v3.4.3
   - `auditoria2_test.sql`    # v3.4.3
3. `supabase/seed.sql`
4. Suítes na ordem sugerida (ou individualmente):
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

### Comando exemplo
```bash
psql -U postgres -d crm_ella -v ON_ERROR_STOP=1 -f supabase/tests/schedule_test.sql
```

- `ON_ERROR_STOP=1` é essencial: sem ele um `ASSERT` falhado pode não interromper.
- `concurrency_test.sql` é um guião de cenário com duas sessões; precisa de orquestração manual (ver comentários no ficheiro).
- A suíte total tem **234 asserts** (212 originais + 8 decisões + 14 auditoria2) e **4 provas de corrida** documentadas em `CRM_ELLA_Studio_v3.4.2.md`.

---

## 7. Considerações de segurança

- **MFA (aal2):** exigido em `cancelar_reserva`/`cancelar_item_reserva` quando há exceção, e em `resolver_revisao`. O pagamento de balcão (`registrar_pagamento_presencial`) **não** exige aal2 por decisão de negócio — o dinheiro está a entrar, tudo auditado.
- **Tokens de anamnese:** são credenciais opacas de uso único. O hash fica na base; o token bruto é devolvido **uma única vez** na criação/regeneração. A RPC `submeter_anamnese` é a única coisa acessível a `anon`.
- **Webhooks:** `processar_pagamento_webhook` é **só `service_role`**. A Edge Function deve verificar a assinatura antes de chamar a RPC com `p_assinatura_verificada=true`.
- **Deadlock:** mantenha sempre a ordem de lock `reserva → cobrança → transacao` em qualquer função nova que mexa nessas tabelas.
- **Revisões:** existe no máximo uma revisão aberta por reserva (`uq_revisao_aberta_reserva`) e por item (`uq_revisao_aberta_item`). Novos valores pagos em reservas mortas/em revisão devem usar `revisao_completar_fila`.

---

## 8. Edge Functions esperadas (fora deste repo)

O banco define o contrato; as Edge Functions do Supabase cumprem-no:

- `mercado-pago-webhook`: recebe eventos MP, valida assinatura, chama `processar_pagamento_webhook(..., p_assinatura_verificada=true)`.
- Consumidor da fila `jobs`: processa `estorno_mercado_pago` e notificações WhatsApp.
- Envio do link de anamnese: lê o token bruto da resposta de `criar_pre_reserva`/`regenerar_token_anamnese` e envia por WhatsApp.

---

## 9. Checklist antes de entregar uma alteração

- [ ] **Migrations imutáveis:** nunca editar uma migration já aplicada; criar nova numerada sequencialmente.
- [ ] Se alterar uma RPC existente, usar `CREATE OR REPLACE FUNCTION` numa migration nova.
- [ ] Testes SQL com `ASSERT` e `RAISE NOTICE` para cada cenário novo.
- [ ] Verificar RLS/privilégios quando adicionar tabela ou RPC.
- [ ] Correr todas as suítes com `ON_ERROR_STOP=1` e confirmar 0 falhas.
- [ ] Atualizar `CRM_ELLA_Studio_v3.4.2.md` se a mudança for de negócio visível; as consolidações `*_migracoes.txt` / `*_testes.txt` são geradas, não editadas à mão.

- [ ] Migration nova numerada sequencialmente (não reordenar as existentes).
- [ ] Se alterar uma RPC existente, usar `CREATE OR REPLACE FUNCTION` e repetir `REVOKE`/`GRANT` se necessário.
- [ ] Testes SQL com `ASSERT` e `RAISE NOTICE` para cada cenário novo.
- [ ] Verificar RLS/privilégios quando adicionar tabela ou RPC.
- [ ] Correr todas as suítes com `ON_ERROR_STOP=1` e confirmar 0 falhas.
- [ ] Atualizar `CRM_ELLA_Studio_v3.4.2.md` se a mudança for de negócio visível; as consolidações `*_migracoes.txt` / `*_testes.txt` são geradas, não editadas à mão.
