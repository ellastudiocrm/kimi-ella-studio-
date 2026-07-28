# AUDITORIA TÉCNICA — CRM ELLA Studio v3.4.3

> Auditoria realizada após deploy no Supabase (projeto `nbmtpgjvsgxnmhylevwh`) e análise do código em `supabase/migrations/001` a `015`.
> Estado geral: **o núcleo de agenda/pagamentos continua sólido**, mas foram encontrados **problemas de segurança, inconsistências de dados e funcionalidades do briefing ainda não implementadas**.

---

## 1. Problemas críticos (resolver antes de produção)

### 1.1 `cancelar_item_reserva` permite exceção financeira SEM MFA

**Onde:** `supabase/migrations/008_booking_rpc.sql`, função `cancelar_item_reserva`.

**O problema:** Quando `p_excecao` é passado (`'credito'`, `'estorno'`, `'perdido'`), a função exige perfil `admin`, mas **não exige `aal2`**. Em `cancelar_reserva` (014) o mesmo tipo de exceção exige MFA. Um admin com sessão roubada pode mudar o destino de dinheiro de um item sem segunda etapa.

**Fix sugerido:**
```sql
IF p_excecao IS NOT NULL THEN
    ...
    IF auth.role() = 'authenticated' AND COALESCE(auth.jwt() ->> 'aal', 'aal1') <> 'aal2' THEN
        RAISE EXCEPTION 'Exceção de cancelamento exige verificação em duas etapas (MFA)';
    END IF;
    ...
END IF;
```

---

### 1.2 Valor do webhook não é validado defensivamente

**Onde:** `010_workflow_rpc.sql`, função `processar_pagamento_webhook`.

**O problema:** A função aceita `p_valor` diretamente. Não rejeita: nulo, zero, negativo, moeda inesperada, pagamento pertencente a outra conta MP, valor incompatível com o consultado na API do Mercado Pago. A segurança depende inteiramente da Edge Function externa.

**Impacto:** Se a Edge Function tiver um bug ou for enganada, o banco registra dinheiro falso.

**Fix sugerido:**
- A Edge Function deve consultar o pagamento na API oficial do MP e passar para a RPC: `mp_transaction_id`, status oficial, valor oficial, moeda, external_reference, payer, request_id.
- A RPC deve rejeitar `p_valor IS NULL OR p_valor <= 0`, e comparar com o valor esperado da cobrança.
- Adicionar `CHECK (valor > 0)` em `transacoes.valor`.

---

### 1.3 Migração 013 pode ficar com cardápio inconsistente entre ela e a 014

**Onde:** `013_decisoes_negocio.sql` e `014_auditoria2_fixes.sql`.

**O problema:** A 013 exige `cardapio IN ('ella_studio','ella_men')` na RPC, mas a tabela `servico_cardapios` só é migrada para esses valores na 014. Se alguém aplicar as migrations uma a uma e correr `criar_pre_reserva` entre a 013 e a 014, o cardápio novo não encontra preço no `servico_cardapios` (ainda tem `'feminino'`/`'masculino'`) e cai no fallback para `preco_base`. Além disso, a 013 não valida se o `cardapio` enviado é um dos dois valores válidos — valores como `'invalido'` passam silenciosamente e usam `preco_base`.

**Fix sugerido:**
- Na 013/015, adicionar validação explícita do cardápio:
  ```sql
  IF v_cardapio NOT IN ('ella_studio','ella_men') THEN
      RAISE EXCEPTION 'Cardápio inválido: % (use ella_studio ou ella_men)', v_cardapio;
  END IF;
  ```
- Considerar fundir as alterações do cardápio para uma única migration (não reordenar as existentes — criar 016).

---

### 1.4 Seed.sql não permite testar o fluxo real

**Onde:** `supabase/seed.sql`.

**O problema:** O seed só insere: empresa, tipos de recurso, recursos, profissional e horários. **Não insere serviços, cardápios, modelos de anamnese, perguntas, habilitações de profissional nem clientes.** Sem isso, `criar_pre_reserva` falha para qualquer pessoa que abra o Supabase Studio e tente testar.

