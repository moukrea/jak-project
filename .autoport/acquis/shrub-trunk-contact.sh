#!/usr/bin/env bash
# Local source invariants only; optional device serial is intentionally ignored.
set -euo pipefail
ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)
exec python3 "$ROOT/.autoport/tests/harness/shrub_contact_local.py" "$ROOT"
