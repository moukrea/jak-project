#!/usr/bin/env bash
# Recensement de l'etude « dosage de modeles et d'efforts ».
#
# ETUDE DU HARNAIS, PAS DU JEU : il n'y a aucun site dans le moteur, donc
# `proof_feature_own_hits` vaudra zero et c'est normal. Ce crochet EST l'instrument :
# il relit nos 1064 journaux d'essai et publie des grandeurs, pas des opinions.
#
# POLARITE : si une des deux etapes echoue, on sort non nul SANS publier. Le validateur
# sera rouge parce que `model_mix_defects` manquera. On ne fabrique jamais la cle.
set -euo pipefail

AP="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
ITEM="owner-se-renseigner-sur-le-combo-le-plus-efficient-tou"
MEAS="$AP/reports/$ITEM/measures"
mkdir -p "$MEAS" "$AP/reports/$ITEM/notes"

# Les deux entrees du jugement (recherche externe + rapport) sont VERSIONNEES a cote du
# script, parce que `.autoport/reports/` est gitignore : sans ca, la porte serait verte
# ici et rouge dans un arbre neuf, en accusant un innocent. On en depose une copie dans
# `reports/` parce que c'est la que l'item a promis a l'owner de les trouver.
cp -f "$AP/lib/census/model-mix/RAPPORT.md"  "$AP/reports/$ITEM/RAPPORT.md"
cp -f "$AP/lib/census/model-mix/sources.json" "$AP/reports/$ITEM/sources.json"
cp -f "$AP/lib/census/model-mix/notes/recherche-externe.md" \
      "$AP/reports/$ITEM/notes/recherche-externe.md"

# 1. MESURER — relit logs/<item>/attempt-*.jsonl[.gz], les verdicts, et les
#    transcriptions du superviseur. Ecrit digest.json + supervisor-timeline.json.
#    Sa sortie de progres va sur stderr : stdout est reserve aux cles.
python3 "$AP/lib/census/model-mix/collect.py" "$MEAS" >&2

# 2. JUGER — relit le digest, sources.json (recherche externe), model-profiles.json et
#    RAPPORT.md, puis publie `model_mix_defects` et le detail terme par terme.
python3 "$AP/lib/census/model-mix/gate.py"
