# Auditoria CRM ELLA Studio v3.4.3

**Data da auditoria:** 2026-07-28
**Base de dados auditada:** staging `crmellastudioblz` (Supabase São Paulo)
**Migrations aplicadas:** 001 a 015
**Ferramenta:** supabase-cli `db query --linked`

---

## 1. RESUMO EXECUTIVO

O **backend está substancialmente maduro e funcional**. A arquitetura de banco (multi-tenant, RLS, RPCs `SECURITY DEFINER`, máquina de estados, concorrência) está bem construída e as regras de negócio críticas estão implementadas. No entanto, **os testes SQL não são isolados** e existem **problemas de segurança e higiene** que devem ser corrigidos antes de avançar para frontend/produção.

| Área | Nota | Estado |
|---|---|---|
| Schema / migrations | 8/10 | ✅ Sólido, com pequenas falhas de higiene |
| RLS e isolamento | 7/10 | ✅ Ativo em todas as tabelas, mas policies faltam em 4 tabelas de sistema |
| Privilégios de funções | 5/10 | 🚨 Helpers/testes expostos a `anon` e `authenticated` |
| Testes SQL | 5/10 | ⚠️ Passam em sequência, mas falham isolados; estado fantasma entre runs |
| Seed / demo | 4/10 | ⚠️ Muito incompleto; não cobre fluxos de teste |
| Documentação | 5/10 | ⚠️ Desatualizada e com repetições |
| Cron / jobs | 8/10 | ✅ Configurado, mas sem worker |

**Conclusão:** o banco de dados é confiável para um piloto controlado, mas a **superfície de ataque das funções expostas** e a **fragilidade dos testes** são bloqueadores reais para avançar com segurança.

---

## 2. O QUE FUNCIONA PERFEITAMENTE

### 2.1 Schema completo e consistente

- **48 tabelas** criadas e alinhadas.
- **Todas as tabelas têm chave primária** (verificado via `pg_constraint`).
- **Todas as tabelas têm `empresa_id`** para isolamento multi-tenant.
- **Foreign keys compostas** `(id, empresa_id)` estão presentes nas tabelas críticas (`reservas`, `reserva_itens`, `cobrancas`, `transacoes`, `agenda_ocupacoes`, etc.).
- **Constraints `EXCLUDE USING gist`** em `agenda_ocupacoes` para evitar sobreposição de profissional e recurso.
- **Migrations 001 a 015** aplicadas em ordem sem gaps.

### 2.2 RLS ativo em todas as tabelas

```
48 tabelas com `rls_ativo = true`
```

- A maioria tem 1–3 policies.
- Tabelas nucleares (`reservas`, `cobrancas`, `transacoes`, `reserva_itens`) têm policies e INSERT/UPDATE/DELETE revogados de `authenticated`.

### 2.3 RPCs principais funcionam

As 15 funções públicas documentadas existem e têm `SECURITY DEFINER SET search_path = ''`:

- `criar_pre_reserva`
- `confirmar_reserva`
- `cancelar_reserva` / `cancelar_item_reserva` / `cancelar_pre_reserva`
- `registrar_pagamento_presencial`
- `finalizar_atendimento`
- `processar_pagamento_webhook`
- `resolver_revisao`
- `criar_bloqueio_com_conflito` / `remover_bloqueio`
- `submeter_anamnese` / `revisar_anamnese` / `regenerar_token_anamnese`
- `expirar_pre_reservas`

### 2.4 Regras de negócio implementadas

- **Cardápio obrigatório:** validado em `criar_pre_reserva`; valores permitidos `ella_studio` / `ella_men`.
- **Sinal 30% fixo:** aplicado na criação da reserva e cobrança.
- **Avaliação gratuita (preço 0):** reserva confirma diretamente sem PIX.
- **Máquina de estados:** transições protegidas por triggers.
- **Última entrada:** regra dos horários implementada (v3.4.2).

### 2.5 Concorrência e cron

- Job `expirar-pre-reservas` configurado no cron a cada 5 minutos.
- Locks `FOR UPDATE` em ordem fixa `reserva → cobrança → transacao`.
- Provas de corrida documentadas no código e testadas.

---

## 3. O QUE ESTÁ ERRADO E PRECISA DE CORREÇÃO

### 3.1 🚨 CRÍTICO: Funções de teste e helpers expostas publicamente

Funções criadas apenas para testes ficaram no schema `public` e estão **acessíveis a `anon` e `authenticated`**:

- `teste_agenda_com_anamnese`
- `teste_cria_reserva`
- `teste_cria_revisao_atrasada`
- `teste_paga_sinal`
- `teste_proximo_dia`

