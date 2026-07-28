# Script PowerShell: gerar master_staging_tests.sql
# Suítes 7-11 para correr no staging de uma vez

$basePath = "C:\Users\ricar\Documents\crm-ella\supabase\tests"
$outputFile = "$basePath\master_staging_tests.sql"

# Cabeçalho
@"
-- =========================================================
-- MASTER: Suítes 7-11 (v3.4.3 staging)
-- Gerado automaticamente — não editar diretamente
-- =========================================================
-- Suíte 7: anamnese_submit_test  (17 asserts, S1-S7)
-- Suíte 8: bloqueio_flow_test    (13 asserts, B1-B4)
-- Suíte 9: v341_fixes_test       (57 asserts, F1-F14)
-- Suíte 10: decisoes_test        (8 asserts, D1-D3)
-- Suíte 11: auditoria2_test      (14 asserts, A1-A7)
-- TOTAL ESPERADO: 109 asserts
-- =========================================================

"@ | Set-Content -Path $outputFile -Encoding UTF8

# Lista de ficheiros na ordem correta
$files = @(
    "anamnese_submit_test.sql",
    "bloqueio_flow_test.sql",
    "v341_fixes_test.sql",
    "decisoes_test.sql",
    "auditoria2_test.sql"
)

$suiteNum = 7
foreach ($file in $files) {
    $filepath = Join-Path $basePath $file
    if (Test-Path $filepath) {
        Add-Content -Path $outputFile -Value "`n-- =========================================================" -Encoding UTF8
        Add-Content -Path $outputFile -Value "-- SUÍTE $suiteNum`: $file" -Encoding UTF8
        Add-Content -Path $outputFile -Value "-- =========================================================`n" -Encoding UTF8
        Get-Content -Path $filepath -Raw | Add-Content -Path $outputFile -Encoding UTF8
        Write-Host "[OK] Adicionado: $file" -ForegroundColor Green
    } else {
        Write-Host "[ERRO] NAO ENCONTRADO: $file" -ForegroundColor Red
    }
    $suiteNum++
}

# Rodapé
Add-Content -Path $outputFile -Value "`n-- =========================================================" -Encoding UTF8
Add-Content -Path $outputFile -Value "-- FIM DAS SUÍTES 7-11" -Encoding UTF8
Add-Content -Path $outputFile -Value "-- =========================================================" -Encoding UTF8

# Estatísticas
$lines = (Get-Content $outputFile | Measure-Object).Count
Write-Host "`nFicheiro criado: $outputFile" -ForegroundColor Cyan
Write-Host "Total de linhas: $lines" -ForegroundColor Cyan
Write-Host "`nProximo passo: Abre o ficheiro, copia TUDO (Ctrl+A, Ctrl+C)," -ForegroundColor Yellow
Write-Host "   cola no SQL Editor do staging e clica RUN." -ForegroundColor Yellow
