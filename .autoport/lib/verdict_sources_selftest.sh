#!/usr/bin/env bash
# lib/verdict_sources_selftest.sh — LE BANC DE `harness-verdict-sources-are-incomplete`.
#
# CE QU'IL MESURE, DANS L'ORDRE DES CINQ POINTS DU LIVRABLE :
#   1. LE CRITERE est epingle      -> deux bras sur le VRAI `validators/generic.sh` : desserrer
#                                     le critere APRES la course doit REFUSER, et le laisser
#                                     tranquille doit PASSER.
#   2. LES ACQUIS sont epingles    -> deux bras : les huit presents passent, l'un d'eux retire
#                                     APRES la course refuse en NOMMANT l'acquis.
#   3. LA DERIVATION ignore la prose -> trois jambes sur un depot jetable : un fichier cite par du
#                                     CODE est epingle, le meme cite par un COMMENTAIRE ne l'est
#                                     pas, et l'ancienne regle (`AUTOPORT_VS_COMMENTS=1`) les
#                                     epingle TOUS LES DEUX. Sans cette troisieme jambe, un
#                                     nommeur qui ne verrait plus rien du tout passerait au vert.
#   4. `proof.txt` n'est plus ecrit apres son `mv` -> le compte de redirections vers `$OUTFILE`
#                                     hors du `mv`, aujourd'hui ET au commit d'avant le correctif
#                                     (`lib/ablation_anchor.sh`, ancre sur le marqueur) ; puis les
#                                     SCEAUX des courses REELLES, ou la machine a relu le fichier
#                                     a la sortie du processus.
#   5. LES BACS A SABLE declarent ce qu'ils copient a partir de la liste de la PORTE -> l'ecart
#                                     entre les deux listes, pour chacun des deux.
#
# Il ne JUGE rien : la somme et la polarite « inconnu = defaut » sont dans
# lib/census/harness-verdict-sources-are-incomplete.sh. Sortie : des `cle=valeur` sur stdout,
# les explications sur stderr.
set -uo pipefail
export LC_ALL=C

ROOT=$(git rev-parse --show-toplevel 2>/dev/null) || { echo "vsq_selftest_ran=0"; exit 1; }
AP="$ROOT/.autoport"
cd "$ROOT" || exit 1
SB=$(mktemp -d -t vsources.XXXXXX) || { echo "vsq_selftest_ran=0"; exit 1; }
trap 'rm -rf "$SB"' EXIT
note(){ printf '[vs-selftest] %s\n' "$*" >&2; }
kv(){ printf '%s=%s\n' "$1" "${2:--}"; }

SANDITEM="sandbox-verdict-sources"

# ============================================ un depot jetable juge par le VRAI validateur =====
# LA LISTE DE CE QU'ON COPIE SORT DU NOMMEUR, jamais d'une enumeration tapee ici : c'est la regle
# du point 5, et ce banc se l'applique a lui-meme.
monte(){  # monte <dossier> -> 0, et laisse un depot que `validators/generic.sh` peut juger
  local dir=$1 rel
  mkdir -p "$dir/.autoport/reports/$SANDITEM" "$dir/build/game" \
           "$dir/game" "$dir/common" "$dir/android" "$dir/goal_src" || return 1
  while IFS= read -r rel; do
    [ -n "$rel" ] || continue
    mkdir -p "$dir/$(dirname "$rel")" || return 1
    cp "$ROOT/$rel" "$dir/$rel" || return 1
  done < <(bash "$AP/lib/verdict_sources.sh" "$SANDITEM" list)
  git -C "$dir" init -q >/dev/null 2>&1 || return 1           # git-sandbox-ok
  printf 'faux gk du banc des sources du verdict\n' > "$dir/build/game/gk"
  critere "$dir" 'key: episodes, op: "==", value: 0'
}

critere(){  # critere <dossier> <corps-du-gate> : le SEUL endroit ou le backlog du bac est ecrit
  cat > "$1/.autoport/backlog.yaml" <<YAML
version: 1
items:
  - id: $SANDITEM
    feature: "banc des sources du verdict"
    status: open
    device: false
    gate: {$2}
YAML
}

