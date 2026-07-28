# CRM ELLA Studio — v3.4.2 (candidata a piloto controlado)

**Data:** 2026-07-27 · **Base:** PostgreSQL 15 / Supabase · **Método:** tudo validado em PostgreSQL 15.13 real no sandbox (nunca só parser)

Esta versão é a v3.4.1 mais **uma correção de regra de negócio** pedida pelo Neri a 27/07/2026: as 17h são a hora da **última entrada**, não o fechamento do estúdio. A v3.4.1 exigia que o serviço coubesse inteiro antes das 17h — errado. **Nenhum módulo novo foi criado** (1 migration nova: `012_ultima_entrada.sql`).

---

## 1. Resumo executivo

| Origem | Ponto | Estado |
|---|---|---|
| Auditoria v3.4 #1 | Pagamento parcial vencido prendendo o horário | **Corrigido** (cron liberta o slot sempre; dinheiro pago → fila de revisão) |
| Auditoria v3.4 #2 | Confirmação após cron criando reserva sem itens | **Corrigido** (resolver 'confirmar' revê disponibilidade + recria ocupações) |
| Auditoria v3.4 #3 | Revisões/estornos contando valores duplicados | **Corrigido** (toda revisão nasce líquida do que já está na fila) |
| Auditoria v3.4 #4 | Pagamento presencial marcando atendimento como realizado | **Corrigido** (pagamento nunca muda estado; nova RPC `finalizar_atendimento`) |
| Auditoria v3.4 #5 | Permissões contornando MFA e RPCs | **Corrigido** (REVOKE em 10 tabelas de workflow/dinheiro) |
| Auditoria v3.4 #6 | Possível deadlock pagamento × cancelamento | **Corrigido** (ordem de lock global reserva → cobrança → transação) + prova F9: 7 rondas, 0 deadlocks |
| Auditoria v3.4 #7 | "001_extensions.sql corrompido (`\[`)'' | **Falso alarme** — confirmado pelo próprio auditor: artefacto da colagem; ficheiros-fonte limpos |
| Auditoria v3.4.1 — GRAVE | Subtração da fila contava revisões decididas `confirmar` (dinheiro devolvido à reserva ficava sem destino num cancelamento posterior) | **Corrigido** (`IS DISTINCT FROM 'confirmar'` nos 4 pontos de subtração) + teste F11 |
| Auditoria v3.4.1 — MÉDIO | `resolver('confirmar')` ressuscitava item cancelado de propósito pela cliente | **Corrigido** (cron não-pago deixa itens `pendente`; `cancelado` = sempre desistência; confirmar revive só `pendente`) + teste F12 |
| **Achado próprio (prova F9)** | Webhook de saldo após cancelamento: a revisão nova era **engolida** pelo índice único `uq_revisao_aberta_reserva` — R$ 70 sem rasto na fila | **Corrigido** (helper `revisao_completar_fila`: a fila aberta é sempre completada até ao pago total) + testes F13/F14 |
| Regra de negócio (Neri, 27/07) | "17h não é o horário de fechar o studio, mas de receber o último cliente — que pode ir até 3 horas. Não dá para agendar depois das 17h." | **Implementado** (migration `012`: início tem de estar dentro de um intervalo; o fim só pode passar do fechamento no **último** intervalo do dia) + testes T13–T18 |

**Validação final:** 212 asserts verdes em 10 suítes + 4 provas de concorrência (SKIP LOCKED, corrida das mesas, webhook × cron, webhook × cancelar) — tudo em PostgreSQL 15.13 real.

**Decisão sugerida:** núcleo pronto para o piloto controlado, nos termos que o Neri definiu ("com os testes específicos verdes"). As três decisões de negócio seguem em aberto por escolha tua (§ 8).

---

## 2. As correções em detalhe

### 2.1 Os 6 pontos da auditoria da v3.4 (conferidos um a um pelo auditor na v3.4.1)

