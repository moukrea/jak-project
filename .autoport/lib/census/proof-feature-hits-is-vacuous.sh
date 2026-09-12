#!/usr/bin/env bash
# census/proof-feature-hits-is-vacuous.sh — LE VERDICT DE L'ITEM `proof-feature-hits-is-vacuous`.
#
# LANCE PAR `lib/proof_run.sh` (crochet generique), apres la course : sa sortie `cle=valeur`
# rejoint celle du moteur dans le meme journal. Il n'ecrit aucun champ de `proof.txt`, et le
# producteur JETTE desormais toute ligne `proof_feature_*` / `proof_census_*` qu'un recensement
# produirait : ce fichier ne peut pas se fabriquer le temoin qu'il juge.
#
# LE DEFAUT. `validators/generic.sh` exigeait `FEATURE <id> armed=1 hits=N` avec N>0. `hits` est
# le compteur GLOBAL du binaire : `dead_probe_census()` l'incrementait a chaque passe, le
# recensement d'eclairage a chaque draw. La ligne etait donc vraie POUR N'IMPORTE QUEL ITEM, y
# compris ceux qui ne touchent pas une ligne du moteur. Un temoin que rien ne peut faire tomber.
#
# `feature_hits_defects` = somme de QUATRE termes publies SEPAREMENT. INCONNU = DEFAUT : une cle
# qui manque, une valeur qui n'est pas un nombre, un bras de controle qui ne se comporte pas
# comme annonce, tout cela AJOUTE. Sans cette polarite, une porte `== 0` serait verte par
# inaction.
#
#   1. fh_d1_attribution : le compte PROPRE a l'item existe, il est non nul, il DIFFERE du
#      global, et l'arithmetique attribue+non-attribue=global se verifie.
#   2. fh_d2_two_arms    : sur LA MEME COURSE, l'item moteur rend un compte non nul, un AUTRE
#      item moteur rend un compte DIFFERENT, et un item de harnais pur rend zero.
#   3. fh_d3_states      : le VRAI validateur, joue sur quatre preuves fabriquees, distingue
#      « feature absente du binaire » de « feature presente jamais atteinte », accepte l'item de
#      harnais et REFUSE la preuve qui ne porte que le compteur global (celle qui passait avant).
#   4. fh_d4_change_list : la liste des items dont le temoin CHANGE DE SENS est publiee, item par
#      item, avec la population sur laquelle elle a ete mesuree.
set -uo pipefail

ROOT=$(git rev-parse --show-toplevel 2>/dev/null) || { echo "fh_census_ran=0"; exit 1; }
cd "$ROOT" || exit 1
AP="$ROOT/.autoport"
ID="${AUTOPORT_CENSUS_ID:-proof-feature-hits-is-vacuous}"

pub(){ printf '%s=%s\n' "$1" "${2:--}"; }
# -1 = la cle manque ou n'est pas un nombre. Jamais 0 : un zero passerait une porte `== 0`.
num(){ case "${1:-}" in ''|*[!0-9-]*|-) echo -1 ;; *) echo "$1" ;; esac; }

# ---------------------------------------------------------- ce que le MOTEUR a dit de la course
# NOMMAGE/un-seul-endroit — LE NOM DU JOURNAL MOTEUR VIENT DE `lib/impossible.py`, PAR BRAS.
# Il etait ecrit ici DEUX fois en dur, un litteral par bras : le jour ou l'extension change,
# ce recensement lit un fichier que plus personne n'ecrit et publie des `-1` silencieux.
ENGNAME=$(python3 -c 'import sys; sys.path.insert(0, sys.argv[1]); import impossible as I; print(I.arm_name("engine", I.arm_suffix(sys.argv[2])))' \
          "$AP/lib" "${AUTOPORT_CENSUS_ARMED:-1}" 2>/dev/null)
[ -n "$ENGNAME" ] || { echo "fh_census_ran=0"; echo "fh_engine_name_missing=1"; exit 1; }
ENG="${AUTOPORT_CENSUS_DIR:-$AP/reports/$ID}/$ENGNAME"
# Meme regle pour la preuve du bras LIVRE — c'est celle que `validators/generic.sh` ouvre, et
# celle qu'on relit sur les items deja sur le disque. Un litteral ici fabriquerait des fixtures
# que le juge n'ouvre pas : il refuserait pour « preuve absente », jamais pour ce qu'on mesure.
PROOFNAME=$(python3 "$AP/lib/impossible.py" name proof "" 2>/dev/null)
[ -n "$PROOFNAME" ] || { echo "fh_census_ran=0"; echo "fh_proof_name_missing=1"; exit 1; }
e(){ grep -aE "^$1=" "$ENG" 2>/dev/null | tail -1 | sed "s/^$1=//"; }

