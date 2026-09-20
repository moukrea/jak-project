#!/usr/bin/env bash
# census/harness-pack-manifest-is-a-build-artefact.sh — LE VERDICT DE L'ITEM.
#
# Lance par `lib/proof_run.sh` (crochet generique `lib/census/<item-id>.sh`) apres la course.
# Il n'ecrit aucun champ de `proof.txt` : ni `sha`, ni `frames`, ni `crash`, qui sortent de la
# machine. Il publie `pack_manifest_defects`, que `validators/generic.sh` exige a 0.
#
# CE QU'IL MESURE, DANS L'ORDRE DE LA PORTE ECRITE DANS L'ITEM :
#   1. `git ls-files` ne liste plus un seul manifeste de pack, et la regle est GENERIQUE  -> pm_statique
#   2. une REECRITURE par le build ne salit plus les dossiers de pack (symptome FABRIQUE) -> pm_sonde
#   3. l'APK porte le MEME manifeste, octet pour octet                                    -> pm_apk
#   4. la mise de cote (`.commit_quarantine.json`) est videe de ces entrees                -> pm_quarantaine
#   5. la garde de non-regression MORD : deux bras sur des depots JETABLES                 -> pm_garde
#   6. le temoin d'AVANT n'est pas nul, et aucun PRODUCTEUR n'a bouge                      -> pm_avant
#
# INCONNU = DEFAUT. Chaque terme non mesure AJOUTE au compte au lieu de valoir zero, et
# `pm_terms_measured` dit combien de termes ont reellement ete lus : une porte agregee qui
# compte 1 par terme aveugle se lit autrement qu'une qui en compte 1 par vrai defaut.
#
# CE QUI EST PUBLIE SANS ETRE COMPTE. La salete du reste d'`android/` : un recensement qui
# assert `git status -- android` rougit pour le chantier de n'importe qui d'autre (signalement 5
# du 12/09). On compte ce que l'item OWNE — les dossiers de pack — et on NOMME le reste a cote.
set -uo pipefail

ROOT=$(git rev-parse --show-toplevel 2>/dev/null) || { echo "pm_census_ran=0"; exit 1; }
AP="$ROOT/.autoport"
cd "$ROOT" || exit 1

# Le moissonneur de proof_run.sh ne garde que `^cle=valeur$` SANS espace : une valeur qui en
# porte serait publiee pour personne. On colle les espaces ICI, au point de publication.
pub(){ printf '%s=%s\n' "$1" "$(printf '%s' "${2:--}" | tr -s '[:space:]' '_')"; }

penalty=0; why=""
faute(){ penalty=$((penalty+1)); why="${why:+$why+}$1"; }
mesures=0; mesure(){ mesures=$((mesures+1)); }

GARDE="$AP/lib/pack_manifest_check.py"
[ -f "$GARDE" ] || { echo "pm_census_ran=0"; exit 1; }

TMP=$(mktemp -d "${TMPDIR:-/tmp}/pm-census.XXXXXX") || { echo "pm_census_ran=0"; exit 1; }
trap '[ -n "${TMP:-}" ] && [ -d "$TMP" ] && rm -rf -- "$TMP"' EXIT

# ================================================== 1. LA GARDE STATIQUE SUR LE DEPOT LIVRE ==
# Une ligne par defaut, chacune nommant son chemin. Zero ligne = la cible est tenue.
python3 "$GARDE" "$ROOT" > "$TMP/live.txt" 2>"$TMP/live.err"
t_statique=$(wc -l < "$TMP/live.txt" 2>/dev/null | tr -d " ")
[ -n "$t_statique" ] || { faute liste-de-defauts-illisible; t_statique=0; }
if [ -s "$TMP/live.err" ]; then faute garde-en-erreur; fi
mesure
SUIVIS=$(git ls-files -- 'android/app/src/*/assets-slim/bundle/*.manifest.properties' | wc -l)