**Fix sugerido:** Adicionar ao seed:
- Pelo menos 2 serviços reais (ex.: manicure, pedicure) com preços e percentual_sinal=30.
- Entradas em `servico_cardapios` para `'ella_studio'` e `'ella_men'`.
- Habilidade da Laira para esses serviços (`profissional_servicos`).
- Modelo de anamnese com 1-2 perguntas (para testar ficha).
- Cliente de exemplo.

---

## 2. Problemas médios

### 2.1 Inconsistência de percentual de sinal na reserva

**Onde:** `013_decisoes_negocio.sql`, `criar_pre_reserva`.

**O problema:** A reserva é inserida com `percentual_sinal = 30` fixo (linha 93), mas o primeiro item usa `v_servico.percentual_sinal` (linha 121) e a cobrança usa `v_pct_reserva`. Se um serviço tiver `percentual_sinal = 0`, a reserva diz 30, o item diz 0, e a cobrança diz 0. A lógica funciona para a decisão, mas os relatórios futuros ficam inconsistentes.

**Fix sugerido:** Usar `v_pct_reserva` já no `INSERT INTO reservas`, ou calcular um percentual efetivo da reserva a partir dos itens.

---

### 2.2 Classificação de finalidade no webhook pode ficar errada

**Onde:** `010_workflow_rpc.sql`, `processar_pagamento_webhook`.

**O problema:** A regra para `'saldo'` é:
```sql
WHEN EXISTS (... sinal pago ...) OR p_valor < c.valor_sinal THEN 'saldo'
```
Se o primeiro pagamento for parcial (ex.: R$ 10 de um sinal de R$ 30), ele é classificado como `'saldo'`, não `'sinal'`. Isso é confuso e pode quebrar relatórios. Se `valor_sinal = 0` e `p_valor < valor_total`, o pagamento é classificado como `'sinal'`, o que também é estranho.

**Fix sugerido:** Classificar a finalidade pelo **estado da cobrança**, não só pelo valor:
- Se ainda não existe sinal pago → `'sinal'` (mesmo que parcial).
- Se já existe sinal pago → `'saldo'`.
- Se p_valor >= valor_total e não havia sinal pago → `'pagamento_total'`.
- Se valor_sinal = 0 → usar `'pagamento_total'` ou `'saldo'`.

---

### 2.3 `templates_mensagem.segmento` e `clientes.segmento_preferido` ainda usam `'feminino'`/`'masculino'`

**Onde:** `002_core.sql` e `003_catalog.sql`.

**O problema:** A Decisão 1 migrou o cardápio para `'ella_studio'`/`'ella_men'`, mas o segmento de template e cliente continuam com os valores antigos. Pode gerar confusão na interface futura.

**Fix sugerido:** Decidir se o segmento do cliente/template também passa para `'ella_studio'`/`'ella_men'` ou se permanece como gênero. Documentar a decisão.

---

### 2.4 Tabela `alocacoes_pagamento` parece não ser usada

**Onde:** `006_payments.sql` (tabela), RPCs de pagamento.

**O problema:** A tabela existe para rastrear quanto de cada transação cobriu cada item, mas nenhuma RPC preenche registos nela. Futuros relatórios por item não terão dados.

**Fix sugerido:** Preencher `alocacoes_pagamento` em `registrar_pagamento_presencial` e `processar_pagamento_webhook`.

---

### 2.5 Fila de jobs não tem lease/heartbeat

**Onde:** `006_payments.sql` (tabela `jobs`).

**O problema:** Recomendado pela auditoria anterior e ainda pendente: falta `locked_at`, `locked_by`, `lease_expires_at`, `ultimo_erro`. Sem lease, um worker que morra durante o processamento deixa o job preso em `'processando'` para sempre.

**Fix sugerido:** Adicionar colunas e criar RPC `buscar_proximo_job(p_worker_id, p_tipos, p_limite)` com `FOR UPDATE SKIP LOCKED`.

---

### 2.6 Worker de estorno e notificações não existe

**Onde:** fora do banco (Edge Functions).

**O problema:** A decisão `'estorno'` cria um registo em `jobs` do tipo `'estorno_mercado_pago'`, mas não existe consumidor. O estúdio não tem como saber se o dinheiro realmente voltou.

**Fix sugerido:** Implementar Edge Function consumidora da fila com idempotência, retry, backoff e dead-letter.

---

## 3. Funcionalidades do briefing ainda não implementadas