F_ID=$(e proof_feature_id);            F_STATE=$(e proof_feature_state)
F_OWN=$(num "$(e proof_feature_own_hits)");     F_GLOB=$(num "$(e proof_feature_global_hits)")
F_GAP=$(num "$(e proof_feature_hits_gap)");     F_ATTR=$(num "$(e proof_feature_hits_attributed)")
F_UNAT=$(num "$(e proof_feature_hits_unattributed)")
F_SITES=$(num "$(e proof_feature_sites_total)"); F_ITEMS=$(num "$(e proof_feature_hits_items)")
F_LIST=$(e proof_feature_sites_list);   F_TABLE=$(e proof_feature_hits_table)
F_DECL=$(num "$(e proof_feature_declared)")

pub fh_run_feature_id "${F_ID:--}"
pub fh_run_state "${F_STATE:--}"
pub fh_run_own_hits "$F_OWN"
pub fh_run_global_hits "$F_GLOB"
pub fh_run_hits_gap "$F_GAP"
pub fh_run_attributed "$F_ATTR"
pub fh_run_unattributed "$F_UNAT"
pub fh_run_sites_total "$F_SITES"
pub fh_run_hits_items "$F_ITEMS"
pub fh_run_sites_list "${F_LIST:--}"
pub fh_run_hits_table "${F_TABLE:--}"

# ====================================================== 1. L'ATTRIBUTION EXISTE ET EST PROPRE ==
d1=0; why1=""
f1(){ d1=$((d1+1)); why1="${why1:+$why1+}$1"; }
[ "$F_ID" = "$ID" ]                || f1 id-non-publie
[ "$F_STATE" = hit ]               || f1 "etat-$F_STATE"
[ "$F_OWN" -gt 0 ] 2>/dev/null     || f1 compte-propre-nul
[ "$F_GLOB" -gt 0 ] 2>/dev/null    || f1 compte-global-nul
# LE COEUR DU DEFAUT : les deux comptes doivent etre DEUX NOMBRES DIFFERENTS. Tant qu'ils sont
# egaux, lire l'un ou l'autre revient au meme et le temoin reste vacue.
[ "$F_GAP" -gt 0 ] 2>/dev/null     || f1 ecart-nul
[ "$F_GAP" = "$((F_GLOB - F_OWN))" ] 2>/dev/null || f1 ecart-incoherent
[ "$F_DECL" = 1 ]                  || f1 site-non-declare
[ "$F_SITES" -gt 0 ] 2>/dev/null   || f1 aucun-site-declare
# L'arithmetique : tout ce que le binaire a compte est soit attribue a un item, soit range dans
# le seau `__unattributed` dont AUCUN item ne peut se prevaloir.
if [ "$F_ATTR" -ge 0 ] 2>/dev/null && [ "$F_UNAT" -ge 0 ] 2>/dev/null && [ "$F_GLOB" -ge 0 ] 2>/dev/null; then
  [ "$((F_ATTR + F_UNAT))" = "$F_GLOB" ] || f1 somme-fausse
else
  f1 sommes-absentes
fi
pub fh_d1_attribution "$d1"
pub fh_d1_why "${why1:--}"

# ============================================ 2. DEUX BRAS, SUR LA MEME COURSE =================
# Un item MOTEUR non nul, un AUTRE item moteur a un compte DIFFERENT, un item de HARNAIS pur a
# zero. Les trois viennent de la MEME table, produite par la MEME course.
ARM_OTHER_ID="-"; ARM_OTHER_HITS=-1
if [ -n "$F_TABLE" ] && [ "$F_TABLE" != "-" ]; then
  read -r ARM_OTHER_ID ARM_OTHER_HITS <<<"$(printf '%s\n' "$F_TABLE" | tr ',' '\n' \
    | awk -F: -v me="$ID" '$1!=me && $1!="__unattributed" && $2+0>0 {if($2+0>b){b=$2+0;n=$1}} END{print (n?n:"-"), (n?b:-1)}')"