pose_preuve(){  # pose_preuve <dossier> : une preuve comme la machine l'ecrit, l'epingle comprise
  local dir=$1 sha
  sha=$(sha256sum "$dir/build/game/gk" | cut -c1-16)
  { echo "source=x86"; echo "binary=build/game/gk"; echo "sha=$sha"
    echo "started_at=2026-09-12T09:00:00Z"; echo "duration_s=62"; echo "crash=0"; echo "frames=1800"
    echo "proof_feature_id=$SANDITEM"; echo "proof_feature_state=hit"
    echo "proof_feature_declared=1"; echo "proof_feature_own_hits=37"
    echo "proof_feature_global_hits=4419755"
    echo "proof_census_present=0"; echo "proof_census_rc=-1"; echo "proof_census_keys=0"
    ( cd "$dir" && bash .autoport/lib/verdict_sources.sh "$SANDITEM" kv )
    echo "FEATURE $SANDITEM armed=1 hits=37"
    echo "episodes=0"
  } > "$dir/.autoport/reports/$SANDITEM/proof.txt"
}

juge(){  # juge <dossier> -> code de retour ; la sortie va dans $JUGE_OUT
  JUGE_OUT=$( cd "$1" && AUTOPORT_PHASE_ID="$SANDITEM" bash .autoport/validators/generic.sh 2>&1 )
  return $?
}
constats(){ printf '%s\n' "$JUGE_OUT" | sed -n 's/.*FAIL\] \([0-9]\{1,\}\) constat.*/\1/p' | tail -1; }

# ================================================== 1. LE CRITERE, DEUX BRAS ==================
# LE BRAS `apres` NE DESSERRE PAS SEULEMENT : il desserre SANS CHANGER LE RESULTAT. `episodes=0`
# satisfait `== 0` comme il satisfait `<= 9`. Le seul constat possible est donc celui qu'on
# cherche — le critere a bouge entre la course et son verdict — et pas un critere viole.
if monte "$SB/crit"; then
  kv vsq_crit_monte 1
  pose_preuve "$SB/crit"
  kv vsq_crit_sha_preuve "$(sed -n 's/^verdict_criterion_sha=//p' "$SB/crit/.autoport/reports/$SANDITEM/proof.txt" | tail -1)"
  juge "$SB/crit"; kv vsq_crit_avant_rc $?
  kv vsq_crit_avant_sortie "$(printf '%s' "$JUGE_OUT" | tr ' \n' '__' | cut -c1-120)"
  critere "$SB/crit" 'key: episodes, op: "<=", value: 9'
  kv vsq_crit_sha_disque "$( cd "$SB/crit" && bash .autoport/lib/verdict_sources.sh "$SANDITEM" criterion_sha )"
  kv vsq_crit_disque "$( cd "$SB/crit" && bash .autoport/lib/verdict_sources.sh "$SANDITEM" criterion )"
  juge "$SB/crit"; kv vsq_crit_apres_rc $?
  kv vsq_crit_apres_constats "$(constats)"
  case "$JUGE_OUT" in *verdict_criterion_sha*) kv vsq_crit_apres_nomme 1 ;; *) kv vsq_crit_apres_nomme 0 ;; esac
  # L'ABLATION GRATUITE : le FICHIER `backlog.yaml` n'est toujours PAS epingle. Si la fraicheur
  # avait attrape ce bras, elle rougirait pour tout item dont l'orchestrateur reecrit le statut.
  case "$JUGE_OUT" in *backlog.yaml*) kv vsq_crit_fichier_epingle 1 ;; *) kv vsq_crit_fichier_epingle 0 ;; esac
else
  kv vsq_crit_monte 0
fi

