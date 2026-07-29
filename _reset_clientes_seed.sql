-- _reset_clientes_seed.sql — trunca clientes (e dependentes) e re-insere o seed base
TRUNCATE TABLE public.clientes CASCADE;

INSERT INTO public.clientes (id, empresa_id, nome, telefone_normalizado) VALUES
('cccccccc-0000-0000-0000-000000000199', '00000000-0000-0000-0000-000000000001', 'Maria Exemplo', '5519999999999')
ON CONFLICT (id) DO NOTHING;
