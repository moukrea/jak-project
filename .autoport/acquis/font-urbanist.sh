#!/usr/bin/env bash
# acquis/font-urbanist.sh — GARDE PERMANENTE D'UN ACQUIS VALIDE PAR L'OWNER (2026-08-30 :
# « Urbanist me semble deja avoir valide »), casse le 2026-09-02 sans qu'aucune garde ne le voie :
# « t'as complètement niqué la font (Urbanist) ça utilise des glyphs chinois de la font par
# défaut du jeu ».
#
# Ce qu'elle verifie, et POURQUOI chaque jambe :
#   S. STATIQUE  — les deux atlas Urbanist existent dans l'arbre (ils sont GENERES et gitignore :
#                  un arbre propre ne les a pas) et sont dans le pack custom construit s'il existe.
#   D. APPAREIL  — `files/font_atlas.txt`, ecrit par le MOTEUR au moment ou le dessin direct LIE
#                  l'atlas (DirectRenderer::update_gl_texture) : `ascii.24lo` et `ascii.12lo`
#                  doivent venir de `bundled-police`, et la grande police doit avoir ete LIEE au
#                  moins une fois (binds>0). C'est le point de LECTURE, pas le chargement : un
#                  atlas charge puis masque par une porte ou un autre niveau de precedence se
#                  voit ici et nulle part ailleurs.
#   X. x86       — meme preuve sur le gk de bureau (lignes `FONTTEX upload` / `FONTTEX bind` sur
#                  stdout) quand aucun appareil n'est fourni ou joignable.
#
# Appel : acquis/font-urbanist.sh [serial]     (serial vide -> jambe x86 seule)
# Sortie 0 = acquis tenu. Toute autre sortie = la phase qui se ferme a CASSE la police, ou ne
# peut pas prouver qu'elle ne l'a pas fait — les deux bloquent, c'est le sens d'un acquis.
set -uo pipefail
cd "$(git rev-parse --show-toplevel)"
SERIAL="${1:-}"
ADB=${ADB:-/home/emeric/Android/platform-tools/adb}
PKG=org.opengoal.gk.jak1
fail(){ echo "[acquis/font] ECHEC : $*" >&2; exit 1; }

# ---- S. statique --------------------------------------------------------------------------
D=custom_assets/jak1/recharged_textures/gamefontnew
[ -s "$D/ascii.12lo.png" ] && [ -s "$D/ascii.24lo.png" ] \
  || fail "atlas Urbanist absents de $D (generes par recharged_assets/font/gen_game_atlas.py)"
ZIP=android/app/src/jak1/assets-slim/bundle/jak1_custom.zip
if [ -f "$ZIP" ]; then
  n=$(unzip -l "$ZIP" 2>/dev/null | grep -c -E 'recharged_textures/gamefontnew/ascii\.(12|24)lo\.png')
  [ "$n" -eq 2 ] || fail "le pack custom construit ($ZIP) n'embarque que $n/2 atlas de police"
fi
echo "[acquis/font] S ok : 2 atlas dans l'arbre$( [ -f "$ZIP" ] && echo ', 2 dans le pack custom')"

check_lines(){ # $1 = fichier de lignes FONTATLAS/FONTTEX ; $2 = libelle
  local f="$1" what="$2" l24 l12 b24
  l24=$(grep -a -E 'name=gamefontnew/ascii\.24lo ' "$f" | tail -1)
  l12=$(grep -a -E 'name=gamefontnew/ascii\.12lo ' "$f" | tail -1)
  [ -n "$l24" ] || fail "$what : aucune ligne pour gamefontnew/ascii.24lo (moteur sans instrument FONTTEX, ou police jamais chargee)"
  echo "$l24" | grep -q 'source=bundled-police' || fail "$what : la GRANDE police n'est pas Urbanist -> $l24"
  [ -n "$l12" ] && { echo "$l12" | grep -q 'source=bundled-police' || fail "$what : la PETITE police n'est pas Urbanist -> $l12"; }
  b24=$(echo "$l24" | sed -n 's/.*binds=\([0-9]*\).*/\1/p')
  if [ -n "$b24" ]; then
    [ "$b24" -gt 0 ] || fail "$what : la grande police n'a jamais ete LIEE au dessin (binds=0) -> rien ne prouve ce que l'ecran montre"
  fi
  echo "[acquis/font] $what ok : $l24"
}