1. **Parcial vencido não prende mais o horário.** `expirar_pre_reservas` expira as ocupações **sempre** (slot livre na hora). Se houver dinheiro pago, a reserva vai para `pagamento_em_revisao` (itens ficam `pendente`) com revisão aberta e aviso ao staff — o dinheiro espera decisão humana sem bloquear a agenda.
2. **Confirmar depois do cron não cria reserva oca.** `resolver_revisao(..., 'confirmar')` recusa horário já passado, re-verifica profissional **e** recurso (outro cliente pode ter ocupado o slot libertado) e recria as ocupações (`origem='reserva'`, `expires_at NULL`). A máquina de estados dos itens ganhou a transição `cancelado → confirmado` — que na v3.4.1b deixou de ser usada pelo cron (ver 2.2), ficando como rede de segurança.
3. **Fila nunca vale mais que o pago.** Toda revisão nasce líquida: `pago_total − SUM(revisões da reserva)`.
4. **Pagamento ≠ atendimento.** `registrar_pagamento_presencial` nunca toca no estado da reserva; a nova RPC `finalizar_atendimento(reserva)` (admin/gestor/receção/profissional) é a **única** via para `realizada`.
5. **MFA e túnel RPC.** REVOKE de `INSERT/UPDATE/DELETE` em `bloqueios`, `revisoes_cancelamento`, `contas_creditos`, `lancamentos_creditos`, `eventos_pagamento`, `anamnese_tokens`, `webhook_inbox`, `jobs`, `dead_letter_jobs` e `notificacoes_internas` (INSERT/DELETE) — antes um admin sem MFA conseguia criar créditos à mão. Decisão documentada: `aal2` fica só onde o dinheiro **sai ou muda de destino** (`resolver_revisao`, exceção de cancelamento); pagamento de balcão (dinheiro a entrar) não exige segundo fator.
6. **Sem deadlock.** Ordem de lock única — **reserva → cobrança → transação** — no webhook, no presencial e nos cancelamentos. Prova F9 (webhook × cancelar com barreira): 0 deadlocks.

### 2.2 GRAVE + MÉDIO da auditoria da v3.4.1 (v3.4.1b)

- **GRAVE — `confirmar` não desconta da fila.** A subtração do ponto 3 contava **todas** as revisões, incluindo as decididas `confirmar` — que é a única decisão que devolve o dinheiro à reserva viva. Cenário real: sinal de R$ 30 atrasado → revisão → admin confirma → semanas depois a cliente cancela → a fila calculava 30 − 30 = **0** e o dinheiro ficava sem destino e sem rasto. Correção: `AND rev.decisao_final IS DISTINCT FROM 'confirmar'` nos 4 pontos de subtração (`cancelar_reserva`, `cancelar_item_reserva`, `registrar_pagamento_presencial`, `expirar_pre_reservas`). Regressão: **F11**.
- **MÉDIO — confirmar não ressuscita desistência.** O loop do confirmar revivia itens `('pendente','cancelado')`, mas o schema não distinguia "cancelado pelo cron" de "cancelado a pedido da cliente". Correção (sugerida pelo auditor): o ramo sem-pagamento do cron também deixa os itens `pendente` — **`cancelado` passa a significar sempre desistência deliberada** — e o confirmar revive só `pendente`. Regressão: **F12** (2 serviços, desiste de 1, paga atrasado, confirma → só o serviço vivo volta à agenda e à cobrança).

### 2.3 Achado próprio — a fila "engolida" (prova de corrida F9)

A prova F9 (webhook de saldo × cancelamento, com barreira) apanhou um bug que nenhum teste sequencial via: `cancelar_reserva` commitava primeiro (revisão de R$ 30 aberta) e o webhook do saldo (R$ 70) chegava depois — o INSERT da revisão dele batia no índice único `uq_revisao_aberta_reserva` e era **engolido** pelo `ON CONFLICT DO NOTHING`: os R$ 70 ficavam fora da fila. Simetricamente, sem revisão prévia o INSERT bruto podia contar a fila em dobro.

Correção: função interna **`revisao_completar_fila(reserva, regra, motivo)`** — a revisão aberta ao nível da reserva passa a valer sempre:

```
fila_reserva = dinheiro_pago_total − decidido(≠ 'confirmar') − já_na_fila_por_item
```

