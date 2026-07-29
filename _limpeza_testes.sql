-- _limpeza_testes.sql — limpa APENAS dados criados por testes SQL
-- NÃO toca nos dados do seed (empresa, Laira, serviços reais)
DO $$
DECLARE
    v_emp UUID := '00000000-0000-0000-0000-000000000001';
BEGIN
    -- 1) Créditos de clientes de teste
    DELETE FROM lancamentos_creditos 
    WHERE conta_id IN (
        SELECT id FROM contas_creditos 
        WHERE cliente_id LIKE 'cccccccc-0000-0000-0000-00000000000%'
    );
    DELETE FROM contas_creditos 
    WHERE cliente_id LIKE 'cccccccc-0000-0000-0000-00000000000%';

    -- 2) Revisões de reservas de teste
    DELETE FROM revisoes_cancelamento 
    WHERE reserva_id IN (
        SELECT id FROM reservas 
        WHERE idempotencia_key LIKE 'd1-%' 
           OR idempotencia_key LIKE 'd2-%' 
           OR idempotencia_key LIKE 'd3-%'
           OR idempotencia_key LIKE 'a1-%'
           OR idempotencia_key LIKE 'a2-%'
           OR idempotencia_key LIKE 'a4-%'
           OR idempotencia_key LIKE 'f%'
           OR idempotencia_key LIKE 'rev-%'
           OR idempotencia_key LIKE 'sched-%'
           OR idempotencia_key LIKE 'conc-%'
           OR idempotencia_key LIKE 'rls-%'
           OR idempotencia_key LIKE 'webhook-%'
           OR idempotencia_key LIKE 'anam-%'
           OR idempotencia_key LIKE 'chave-%'
    );

    -- 3) Eventos de pagamento de teste
    DELETE FROM eventos_pagamento 
    WHERE mp_event_id LIKE 'teste-%' 
       OR mp_event_id LIKE 'mp-%' 
       OR mp_event_id LIKE 'evt-%';

    -- 4) Webhooks de teste
    DELETE FROM webhook_inbox 
    WHERE external_event_id LIKE 'teste-%' 
       OR external_event_id LIKE 'mp-%' 
       OR external_event_id LIKE 'evt-%';

    -- 5) Alocações de transações de teste
    DELETE FROM alocacoes_pagamento 
    WHERE transacao_id IN (
        SELECT t.id FROM transacoes t 
        JOIN cobrancas c ON c.id = t.cobranca_id 
        JOIN reservas r ON r.id = c.reserva_id 
        WHERE r.idempotencia_key LIKE 'd%' 
           OR r.idempotencia_key LIKE 'a%' 
           OR r.idempotencia_key LIKE 'f%'
           OR r.idempotencia_key LIKE 'rev-%'
           OR r.idempotencia_key LIKE 'sched-%'
           OR r.idempotencia_key LIKE 'conc-%'
           OR r.idempotencia_key LIKE 'rls-%'
           OR r.idempotencia_key LIKE 'webhook-%'
           OR r.idempotencia_key LIKE 'anam-%'
           OR r.idempotencia_key LIKE 'chave-%'
    );

    -- 6) Transações de teste
    DELETE FROM transacoes 
    WHERE cobranca_id IN (
        SELECT c.id FROM cobrancas c 
        JOIN reservas r ON r.id = c.reserva_id 
        WHERE r.idempotencia_key LIKE 'd%' 
           OR r.idempotencia_key LIKE 'a%' 
           OR r.idempotencia_key LIKE 'f%'
           OR r.idempotencia_key LIKE 'rev-%'
           OR r.idempotencia_key LIKE 'sched-%'
           OR r.idempotencia_key LIKE 'conc-%'
           OR r.idempotencia_key LIKE 'rls-%'
           OR r.idempotencia_key LIKE 'webhook-%'
           OR r.idempotencia_key LIKE 'anam-%'
           OR r.idempotencia_key LIKE 'chave-%'
    );

    -- 7) Ocupações de teste
    DELETE FROM agenda_ocupacoes 
    WHERE origem_id IN (
        SELECT id FROM reservas 
        WHERE idempotencia_key LIKE 'd%' 
           OR idempotencia_key LIKE 'a%' 
           OR idempotencia_key LIKE 'f%'
           OR idempotencia_key LIKE 'rev-%'
           OR idempotencia_key LIKE 'sched-%'
           OR idempotencia_key LIKE 'conc-%'
           OR idempotencia_key LIKE 'rls-%'
           OR idempotencia_key LIKE 'webhook-%'
           OR idempotencia_key LIKE 'anam-%'
           OR idempotencia_key LIKE 'chave-%'
    );

    -- 8) Cobranças de teste
    DELETE FROM cobrancas 
    WHERE reserva_id IN (
        SELECT id FROM reservas 
        WHERE idempotencia_key LIKE 'd%' 
           OR idempotencia_key LIKE 'a%' 
           OR idempotencia_key LIKE 'f%'
           OR idempotencia_key LIKE 'rev-%'
           OR idempotencia_key LIKE 'sched-%'
           OR idempotencia_key LIKE 'conc-%'
           OR idempotencia_key LIKE 'rls-%'
           OR idempotencia_key LIKE 'webhook-%'
           OR idempotencia_key LIKE 'anam-%'
           OR idempotencia_key LIKE 'chave-%'
    );

    -- 9) Itens de reservas de teste
    DELETE FROM reserva_itens 
    WHERE reserva_id IN (
        SELECT id FROM reservas 
        WHERE idempotencia_key LIKE 'd%' 
           OR idempotencia_key LIKE 'a%' 
           OR idempotencia_key LIKE 'f%'
           OR idempotencia_key LIKE 'rev-%'
           OR idempotencia_key LIKE 'sched-%'
           OR idempotencia_key LIKE 'conc-%'
           OR idempotencia_key LIKE 'rls-%'
           OR idempotencia_key LIKE 'webhook-%'
           OR idempotencia_key LIKE 'anam-%'
           OR idempotencia_key LIKE 'chave-%'
    );

    -- 10) Reservas de teste
    DELETE FROM reservas 
    WHERE idempotencia_key LIKE 'd%' 
       OR idempotencia_key LIKE 'a%' 
       OR idempotencia_key LIKE 'f%'
       OR idempotencia_key LIKE 'rev-%'
       OR idempotencia_key LIKE 'sched-%'
       OR idempotencia_key LIKE 'conc-%'
       OR idempotencia_key LIKE 'rls-%'
       OR idempotencia_key LIKE 'webhook-%'
       OR idempotencia_key LIKE 'anam-%'
       OR idempotencia_key LIKE 'chave-%';

    -- 11) Tokens de anamnese de teste
    DELETE FROM anamnese_tokens WHERE token LIKE 'teste-%' OR reserva_id IS NULL;

    -- 12) Anamneses órfãs
    DELETE FROM anamneses WHERE reserva_item_id IS NULL;

    -- 13) Modelos de anamnese de teste
    DELETE FROM modelo_perguntas WHERE modelo_id LIKE 'bbbbbbbb%' OR modelo_id LIKE 'cccccccc%';
    DELETE FROM modelos_anamnese WHERE id LIKE 'bbbbbbbb%' OR id LIKE 'cccccccc%';

    -- 14) Exceções de calendário de teste
    DELETE FROM excecoes_calendario WHERE motivo LIKE 'Teste%';

    -- 15) Notificações de teste
    DELETE FROM notificacoes_internas 
    WHERE mensagem LIKE '%teste%' OR mensagem LIKE '%smoke%' OR (empresa_id = v_emp AND created_at > now() - interval '1 hour');

    -- 16) Serviços de teste (não os reais do seed)
    DELETE FROM profissional_servicos 
    WHERE servico_id IN (
        SELECT id FROM servicos 
        WHERE nome_tecnico LIKE 'teste_%' 
           OR nome_tecnico LIKE 'smoke_%'
    );
    DELETE FROM servicos 
    WHERE nome_tecnico LIKE 'teste_%' 
       OR nome_tecnico LIKE 'smoke_%';

    -- 17) Profissionais de teste
    DELETE FROM profissional_servicos 
    WHERE profissional_id LIKE 'dddddddd-0000-0000-0000-00000000000%' 
      AND profissional_id <> 'dddddddd-0000-0000-0000-000000000000';
    DELETE FROM horarios_profissional 
    WHERE profissional_id LIKE 'dddddddd-0000-0000-0000-00000000000%'
      AND profissional_id <> 'dddddddd-0000-0000-0000-000000000000';
    DELETE FROM profissionais 
    WHERE id LIKE 'dddddddd-0000-0000-0000-00000000000%'
      AND id <> 'dddddddd-0000-0000-0000-000000000000';

    -- 18) Clientes de teste
    DELETE FROM clientes 
    WHERE id LIKE 'cccccccc-0000-0000-0000-00000000000%'
      AND id <> 'cccccccc-0000-0000-0000-000000000199';

    RAISE NOTICE 'Limpeza de testes concluida';
END $$;