# ================================================== 2. LES ACQUIS, DEUX BRAS ==================
if monte "$SB/acq"; then
  kv vsq_acq_monte 1
  pose_preuve "$SB/acq"
  kv vsq_acq_count_preuve "$(sed -n 's/^verdict_acquis_count=//p' "$SB/acq/.autoport/reports/$SANDITEM/proof.txt" | tail -1)"
  juge "$SB/acq"; kv vsq_acq_complet_rc $?
  VICTIME=$( cd "$SB/acq" && ls -1 .autoport/acquis/*.sh | LC_ALL=C sort | tail -1 )
  rm -f "$SB/acq/$VICTIME"
  kv vsq_acq_victime "$(basename "$VICTIME")"
  kv vsq_acq_count_disque "$( cd "$SB/acq" && bash .autoport/lib/verdict_sources.sh "$SANDITEM" acquis_count )"
  juge "$SB/acq"; kv vsq_acq_ampute_rc $?
  case "$JUGE_OUT" in *"garde d'acquis"*) kv vsq_acq_ampute_nomme 1 ;; *) kv vsq_acq_ampute_nomme 0 ;; esac
else
  kv vsq_acq_monte 0
fi
kv vsq_acq_count_reel "$(bash "$AP/lib/verdict_sources.sh" "$SANDITEM" acquis_count)"
kv vsq_acq_sha_reel   "$(bash "$AP/lib/verdict_sources.sh" "$SANDITEM" acquis_sha)"

# ======================================= 3. LA DERIVATION IGNORE LA PROSE =====================
# Sur le depot REEL d'abord : le compte AVANT (ancienne regle) et APRES, et qui sort.
for it in harness-proof-props-pin harness-verdict-integrity harness-verdict-sources-are-incomplete; do
  cle=$(printf '%s' "$it" | tr -c 'A-Za-z0-9' '_')
  av=$(AUTOPORT_VS_COMMENTS=1 bash "$AP/lib/verdict_sources.sh" "$it" list)
  ap=$(bash "$AP/lib/verdict_sources.sh" "$it" list)
  kv "vsq_deriv_${cle}_avant" "$(printf '%s\n' "$av" | grep -c .)"
  kv "vsq_deriv_${cle}_apres" "$(printf '%s\n' "$ap" | grep -c .)"
  kv "vsq_deriv_${cle}_sortants" \
     "$(comm -23 <(printf '%s\n' "$av") <(printf '%s\n' "$ap") | paste -sd, -)"
done
# Puis la jambe qui rend la regle FALSIFIABLE : meme fichier, une citation en code, une en prose.
DV="$SB/deriv"
mkdir -p "$DV/.autoport/lib/census" "$DV/.autoport/validators" "$DV/.autoport/acquis"
git -C "$DV" init -q >/dev/null 2>&1                          # git-sandbox-ok
cp "$AP/lib/verdict_sources.sh" "$DV/.autoport/lib/"
: > "$DV/.autoport/validators/generic.sh"
: > "$DV/.autoport/lib/proof_run.sh"
: > "$DV/.autoport/lib/backlog.py"
: > "$DV/.autoport/lib/sonde_code.sh"
: > "$DV/.autoport/lib/sonde_prose.sh"
cat > "$DV/.autoport/lib/census/$SANDITEM.sh" <<'PROBE'
#!/usr/bin/env bash
# Cette ligne de PROSE nomme lib/sonde_prose.sh et ne doit epingler personne.
bash .autoport/lib/sonde_code.sh
PROBE
DVL=$( cd "$DV" && bash .autoport/lib/verdict_sources.sh "$SANDITEM" list )
DVA=$( cd "$DV" && AUTOPORT_VS_COMMENTS=1 bash .autoport/lib/verdict_sources.sh "$SANDITEM" list )
case "$DVL" in *sonde_code.sh*)  kv vsq_deriv_code_epingle 1 ;;  *) kv vsq_deriv_code_epingle 0 ;; esac
case "$DVL" in *sonde_prose.sh*) kv vsq_deriv_prose_epingle 1 ;; *) kv vsq_deriv_prose_epingle 0 ;; esac
case "$DVA" in *sonde_prose.sh*) kv vsq_deriv_prose_ancienne 1 ;; *) kv vsq_deriv_prose_ancienne 0 ;; esac
kv vsq_deriv_sonde_count "$(printf '%s\n' "$DVL" | grep -c .)"

# ================== 4. `proof.txt` N'EST PLUS ECRIT APRES SON PROPRE `mv` =====================
# LA GRANDEUR STATIQUE : les redirections vers `$OUTFILE` qui ne sont pas le `mv`. Les
# commentaires sont retires avant de compter — sinon cette prose-ci se compterait elle-meme.
MARQUEUR='PROOF-SCELLE/rien-apres-le-mv'
ecritures(){ sed -e 's/^[[:space:]]*#.*$//' -e 's/[[:space:]]#.*$//' \
             | grep -cE '(^|[^>])>>?[[:space:]]*"\$OUTFILE"'; }
kv vsq_seal_ecritures_now "$(ecritures < "$AP/lib/proof_run.sh")"
ANC=$(bash "$AP/lib/ablation_anchor.sh" "$ROOT" .autoport/lib/proof_run.sh "$MARQUEUR" kv 2>/dev/null)
ANCC=$(printf '%s\n' "$ANC" | sed -n 's/^anchor_commit=//p' | tail -1)
kv vsq_seal_ablation_method "$(printf '%s\n' "$ANC" | sed -n 's/^anchor_method=//p' | tail -1)"
kv vsq_seal_ablation_commit "${ANCC:0:12}"
if [ -n "$ANCC" ] && [ "$ANCC" != "-" ]; then
  BLOB=$(git -C "$ROOT" show "$ANCC:.autoport/lib/proof_run.sh" 2>/dev/null)
  kv vsq_seal_ecritures_avant "$(printf '%s\n' "$BLOB" | ecritures)"
else
  kv vsq_seal_ecritures_avant -1
fi
# LA GRANDEUR OBSERVEE, sur des courses REELLES. Le sceau est pose au `mv` et relu a la sortie du
# processus : deux empreintes differentes NOMMENT une ecriture posterieure. Le recensement tourne
# AVANT le `mv` de sa propre course — c'est donc la course PRECEDENTE, et celles des autres items,
# qu'on lit ici. Un zero sans population ne prouve rien : `vsq_seal_paires` le dit.
paires=0; ecarts=0; derive=0; liste=""
for sf in "$AP"/reports/*/proof*.seal; do
  [ -f "$sf" ] || continue
  ss=$(sed -n 's/^seal_sha=//p' "$sf" | tail -1)
  es=$(sed -n 's/^exit_sha=//p' "$sf" | tail -1)
  [ -n "$ss" ] && [ -n "$es" ] || continue
  pf="${sf%.seal}.txt"; [ -s "$pf" ] || continue
  paires=$((paires+1))
  nom=${sf#"$AP"/reports/}
  [ "$ss" = "$es" ] || { ecarts=$((ecarts+1)); liste="${liste:+$liste,}$nom"; }
  [ "$(sha256sum "$pf" | cut -c1-64)" = "$es" ] || derive=$((derive+1))
done
kv vsq_seal_paires "$paires"
kv vsq_seal_ecarts "$ecarts"
kv vsq_seal_derive_disque "$derive"
kv vsq_seal_ecarts_liste "${liste:--}"

# ============ 5. LES BACS A SABLE COPIENT LA LISTE DE LA PORTE, ET 4bis LE SCEAU D'UNE COURSE ==
# UNE SEULE course du bac a sable de l'epinglage sert les deux mesures :
#   - ce que le bac CONTIENT (on regarde le disque, pas ce qu'il dit copier) ;
#   - le SCEAU d'une course REELLE de `proof_run.sh` en mode APPAREIL. C'est le seul chemin du
#     harnais qui passe par le teardown de FIN — celui qui ajoutait ses cles a `proof.txt` APRES
#     son `mv`. Les sceaux que la course x86 laisse sur le disque ne traversent JAMAIS ce chemin :
#     un zero compte sur eux seuls serait vert par INACTION.
MP="$SB/manif-pin"; MT="$SB/manif-test"
: > "$MP"
PINOUT=$(AUTOPORT_PIN_MANIFEST="$MP" timeout -k 20 600 bash "$AP/lib/pin_props_selftest.sh" 2>/dev/null)
pg(){ printf '%s\n' "$PINOUT" | sed -n "s/^$1=//p" | tail -1; }
kv vsq_bac_pin_monte "$([ -s "$MP" ] && echo 1 || echo 0)"
kv vsq_bac_pin_arms_ok "$(pg selftest_arms_ok)"
PORTE_PIN=$(bash "$AP/lib/verdict_sources.sh" sandbox-pin list)
kv vsq_bac_pin_porte   "$(printf '%s\n' "$PORTE_PIN" | grep -c .)"
kv vsq_bac_pin_contenu "$(grep -c . "$MP" 2>/dev/null || echo 0)"
kv vsq_bac_pin_ecart \
   "$(comm -3 <(printf '%s\n' "$PORTE_PIN" | LC_ALL=C sort) <(LC_ALL=C sort "$MP" 2>/dev/null) | grep -c .)"
kv vsq_bac_pin_ecart_liste \
   "$(comm -3 <(printf '%s\n' "$PORTE_PIN" | LC_ALL=C sort) <(LC_ALL=C sort "$MP" 2>/dev/null) | tr -d '\t' | paste -sd, -)"

# LE SCEAU DE CETTE COURSE APPAREIL, et le temoin que rien n'a ete PERDU en avancant le teardown
# de fin avant le `mv` : ses cles doivent toujours etre DANS la preuve.
kv vsq_seal_bac_lu       "$(pg arm_neuf_seal_lu)"
kv vsq_seal_bac_sha      "$(pg arm_neuf_seal_sha)"
kv vsq_seal_bac_exit     "$(pg arm_neuf_seal_exit)"
kv vsq_seal_bac_disque   "$(pg arm_neuf_seal_disque)"
kv vsq_seal_bac_teardown "$(pg arm_neuf_teardown_fin_ran)"
kv vsq_seal_bac_props    "$(pg arm_neuf_teardown_fin_props_found)"
kv vsq_seal_bac_proof    "$(pg arm_neuf_proof)"
if [ -n "$(pg arm_neuf_seal_sha)" ] && [ "$(pg arm_neuf_seal_sha)" = "$(pg arm_neuf_seal_exit)" ]; then
  kv vsq_seal_bac_ecart 0
else
  kv vsq_seal_bac_ecart 1
fi

# LE SCEAU EST-IL SEULEMENT CAPABLE DE ROUGIR ? Meme bac a sable, meme course, un `proof_run.sh`
# a qui on RAJOUTE l'ecriture posterieure que ce chantier vient de retirer. Les deux empreintes
# doivent alors DIFFERER. Sans cette jambe, `vsq_seal_bac_ecart=0` se lirait aussi bien
# « rien n'a ete ecrit apres le mv » que « le sceau ne regarde rien ».
SEDBAD='s|^seal_et_arme$|&\necho "sonde_ecriture_posterieure=1" >> "$OUTFILE"|'
PINBAD=$(AUTOPORT_PIN_SED_NEUF="$SEDBAD" timeout -k 20 600 bash "$AP/lib/pin_props_selftest.sh" 2>/dev/null)
pb(){ printf '%s\n' "$PINBAD" | sed -n "s/^$1=//p" | tail -1; }
kv vsq_seal_sonde_proof "$(pb arm_neuf_proof)"
kv vsq_seal_sonde_lu    "$(pb arm_neuf_seal_lu)"
kv vsq_seal_sonde_sha   "$(pb arm_neuf_seal_sha)"
kv vsq_seal_sonde_exit  "$(pb arm_neuf_seal_exit)"
if [ -n "$(pb arm_neuf_seal_sha)" ] && [ "$(pb arm_neuf_seal_sha)" != "$(pb arm_neuf_seal_exit)" ]; then
  kv vsq_seal_sonde_detectee 1
else
  kv vsq_seal_sonde_detectee 0
fi

# La jambe pytest ne peut pas tourner sans son socle de fixtures : on le NOMME, donc on l'epingle.
kv vsq_bac_test_conftest "$([ -f "$AP/tests/harness/conftest.py" ] && echo 1 || echo 0)"
if AUTOPORT_SANDBOX_MANIFEST="$MT" timeout -k 10 300 python3 -m pytest \
     "$AP/tests/harness/test_proof.py" -k contient_exactement -q >"$SB/pytest.log" 2>&1; then
  kv vsq_bac_test_rc 0
else
  kv vsq_bac_test_rc 1; note "pytest : $(tail -3 "$SB/pytest.log" | tr '\n' ' ')"
fi
for k in attendu trouve manque en_trop; do
  kv "vsq_bac_test_$k" "$(sed -n "s/^$k=//p" "$MT" 2>/dev/null | tail -1)"
done
kv vsq_bac_test_manque_liste "$(sed -n 's/^manque_liste=//p' "$MT" 2>/dev/null | tail -1)"
kv vsq_bac_test_en_trop_liste "$(sed -n 's/^en_trop_liste=//p' "$MT" 2>/dev/null | tail -1)"

kv vsq_selftest_ran 1
