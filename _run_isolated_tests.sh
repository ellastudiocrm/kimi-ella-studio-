#!/bin/bash
set -e

SUPABASE="C:/Users/ricar/Documents/crm-ella/supabase-cli/supabase.exe"
WORKDIR="C:/Users/ricar/Documents/crm-ella"
TRUNCATE="C:/Users/ricar/Documents/crm-ella/_truncate_all.sql"
SEED="C:/Users/ricar/Documents/crm-ella/supabase/seed.sql"

TESTS=(
    schedule_test.sql
    payment_race_test.sql
    rls_test.sql
    anamnesis_token_test.sql
    webhook_flow_test.sql
    review_flow_test.sql
    anamnese_submit_test.sql
    bloqueio_flow_test.sql
    concurrency_test.sql
    v341_fixes_test.sql
    decisoes_test.sql
    auditoria2_test.sql
)

for test in "${TESTS[@]}"; do
    echo "=== ISOLATED: $test ==="
    "$SUPABASE" db query --linked -f "$TRUNCATE" --workdir "$WORKDIR" >/dev/null 2>&1
    "$SUPABASE" db query --linked -f "$SEED" --workdir "$WORKDIR" >/dev/null 2>&1
    if "$SUPABASE" db query --linked -f "$WORKDIR/supabase/tests/$test" --workdir "$WORKDIR" >/dev/null 2>&1; then
        echo "PASS"
    else
        echo "FAIL"
    fi
done