fi
# L'item de HARNAIS PUR : un item du backlog dont le verdict vit dans son recensement et dont
# AUCUN site n'est compile dans ce binaire. Il est CHOISI par la donnee, pas ecrit en dur.
ARM_HARNESS_ID=$(python3 - "$AP" "$F_LIST" <<'PY' 2>/dev/null
import os, sys, yaml
ap, sites = sys.argv[1], set(filter(None, sys.argv[2].split(',')))
try:
    items = (yaml.safe_load(open(os.path.join(ap, 'backlog.yaml'), encoding='utf-8')) or {}).get('items') or []
except Exception:
    items = []
cand = [i['id'] for i in items if i.get('id') and i['id'] not in sites
        and os.path.exists(os.path.join(ap, 'lib', 'census', i['id'] + '.sh'))]
print(sorted(cand)[0] if cand else '-')
PY
)
ARM_HARNESS_HITS=0
if [ -n "$ARM_HARNESS_ID" ] && [ "$ARM_HARNESS_ID" != "-" ]; then
  ARM_HARNESS_HITS=$(printf '%s\n' "$F_TABLE" | tr ',' '\n' | awk -F: -v n="$ARM_HARNESS_ID" '$1==n{print $2+0}' | tail -1)
  ARM_HARNESS_HITS="${ARM_HARNESS_HITS:-0}"
fi
d2=0; why2=""
f2(){ d2=$((d2+1)); why2="${why2:+$why2+}$1"; }
[ "$F_OWN" -gt 0 ] 2>/dev/null                 || f2 bras-moteur-nul
[ "$ARM_OTHER_ID" != "-" ]                     || f2 pas-de-second-item-moteur
[ "$ARM_OTHER_HITS" != "$F_OWN" ]              || f2 deux-items-meme-compte
[ "$ARM_HARNESS_ID" != "-" ]                   || f2 pas-d-item-de-harnais-pur
[ "$ARM_HARNESS_HITS" = 0 ]                    || f2 item-de-harnais-non-nul
case ",$F_LIST," in *",$ARM_HARNESS_ID,"*) f2 item-de-harnais-declare-comme-site ;; esac
pub fh_arm_engine_id "$ID"
pub fh_arm_engine_hits "$F_OWN"
pub fh_arm_other_id "$ARM_OTHER_ID"
pub fh_arm_other_hits "$ARM_OTHER_HITS"
pub fh_arm_harness_id "$ARM_HARNESS_ID"
pub fh_arm_harness_hits "$ARM_HARNESS_HITS"
pub fh_d2_two_arms "$d2"
pub fh_d2_why "${why2:--}"

# ================== 3. LE VRAI VALIDATEUR, JOUE SUR QUATRE PREUVES FABRIQUEES ==================
# On ne lit pas le texte du juge : on le JOUE. Quatre preuves, quatre etats, et c'est
# `validators/generic.sh` lui-meme — pas une tranche recopiee — qui rend son verdict. Les autres
# constats (sha, fraicheur) sont attendus et ignores : on ne compte QUE les lignes du temoin.
FIXD="$AP/reports"; FIX_PFX="zzfix-feature-hits"
FIXCEN="$AP/lib/census/$FIX_PFX-d.sh"
nettoie(){ rm -rf "$FIXD/$FIX_PFX-a" "$FIXD/$FIX_PFX-b" "$FIXD/$FIX_PFX-c" "$FIXD/$FIX_PFX-d" "$FIXCEN"; }
trap nettoie EXIT
nettoie
ERRD=$(mktemp -d 2>/dev/null) || ERRD="/tmp/fh.$$"; mkdir -p "$ERRD"

# Les lignes du TEMOIN, et rien d'autre.
WIT_ANY="instrument de CET item|JAMAIS tire|ne sait pas attribuer|l'etat et le compte se contredisent|son recensement|etat que le validateur ne connait pas|sans_item|armed=1' absente"

joue(){   # $1 = suffixe de fixture, le reste = lignes de proof.txt
  local sfx="$1"; shift
  local fid="$FIX_PFX-$sfx" d
  d="$FIXD/$fid"; mkdir -p "$d"
  { echo "source=x86"; echo "binary=build/game/gk"; echo "sha=0000000000000000"
    echo "crash=0"; echo "frames=100000"
    printf '%s\n' "$@" | sed "s/@ID@/$fid/g"
  } > "$d/$PROOFNAME"
  AUTOPORT_PHASE_ID="$fid" bash "$AP/validators/generic.sh" >/dev/null 2>"$ERRD/$sfx.err"
  echo $?
}
wit(){ local n; n=$(grep -acE "$1" "$ERRD/$2.err" 2>/dev/null); echo "${n:-0}"; }

