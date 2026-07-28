import subprocess, sys, os

os.chdir(r'C:\Users\ricar\Documents\crm-ella')
supabase = r'C:\Users\ricar\Documents\crm-ella\supabase-cli\supabase.exe'

tests = [
    ('decisoes_test.sql', 'Suíte 10: decisoes_test'),
    ('auditoria2_test.sql', 'Suíte 11: auditoria2_test'),
]

results = []
for test_file, label in tests:
    print(f'Correndo {label}...')
    cmd = [supabase, 'db', 'query', '--linked', '-f', f'supabase/tests/{test_file}']
    try:
        result = subprocess.run(cmd, capture_output=True, text=True, timeout=120)
        if result.returncode == 0:
            results.append(f'{label}: PASS')
            print(f'  {label}: PASS')
        else:
            results.append(f'{label}: FAIL')
            print(f'  {label}: FAIL')
            print(f'  stderr: {result.stderr[:500]}')
    except subprocess.TimeoutExpired:
        results.append(f'{label}: TIMEOUT')
        print(f'  {label}: TIMEOUT')
    except Exception as e:
        results.append(f'{label}: ERROR {e}')
        print(f'  {label}: ERROR {e}')

with open('tests_result.txt', 'w') as f:
    f.write('\n'.join(results))

print('\n=== RESUMO ===')
for r in results:
    print(r)
print(f'Resultados guardados em: C:\\Users\\ricar\\Documents\\crm-ella\\tests_result.txt')