**Risco:** em produção, qualquer utilizador anónimo pode chamar `teste_paga_sinal` ou `teste_cria_reserva`.

**Correção:** estas funções devem ser:
- movidas para um schema separado (ex: `tests`); **ou**
- eliminadas do banco de staging/produção após os testes; **ou**
- pelo menos ter `REVOKE EXECUTE FROM PUBLIC, anon, authenticated`.

### 3.2 🚨 CRÍTICO: Helpers internos expostos a `anon`

Funções que deviam ser privadas estão acessíveis a todos:

- `atualizar_bloqueio_ocupacoes`
- `remover_bloqueio_ocupacoes`
- `sincronizar_bloqueio_ocupacoes`
- `validar_alocacao_mesma_empresa`
- `validar_compra_item_mesma_empresa`
- `validar_credito_servico_mesma_empresa`
- `validar_recurso_compativel`
- `validar_resposta_mesma_empresa`
- `validar_transicao_ocupacao`
- `validar_transicao_reserva`
- `validar_transicao_reserva_item`
- `validar_usuario_profissional_mesma_empresa`
- `validar_utilizacao_mesma_empresa`
- `set_updated_at`

**Correção:** revogar `EXECUTE` destas funções de `anon`, `authenticated` e `PUBLIC`. Algumas podem precisar ficar acessíveis a `authenticated` se forem triggers disparadas por policies, mas a maioria deve ser privada.

### 3.3 🚨 ALTO: `notificar_staff` acessível a `anon`

A função `notificar_staff` permite a qualquer anon criar notificações internas.

**Correção:** restringir a `authenticated` (admin/gestor/recepcao) ou `service_role`.

### 3.4 ⚠️ ALTO: Testes SQL não são isolados

Resultados reais da execução:

#### Modo isolado (TRUNCATE + SEED + 1 suíte)

| Suíte | Resultado | Causa |
|---|---|---|
| schedule_test.sql | ✅ PASS | cria próprias fixtures |
| payment_race_test.sql | ✅ PASS | cria próprias fixtures |
| rls_test.sql | ❌ FAIL | usa cliente `cccccccc...0001` que não existe no seed |
| anamnesis_token_test.sql | ❌ FAIL | usa cliente `cccccccc...0001` que não existe no seed |
| webhook_flow_test.sql | ❌ FAIL | usa cliente `cccccccc...0001` que não existe no seed |
| review_flow_test.sql | ❌ FAIL | usa cliente `cccccccc...0001` que não existe no seed |
| anamnese_submit_test.sql | ❌ FAIL | usa profissional `dddddddd...0001` que não existe no seed |
| bloqueio_flow_test.sql | ❌ FAIL | usa profissional `dddddddd...0001` que não existe no seed |
| concurrency_test.sql | ❌ FAIL | usa cliente `cccccccc...0001` que não existe no seed |
| v341_fixes_test.sql | ❌ FAIL | usa `teste_paga_sinal` (de payment_race_test) e serviço `aaaaaaaa...0011` |
| decisoes_test.sql | ✅ PASS | cria próprias fixtures |
| auditoria2_test.sql | ✅ PASS | cria próprias fixtures |

#### Modo sequencial (TRUNCATE + SEED + todas na ordem)

| Suíte | Resultado |
|---|---|
| schedule_test.sql | ✅ PASS |
| payment_race_test.sql | ✅ PASS |
| rls_test.sql | ✅ PASS |
| anamnesis_token_test.sql | ✅ PASS |
| webhook_flow_test.sql | ✅ PASS |
| review_flow_test.sql | ✅ PASS |
| anamnese_submit_test.sql | ✅ PASS |
| bloqueio_flow_test.sql | ✅ PASS |
| concurrency_test.sql | ✅ PASS |
| v341_fixes_test.sql | ✅ PASS |
| **decisoes_test.sql** | ❌ FAIL: "Profissional indisponível neste horário" |
| **auditoria2_test.sql** | ❌ FAIL: "Nenhum recurso compatível disponível neste horário" |

#### Modo master_staging_tests.sql

- ❌ FAIL: `profissional_id = dddddddd...0001` não existe (o master não inclui as fixtures dos testes anteriores corretamente).

**Diagnóstico:**

1. Os testes **não são idempotentes nem autocontidos**.
2. `decisoes_test.sql` e `auditoria2_test.sql` falham no final da sequência porque os horários/dias escolhidos colidem com ocupações/reservas deixadas pelas suítes anteriores.
3. `master_staging_tests.sql` parece gerado automaticamente mas está inconsistente — falta a definição/execução das fixtures dos primeiros testes.

