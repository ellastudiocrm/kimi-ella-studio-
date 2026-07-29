# DECISÕES.md — CRM ELLA Studio

> Fonte oficial de decisões de negócio. As decisões aqui registradas têm prioridade sobre qualquer comportamento default no código.

---

## Como usar este ficheiro

- Cada decisão tem: **data**, **quem decidiu**, **o quê**, **porquê**.
- Decisões não são alteradas — se mudar, adiciona-se uma nova entrada com data e versão.
- O código (migrations, RPCs, seed) reflete a decisão mais recente.

---

## Decisão 1 — Cardápio obrigatório (atualizada)

| Campo | Valor |
|---|---|
| **Data** | 2026-07-27 |
| **Quem** | Dono do estúdio (Neri / Laira) |
| **O quê** | O campo `cardápio` passa a ser **obrigatório** em `criar_pre_reserva`. Se vier vazio ou null, a RPC rejeita com mensagem clara. |
| **Porquê** | Nunca assumir um cardápio default. A atendente (Ella) pergunta sempre ao cliente. O frontend futuro também terá de perguntar. |
| **Mensagem de erro** | `"Indica o cardápio: ella_studio ou ella_men"` |
| **Valores válidos** | `'ella_studio'` (feminino), `'ella_men'` (masculino) |

**Atualização (2026-07-27, v3.4.3):** Os valores `'feminino'` e `'masculino'` foram **substituídos** por `'ella_studio'` e `'ella_men'`. O estúdio pensa em marcas — o cardápio é oficialmente a marca. O schema da tabela `servico_cardapios` foi atualizado com `CHECK (cardapio IN ('ella_studio', 'ella_men'))`.

**Nota técnica:** O fallback `COALESCE(v_item->>'cardapio', 'feminino')` foi removido. A aplicação/frontend **tem de enviar** o cardápio em cada item. Valores antigos `'feminino'`/`'masculino'` são **rejeitados** pelo banco.

---

## Decisão 2 — Sinal 30% fixo (fase inicial)

| Campo | Valor |
|---|---|
| **Data** | 2026-07-27 |
| **Quem** | Dono do estúdio |
| **O quê** | **30% de sinal fixo** sobre o valor do serviço, para todos os serviços que exijam sinal. |
| **Porquê** | Política da fase de abertura do estúdio. Simples, previsível, fácil de explicar ao cliente. |
| **Revisão** | 🔄 **Rever após 3 meses de operação** (previsto: outubro 2026) |

**Nota técnica:** O `percentual_sinal` default da tabela `reservas` continua 30. O `seed.sql` reflete explicitamente 30% nos serviços. Quando a política mudar, atualiza-se o `seed` e/ou o default da tabela.

---

## Decisão 3 — Avaliação gratuita (preço 0)

| Campo | Valor |
|---|---|
| **Data** | 2026-07-27 |
| **Quem** | Dono do estúdio |
| **O quê** | Serviços de **avaliação** têm preço 0. Quando o valor total da pré-reserva for 0, **não se gera PIX** — a reserva confirma diretamente. |
| **Porquê** | Avaliação é um serviço de triagem sem custo. O cliente não deve receber link de pagamento. |

**Nota técnica:** A lógica `IF v_sinal <= 0 THEN ... confirmada` já existia (v3.4.1, auditoria #3). O que muda é a **cobrança**: para reservas com valor 0, a cobrança é criada com valor 0 (registo interno) mas **nunca gera PIX** porque a reserva confirma imediatamente. O registo de cobrança existe para compatibilidade com relatórios futuros e com as RPCs de pagamento que esperam uma cobrança.

---

## Decisão 4 — Frontend-ready e leitura pública (v3.4.4)

| Campo | Valor |
|---|---|
| **Data** | 2026-07-29 |
| **Quem** | Dono do estúdio (Neri / Laira) |
| **O quê** | Preparar o backend para app web Next.js: catálogo público de serviços/profissionais, slots de agenda públicos, e agendamento anónimo seguro. |
| **Porquê** | A cliente escolhe serviço e horário no browser sem login; o estúdio controla tudo pelo backoffice. |

**Sub-decisões v3.4.4:**

1. **Cardápio obrigatório na RPC de slots:** `listar_horarios_disponiveis` exige cardápio ativo em `servico_cardapios`. Sem cardápio, a função retorna vazio — nunca usa preço/duração do serviço base como fallback.
2. **Agendamento anónimo via API route server-side:** `criar_pre_reserva` **nunca** ganha `GRANT` a `anon`. A página pública chama uma API route Next.js que valida os dados e invoca a RPC com `service_role`.
3. **Escrita de storage validada na API route:** buckets `servicos` e `profissionais` são públicos para leitura, mas upload/delete só acontecem via API route server-side (validação de empresa e perfil no backend), nunca diretamente pelo browser.
4. **Correção da regra de última entrada em ajustes:** horários de **ajuste** (`excecoes_calendario.tipo = 'ajuste'`) exigem que o serviço caiba **inteiro** no intervalo; a exceção de "última entrada do dia" aplica-se apenas a horários recorrentes.

---

## Decisões pendentes (registro histórico)

| # | Tema | Estado | Notas |
|---|---|---|---|
| 4 | Preço na avaliação | Pausado | Se a avaliação descobrir que o cliente precisa de tratamento, o preço é definido na mesa. Fora do MVP. |
| 5 | Cardápio default | **Resolvido** pela Decisão 1 | Não existe mais default. |
| 6 | Sinal variável por serviço | **Resolvido** pela Decisão 2 | 30% fixo por enquanto. |

---

*Última atualização: 2026-07-29 · v3.4.4*

---

## Nota técnica — 2ª auditoria (v3.4.3)

A migration `014_auditoria2_fixes.sql` corrige 5 pontos levantados numa auditoria independente:

| # | Severidade | Descrição | Fix |
|---|---|---|---|
| 2 | **GRAVE** | `confirmar_reserva`, `cancelar_reserva`, `cancelar_pre_reserva` só verificavam empresa, não perfil | Verificação de perfil: admin/gestor/recepcao tudo; profissional só com item/reserva própria |
| 3 | **MÉDIO** | `resolver_revisao` (ramo 'perdido') deixava cobrança em `'sinal_pago'` (não-terminal) | Todos os ramos de revisão forçam `'cancelada'` na cobrança |
| 4 | **MENOR** | `log_acoes_sensiveis.acao` sem `CHECK` | `CHECK (acao IN ('INSERT', 'UPDATE', 'DELETE'))` |
| 5 | **MENOR** | `submeter_anamnese` sem validação de formato | `numero` tem de ser numérico; `multipla_escolha` tem de estar nas opções |
| 7 | — | Valores do cardápio atualizados para `'ella_studio'`/`'ella_men'` | `CHECK` da tabela + migração de dados antigos |