com UPSERT (UPDATE da revisão aberta; INSERT se não houver). Aplicada nos **6 pontos** onde dinheiro chega a reserva morta/em revisão: webhook (atrasado, já-em-revisão, cancelada/realizada) e presencial (expirada/cancelada, já-em-revisão) e no cron. Antes, os ramos "já em revisão" **só notificavam** — agora o dinheiro entra na fila. Pré-condição documentada: chamador sempre com a reserva bloqueada (`FOR UPDATE`), o que todos já faziam. Regressões: **F13** (saldo pós-cancelamento → fila de R$ 100) e **F14** (2.º pagamento em revisão → fila 10 + 20 = 30).

### 2.4 Regra da "última entrada" (v3.4.2 — pedido do Neri)

**Antes (errado para o negócio):** o serviço tinha de acabar antes do fechamento — uma cliente das 16h com 2 h de serviço era recusada.

**Agora (migration `012`, `CREATE OR REPLACE criar_pre_reserva`):**

1. O **início** tem de estar dentro de um intervalo de atendimento (`abertura ≤ início ≤ fechamento`) — começar **exatamente** às 17h vale;
2. O **fim** pode passar do fechamento **apenas no último intervalo do dia** (`fechamento = max(fechamentos do dia)`). Cliente das 17h com 3 h de serviço → entra, acaba às 20h. Mas um serviço das 11h que atravessaria o almoço (12:30–13:30) continua **recusado** — a manhã não é o último intervalo do dia;
3. Dias de **exceção** (`ajuste` no calendário) mantêm a regra antiga: o serviço tem de caber inteiro. Um ajuste é deliberado ("hoje saio às 15h") — ninguém fica além da hora especial;
4. Aplica-se aos dois níveis: horário da empresa **e** da profissional.

Regressões: **T13** (sábado 12:30, acaba 13:30 — último intervalo estica) · **T14** (começar às 17:00 em ponto entra) · **T15** (17:30 é recusado) · **T16** (almoço continua protegido) · **T17** (dia de ajuste: quem cabe inteiro entra) · **T18** (dia de ajuste não estica).

---

## 3. Máquina de estados (v3.4.1)

```
pre_reserva ──┬─ confirmada ──┬─ realizada          (só via finalizar_atendimento)
              │               ├─ cancelada          (regra 16h → revisão se houver dinheiro)
              │               └─ no_show
              ├─ expirada ────┬─ pagamento_em_revisao (PIX/balcão tardio)
              │               └─ cancelada            (cancelar_pre_reserva aceita expirada)
              ├─ cancelada    (desistência sem pagamento — sem revisão)
              └─ pagamento_em_revisao ──┬─ confirmada (resolver: confirmar — re-verifica slot)
                                        └─ cancelada  (resolver: estorno/credito/perdido)
```

Itens: `pendente → confirmado → realizado | no_show`, e `pendente|confirmado → cancelado` (**sempre** desistência deliberada — o cron já não cancela itens). Ocupações: `ativa → cancelada | expirada`; sinal 0% (`percentual_sinal = 0`) nasce **confirmada** com ocupações definitivas, sem espera de PIX.

## 4. Superfície RPC (15 públicas) e matriz de autorização

| RPC | Quem chama | MFA | Notas |
|---|---|---|---|
| `criar_pre_reserva(empresa, cliente, itens, chave)` | service_role, authenticated | — | Idempotente; tz-safe; retry de recurso; sinal 0% nasce confirmada |
| `processar_pagamento_webhook(...)` | **só service_role** | n/a | Atômica; dedupe inbox; classifica finalidade; completa a fila |
| `confirmar_reserva(reserva)` | service_role, authenticated | — | Atrasado → `pagamento_em_revisao` |
| `registrar_pagamento_presencial(cobrança, valor, meio, finalidade, chave)` | authenticated (equipe), service_role | — | Idempotente; **nunca** muda estado da reserva; dinheiro em reserva morta → fila |
| `finalizar_atendimento(reserva)` | authenticated (equipe), service_role | — | **Única** via para `realizada` (v3.4.1) |
| `cancelar_reserva(reserva, exceção, motivo)` | authenticated, service_role | **aal2 na exceção** | Regra 16h no horário do estúdio |
| `cancelar_item_reserva(item, exceção, motivo)` | authenticated, service_role | **aal2 na exceção** | Último item → cancela a reserva; revisão proporcional líquida |
| `cancelar_pre_reserva(reserva)` | authenticated, service_role | — | Aceita `pre_reserva` **e** `expirada` (era estado sem saída) |
| `resolver_revisao(revisão, decisão, motivo)` | authenticated (admin/gestor), service_role | **aal2** | Final + auditada; confirmar re-verifica passado e slot |
| `criar_bloqueio_com_conflito(prof, início, fim, tipo, motivo, recurso?)` | authenticated (equipe), service_role | — | Cancela afetados + avisa clientes |
| `remover_bloqueio(bloqueio)` | authenticated (equipe), service_role | — | v3.4.1 (bloqueio órfão tinha REVOKE mas não tinha saída RPC) |
| `submeter_anamnese(token, respostas, consentimento, texto)` | **anon**, authenticated, service_role | — | Token = credencial; recusa ficha de agendamento morto |
| `revisar_anamnese(ficha, estado)` | authenticated (revisora/admin), service_role | — | |
| `regenerar_token_anamnese(ficha)` | authenticated (equipe), service_role | — | Invalida anterior; `LEAST(agendamento, 24h)` |
| `expirar_pre_reservas(limite)` | **só service_role** (cron) | — | `SKIP LOCKED`; slot sempre libertado; pago → fila |