# ============================================ 2. LA SONDE DE REECRITURE (LE SYMPTOME, VRAI) ==
# On rejoue ce que gradle fait a chaque build — reecrire le manifeste — et on regarde si les
# dossiers de pack deviennent sales. Les octets ET la date sont remis derriere, et la
# restitution est VERIFIEE : un echec de restitution est lui-meme compte.
python3 - "$ROOT" <<'PY' > "$TMP/sonde.kv" 2>"$TMP/sonde.err"
import json, sys
sys.path.insert(0, sys.argv[1] + "/.autoport/lib")
import pack_manifest_check as G
r = G.sonde_reecriture(sys.argv[1])
print("reecrits=%d" % r["reecrits"])
print("sale=%d" % len(r["sale"]))
print("rendus=%d" % r["rendus"])
print("intacts=%d" % r["intacts"])
print("sale_liste=%s" % ("|".join(r["sale"]) or "-"))
PY
s(){ sed -n "s/^$1=//p" "$TMP/sonde.kv" 2>/dev/null | tail -1; }
n(){ local v; v=$(s "$1"); case "$v" in ''|*[!0-9-]*) echo -1 ;; *) echo "$v" ;; esac; }
SO_REECRITS=$(n reecrits); SO_SALE=$(n sale); SO_RENDUS=$(n rendus); SO_INTACTS=$(n intacts)
t_sonde=0
if [ "$SO_REECRITS" -le 0 ]; then
  # PLANCHER DE VACUITE : aucun manifeste reecrit = la sonde n'a RIEN mesure, et un `sale=0`
  # se lirait « tenu ». C'est l'instrument qui est aveugle, et il le dit.
  faute sonde-aveugle-aucun-manifeste-sur-le-disque
else
  mesure
  [ "$SO_SALE" -ge 0 ] && t_sonde=$((t_sonde + SO_SALE)) || faute sonde-muette
  [ "$SO_RENDUS" = "$SO_REECRITS" ] || t_sonde=$((t_sonde + 1))    # non-destruction
  [ "$SO_INTACTS" = "$SO_REECRITS" ] || t_sonde=$((t_sonde + 1))
fi

# ============================================= 3. L'APK PORTE LE MEME MANIFESTE, OCTET/OCTET ==
# La question que la cible pose : le de-suivi change-t-il ce qui est LIVRE ? Gradle prend
# `src/<jeu>/assets-slim` en BLOC (build.gradle.kts, `assets.setSrcDirs`) — git n'y entre pas.
# La preuve n'est pas dans cette phrase mais dans le frere du manifeste : `*_cgo.zip` est
# ignore depuis toujours (.gitignore:170) et part dans CHAQUE APK. On le mesure.
APK=android/app/build/outputs/apk/jak1/debug/app-jak1-debug.apk
t_apk=0; APK_PAIRS=0; APK_EGAUX=0; ZIP_LIVRE=-1; ZIP_SUIVI=-1
if [ -f "$APK" ]; then
  mesure
  for nom in jak1_cgo.manifest.properties jak1_custom.manifest.properties; do
    arbre="android/app/src/jak1/assets-slim/bundle/$nom"
    [ -f "$arbre" ] || continue
    APK_PAIRS=$((APK_PAIRS+1))
    a=$(md5sum < "$arbre" | cut -d' ' -f1)
    b=$(unzip -p "$APK" "assets/bundle/$nom" 2>/dev/null | md5sum | cut -d' ' -f1)
    if [ -n "$b" ] && [ "$a" = "$b" ]; then APK_EGAUX=$((APK_EGAUX+1)); else t_apk=$((t_apk+1)); fi
  done
  [ "$APK_PAIRS" -gt 0 ] || faute apk-sans-manifeste-a-comparer
  ZIP_SUIVI=$(git ls-files -- 'android/app/src/jak1/assets-slim/bundle/jak1_cgo.zip' | wc -l)
  ZIP_LIVRE=$(unzip -l "$APK" 'assets/bundle/jak1_cgo.zip' 2>/dev/null | grep -c 'assets/bundle/jak1_cgo.zip')
  # LE PRECEDENT, MESURE : non suivi par git, et pourtant dans l'APK.
  { [ "$ZIP_SUIVI" = 0 ] && [ "$ZIP_LIVRE" -ge 1 ]; } || t_apk=$((t_apk+1))
else
  faute apk-absent-terme-non-mesure
fi

# ======================================================= 4. LA MISE DE COTE EST SANS OBJET ===
QUAR=$(python3 - "$AP/.commit_quarantine.json" <<'PY'
import json, sys
try:
    b = json.load(open(sys.argv[1], encoding="utf-8"))
except Exception:
    b = {}
print(sum(1 for k in b if k.endswith(".manifest.properties")))
PY
)
case "$QUAR" in ''|*[!0-9]*) faute quarantaine-illisible; t_quarantaine=1 ;; *) mesure; t_quarantaine=$QUAR ;; esac

