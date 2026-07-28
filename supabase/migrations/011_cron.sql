-- 011_cron.sql — agendamento REAL da expiração de pré-reservas (a cada 5 min)
-- pg_cron só existe no Supabase gerido; em ambiente local esta migration é um no-op seguro.

DO $$
BEGIN
    IF EXISTS (SELECT 1 FROM pg_available_extensions WHERE name = 'pg_cron') THEN
        CREATE EXTENSION IF NOT EXISTS pg_cron;

        -- Idempotente: re-agendar não duplica o job
        IF EXISTS (SELECT 1 FROM cron.job WHERE jobname = 'expirar-pre-reservas') THEN
            PERFORM cron.unschedule('expirar-pre-reservas');
        END IF;

        PERFORM cron.schedule(
            'expirar-pre-reservas',
            '*/5 * * * *',
            $cmd$SELECT public.expirar_pre_reservas();$cmd$
        );
    ELSE
        RAISE NOTICE 'pg_cron indisponível neste ambiente — no Supabase: Database → Extensions → pg_cron, depois rode esta migration';
    END IF;
EXCEPTION WHEN OTHERS THEN
    -- pg_cron instalado mas sem permissão de agendar (ex.: role não-superuser):
    -- a migration não pode falhar por causa do agendamento
    RAISE NOTICE 'Não foi possível agendar o cron (%). Agende manualmente: SELECT cron.schedule(''expirar-pre-reservas'', ''*/5 * * * *'', $cmd$SELECT public.expirar_pre_reservas();$cmd$);', SQLERRM;
END $$;

-- Conferir depois de aplicar:
--   SELECT jobid, jobname, schedule, command FROM cron.job WHERE jobname = 'expirar-pre-reservas';
-- Histórico de execuções:
--   SELECT * FROM cron.job_run_details WHERE jobid = (SELECT jobid FROM cron.job WHERE jobname = 'expirar-pre-reservas') ORDER BY start_time DESC LIMIT 10;
