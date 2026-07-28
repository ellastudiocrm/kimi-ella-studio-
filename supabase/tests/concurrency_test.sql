-- concurrency_test.sql — prova de que pagamento e cron NÃO disputam a mesma reserva (Ricardo #4)
--
-- Este ficheiro descreve o teste de DUAS SESSÕES. Correr com dois psql em paralelo,
-- ou com o orquestrador Python (ver resultados no documento v3.3 — foi executado
-- contra PostgreSQL 15.10 real).
--
-- Cenário: reserva PAGA com ocupações vencidas.
--   Sessão A (confirmação): bloqueia a reserva FOR UPDATE (como confirmar_reserva faz).
--   Sessão B (cron):        expirar_pre_reservas() tenta bloquear a MESMA linha.
-- Prova: B fica à espera de A; quando A termina, B vê o pagamento e NÃO cancela.
--
-- Preparação (qualquer sessão):

SET TIME ZONE 'America/Sao_Paulo';

CREATE OR REPLACE FUNCTION teste_proximo_dia(dow INT, hora TEXT) RETURNS TIMESTAMPTZ
LANGUAGE sql STABLE AS $$
    SELECT ((CURRENT_DATE + ((dow - EXTRACT(DOW FROM CURRENT_DATE)::INT + 7) % 7 + 7))::TEXT || ' ' || hora)::TIMESTAMPTZ
$$;

INSERT INTO servicos (id, empresa_id, nome_tecnico, tipo_recurso_id, duracao_minutos, preco_base, anamnese_obrigatoria) VALUES
('aaaaaaaa-0000-0000-0000-000000000031', '00000000-0000-0000-0000-000000000001', 'teste_concorrencia', '11111111-1111-1111-1111-111111111111', 60, 100.00, false)
ON CONFLICT (empresa_id, nome_tecnico) DO NOTHING;
INSERT INTO profissional_servicos (profissional_id, servico_id, empresa_id) VALUES
('33333333-3333-3333-3333-333333333333', 'aaaaaaaa-0000-0000-0000-000000000031', '00000000-0000-0000-0000-000000000001')
ON CONFLICT DO NOTHING;

DO $$
DECLARE v UUID;
BEGIN
    v := (public.criar_pre_reserva('00000000-0000-0000-0000-000000000001',
        'cccccccc-0000-0000-0000-000000000011',
        jsonb_build_array(jsonb_build_object('servico_id','aaaaaaaa-0000-0000-0000-000000000031',
            'profissional_id','33333333-3333-3333-3333-333333333333',
            'cardapio','ella_studio',
            'inicio', teste_proximo_dia(4,'11:00'))), 'conc-t1')) ->> 'reserva_id';
    -- paga o sinal
    INSERT INTO transacoes (cobranca_id, empresa_id, mp_idempotency_key, valor, meio, finalidade, estado)
    SELECT c.id, c.empresa_id, 'conc-' || gen_random_uuid()::TEXT, 30.00, 'pix', 'sinal', 'pago'
    FROM cobrancas c WHERE c.reserva_id = v;
    -- vence as ocupações (cron ainda não correu)
    UPDATE agenda_ocupacoes SET expires_at = now() - interval '1 minute'
    WHERE origem = 'pre_reserva' AND origem_id = v;
    RAISE NOTICE 'RESERVA DO TESTE DE CONCORRÊNCIA: %', v;
END $$;

-- =======================  SESSÃO A (numa janela psql)  =======================
-- BEGIN;
-- SELECT id FROM reservas WHERE id = '<RESERVA>' FOR UPDATE;
-- SELECT pg_sleep(5);            -- segura o lock 5 segundos
-- COMMIT;
--
-- =======================  SESSÃO B (outra janela, 1s depois)  ==============
-- SELECT expirar_pre_reservas();  -- TEM DE ESPERAR pela Sessão A
-- SELECT estado FROM reservas WHERE id = '<RESERVA>';
-- -- resultado esperado: 'pre_reserva' (NÃO cancelada — está paga)
--
-- Veredito: se B terminou ANTES de A sem esperar, ou se a reserva ficou
-- 'cancelada', o teste FALHOU e a corrida existe.