# ============================================ 5. LA GARDE MORD — DEUX BRAS, DEPOTS JETABLES ==
# Le bras d'AVANT reproduit l'etat du 19/09 (manifeste commite, aucune regle) : la garde doit
# ROUGIR, et la reecriture doit SALIR. Sans ce bras, le vert du depot livre serait aussi celui
# d'une garde qui ne regarde rien.
python3 - "$ROOT" "$TMP" <<'PY' > "$TMP/bras.kv" 2>"$TMP/bras.err"
import sys
sys.path.insert(0, sys.argv[1] + "/.autoport/lib")
import pack_manifest_check as G
from pathlib import Path
for nom, suivi in (("avant", True), ("apres", False)):
    d = G.semer(Path(sys.argv[2]) / ("bras-" + nom), suivi=suivi)
    m = G.defauts(d)
    r = G.sonde_reecriture(d)
    print("%s_defauts=%d" % (nom, len(m)))
    print("%s_suivi=%d" % (nom, sum(1 for x in m if x.startswith("suivi:"))))
    print("%s_regle=%d" % (nom, sum(1 for x in m if x.startswith("regle-non-generique:"))))
    print("%s_sale=%d" % (nom, len(r["sale"])))
    print("%s_intacts=%d" % (nom, r["intacts"]))
PY
b(){ local v; v=$(sed -n "s/^$1=//p" "$TMP/bras.kv" 2>/dev/null | tail -1)
     case "$v" in ''|*[!0-9-]*) echo -1 ;; *) echo "$v" ;; esac; }
t_garde=0
if [ ! -s "$TMP/bras.kv" ]; then
  faute bras-jetables-muets; t_garde=$((t_garde+1))
else
  mesure
  [ "$(b avant_suivi)" -ge 1 ] || t_garde=$((t_garde+1))   # AVANT : le manifeste est suivi
  [ "$(b avant_regle)" -ge 1 ] || t_garde=$((t_garde+1))   # AVANT : aucune regle ne le couvre
  [ "$(b avant_sale)"  -ge 1 ] || t_garde=$((t_garde+1))   # AVANT : la reecriture SALIT
  [ "$(b apres_defauts)" = 0 ] || t_garde=$((t_garde+1))   # APRES : rien a redire
  [ "$(b apres_sale)"    = 0 ] || t_garde=$((t_garde+1))   # APRES : la reecriture ne salit plus
  [ "$(b avant_intacts)" = 1 ] || t_garde=$((t_garde+1))
  [ "$(b apres_intacts)" = 1 ] || t_garde=$((t_garde+1))
fi

# ET LA GARDE EST DANS LA SUITE, VERTE. Un module que personne ne lance n'est pas une garde.
SUITE_RC=-1; SUITE_N=-1
if out=$(cd "$ROOT" && timeout 300 python3 -m pytest \
          .autoport/tests/harness/test_pack_manifest_is_generated.py \
          -q -p no:cacheprovider --basetemp="$TMP/pytest" 2>&1); then SUITE_RC=0; else SUITE_RC=$?; fi
SUITE_N=$(printf '%s\n' "$out" | grep -oE '[0-9]+ passed' | tail -1 | cut -d' ' -f1)
case "$SUITE_N" in ''|*[!0-9]*) SUITE_N=-1 ;; esac
[ "$SUITE_RC" = 0 ] || t_garde=$((t_garde+1))
[ "${SUITE_N:-0}" -ge 5 ] 2>/dev/null || t_garde=$((t_garde+1))

# ============================== 6. LE TEMOIN D'AVANT, ANCRE SUR LA DONNEE, ET LES PRODUCTEURS ==
# Ancre sur la PRESENCE DU BLOB dans l'arbre du commit, jamais sur `HEAD:` — un temoin lu a
# `HEAD:` devient faux des le commit qui corrige, et s'accuse lui-meme.
PIL=android/app/src/jak1/assets-slim/bundle/jak1_cgo.manifest.properties
AVANT=""
for c in $(git rev-list -n 200 HEAD 2>/dev/null); do
  if git cat-file -e "$c:$PIL" 2>/dev/null; then AVANT=$c; break; fi
done
t_avant=0; AV_SUIVIS=-1
if [ -z "$AVANT" ]; then
  faute temoin-avant-introuvable; t_avant=$((t_avant+1))
else
  mesure
  AV_SUIVIS=$(git ls-files --with-tree="$AVANT" -- \
      'android/app/src/*/assets-slim/bundle/*.manifest.properties' | wc -l)
  # AVANT NON NUL : sans ca, « plus aucun manifeste suivi » se lirait aussi sur un depot qui
  # n'en a jamais eu, et la mesure ne dirait rien.
  [ "$AV_SUIVIS" -ge 2 ] || t_avant=$((t_avant+1))
fi

