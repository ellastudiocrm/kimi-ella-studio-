-- 000_test_setup.sql — AMBIENTE LOCAL APENAS.
-- Corre ANTES das migrations num PostgreSQL sem Supabase.
-- No Supabase real NÃO correr: o schema auth, as roles e os grants já existem.
-- Todos os blocos são defensivos (IF NOT EXISTS) para nunca interferir com o Supabase.

CREATE SCHEMA IF NOT EXISTS auth;
CREATE TABLE IF NOT EXISTS auth.users (id UUID PRIMARY KEY);

DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
                   WHERE n.nspname = 'auth' AND p.proname = 'uid') THEN
        EXECUTE $f$
            CREATE FUNCTION auth.uid() RETURNS UUID
            LANGUAGE sql STABLE AS $g$
                SELECT CASE WHEN current_setting('request.jwt.claims', true) IS NULL THEN NULL
                       ELSE NULLIF(current_setting('request.jwt.claims', true)::jsonb ->> 'sub', '')::UUID END
            $g$
        $f$;
    END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
                   WHERE n.nspname = 'auth' AND p.proname = 'role') THEN
        EXECUTE $f$
            CREATE FUNCTION auth.role() RETURNS TEXT
            LANGUAGE sql STABLE AS $g$
                SELECT CASE WHEN current_setting('request.jwt.claims', true) IS NULL THEN NULL
                       ELSE NULLIF(current_setting('request.jwt.claims', true)::jsonb ->> 'role', '') END
            $g$
        $f$;
    END IF;
    -- v3.4: RPCs financeiras leem auth.jwt()->>'aal' (MFA)
    IF NOT EXISTS (SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
                   WHERE n.nspname = 'auth' AND p.proname = 'jwt') THEN
        EXECUTE $f$
            CREATE FUNCTION auth.jwt() RETURNS JSONB
            LANGUAGE sql STABLE AS $g$
                SELECT CASE WHEN current_setting('request.jwt.claims', true) IS NULL THEN NULL
                       ELSE current_setting('request.jwt.claims', true)::jsonb END
            $g$
        $f$;
    END IF;
END $$;

-- Roles do Supabase para testes locais
DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'anon') THEN CREATE ROLE anon NOLOGIN; END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'authenticated') THEN CREATE ROLE authenticated NOLOGIN; END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'service_role') THEN CREATE ROLE service_role NOLOGIN BYPASSRLS; END IF;
END $$;

GRANT USAGE ON SCHEMA public TO anon, authenticated, service_role;
GRANT USAGE ON SCHEMA auth TO anon, authenticated, service_role;

-- Replica os default privileges do Supabase (tabelas futuras acessíveis às roles)
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT SELECT, INSERT, UPDATE, DELETE ON TABLES TO anon, authenticated, service_role;
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT EXECUTE ON FUNCTIONS TO anon, authenticated, service_role;
