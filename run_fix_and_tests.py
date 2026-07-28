import subprocess, sys, os

os.chdir(r'C:\Users\ricar\Documents\crm-ella')
supabase = r'C:\Users\ricar\Documents\crm-ella\supabase-cli\supabase.exe'

# 1. Aplicar migration 015
print("Aplicando migration 015...")
cmd = [supabase, 'db', 'query', '--linked', '-f', 'supabase/migrations/015_fix_cobranca_revisao.sql']
result = subprocess.run(cmd, capture_output=True, text=True, timeout=120)
if result.returncode == 0:
    print("  Migration 015: APLICADA")
else:
    print(f"  Migration 015: FALHOU - {result.stderr[:300]}")
    sys.exit(1)

# 2. Correr suítes 10 e 11
for test_file, label in [('decisoes_test.sql', 'Suíte 10'), ('auditoria2_test.sql', 'Suíte 11')]:
    print(f"Correndo {label}...")
    cmd = [supabase, 'db', 'query', '--linked', '-f', f'supabase/tests/{test_file}']
    result = subprocess.run(cmd, capture_output=True, text=True, timeout=120)
    if result.returncode == 0:
        print(f"  {label}: PASS")
    else:
        print(f"  {label}: FAIL")
        print(f"  Erro: {result.stderr[:500]}")

print("\n=== DONE ===")