# ---- D. appareil --------------------------------------------------------------------------
if [ -n "$SERIAL" ] && timeout 15 "$ADB" -s "$SERIAL" get-state 2>/dev/null | grep -q device; then
  pid=$(timeout 15 "$ADB" -s "$SERIAL" shell pidof $PKG 2>/dev/null | tr -d '\r')
  if [ -z "$pid" ]; then
    comp=$(timeout 15 "$ADB" -s "$SERIAL" shell cmd package resolve-activity --brief $PKG 2>/dev/null | tr -d '\r' | grep "^$PKG/" | head -1)
    [ -n "$comp" ] || comp="$PKG/org.opengoal.gk.LoaderActivity"
    timeout 15 "$ADB" -s "$SERIAL" exec-out run-as $PKG rm -f files/font_atlas.txt >/dev/null 2>&1
    timeout 15 "$ADB" -s "$SERIAL" shell am start -n "$comp" >/dev/null 2>&1
    sleep 60
  fi
  # `exec-out run-as` melange stderr a stdout : on ne juge que sur le CONTENU (une ligne FONTATLAS),
  # jamais sur « la commande a rendu quelque chose ».
  out=$(timeout 15 "$ADB" -s "$SERIAL" exec-out run-as $PKG sh -c 'cat files/font_atlas.txt 2>/dev/null' | tr -d '\r' | grep -a '^FONTATLAS')
  [ -n "$out" ] || fail "appareil $SERIAL : files/font_atlas.txt absent — le moteur installe n'ecrit pas la preuve de liaison (build anterieur a Gfont-regression, ou police jamais dessinee en 60 s)"
  tmp=$(mktemp); printf '%s\n' "$out" > "$tmp"
  check_lines "$tmp" "D appareil $SERIAL"
  rm -f "$tmp"
  exit 0
fi

# ---- X. x86 ---------------------------------------------------------------------------------
GK=build/game/gk; ISO=out/jak1/iso
[ -x "$GK" ] || fail "ni appareil joignable ni $GK : impossible de prouver l'acquis"

