#!/usr/bin/env bash
# This census writes only stdout; proof_run.sh alone composes proof.txt.
set -euo pipefail
cd "$(git rev-parse --show-toplevel)"
python3 .autoport/lib/build_leftovers_checks.py
