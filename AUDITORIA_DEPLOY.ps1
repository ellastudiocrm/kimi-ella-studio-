# AUDITORIA_DEPLOY.ps1 — Script de auditoria do CRM ELLA Studio v3.4.3
# EXECUTAR NO POWERSHELL
# Este script NAO abre o SQL Editor — tudo via Supabase CLI

$ErrorActionPreference = "Stop"
$Projeto = "C:\Users\ricar\Documents\crm-ella"
$SupabaseCLI = "$Projeto\supabase-cli\supabase.exe"

Write-Host "==========================================" -ForegroundColor Cyan
Write-Host "AUDITORIA CRM ELLA Studio v3.4.3" -ForegroundColor Cyan
Write-Host "==========================================" -ForegroundColor Cyan

# ==========================================
# PASSO 0 — Verificar CLI
# ==========================================
Write-Host "`n[PASSO 0] Verificando Supabase CLI..." -ForegroundColor Yellow
if (-not (Test-Path $SupabaseCLI)) {
    Write-Error "Supabase CLI nao encontrado em: $SupabaseCLI"
    exit 1
}
& $SupabaseCLI --version
if ($LASTEXITCODE -ne 0) {
    Write-Error "CLI nao responde."
    exit 1
}

Set-Location $Projeto

# ==========================================
# PASSO 1 — Criar _truncate_all.sql
# ==========================================
Write-Host "`n[PASSO 1] Criando _truncate_all.sql..." -ForegroundColor Yellow
$truncateSql = @'
-- _truncate_all.sql — limpa dados de teste, mantem estrutura e seed base
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
'@
Set-Content "$Projeto\_truncate_all.sql" $truncateSql -Encoding UTF8
Write-Host "OK _truncate_all.sql criado" -ForegroundColor Green

# ==========================================
# PASSO 2 — Aplicar truncamento no staging
# ==========================================
Write-Host "`n[PASSO 2] Limpando dados de testes anteriores..." -ForegroundColor Yellow
& $SupabaseCLI db query --linked --file "$Projeto\_truncate_all.sql"
if ($LASTEXITCODE -eq 0) {
    Write-Host "OK Limpeza aplicada" -ForegroundColor Green
} else {
    Write-Host "ERRO na limpeza" -ForegroundColor Red
    exit 1
}

# ==========================================
# PASSO 3 — Correr decisoes_test.sql
# ==========================================
Write-Host "`n[PASSO 3] Correndo decisoes_test.sql..." -ForegroundColor Yellow
& $SupabaseCLI db query --linked --file "$Projeto\supabase\tests\decisoes_test.sql"
if ($LASTEXITCODE -eq 0) {
    Write-Host "OK decisoes_test.sql PASSOU" -ForegroundColor Green
} else {
    Write-Host "ERRO decisoes_test.sql FALHOU" -ForegroundColor Red
    exit 1
}

# ==========================================
# PASSO 4 — Correr v341_fixes_test.sql
# ==========================================
Write-Host "`n[PASSO 4] Correndo v341_fixes_test.sql..." -ForegroundColor Yellow
& $SupabaseCLI db query --linked --file "$Projeto\supabase\tests\v341_fixes_test.sql"
if ($LASTEXITCODE -eq 0) {
    Write-Host "OK v341_fixes_test.sql PASSOU" -ForegroundColor Green
} else {
    Write-Host "ERRO v341_fixes_test.sql FALHOU" -ForegroundColor Red
    exit 1
}

# ==========================================
# PASSO 5 — Verificacao final no banco
# ==========================================
Write-Host "`n[PASSO 5] Verificacao final no banco..." -ForegroundColor Yellow

$verificacaoSql = @'
SELECT 'expirar-pre-reservas' as check_item,
       CASE WHEN COUNT(*) > 0 THEN 'OK' ELSE 'FALHA' END as estado
FROM cron.job WHERE jobname = 'expirar-pre-reservas'
UNION ALL
SELECT 'total_tabelas', COUNT(*)::text
FROM pg_tables WHERE schemaname = 'public'
UNION ALL
SELECT 'total_policies', COUNT(*)::text
FROM pg_policies WHERE schemaname = 'public'
UNION ALL
SELECT 'constraints_exclude', COUNT(*)::text
FROM pg_constraint WHERE contype = 'x'
UNION ALL
SELECT 'reservas_teste_decisoes', COUNT(*)::text
FROM reservas WHERE idempotencia_key LIKE 'd%'
UNION ALL
SELECT 'reservas_teste_v341', COUNT(*)::text
FROM reservas WHERE idempotencia_key LIKE 'f%'
UNION ALL
SELECT 'funcoes_teste_no_schema', COUNT(*)::text
FROM pg_proc WHERE proname LIKE 'teste_%' AND pronamespace = 'public'::regnamespace;
'@
$verificacaoPath = "$Projeto\_verificacao_final.sql"
Set-Content $verificacaoPath $verificacaoSql -Encoding UTF8

& $SupabaseCLI db query --linked --file $verificacaoPath
Remove-Item $verificacaoPath -Force

# ==========================================
# RESUMO FINAL
# ==========================================
Write-Host "`n==========================================" -ForegroundColor Cyan
Write-Host "AUDITORIA CONCLUIDA" -ForegroundColor Cyan
Write-Host "==========================================" -ForegroundColor Cyan
Write-Host "Passos executados:" -ForegroundColor Green
Write-Host "   1. _truncate_all.sql criado"
Write-Host "   2. Limpeza de testes aplicada"
Write-Host "   3. decisoes_test.sql - PASSOU"
Write-Host "   4. v341_fixes_test.sql - PASSOU"
Write-Host "   5. Verificacao final no banco"
Write-Host "`nSe ambos os testes passaram, o backend esta PRONTO." -ForegroundColor Green
