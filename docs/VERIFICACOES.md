# VERIFICACOES.md — Observações de auditoria CRM ELLA Studio

> Este ficheiro regista observações e decisões de implementação que NÃO são bugs, mas sim escolhas conscientes com justificação documentada. Serve para evitar que auditorias futuras reabram pontos já deliberados.

---

## Observação 001 — Estado da cobrança em revisão (v3.4.3)

**Contexto:** A migration `014_auditoria2_fixes.sql` alterou `resolver_revisao` para forçar `cobrancas.estado = 'cancelada'` em TODOS os ramos (`credito`, `estorno`, `perdido`). Antes, o ramo `perdido` deixava `'sinal_pago'`.

**Decisão implementada:** Cobrança `'cancelada'` como estado terminal quando a reserva está em `pagamento_em_revisao` e a revisão é decidida.

**Observação futura (NÃO é bug):** A cobrança SÓ fica `'cancelada'` quando a reserva está em `pagamento_em_revisao`. Num cancelamento após pagamento (reserva `confirmada` → `cancelada` via `cancelar_reserva`), a cobrança mantém o estado histórico pago (`'sinal_pago'` ou `'total_pago'`). Isto é intencional: o dinheiro entrou, foi registado, e a revisão de cancelamento é que decide o destino (crédito, estorno, perdido). A cobrança em si não muda de estado — quem muda é a transação (`estornada`) ou a conta de crédito (`credito_cancelamento`).

**Refinamento futuro:** Quando existirem relatórios financeiros, avaliar se faz sentido estados terminais mais ricos para a cobrança:
- `'estornada'` — quando o estorno real foi processado pela Edge Function
- `'creditada'` — quando o valor foi convertido em crédito do cliente
- `'perdida'` — quando o estúdio ficou com o sinal (mas a cobrança em si foi paga)

Por agora, `'cancelada'` cobre todos os casos de reserva em revisão; e `'sinal_pago'`/`'total_pago'` cobrem os casos de pagamento histórico.

**Data:** 2026-07-27
**Versão:** v3.4.3
**Migration:** `014_auditoria2_fixes.sql`

---

## Observação 002 — Exceção única de edição da migration 017 (v3.4.4)

**Contexto:** A migration `017_frontend_ready.sql` foi aplicada na base linked e depois editada no repositório para trocar `array_length(v_intersecoes, 1) = 0` por `v_intersecoes = '{}'::int4range[]`.

**Decisão implementada:** A alteração foi reaplicada na base linked como exceção autorizada.

**Justificação:** A mudança era semanticamente idêntica (ambas detectam array vazio) e a migration 017 só existia em staging — ainda não tinha sido promovida a produção. A reaplicação não alterou comportamento de negócio nem quebrou a suíte: **258/258 asserts verdes**.

**Regra reforçada:** A partir desta data, TODA a migration aplicada na base linked é imutável. Qualquer correção subsequente entra obrigatoriamente como migration nova numerada sequencialmente (018, 019, ...).

**Data:** 2026-07-29
**Versão:** v3.4.4
**Migration:** `017_frontend_ready.sql`
