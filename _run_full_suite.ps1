# _run_full_suite.ps1 - corre suite completa de testes CRM ELLA v3.4.4 com isolamento total
$ErrorActionPreference = "Stop"
$Projeto = "C:\Users\ricar\Documents\crm-ella"
$SupabaseCLI = "$Projeto\supabase-cli\supabase.exe"

Set-Location $Projeto

function Reset-TestData {
    & $SupabaseCLI db query --linked --file "$Projeto\_truncate_all.sql"
    if ($LASTEXITCODE -ne 0) { throw "Falha no truncate_all" }
    & $SupabaseCLI db query --linked --file "$Projeto\_reset_clientes_seed.sql"
    if ($LASTEXITCODE -ne 0) { throw "Falha no reset de clientes" }
}

# Lista de testes (exceto 000_test_setup.sql que e so para local)
$testes = @(
    "anamnese_submit_test.sql",
    "anamnesis_token_test.sql",
    "auditoria2_test.sql",
    "bloqueio_flow_test.sql",
    "concurrency_test.sql",
    "decisoes_test.sql",
    "frontend_ready_test.sql",
    "payment_race_test.sql",
    "review_flow_test.sql",
    "rls_test.sql",
    "schedule_test.sql",
    "v341_fixes_test.sql",
    "webhook_flow_test.sql"
)

$passaram = 0
$falharam = 0
$resultados = @()

foreach ($teste in $testes) {
    $caminho = "$Projeto\supabase\tests\$teste"
    Write-Host "`n[RESET] $teste ..." -ForegroundColor DarkGray
    Reset-TestData

    Write-Host "[TESTE] $teste ..." -ForegroundColor Yellow
    try {
        & $SupabaseCLI db query --linked --file $caminho
        if ($LASTEXITCODE -eq 0) {
            Write-Host "OK $teste PASSOU" -ForegroundColor Green
            $passaram++
            $resultados += [PSCustomObject]@{ Suite = $teste; Estado = "PASSOU" }
        } else {
            Write-Host "ERRO $teste FALHOU (exit $LASTEXITCODE)" -ForegroundColor Red
            $falharam++
            $resultados += [PSCustomObject]@{ Suite = $teste; Estado = "FALHOU" }
        }
    } catch {
        Write-Host "ERRO $teste FALHOU: $_" -ForegroundColor Red
        $falharam++
        $resultados += [PSCustomObject]@{ Suite = $teste; Estado = "FALHOU" }
    }
}

# Limpeza depois
Write-Host "`n[LIMPEZA FINAL] ..." -ForegroundColor Yellow
Reset-TestData

# Resumo
Write-Host "`n==========================================" -ForegroundColor Cyan
Write-Host "RESUMO DA SUITE COMPLETA" -ForegroundColor Cyan
Write-Host "==========================================" -ForegroundColor Cyan
$resultados | Format-Table -AutoSize
$cor = if ($falharam -eq 0) { "Green" } else { "Red" }
Write-Host "Total: $($testes.Count) | Passaram: $passaram | Falharam: $falharam" -ForegroundColor $cor

if ($falharam -gt 0) { exit 1 }
