#!/usr/bin/env bash
# Le critere moteur reste shrub_trunk_anchor_defects ; ce crochet exerce la garde locale.
set -uo pipefail
cd "$(git rev-parse --show-toplevel)" || exit 1
D=${AUTOPORT_CENSUS_DIR:-.autoport/reports/acquis-shrub-trunk-contact}
mkdir -p "$D/notes" "$HOME/.autoport-tmp" || exit 1
export TMPDIR="${TMPDIR:-$HOME/.autoport-tmp}"
bash .autoport/acquis/shrub-trunk-contact.sh > "$D/notes/local-guard.log" 2>&1
guard_rc=$?
cat "$D/notes/local-guard.log" >&2
# Dependances Python explicites pour l'empreinte du verdict.
for source in .autoport/tests/harness/conftest.py .autoport/tests/harness/bench_env.py \
    .autoport/tests/harness/shrub_contact_contract_fixture.py; do
  [ -f "$source" ] || exit 1
done
python3 -m pytest .autoport/tests/harness/test_acquis_shrub_trunk_contact.py \
    -q -s -p no:cacheprovider > "$D/notes/local-tests.log" 2>&1
tests_rc=$?
cat "$D/notes/local-tests.log" >&2
printf 'shrub_local_guard_rc=%s\nshrub_local_tests_rc=%s\n' "$guard_rc" "$tests_rc"
[ "$guard_rc" = 0 ] && [ "$tests_rc" = 0 ]