# ATTENDRE QU'AUCUN BUILD N'ECRIVE `out/jak1/iso`, PUIS TENIR LE VERROU PENDANT LA COURSE.
# Le 2026-09-05 cette garde a rendu un ROUGE que le code ne meritait pas : `auto_build_apk.sh`
# a lance `(make-group "iso")` (auto_build_apk.sh:366) pendant les 75 s de course, et le gk est
# mort en SIGILL sur un CGO a moitie reecrit — « la grande police n'a jamais ete liee en 75 s ».
# Un acquis qui rend rouge parce qu'un builder tournait ne garde rien : il coute un essai.
# `lib/proof_run.sh::busy_reason` attend deja exactement ca ; cette garde ne le faisait pas.
# Fail-closed reste fail-closed : si ca ecrit encore au bout du plafond, on ECHOUE.
#
# 2026-09-14 — CETTE GARDE N'A PLUS DE COPIE A ELLE.
# Elle en portait une, figee au 05/09 : `pgrep -f` sur '[g]radle' '[n]inja' '[g]oalc' '[c]c1plus'.
# Quatre mots cherches dans des LIGNES DE COMMANDE, donc trois populations confondues dont une
# seule est un build — le demon Gradle (idleTimeout=3 h, vivant longtemps apres l'APK), un shell
# qui NOMME l'outil, et le build lui-meme. `harness-busy-guard-matches-gradle-daemon` a corrige
# exactement ca dans `lib/proof_run.sh` le 14/09 ; la copie d'ici n'a pas suivi, et elle a tue
# l'essai 1 de harness-close-gate-separates-inherited-reds en 420 s d'attente alors qu'AUCUN
# build ne tournait (releve : `notes/busy-guard-acquis-avant.txt`, verdict « processus [g]radle
# en cours » sur un arbre calme). Une regle dupliquee derive : c'est la deuxieme fois.
# On ne duplique donc plus — on EMBARQUE LA VRAIE DEFINITION, decoupee dans proof_run.sh, la
# meme tranche que `lib/busy_guard_selftest.sh` rejoue. La fonction reste chez elle : le temoin
# de l'item busy-guard l'epingle DANS proof_run.sh, la deplacer le rendrait muet.
# Fail-closed jusqu'au bout : une tranche qui ne vient pas ECHOUE l'acquis, elle ne le laisse
# pas courir sans garde.
LOCK=.autoport/.deploy-in-progress
AP=.autoport
log(){ echo "[acquis/font] $*" >&2; }
BR=$(python3 - "$AP/lib/proof_run.sh" <<'PY' 2>/dev/null
import sys
src = open(sys.argv[1], encoding='utf-8', errors='replace').read()
out = ""
for nom in ("busy_procs", "busy_reason"):
    ouv = "\n%s(){" % nom
    if ouv not in src:
        sys.exit(1)
    out += "%s(){%s\n}\n" % (nom, src.split(ouv, 1)[1].split("\n}\n", 1)[0])
# La tranche DOIT passer par l'indirection, sinon on aurait decoupe un decor et pas la garde.
if "busy_procs cmdline" not in out or "busy_procs comm" not in out:
    sys.exit(1)
sys.stdout.write(out)
PY
) || BR=""
[ -n "$BR" ] || fail "impossible de decouper busy_procs/busy_reason dans $AP/lib/proof_run.sh : la garde « aucun build en cours » n'existe pas, l'acquis ne se mesure pas a l'aveugle"
eval "$BR"
waited=0
while :; do
  why=$(busy_reason)
  [ -z "$why" ] && break
  [ "$waited" -ge 420 ] && fail "un build ecrit encore $ISO apres ${waited}s ($why) : l'acquis n'a pas pu etre mesure"
  [ "$waited" = 0 ] && echo "[acquis/font] attente d'un arbre calme : $why" >&2
  sleep 15; waited=$((waited+15))
done
[ "$waited" -gt 0 ] && echo "[acquis/font] build fini apres ${waited}s, on mesure." >&2
# Le PID est celui de CE script, qui vit pendant toute la course : un verrou qui nomme le
# shell d'un appel d'outil est mort dans la seconde et ne protege rien.
printf '%s pid=%s what=acquis-font-urbanist\n' "$0" "$$" > "$LOCK"
trap 'rm -f "$LOCK"' EXIT

export DISPLAY="${DISPLAY:-:0}"
[ -n "${XAUTHORITY:-}" ] || for x in /run/user/1000/.mutter-Xwaylandauth.*; do [ -e "$x" ] && export XAUTHORITY="$x"; done
export SDL_VIDEODRIVER=x11
log=$(mktemp)
timeout 75 "$GK" --game jak1 --portable -fakeiso --verbose --disable-ansi -iso-data "$ISO" -- -boot -debug-mem > "$log" 2>&1
grep -a '^FONTTEX bind' "$log" | grep -q 'tbp=0x3980' \
  || fail "x86 : la grande police n'a jamais ete liee en 75 s (0 ligne 'FONTTEX bind tbp=0x3980') — voir $log"
# la ligne de liaison porte la source ; on la normalise au format FONTATLAS (binds=1 : elle a ete liee)
grep -a '^FONTTEX bind' "$log" | grep 'tbp=0x3980' | tail -1 | sed 's/$/ binds=1/' > "$log.l"
grep -a '^FONTTEX upload' "$log" | grep 'ascii.12lo' | tail -1 >> "$log.l"
check_lines "$log.l" "X x86"
rm -f "$log" "$log.l"
exit 0