Internas (EXECUTE revogado das roles de API): `revisao_completar_fila` (nova, v3.4.1b), `notificar_staff`, `gerar_token_opaco`, `sha256_hex`, helpers de tenant.

Tabelas nucleares e de workflow com `REVOKE INSERT/UPDATE/DELETE` de `anon, authenticated` (RLS por baixo como rede de segurança): `reservas`, `reserva_itens`, `cobrancas`, `transacoes`, `agenda_ocupacoes`, `bloqueios`, `revisoes_cancelamento`, `contas_creditos`, `lancamentos_creditos`, `eventos_pagamento`, `anamnese_tokens`, `webhook_inbox`, `jobs`, `dead_letter_jobs`, `notificacoes_internas` (INSERT/DELETE).

## 5. Invariantes de dinheiro (v3.4.1)

1. **Um sinal pago por cobrança** (`idx_transacao_sinal_pago_unico`); parcelas/saldo como `saldo`; 100% como `pagamento_total`.
2. "Dinheiro recebido" = `sinal + saldo + pagamento_total` pagos, o mesmo critério em todo o lado.
3. **Nunca há revisão sem dinheiro** e **a fila nunca vale mais que o pago** — toda revisão nasce líquida.
4. **`confirmar` não desconta**: revisão decidida `confirmar` devolveu o dinheiro à reserva; ele volta a contar num cancelamento posterior.
5. **A fila é completada**: dinheiro novo em reserva morta/em revisão entra na fila aberta (UPSERT), nunca é engolido nem duplicado — `fila_aberta = pago − decidido(≠confirmar) − fila_por_item`.
6. Idempotência em camadas: reserva, transação, evento de webhook, lançamentos de crédito.
7. Decisão financeira = admin/gestor + MFA + log; estorno real sai pela fila `jobs` para a Edge Function.

## 6. O que mudou em cada ficheiro (v3.4 → v3.4.1 → v3.4.2)

| Ficheiro | Mudança |
|---|---|
| `006_payments.sql` | Transição de item `cancelado → confirmado` (rede de segurança do resolver) |
| `007_rls.sql` | REVOKE em 10 tabelas de workflow/dinheiro (fecham contornos de MFA — inclui bónus não pedido: `revisoes_cancelamento`, `contas_creditos`, `lancamentos_creditos`) |
| `008_booking_rpc.sql` | Sinal 0% nasce confirmada (ocupações definitivas); `cancelar_item_reserva` com ordem de lock, guarda de revisão e valor **líquido** (+ filtro `≠ confirmar` na v3.4.1b) |
| `009_payment_rpc.sql` | `registrar_pagamento_presencial` reescrito (sem aal2, ordem de lock, reserva morta → fila, nunca `realizada`); **`finalizar_atendimento` (novo)**; `cancelar_pre_reserva` aceita `expirada`; cron: slot sempre livre + pago→fila (+ itens `pendente` no ramo sem-pagamento, v3.4.1b); **`revisao_completar_fila` (nova, v3.4.1b)**; subtrações com filtro `≠ confirmar` |
| `010_workflow_rpc.sql` | Webhook com ordem de lock reserva→cobrança→transação; resolver com guarda de passado + re-verificação de slot; **`remover_bloqueio` (novo)**; `submeter_anamnese` recusa ficha de agendamento morto; resolver revive só `pendente` (v3.4.1b); 3 ramos do webhook usam `revisao_completar_fila` (v3.4.1b) |
| `012_ultima_entrada.sql` | **(v3.4.2 — novo)** `CREATE OR REPLACE criar_pre_reserva`: regra da última entrada (§ 2.4). Permissões preservadas pelo OR REPLACE |