# LES PRODUCTEURS N'ONT PAS BOUGE. C'est ce qui rend « l'APK porte le meme manifeste »
# structurel et non anecdotique : le chemin, le contenu et les cles sont ecrits par les memes
# octets qu'avant ce chantier.
PROD_EGAUX=0; PROD_N=0
for f in android/build_cgo_pack.sh android/build_custom_pack.sh; do
  PROD_N=$((PROD_N+1))
  d=$(sha256sum "$f" 2>/dev/null | cut -c1-16)
  a=$(git show "$AVANT:$f" 2>/dev/null | sha256sum | cut -c1-16)
  if [ -n "$AVANT" ] && [ -n "$d" ] && [ "$d" = "$a" ]; then PROD_EGAUX=$((PROD_EGAUX+1))
  else t_avant=$((t_avant+1)); fi
done

# ============================================================================ LE VERDICT ====
TOTAL=$((t_statique + t_sonde + t_apk + t_quarantaine + t_garde + t_avant + penalty))

pub pm_census_ran 1
pub pack_manifest_defects "$TOTAL"
pub pack_manifest_defects_terms \
  "statique$t_statique+sonde$t_sonde+apk$t_apk+quarantaine$t_quarantaine+garde$t_garde+avant$t_avant+penalite$penalty${why:+:$why}"
pub pm_terms_measured "$mesures"

# 1. LA GARDE STATIQUE — le compte, et les defauts NOMMES tels quels.
pub pm_tracked_now "$SUIVIS"
pub pm_static_defects "$t_statique"
pub pm_static_list "$(paste -sd'|' "$TMP/live.txt" 2>/dev/null | head -c 400)"
pub pm_rule_generic "$(git check-ignore -q --no-index -- \
      android/app/src/jak3/assets-slim/bundle/jak3_cgo.manifest.properties && echo 1 || echo 0)"
pub pm_manifests_on_disk "$(find android/app/src -path '*/assets-slim/bundle/*.manifest.properties' 2>/dev/null | wc -l)"

# 2. LA SONDE — ce que la reecriture a produit, et ce qu'elle a rendu.
pub pm_probe_rewritten "$SO_REECRITS"
pub pm_probe_dirty "$SO_SALE"
pub pm_probe_dirty_list "$(s sale_liste)"
pub pm_probe_restored "$SO_RENDUS"
pub pm_probe_intact "$SO_INTACTS"

# 3. L'APK — les paires comparees, et le precedent du zip non suivi.
pub pm_apk_present "$([ -f "$APK" ] && echo 1 || echo 0)"
pub pm_apk_pairs "$APK_PAIRS"
pub pm_apk_identical "$APK_EGAUX"
pub pm_apk_zip_untracked "$ZIP_SUIVI"
pub pm_apk_zip_shipped "$ZIP_LIVRE"
pub pm_apk_defects "$t_apk"

# 4. LA MISE DE COTE.
pub pm_quarantine_entries "$QUAR"

# 5. LES DEUX BRAS, COTE A COTE, ET LA SUITE.
pub pm_arm_before_defects "$(b avant_defauts)"
pub pm_arm_before_tracked "$(b avant_suivi)"
pub pm_arm_before_dirty "$(b avant_sale)"
pub pm_arm_after_defects "$(b apres_defauts)"
pub pm_arm_after_dirty "$(b apres_sale)"
pub pm_guard_defects "$t_garde"
pub pm_suite_rc "$SUITE_RC"
pub pm_suite_passed "$SUITE_N"

# 6. LE TEMOIN D'AVANT, PAR SON COMMIT, ET LES PRODUCTEURS.
pub pm_before_commit "${AVANT:0:12}"
pub pm_before_tracked "$AV_SUIVIS"
pub pm_producers_unchanged "$PROD_EGAUX/$PROD_N"

# HORS PERIMETRE, PUBLIE ET JAMAIS COMPTE : la salete du reste d'`android/`. Elle appartient au
# chantier de qui l'a faite, pas a cet item.
pub pm_android_dirty_total "$(git status --porcelain=v1 -uall -- android | wc -l)"
pub pm_android_dirty_list "$(git status --porcelain=v1 -uall -- android | head -5 | paste -sd'|' | head -c 300)"

# LES OCTETS JUGES. Un chemin n'est pas une provenance.
for f in lib/pack_manifest_check.py tests/harness/test_pack_manifest_is_generated.py \
         lib/census/harness-pack-manifest-is-a-build-artefact.sh; do
  k="pm_sha_$(printf '%s' "$f" | tr -c 'A-Za-z0-9_' '_')"
  pub "$k" "$(sha256sum "$AP/$f" 2>/dev/null | cut -c1-16)"
done
pub pm_sha_gitignore "$(sha256sum "$ROOT/.gitignore" 2>/dev/null | cut -c1-16)"
