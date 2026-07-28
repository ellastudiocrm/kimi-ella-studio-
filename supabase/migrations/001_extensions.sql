-- 001_extensions.sql — extensões e configuração base
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";
CREATE EXTENSION IF NOT EXISTS "btree_gist";   -- EXCLUDE com UUID e int4
CREATE EXTENSION IF NOT EXISTS "pgcrypto";     -- gen_random_bytes + digest (tokens)

ALTER DATABASE postgres SET timezone TO 'America/Sao_Paulo';
SET TIME ZONE 'America/Sao_Paulo';

-- Wrappers determinísticos de cripto — as RPCs correm com search_path='' (anti-hijack)
-- e chamam SEMPRE estes wrappers do nosso schema, nunca as funções da extensão diretamente.
-- (a extensão pode viver em public ou em extensions, conforme o ambiente Supabase)
CREATE OR REPLACE FUNCTION public.gerar_token_opaco()
RETURNS TEXT
LANGUAGE sql VOLATILE SET search_path = public, extensions AS $$
    SELECT encode(gen_random_bytes(32), 'hex');
$$;

CREATE OR REPLACE FUNCTION public.sha256_hex(valor TEXT)
RETURNS TEXT
LANGUAGE sql IMMUTABLE SET search_path = public, extensions AS $$
    SELECT encode(digest(valor, 'sha256'), 'hex');
$$;