**Estrutura aplicada:** 12 migrations + seed · 48 tabelas (48 com RLS) · 77 policies · 15 triggers · 4 EXCLUDE · **15 RPCs públicas** + helpers internos.

## 7. Relatório de validação (PostgreSQL 15.13 real)

Ambiente: binários PostgreSQL 15.13 (zonky) em sandbox, `auth.users`/`auth.uid()`/`auth.role()`/`auth.jwt()` simulados, roles `anon`/`authenticated`/`service_role` (BYPASSRLS) — o desenho do Supabase.

### 7.1 Suítes funcionais — **212 asserts verdes, 0 falhas**

| Suíte | Asserts | Âmbito |
|---|---|---|
| `schedule_test.sql` | 16 | Disponibilidade, exceções, bloqueios, recursos, multi-item + **última entrada (T13–T18, v3.4.2)** |
| `payment_race_test.sql` | 32 | Sinal, atraso→revisão, expiração, regra 16h, último item, proporcional |
| `rls_test.sql` | 16 | Isolamento de inquilino, REVOKEs, EXECUTE por role |
| `anamnesis_token_test.sql` | 10 | Token: emissão, uso único, regeneração, revisão |
| `webhook_flow_test.sql` | 29 | Confirmação atômica, dedupe, atrasado, assinatura, saldo, parcial |
| `review_flow_test.sql` | 22 | Confirmar (livre/ocupado/passado), decisões, crédito, estorno, MFA |
| `anamnese_submit_test.sql` | 17 | Entrega pelo link (incl. anon), regras, LGPD, ficha morta |
| `bloqueio_flow_test.sql` | 13 | Conflito com cancelamento, cirúrgico, EXCLUDE como rede |
| `concurrency_test.sql` | (guia) | Cenário de 2 sessões, executado pelo orquestrador |
| `v341_fixes_test.sql` | 57 | **F1–F14**: regressões de todos os pontos da v3.4.1 e v3.4.1b |

Destaques F1–F14: fila = exatamente o pago (cancelamento de 2 itens; bloqueio com 2 itens) · sinal 0% nasce confirmada e o cron ignora-a · presencial com aal1 confirma sem virar `realizada`; `finalizar_atendimento` fecha · confirmar recusa horário passado · ciclo cron→webhook→confirmar completo (item revivido + 2 ocupações) · REVOKEs negam escrita direta (admin com aal2 incluído) e `remover_bloqueio` funciona · parcial vencido liberta o slot e outro cliente agenda no lugar · **F11**: cancelamento após `confirmar` reabre fila de R$ 30 (o GRAVE) · **F12**: confirmar revive só `pendente`, item recusado não volta (o MÉDIO) · **F13**: saldo pós-cancelamento completa a fila para R$ 100 (o achado F9) · **F14**: 2.º pagamento em revisão entra na fila (10 + 20 = 30).

### 7.2 Provas de concorrência (sessões reais, com barreira)

1. **SKIP LOCKED (cron × cron)** — 3 rondas × 6 pré-reservas vencidas, dois `expirar_pre_reservas` em paralelo: lotes disjuntos, zero erros, zero duplo-processamento.
2. **Corrida das mesas** — 4 threads no mesmo horário (3 profissionais + 1 profissional repetida, 2 mesas): sempre **2 vencedoras em mesas distintas** e 2 erros amigáveis; nunca a mesma profissional 2×; invariante global de sobreposição de ocupações ativas = **0**.
3. **Webhook × cron, 6 rondas** — atrasado → `pagamento_em_revisao` (revisão aberta, slot livre, itens `pendente`) ou `confirmada` no prazo; sempre uma única decisão terminal; dinheiro nunca duplicado.
4. **Webhook × cancelar (F9), 7 rondas** — **0 deadlocks** (ordem de lock única) e, depois da correção 2.3, fila = R$ 100 em todas as ordens de chegada.

