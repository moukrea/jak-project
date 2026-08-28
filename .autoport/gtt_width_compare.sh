#!/usr/bin/env bash
# Phase Gtext-tone — largeur RENDUE, AVANT contre APRES, sur les OCTETS QUI PARTENT.
#
# Le contrat de phase demande : « Aucun depassement de boite : les nouvelles formulations sont
# plus courtes ou egales ». C'est un critere de DELTA, et c'est le bon : si aucune chaine n'est
# plus large qu'avant, aucune boite qui tenait ne peut deborder. Il ne demande pas de modeliser
# les 14 boites du jeu, il demande de ne rien elargir.
#
# METHODE — on ne mesure JAMAIS le JSON, on mesure la banque construite :
#   1. on met de cote les 3 fichiers de texte modifies, on reconstruit -> banques AVANT
#   2. on sonde les ids concernes (.autoport/gtt_bank_probe.py reproduit get-string-length)
#   3. on remet les fichiers, on reconstruit -> banques APRES
#   4. on sonde les memes ids, et on publie le delta
#
# La reconstruction est deterministe (verifiee : 3 constructions, 1 seul md5), donc l'aller-retour
# rend bien la banque de depart au bit pres — le script le VERIFIE et s'arrete sinon.
set -uo pipefail
cd "$(git rev-parse --show-toplevel)"

GOALC=build/goalc/goalc
OUT=${1:-.autoport/reports/Gtext-tone/width-compare.txt}
FILES="game/assets/jak1/text/game_custom_text_fr-FR.json
game/assets/jak1/text/game_custom_text_de-DE.json
game/assets/jak1/text/game_custom_text_android_fr-FR.json"

fail(){ echo "[width] FATAL: $*" >&2; exit 1; }

# UN SEUL ECRIVAIN : l'auto-constructeur reecrit out/jak1/iso/*COMMON.TXT. Une mesure prise
# pendant son ecriture n'est pas une mesure. On refuse de commencer s'il tourne.
if pgrep -f "build_arm64_full_consistent|gtt_build_android_text" >/dev/null; then
  fail "un constructeur ecrit dans out/jak1/iso — mesure refusee (regle: pgrep avant d'y croire)"
fi

[ -x "$GOALC" ] || fail "no $GOALC"
build_banks(){ "$GOALC" --user-auto --game jak1 --disable-ansi -c '(make "out/jak1/iso/0COMMON.TXT" :force #t)' >/dev/null 2>&1 || fail "build banks"; }

IDS_FR=113,134,135,138,140,141,143,158,15a,15b,161,163,16b,16d,16e,100d,103f
IDS_DE=113,169,16e

STASH=$(mktemp -d)
for f in $FILES; do cp -f "$f" "$STASH/$(basename "$f")"; done
trap 'for f in $FILES; do cp -f "$STASH/$(basename "$f")" "$f"; done; rm -rf "$STASH"' EXIT

echo "[width] === 1/4 etat AVANT (fichiers de texte remis a HEAD) ==="
for f in $FILES; do git show "HEAD:$f" > "$f" || fail "git show $f"; done
build_banks
MD5_BEFORE_FR=$(md5sum out/jak1/iso/1COMMON.TXT | cut -d' ' -f1)
python3 .autoport/gtt_bank_probe.py out/jak1/iso/1COMMON.TXT --ids "$IDS_FR" > "$STASH/before-fr.txt"
python3 .autoport/gtt_bank_probe.py out/jak1/iso/2COMMON.TXT --ids "$IDS_DE" > "$STASH/before-de.txt"
python3 .autoport/gtt_bank_probe.py out/jak1-android-text/1COMMON.TXT --ids 16e > "$STASH/before-android-fr.txt"
python3 .autoport/gtt_bank_probe.py out/jak1-android-text/0COMMON.TXT --ids 16e > "$STASH/before-android-en.txt"

echo "[width] === 2/4 etat APRES (fichiers de travail restaures) ==="
for f in $FILES; do cp -f "$STASH/$(basename "$f")" "$f"; done
build_banks
python3 .autoport/gtt_bank_probe.py out/jak1/iso/1COMMON.TXT --ids "$IDS_FR" > "$STASH/after-fr.txt"
python3 .autoport/gtt_bank_probe.py out/jak1/iso/2COMMON.TXT --ids "$IDS_DE" > "$STASH/after-de.txt"