### 3.1 Pagamento com crédito, voucher, pacote e cartão-presente

**Onde:** briefing menciona PIX, dinheiro, cartão, crédito, voucher, cartão presente e pacotes.

**O problema:** As `transacoes.meio` só aceitam `('pix','dinheiro','cartao_debito','cartao_credito')`. Não existe mecanismo para:
- Resgatar crédito do cliente em uma reserva.
- Usar pacotes comprados.
- Aplicar voucher/cartão-presente.

**Fix sugerido:** Criar RPCs `aplicar_credito_na_reserva`, `usar_pacote_na_reserva`, `aplicar_voucher`.

---

### 3.2 Compra de pacotes e cartões-presente

**Onde:** tabelas `compras_pacote`, `cartoes_presente`.

**O problema:** As tabelas existem, mas não há RPC para comprar um pacote ou um cartão-presente.

---

### 3.3 Painel de saúde / observabilidade

**Onde:** recomendado pela auditoria anterior.

**O problema:** Não existe view ou RPC que exponha: cron sem execução, revisões abertas antigas, webhooks rejeitados, jobs falhados, dead-letter jobs, ocupações sem reserva, etc.

---

### 3.4 LGPD operacional

**Onde:** anamneses.

**O problema:** Existe consentimento, mas falta: tempo de retenção, log de acesso à ficha, anonização, exportação dos dados do titular.

---

## 4. Problemas menores / code smell

### 4.1 `AGENTS.md` e documentação desatualizados

**Onde:** `AGENTS.md`, `CRM_ELLA_Studio_v3.4.2.md`.

**O problema:** `AGENTS.md` diz que existem 12 migrations (vai até `012_ultima_entrada.sql`), mas o projeto já tem `015_fix_cobranca_revisao.sql`. A documentação lista 10 suítes, mas existem 11.

**Fix sugerido:** Atualizar `AGENTS.md` para refletir o estado atual (migrations 001-015, 11 suítes).

---

### 4.2 `now()` vs `clock_timestamp()` no agendamento

**Onde:** `criar_pre_reserva`.

**O problema:** A validação `v_inicio <= now()` usa o início da transação. Em transações muito longas, pode permitir agendar no passado.

**Fix sugerido:** Usar `clock_timestamp()` ou `statement_timestamp()`.

---

### 4.3 `servico_cardapios` criado com valores antigos

**Onde:** `003_catalog.sql`.

**O problema:** O `CREATE TABLE` usa `CHECK (cardapio IN ('feminino','masculino'))`. A 014 corrige, mas a migration original já nasce desatualizada relativamente à Decisão 1.

**Fix sugerido:** Deixar comentário na 003 indicando que a constraint é atualizada na 014, ou alterar o `CREATE TABLE` se ainda for seguro (não reordenar migrations; apenas documentar).

---

## 5. Checklist de correção recomendada

### Antes de qualquer produção real:
- [ ] 1.1 — MFA em `cancelar_item_reserva` com exceção.
- [ ] 1.2 — Validação defensiva do valor/moeda no webhook.
- [ ] 1.3 — Validação explícita de cardápio e seed completo.
- [ ] 2.1 — Consistência de `percentual_sinal` na reserva.
- [ ] 2.2 — Regras de finalidade no webhook.
- [ ] 2.5 — Lease na fila de jobs.
- [ ] 2.6 — Worker de estorno/notificações.
- [ ] 3.1 — Pagamento com crédito/pacote/voucher.
- [ ] 3.3 — Painel de saúde básico.

### Imediato (qualidade do repo):
- [ ] 1.4 — Seed completo para permitir testes de ponta a ponta.
- [ ] 4.1 — Atualizar `AGENTS.md` e documentação.
- [ ] 4.2 — `clock_timestamp()` no agendamento.

---

## 6. Veredito

O banco continua tecnicamente robusto na agenda e nos pagamentos simples. Os problemas encontrados agora são, na sua maioria, **falta de funcionalidade do briefing** (créditos, pacotes, vouchers) e **pequenas inconsistências de segurança/dados** que não travam o staging mas impediriam a produção real.

**Nota:** 7,5/10 (descida de 8,8/10 da auditoria anterior por causa das funcionalidades não implementadas e do seed incompleto).
