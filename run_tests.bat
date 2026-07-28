@echo off
cd /d C:\Users\ricar\Documents\crm-ella
supabase-cli\supabase.exe db query --linked -f supabase\tests\decisoes_test.sql > tests_result.txt 2>&1
echo --- >> tests_result.txt
supabase-cli\supabase.exe db query --linked -f supabase\tests\auditoria2_test.sql >> tests_result.txt 2>&1
echo DONE >> tests_result.txt
