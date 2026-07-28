# Script PowerShell para descarregar e instalar Supabase CLI
$targetDir = "C:\Users\ricar\Documents\crm-ella\supabase-cli"
$tarFile = "$targetDir\supabase-cli.tar.gz"

# Criar pasta
New-Item -ItemType Directory -Force -Path $targetDir | Out-Null

# Descarregar
Write-Host "A descarregar Supabase CLI..."
Invoke-WebRequest -Uri "https://github.com/supabase/cli/releases/download/v2.110.0/supabase_2.110.0_windows_amd64.tar.gz" -OutFile $tarFile -UseBasicParsing

# Extrair (tar disponível no Git Bash)
Write-Host "A extrair..."
$env:Path += ";C:\Program Files\Git\usr\bin"
tar -xzf $tarFile -C $targetDir

# Verificar
$supabaseExe = "$targetDir\supabase.exe"
if (Test-Path $supabaseExe) {
    & $supabaseExe --version
    Write-Host ""
    Write-Host "=== SUPABASE CLI INSTALADA ===" -ForegroundColor Green
    Write-Host "Caminho: $supabaseExe"
    Write-Host ""
    Write-Host "Para usar em qualquer lado, adiciona ao PATH:"
    Write-Host "   [Environment]::SetEnvironmentVariable('Path', `$env:Path + ';$targetDir', 'User')"
} else {
    Write-Host "ERRO: supabase.exe nao encontrado apos extracao" -ForegroundColor Red
}
