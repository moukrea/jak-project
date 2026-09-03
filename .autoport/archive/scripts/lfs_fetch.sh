#!/usr/bin/env bash
# lfsget.sh — recupere des fichiers LFS UN PAR UN via l'API batch, sans `git lfs`.
# `git lfs pull` se bloque indefiniment sur ce depot (file d'attente demarree, aucune sortie,
# tue par timeout). L'API repond, elle, immediatement. On l'appelle directement.
set -uo pipefail
REPO_DIR="${REPO_DIR:-$(pwd)}"
API="https://github.com/moukrea/recharged-assets.git/info/lfs/objects/batch"
TOK=$(gh auth token 2>/dev/null)
n=0
for rel in "$@"; do
  f="$REPO_DIR/$rel"
  [ -f "$f" ] || { echo "[skip] $rel absent"; continue; }
  head -1 "$f" | grep -q '^version https://git-lfs' || { echo "[deja] $rel"; continue; }
  oid=$(sed -n 's/^oid sha256://p' "$f"); sz=$(sed -n 's/^size //p' "$f")
  url=$(curl -s --max-time 60 -X POST -H "Authorization: Bearer $TOK" \
        -H "Accept: application/vnd.git-lfs+json" -H "Content-Type: application/vnd.git-lfs+json" \
        -d "{\"operation\":\"download\",\"transfers\":[\"basic\"],\"objects\":[{\"oid\":\"$oid\",\"size\":$sz}]}" \
        "$API" | python3 -c "import json,sys;d=json.load(sys.stdin);print(d['objects'][0]['actions']['download']['href'])" 2>/dev/null)
  [ -n "$url" ] || { echo "[FAIL] $rel : pas d'URL"; continue; }
  curl -s --max-time 180 -o "$f.tmp" "$url" && mv "$f.tmp" "$f" && { n=$((n+1)); echo "[ok] $rel  $(( $(stat -c%s "$f")/1024 )) Ko"; }
done
echo "recuperes: $n"
