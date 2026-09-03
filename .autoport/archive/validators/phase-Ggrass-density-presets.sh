#!/usr/bin/env bash
# phase-Ggrass-density-presets.sh — CINQ PALIERS PRE-CALCULES, PLUS DE PLACEMENT EN DIRECT.
#
# CE QUE CE VALIDATEUR REFUSE DE FAIRE : croire le rapport sur parole. Tout ce qui est lisible
# DIRECTEMENT (l'etat du code, le nom et l'en-tete des bakes livres, le contenu du pack) est relu
# ici, par ce script, sur les fichiers eux-memes. Le rapport ne porte que ce qu'une COURSE seule
# peut produire : les basculements observes, la memoire, le cout de la plage avant/apres.
set -uo pipefail
cd "$(git rev-parse --show-toplevel)"
R=.autoport/reports/Ggrass-density-presets/report.txt
FR3=out/jak1/fr3
SLUGS="very-low low medium high very-high"
FAILED=0
fail(){ echo "[Ggdp FAIL] $*" >&2; FAILED=1; }
die(){  echo "[Ggdp FAIL] $*" >&2; exit 1; }   # reserve a ce qui casse la LECTURE

[ -f "$R" ] || die "pas de rapport a $R"

# ---------------------------------------------------------------------------------------------
# 0. Le rapport travaille-t-il sur le contrat COURANT ?
# ---------------------------------------------------------------------------------------------
ACC=$(python3 .autoport/lib/directives.py accepted 2>/dev/null || echo "")
if [ -n "$ACC" ]; then
  got=$(grep -oE '^DIRECTIVES v[0-9a-f]+' "$R" | head -1 | awk '{print $2}')
  [ -n "$got" ] || fail "le rapport ne porte aucune ligne 'DIRECTIVES v<version>'"
  if [ -n "$got" ] && ! grep -qw -- "$got" <<< "$ACC"; then
    fail "version de directives perimee dans le rapport ($got ; acceptees : $ACC)"
  fi
fi
grep -qE '^RESULT:[[:space:]]*GRASS DENSITY PRESETS[[:space:]]*$' "$R" \
  || fail "ligne 'RESULT: GRASS DENSITY PRESETS' absente"

# ---------------------------------------------------------------------------------------------
# 1. L'ETAT DU CODE — relu ici, pas rapporte
# ---------------------------------------------------------------------------------------------
HDR=game/graphics/opengl_renderer/background/background_common.h
LEVELS=$(grep -oP 'kGrassLevels\[\]\s*=\s*\{\K[^}]*' "$HDR" 2>/dev/null | tr -d '" ' | tr ',' '\n' | sed '/^$/d')
[ -n "$LEVELS" ] || die "kGrassLevels illisible dans $HDR"
[ "$(echo $LEVELS)" = "training" ] \
  || fail "kGrassLevels vaut '$(echo $LEVELS)' — la plage devait en sortir (owner 2026-08-30 : « tu peux completement dismiss »)"

GR=game/graphics/opengl_renderer/GrassRenderer.cpp
grep -q 'density slider above bake density' "$GR" \
  && fail "la condition « density slider above bake density » survit dans $GR — c'est elle qui basculait le placement en direct, elle doit DISPARAITRE, pas devenir inatteignable"
grep -q 'AUCUN BAKE VALIDE' "$GR" \
  || fail "$GR : la branche « aucun bake valide -> pas d'herbe » est absente ; sans elle un echec de bake retombe sur le chemin lourd"
n_scan=$(grep -c 'grass_bake::scan_level(' "$GR")
[ "$n_scan" -le 1 ] \
  || fail "$GR : $n_scan appels a scan_level (le placement EN DIRECT) ; il n'en reste qu'un, la jambe de mesure hors menu"
grep -q 'density_preset_slug' "$GR" \
  || fail "$GR : la resolution par palier (<niveau>.<palier>.grassbake) est absente"

PP=goal_src/jak1/pc/progress-pc.gc
grep -q 'game-option-type grass-density' "$PP" \
  || fail "$PP : le type d'option 'grass-density' est absent — le menu n'offre pas les cinq paliers"
grep -q 'carousell-grass-density' "$PP" \
  || fail "$PP : le tableau *carousell-grass-density* est absent"
grep -q 'recharged-grass-precomputed?) (the-as symbol val)' "$PP" \
  && fail "$PP : la rangee de menu GRASS MODE (PRECOMPUTED/LIVE) survit — elle propose au joueur le chemin de 1 207 Mo sur lequel les plantages ont ete reproduits"