# A — CONTROLE A LAISSER : compte propre non nul. Le juge ne doit RIEN dire sur le temoin.
RC_A=$(joue a "FEATURE @ID@ armed=1 hits=4419755" "proof_feature_id=@ID@" "proof_feature_state=hit" \
  "proof_feature_declared=1" "proof_feature_own_hits=42" "proof_feature_global_hits=4419755" \
  "proof_census_present=0" "proof_census_rc=-1" "proof_census_keys=0")
# B — site COMPILE, jamais atteint. Etat nomme, distinct de C.
RC_B=$(joue b "FEATURE @ID@ armed=1 hits=4419755" "proof_feature_id=@ID@" "proof_feature_state=declared_unreached" \
  "proof_feature_declared=1" "proof_feature_own_hits=0" "proof_feature_global_hits=4419755" \
  "proof_census_present=0" "proof_census_rc=-1" "proof_census_keys=0")
# C — LA PREUVE QUI PASSAIT AVANT : `armed=1 hits=4419755`, et rien du tout de l'item. Elle doit
# etre REFUSEE, sinon le correctif n'a rien change.
RC_C=$(joue c "FEATURE @ID@ armed=1 hits=4419755" "proof_feature_id=@ID@" "proof_feature_state=absent" \
  "proof_feature_declared=0" "proof_feature_own_hits=0" "proof_feature_global_hits=4419755" \
  "proof_census_present=0" "proof_census_rc=-1" "proof_census_keys=0")
# D — ITEM DE HARNAIS : aucun site moteur, mais un recensement qui a tourne et publie. Accepte.
printf '#!/usr/bin/env bash\necho fh_fixture=1\n' > "$FIXCEN"
RC_D=$(joue d "FEATURE @ID@ armed=1 hits=4419755" "proof_feature_id=@ID@" "proof_feature_state=absent" \
  "proof_feature_declared=0" "proof_feature_own_hits=0" "proof_feature_global_hits=4419755" \
  "proof_census_present=1" "proof_census_rc=0" "proof_census_keys=12")

W_A=$(wit "$WIT_ANY" a); W_B=$(wit "JAMAIS tire" b); W_C=$(wit "n'a pas de recensement" c)
W_D=$(wit "$WIT_ANY" d)
# En CROIX : le marqueur de l'un doit etre ABSENT de la sortie de l'autre. Deux messages
# differents rendent tous les deux « 1 occurrence » — comparer les comptes ne separerait rien.
W_B_DANS_C=$(wit "JAMAIS tire" c); W_C_DANS_B=$(wit "n'a pas de recensement" b)
d3=0; why3=""
f3(){ d3=$((d3+1)); why3="${why3:+$why3+}$1"; }
[ "$W_A" = 0 ]                 || f3 bras-a-accuse-un-compte-propre-non-nul
[ "$W_B" -gt 0 ] 2>/dev/null   || f3 bras-b-ne-nomme-pas-le-site-jamais-atteint
[ "$W_C" -gt 0 ] 2>/dev/null   || f3 bras-c-accepte-le-compteur-global-seul
[ "$W_D" = 0 ]                 || f3 bras-d-refuse-un-item-de-harnais
[ "$W_B_DANS_C" = 0 ]          || f3 le-message-de-b-sort-aussi-pour-c
[ "$W_C_DANS_B" = 0 ]          || f3 le-message-de-c-sort-aussi-pour-b
pub fh_fixture_a_witness "$W_A"; pub fh_fixture_a_rc "$RC_A"
pub fh_fixture_b_witness "$W_B"; pub fh_fixture_b_rc "$RC_B"
pub fh_fixture_c_witness "$W_C"; pub fh_fixture_c_rc "$RC_C"
pub fh_fixture_d_witness "$W_D"; pub fh_fixture_d_rc "$RC_D"
pub fh_fixture_b_marker_in_c "$W_B_DANS_C"
pub fh_fixture_c_marker_in_b "$W_C_DANS_B"
pub fh_d3_states "$d3"
pub fh_d3_why "${why3:--}"
nettoie; trap - EXIT; rm -rf "$ERRD"