echo "[width] === 3/4 controle d'aller-retour : la banque AVANT doit se reproduire au bit ==="
for f in $FILES; do git show "HEAD:$f" > "$f"; done
build_banks
MD5_AGAIN_FR=$(md5sum out/jak1/iso/1COMMON.TXT | cut -d' ' -f1)
for f in $FILES; do cp -f "$STASH/$(basename "$f")" "$f"; done
build_banks
[ "$MD5_BEFORE_FR" = "$MD5_AGAIN_FR" ] \
  || fail "la banque AVANT ne se reproduit pas ($MD5_BEFORE_FR vs $MD5_AGAIN_FR) — mesure non fiable"
echo "[width]   banque AVANT reproductible : $MD5_BEFORE_FR"

echo "[width] === 4/4 delta ==="
python3 - "$STASH" "$OUT" "$MD5_BEFORE_FR" <<'PY'
import re, sys, os
stash, out, md5b = sys.argv[1], sys.argv[2], sys.argv[3]
row = re.compile(r'^\s+#x([0-9a-f]+)\s+w=\s*([\d.]+)\s+(.*)$')

def load(p):
    d = {}
    if not os.path.exists(p):
        return d
    for line in open(p, encoding='utf-8'):
        m = row.match(line.rstrip('\n'))
        if m:
            d[m.group(1)] = (float(m.group(2)), m.group(3))
    return d

L = ["# Gtext-tone — LARGEUR RENDUE, AVANT contre APRES",
     "#",
     "# Mesuree par .autoport/gtt_bank_probe.py, qui reproduit get-string-length",
     "# (goal_src/jak1/engine/gfx/font.gc:1531) sur les OCTETS de la banque construite —",
     "# jamais sur le JSON source. Unite = unite de chasse de *font24-table* (grande police).",
     "# Controle d'aller-retour : la banque AVANT se reproduit au bit (md5 %s)." % md5b,
     "#",
     "# CRITERE DU CONTRAT : « les nouvelles formulations sont plus courtes ou egales ».",
     "# Une chaine dont le delta est <= 0 ne peut faire deborder AUCUNE boite qui tenait avant.",
     ""]
worst = 0.0
grew = []
for tag, bf, af in (("fr-FR  (desktop)", "before-fr.txt", "after-fr.txt"),
                    ("de-DE  (desktop)", "before-de.txt", "after-de.txt")):
    b, a = load(os.path.join(stash, bf)), load(os.path.join(stash, af))
    L.append("## %s" % tag)
    tb = ta = 0.0
    for ident in sorted(set(b) | set(a), key=lambda k: int(k, 16)):
        wb, sb = b.get(ident, (0.0, "<ABSENT>"))
        wa, sa = a.get(ident, (0.0, "<ABSENT>"))
        tb += wb
        ta += wa
        d = wa - wb
        worst = max(worst, d)
        if d > 0:
            grew.append((tag, ident, d))
        L.append("  #x%-5s %8.2f -> %8.2f  (%+7.2f)%s" % (ident, wb, wa, d, "   <-- PLUS LARGE" if d > 0 else ""))
        L.append("     AVANT : %s" % sb)
        L.append("     APRES : %s" % sa)
    L.append("  TOTAL   %8.2f -> %8.2f  (%+7.2f)" % (tb, ta, ta - tb))
    L.append("")

L.append("## android fr-FR / en-US (surcouche de paquet)")
for tag, f in (("fr-FR", "before-android-fr.txt"), ("en-US", "before-android-en.txt")):
    for ident, (w, s) in sorted(load(os.path.join(stash, f)).items()):
        L.append("  %-6s #x%-5s %8.2f  (etat LIVRE avant ce lot)  %s" % (tag, ident, w, s))
L.append("")
L.append("## VERDICT")
if grew:
    L.append("  %d chaine(s) PLUS LARGE(S) qu'avant — a justifier une par une :" % len(grew))
    for tag, ident, d in grew:
        L.append("    %s #x%s : +%.2f" % (tag, ident, d))
else:
    L.append("  AUCUNE chaine n'est plus large qu'avant. Le critere du contrat est tenu")
    L.append("  par construction : aucune boite qui tenait ne peut deborder.")
txt = "\n".join(L) + "\n"
os.makedirs(os.path.dirname(out), exist_ok=True)
open(out, "w", encoding="utf-8").write(txt)
print(txt)
PY
echo "[width] -> $OUT"