# ---------------------------------------------------------------------------------------------
# 2. LES BAKES LIVRES — noms, en-tetes, et accord avec le fr3 qui part avec eux
# ---------------------------------------------------------------------------------------------
[ -f "$FR3/training.fr3" ] || die "$FR3/training.fr3 absent — rien a valider"
FR3SZ=$(stat -c %s "$FR3/training.fr3")
declare -A PCT=([very-low]=50 [low]=100 [medium]=150 [high]=200 [very-high]=250)
n_bake=0
for sg in $SLUGS; do
  f="$FR3/training.$sg.grassbake"
  if [ ! -f "$f" ]; then fail "bake manquant : $f"; continue; fi
  line=$(python3 scripts/shell/grassbake_header.py "$f" 2>&1) || { fail "en-tete illisible : $f — $line"; continue; }
  lv=$(sed -n 's/.* niveau=\([^ ]*\).*/\1/p' <<< "$line")
  sz=$(sed -n 's/.* fr3_size=\([0-9]*\).*/\1/p' <<< "$line")
  dn=$(sed -n 's/.* densite=\([0-9.]*\).*/\1/p' <<< "$line")
  [ "$lv" = "training" ] || fail "$f : niveau='$lv' au lieu de 'training'"
  [ "$sz" = "$FR3SZ" ]   || fail "$f : fr3_size=$sz alors que le training.fr3 livre fait $FR3SZ — REFUSE a l'arrivee, l'herbe disparaitrait"
  [ "${dn%.*}" = "${PCT[$sg]}" ] || fail "$f : densite=$dn au lieu de ${PCT[$sg]} pour le palier '$sg'"
  n_bake=$((n_bake + 1))
done
[ "$n_bake" = 5 ] || fail "$n_bake bake(s) de palier valides sur 5"

# aucun bake residuel : le moteur ne resout QUE <niveau>.<palier>.grassbake, tout le reste
# alourdirait le pack sans jamais etre lu.
while IFS= read -r f; do
  [ -n "$f" ] || continue
  b=$(basename "$f"); keep=0
  for sg in $SLUGS; do [ "$b" = "training.$sg.grassbake" ] && keep=1; done
  [ "$keep" = 1 ] || fail "bake residuel jamais resolu par le moteur : $b (il partirait dans le pack pour rien)"
done < <(find "$FR3" -maxdepth 1 -type f -name '*.grassbake' | sort)

# ---------------------------------------------------------------------------------------------
# 3. LE PACK — recompte ici, sur le zip lui-meme
# ---------------------------------------------------------------------------------------------
ZIP=android/app/src/jak1/assets-slim/bundle/jak1_custom.zip
if [ -f "$ZIP" ]; then
  # `set -o pipefail` + `grep -q` = SIGPIPE(141) sur `unzip` des la premiere correspondance, donc
  # une branche d'echec qui tire alors que le membre EST present. On liste UNE fois, on cherche
  # ensuite dans la variable. (Le meme piege est deja documente dans build_custom_pack.sh.)
  ZLIST=$(unzip -Z1 "$ZIP" 2>/dev/null || true)
  inpack=$(grep -c '\.grassbake$' <<< "$ZLIST" || true)
  [ "$inpack" = 5 ] || fail "le pack livre porte $inpack .grassbake au lieu de 5 ($ZIP)"
  for sg in $SLUGS; do
    grep -qx "fr3/training.$sg.grassbake" <<< "$ZLIST" \
      || fail "le pack ne contient pas fr3/training.$sg.grassbake"
  done
  newest=$(find "$FR3" -maxdepth 1 -name '*.grassbake' -newer "$ZIP" | head -1)
  [ -z "$newest" ] || fail "le pack ($ZIP) est ANTERIEUR aux bakes (ex. $newest) — il ne porte pas ce qui vient d'etre cuit"
else
  fail "pack absent : $ZIP — les paliers n'existeraient que chez nous"
fi

# ---------------------------------------------------------------------------------------------
# 4. CE QUE SEULE UNE COURSE PRODUIT — lu dans le rapport
# ---------------------------------------------------------------------------------------------
python3 - "$R" <<'PY' || FAILED=1
import re, sys
t = open(sys.argv[1]).read()
kv = lambda l: dict(re.findall(r'(\w+)=([^\s]+)', l))
bad = []
def F(m): bad.append(m)

SLUGS = ["very-low", "low", "medium", "high", "very-high"]

pres = [kv(l) for l in re.findall(r'^GRASSPRESET .*$', t, re.M)]
seen = {d.get('palier') for d in pres}
for s in SLUGS:
    if s not in seen:
        F(f"GRASSPRESET manquant pour le palier '{s}'")
for d in pres:
    if d.get('niveau') != 'training':
        F(f"GRASSPRESET palier={d.get('palier')} : niveau={d.get('niveau')} (attendu training)")
    if int(d.get('bake_octets', 0)) <= 0:
        F(f"GRASSPRESET palier={d.get('palier')} : bake_octets={d.get('bake_octets')}")
    if int(d.get('fr3_size', 0)) <= 0:
        F(f"GRASSPRESET palier={d.get('palier')} : fr3_size absent")

live = [kv(l) for l in re.findall(r'^GRASSLIVE .*$', t, re.M)]
if not live:
    F("GRASSLIVE absent : rien ne dit combien de courses ont tourne ni combien ont bascule en direct")
