-- _truncate_all.sql â€” limpa dados de teste, mantem estrutura e seed base
DO $$
DECLARE
    t TEXT;
BEGIN
    FOR t IN
        SELECT tablename FROM pg_tables
        WHERE schemaname = 'public'
        AND tablename NOT IN (
            'empresas', 'tipos_recurso', 'recursos', 'profissionais',
            'horarios_empresa', 'horarios_profissional', 'servicos',
            'servico_cardapios', 'profissional_servicos', 'clientes'
        )
    LOOP
        EXECUTE 'TRUNCATE TABLE public.' || t || ' CASCADE';
    END LOOP;
END $$;