# ================== 4. LES ITEMS DONT LE TEMOIN CHANGE DE SENS, NOMMES ========================
# Trois familles, mesurees sur le backlog VERSIONNE croise avec les sites reellement compiles
# dans ce binaire. La troisieme est celle dont la prochaine preuve sera rouge pour cette raison :
# elle est publiee ITEM PAR ITEM, pas seulement comptee.
CHG=$(python3 - "$AP" "$F_LIST" <<'PY' 2>/dev/null
import os, sys, yaml
ap, sites = sys.argv[1], set(filter(None, sys.argv[2].split(',')))
try:
    items = (yaml.safe_load(open(os.path.join(ap, 'backlog.yaml'), encoding='utf-8')) or {}).get('items') or []
except Exception:
    items = []
vivant = lambda s: s not in ('archived', 'validated')
eng = cen = non = 0; liste = []
for it in items:
    iid = it.get('id')
    if not iid:
        continue
    if iid in sites:
        eng += 1
    elif os.path.exists(os.path.join(ap, 'lib', 'census', iid + '.sh')):
        cen += 1
    else:
        non += 1
        if vivant(it.get('status')):
            liste.append(iid)
print('fh_items_total=%d' % len(items))
print('fh_witness_engine=%d' % eng)
print('fh_witness_census=%d' % cen)
print('fh_witness_none=%d' % non)
print('fh_witness_none_live=%d' % len(liste))
s = ','.join(sorted(liste))
print('fh_witness_none_live_list=%s' % (s[:4000] if s else '-'))
print('fh_witness_none_live_truncated=%d' % (1 if len(s) > 4000 else 0))
PY
)
printf '%s\n' "$CHG"
g(){ printf '%s\n' "$CHG" | sed -n "s/^$1=//p" | tail -1; }
# Les preuves DEJA sur le disque de cet arbre : combien portaient le temoin vacue, combien
# changent de sens. `.autoport/reports/` est GITIGNORE — le compte depend donc de l'arbre, et on
# dit LEQUEL plutot que de le taire.
SEEN=0; FLIP=0; FLIPL=""
for pf in "$AP"/reports/*/"$PROOFNAME"; do
  [ -f "$pf" ] || continue
  iid=$(basename "$(dirname "$pf")")
  case "$iid" in $FIX_PFX-*) continue ;; esac
  grep -qaE "^FEATURE $iid armed=1 hits=[1-9][0-9]*$" "$pf" || continue
  SEEN=$((SEEN+1))
  case ",$F_LIST," in *",$iid,"*) continue ;; esac
  [ -f "$AP/lib/census/$iid.sh" ] && continue
  FLIP=$((FLIP+1))
  # NOMMER, pas seulement COMPTER. « 15 preuves changent de sens » n'est pas une liste : le
  # rapport doit pouvoir dire LESQUELLES, sinon personne ne sait laquelle rouvrir.
  FLIPL="${FLIPL:+$FLIPL,}$iid"
done
pub fh_proofs_seen "$SEEN"
pub fh_proofs_flip "$FLIP"
pub fh_proofs_flip_list "${FLIPL:--}"
pub fh_proofs_measured_in "$ROOT"
d4=0; why4=""
f4(){ d4=$((d4+1)); why4="${why4:+$why4+}$1"; }
[ -n "$(g fh_witness_engine)" ]      || f4 classement-absent
[ "$(num "$(g fh_witness_engine)")" -gt 0 ] 2>/dev/null || f4 aucun-item-a-temoin-moteur
[ -n "$(g fh_witness_none_live_list)" ] || f4 liste-non-publiee
[ "$(e proof_feature_sites_list_truncated)" = 0 ] || f4 liste-des-sites-tronquee-classement-faux
[ "$(g fh_witness_none_live_truncated)" = 0 ] || f4 liste-des-items-qui-changent-tronquee
# Le compte et la liste disent la MEME chose ou l'un des deux ment : un `fh_proofs_flip=15`
# a cote d'une liste vide serait un chiffre que personne ne peut verifier.
[ "$FLIP" = 0 ] || [ -n "$FLIPL" ] || f4 preuves-qui-changent-comptees-mais-non-nommees
pub fh_d4_change_list "$d4"
pub fh_d4_why "${why4:--}"

# ============================================================== LA SOMME ======================
pub fh_census_ran 1
pub feature_hits_defects "$((d1 + d2 + d3 + d4))"