for d in live:
    if int(d.get('courses', 0)) < 10:
        F(f"GRASSLIVE courses={d.get('courses')} — il en faut >= 10")
    if int(d.get('basculements_en_direct', 1)) != 0:
        F(f"GRASSLIVE basculements_en_direct={d.get('basculements_en_direct')} — le chemin lourd a ete emprunte")
    if int(d.get('paliers_couverts', 0)) != 5:
        F(f"GRASSLIVE paliers_couverts={d.get('paliers_couverts')} — les cinq paliers doivent avoir tourne")

mem = [kv(l) for l in re.findall(r'^GRASSMEM .*$', t, re.M)]
base = [d for d in mem if d.get('palier') == 'en-direct']
if not base:
    F("GRASSMEM palier=en-direct absent : sans la ligne de base du chemin direct, « sous le pic direct » n'a pas d'echelle")
else:
    ref = float(base[0].get('rss_max_mo', 0))
    if ref <= 0:
        F("GRASSMEM palier=en-direct : rss_max_mo <= 0")
    for s in SLUGS:
        row = [d for d in mem if d.get('palier') == s]
        if not row:
            F(f"GRASSMEM manquant pour le palier '{s}'")
            continue
        v = float(row[0].get('rss_max_mo', 1e9))
        if v >= ref:
            F(f"GRASSMEM palier={s} : {v} Mo >= le pic du chemin direct ({ref} Mo)")

pack = [kv(l) for l in re.findall(r'^GRASSPACK .*$', t, re.M)]
if not pack:
    F("GRASSPACK absent")
else:
    if int(pack[0].get('bakes_dans_le_pack', -1)) != 5:
        F(f"GRASSPACK bakes_dans_le_pack={pack[0].get('bakes_dans_le_pack')} (attendu 5)")

bch = [kv(l) for l in re.findall(r'^GRASSBEACH .*$', t, re.M)]
av = [d for d in bch if d.get('etat') == 'avant']
ap = [d for d in bch if d.get('etat') == 'apres']
rp = [d for d in bch if d.get('etat') == 'apres-repetition']
if not av:
    F("GRASSBEACH etat=avant absent : le mandat exige de PUBLIER ce que la plage coutait AVANT de la retirer")
if not ap:
    F("GRASSBEACH etat=apres absent : le mandat exige de prouver que chargement et memoire de la plage ne montent pas")
if not rp:
    F("GRASSBEACH etat=apres-repetition absent : sans DEUX courses de la MEME configuration, le "
      "bruit de course a course n'est pas mesure, et un ecart de memoire n'a pas d'echelle a "
      "laquelle se comparer")
# LE TEMPS DE PLACEMENT : l'effet attendu est total (la plage ne place plus rien), donc pas de
# tolerance — une hausse ici serait un vrai defaut.
if av and ap:
    try:
        a, b = float(av[0]['place_ms']), float(ap[0]['place_ms'])
        if b > a + 1e-9:
            F(f"GRASSBEACH : le temps de placement de la plage MONTE apres retrait ({a} -> {b} ms)")
    except (KeyError, ValueError):
        F("GRASSBEACH : champ 'place_ms' absent ou illisible sur avant/apres")
# LA MEMOIRE : deux PROCESSUS differents ne rendent pas le meme pic au kilo-octet pres. La
# tolerance n'est pas choisie, elle est MESUREE — c'est l'ecart entre les deux courses de la
# configuration APRES, qui ne different par construction que par le bruit.
if av and ap and rp:
    try:
        a = float(av[0]['rss_max_mo'])
        b = float(ap[0]['rss_max_mo'])
        c = float(rp[0]['rss_max_mo'])  # au moins une repetition, verifiee plus haut
    except (KeyError, ValueError):
        F("GRASSBEACH : champ 'rss_max_mo' absent ou illisible sur avant/apres/apres-repetition")
    else:
        # Le bruit = l'ETENDUE des courses de la configuration APRES (celle-ci et ses repetitions).
        # Elles ne different que par le bruit, par construction : c'est la seule echelle honnete a
        # laquelle comparer un ecart avant/apres.
        ech = [b] + [float(d['rss_max_mo']) for d in rp if 'rss_max_mo' in d]
        bruit = max(ech) - min(ech)
        if b > a + bruit:
            F(f"GRASSBEACH : la memoire de la plage MONTE apres retrait au-dela du bruit mesure "
              f"({a} -> {b} Mo, etendue des {len(ech)} courses APRES : {bruit:.2f} Mo)")

for m in bad:
    print("[Ggdp FAIL] " + m, file=sys.stderr)
sys.exit(1 if bad else 0)
PY

if [ "$FAILED" != 0 ]; then
  echo "[Ggdp FAIL] validateur en echec — voir les lignes ci-dessus" >&2
  exit 1
fi
echo "[Ggdp ok] 5 paliers cuits contre le training.fr3 livre, 5 dans le pack, 0 basculement en direct sur >=10 courses, plage retiree cout publie"