### 7.3 Nota sobre a anomalia da sessão anterior

Numa ronda anterior de depuração, 4/4 threads venceram uma corrida que devia dar 2/4. Investigação: as duas EXCLUDE existem e nunca são removidas por nenhuma migration (verificado estaticamente), são `NOT DEFERRABLE`, e em ambiente limpo a corrida dá sempre 2/4 + invariante global 0. Conclusão: estado transitório da base de depuração daquela sessão (dúzias de células ad-hoc e re-aplicações parciais), **não** defeito dos ficheiros entregues. Se alguma vez reaparecer em staging, o diagnóstico é: `SELECT conname FROM pg_constraint WHERE conrelid='agenda_ocupacoes'::regclass AND contype='x'` — têm de existir `exclude_profissional_conflito` e `exclude_recurso_conflito`.

### 7.4 Bugs apanhados pelos testes nesta ronda (corrigidos antes da entrega)

O GRAVE e o MÉDIO da auditoria (F11/F12 falhariam na v3.4.1 original); a fila engolida da F9 (F13/F14 falhariam); e, na montagem do ambiente, o `ASSERT cond, 'msg %', arg` do PL/pgSQL (a mensagem é **uma** expressão — a forma com vírgula mascarava o erro real; os 209 asserts usam `format(...)`).

## 8. Decisões de negócio pendentes (tuas há cinco versões, mantidas)

1. **Preço na avaliação** (serviços de avaliação com preço a definir na mesa).
2. **Sinal na fase de agenda vazia** (política de sinal quando a agenda ainda não tem histórico).
3. **Default do cardápio** (qual cardápio assume quando o cliente não escolhe).

## 9. Checklist de deploy (Supabase)

1. Extensões: `btree_gist`, `pgcrypto`, `uuid-ossp` (001) e **pg_cron**.
2. Aplicar migrations `001` → `012` pela ordem, depois `seed.sql` em staging. (Staging já na v3.4.1: aplicar **só** a `012`.)
3. Confirmar o cron: `SELECT jobname, schedule FROM cron.job WHERE jobname='expirar-pre-reservas';` → `*/5 * * * *`.
4. Edge Functions (contrato pronto): `mercado-pago-webhook` (verifica assinatura → `processar_pagamento_webhook` com `p_assinatura_verificada=true`); consumidor da fila `jobs` (estorno real + WhatsApp); envio do link de anamnese (token cru lido **uma vez** da resposta da RPC).
5. MFA: TOTP no Supabase Auth — o banco recusa exceção de cancelamento e decisão de revisão sem `aal2`.
6. Smoke test pós-deploy: pré-reserva → pagar fora do prazo → `pagamento_em_revisao` → `resolver_revisao(..., 'confirmar')` → cancelar → **conferir que a fila reabre com o valor pago** (cobre o GRAVE e o achado F9 num único percurso).

## 10. Ficheiros entregues

| Ficheiro | Conteúdo |
|---|---|
| `CRM_ELLA_Studio_v3.4.2.md` | Este documento |
| `supabase/migrations/001…012.sql` + `supabase/seed.sql` | Fonte da verdade (aplicar os ficheiros individuais) |
| `supabase/tests/*.sql` | 10 suítes + setup (212 asserts) |
| `CRM_ELLA_Studio_v3.4.2_migracoes.txt` | Consolidação das migrations (conveniência; em caso de dúvida manda o ficheiro individual) |
| `CRM_ELLA_Studio_v3.4.2_testes.txt` | Consolidação das suítes |

---

### Nota honesta

A v3.4.1 é o resultado de três voltas de verificação independente: a auditoria da v3.4 (6 pontos reais), a auditoria da v3.4.1 (GRAVE + MÉDIO reais, falso alarme do 001 fechado pelo próprio auditor) e as minhas provas de corrida, que apanham o que testes sequenciais não veem — foi assim que a fila engolida da F9 apareceu. Cada correção vem com regressão executável (F1–F14), e a suíte inteira correu verde num PostgreSQL real, com RLS, triggers e EXCLUDE ativos, statement a statement.