### 3.5 ⚠️ MÉDIO: Seed.sql é muito incompleto

O `seed.sql` só cria:

- 1 empresa (ELLA Studio)
- 4 tipos de recurso
- 5 recursos
- 1 profissional (Laira)
- Horários da empresa e da Laira

**Não cria:**
- Serviços
- Cardápios
- Clientes
- Modelos de anamnese
- Usuários internos
- Configurações de pagamento

**Impacto:** sem os testes anteriores, várias suítes falham por falta de fixtures. O seed não serve para uma demo completa.

### 3.6 ⚠️ MÉDIO: Tabelas sem policies

As seguintes tabelas têm RLS ativo mas **0 policies**:

- `anamnese_tokens`
- `dead_letter_jobs`
- `jobs`
- `webhook_inbox`

Isto significa que **nenhuma role consegue ler/escrever** nelas exceto `service_role` / dono. Pode ser intencional (só worker/service_role), mas deve ser documentado explicitamente.

### 3.7 ⚠️ MÉDIO: `gerar_token_opaco` e `sha256_hex` como INVOKER

Estas funções de cripto usam `SECURITY INVOKER` com `search_path=public, extensions`. Para evitar ataques de search_path, funções que lidam com tokens deveriam ser `SECURITY DEFINER`.

### 3.8 ⚠️ MÉDIO: Documentação desatualizada

- `AGENTS.md` menciona migrations até `014` mas já existe `015`.
- `AGENTS.md` tem **repetições literais** de blocos inteiros (visão geral, checklist).
- `CRM_ELLA_Studio_v3.4.2.md` não inclui as migrations `013`, `014`, `015`.
- `DECISOES.md` repete a Decisão 1 duas vezes.
- `master_staging_tests.sql` está desatualizado/inconsistente.

### 3.9 ⚠️ MÉDIO: Ficheiros temporários no repo

Existem ficheiros de teste temporários que devem ser removidos:

- `_d1_unico_bloco.sql`
- `_d1ab_only.sql`
- `_decisoes_min.sql`
- `_decisoes_sem_d1ab.sql`
- `gerar_master.ps1`
- `master_staging_tests.sql` (ou regenerar de forma correta)

### 3.10 ⚠️ BAIXO: Nome do projeto no ficheiro de documentação

`CRM_ELLA_Studio_v3.4.2.md` ainda se refere a v3.4.2 enquanto o projeto está em v3.4.3. Não é grave, mas causa confusão.

---

## 4. URGÊNCIAS PARA CORRIGIR ANTES DE AVANÇAR

Ordem de prioridade:

1. **Remover/restringir funções de teste do schema public** (`teste_*`).
2. **Revogar acesso de `anon`/`authenticated` aos helpers internos** (`validar_*`, `atualizar_*`, `sincronizar_*`, `set_updated_at`).
3. **Tornar os testes SQL autocontidos** — cada suíte deve criar todas as fixtures que precisa, sem depender de estado de outras.
4. **Corrigir colisões de horário** em `decisoes_test.sql` e `auditoria2_test.sql` (usar horários únicos ou limpar ocupações no início).
5. **Atualizar `seed.sql`** com serviços, cardápios, clientes e usuários mínimos para demo.
6. **Atualizar e limpar `AGENTS.md`**.
7. **Remover ficheiros temporários** do repo.
8. **Documentar intenção das 4 tabelas sem policies**.

---

## 5. O QUE NÃO EXISTE (E É ESPERADO NÃO EXISTIR AINDA)

| Área | Estado | Nota |
|---|---|---|
| Frontend | 0% | Nenhum ficheiro HTML/JSX/TSX/Vue encontrado |
| Edge Functions | 0% | Diretório `supabase/functions` não existe |
| MFA no Supabase Auth | não configurado | O banco exige `aal2`; o projeto Auth não tem MFA ativo |
| Worker de jobs | 0% | Tabela `jobs` existe, nenhum consumidor |
| Produção | 0% | Só existe staging |

Estes itens **não são bugs** — são o próximo passo do projeto.

---

## 6. RECOMENDAÇÃO FINAL

> **O backend é sólido o suficiente para avançar, mas não sem primeiro corrigir a higiene de segurança e os testes.**

Sugiro que, antes de escolher frontend ou integrações, faças uma **sprint de consolidação**:

1. Cleanup de funções expostas.
2. Refactor dos testes para serem autocontidos.
3. Seed completo para demo.
4. Atualização da documentação.

Depois disso, o caminho para frontend + Edge Functions estará livre de surpresas.
