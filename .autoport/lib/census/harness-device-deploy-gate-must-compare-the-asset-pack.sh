#!/usr/bin/env bash
# census/harness-device-deploy-gate-must-compare-the-asset-pack.sh — LE VERDICT DE L'ITEM.
#
# LANCE PAR `lib/proof_run.sh` (crochet `lib/census/<item-id>.sh`), apres la course. Il n'ecrit
# aucun champ de `proof.txt` lui-meme.
#
# `asset_deploy_ungated` = SOMME de termes publies separement, dans l'ordre du livrable :
#   1. le cout d'avant, CHIFFRE (compte publie ; un recensement vide est un terme, pas un vert)
#   2. la porte lit les deux : branchee dans le chemin appareil de proof_run.sh ET dans la
#      fermeture (deploy_verify.sh) ; ecart -> livraison ; livraison ratee -> ROUGE
#   3. controle positif fabrique : porte d'AVANT `identique/deploy_attempted=0`, porte d'APRES
#      `deploye` — les deux verdicts publies
#   4. controle negatif : pack identique -> aucune installation, et la course tourne
#   5. aucune livraison a la main : le cas de l'essai 17 de hud-eco-gauge se livre tout seul
# INCONNU = DEFAUT : chaque temoin manquant AJOUTE au compte.
set -uo pipefail

ROOT=$(git rev-parse --show-toplevel 2>/dev/null) || { echo "asset_census_ran=0"; exit 1; }
AP="$ROOT/.autoport"
cd "$ROOT" || exit 1

RAW=$(bash "$AP/lib/asset_pack_selftest.sh" 2>/dev/null)
g(){ printf '%s\n' "$RAW" | sed -n "s/^$1=//p" | tail -1; }
n(){ local v; v=$(g "$1"); case "$v" in ''|*[!0-9-]*) echo -1 ;; *) echo "$v" ;; esac; }
pub(){ printf '%s=%s\n' "$1" "${2:--}"; }
hex32(){ printf '%s' "$1" | grep -cE '^[0-9a-f]{32}$'; }
DEFAUTS=0
terme(){ pub "$1" "$2"; DEFAUTS=$((DEFAUTS + $2)); }

# ============================================================== 0. LE BANC A-T-IL TOURNE =====
pub asset_banc_ran "$(n selftest_ran)"
pub asset_banc_arms_courus "$(n selftest_arms_courus)"
t=0; [ "$(n selftest_ran)" = 1 ] || t=$((t + 1)); [ "$(n selftest_arms_courus)" = 5 ] || t=$((t + 1))
terme asset_t0_banc_incomplet "$t"

# LES VERDICTS DE CHAQUE BRAS, COTE A COTE, avant d'en juger un seul.
for a in egaux goal vieux sansapk installko; do
  for k in rc decision raison installs started proof preuve_precedente pack_local pack_ancien \
           pack_dev_final pack_mesure mesure_sur_pack_perime octets_modifies_game_cgo \
           p_proof_binary_decision p_proof_binary_deploy_attempted p_asset_pack_decision \
           p_asset_pack_deploy_attempted p_asset_pack_local_md5 p_asset_pack_device_md5_before \
           p_asset_pack_device_md5; do
    v=$(g "arm_${a}_$k"); [ -n "$v" ] && pub "asset_arm_${a}_$k" "$v"
  done
done

# ========================================= 2. LA PORTE EST BRANCHEE, ET ELLE LIT LES DEUX =====
# Le branchement se lit dans le CODE (appel hors commentaire, entre les marqueurs du bloc que le
# bras `vieux` retire) — et son EFFET se lit sur le bras `goal`. L'un sans l'autre ne vaut rien.
SITES_PR=$(awk 'index($0,"GARDE-PACK/debut"){f=1} f && !/^[[:space:]]*#/ && /deploy_verify_assets\.sh"[[:space:]]+--gate/{c++} index($0,"GARDE-PACK/fin"){f=0} END{print c+0}' "$AP/lib/proof_run.sh")
SITES_DV=$(grep -v '^[[:space:]]*#' "$AP/lib/deploy_verify.sh" | grep -cE 'deploy_verify_assets\.sh"[[:space:]]+--gate' || true)
pub asset_gate_call_sites_proof_run "$SITES_PR"
pub asset_gate_call_sites_deploy_verify "$SITES_DV"
t=0; [ "$SITES_PR" -ge 1 ] 2>/dev/null || t=1
terme asset_t2_proof_run_non_branche "$t"
t=0; [ "${SITES_DV:-0}" -ge 1 ] 2>/dev/null || t=1
terme asset_t2_cloture_non_branchee "$t"

# LES DEUX EMPREINTES COTE A COTE dans la preuve du bras `goal` : deux md5 de zip, differents.
t=0
[ "$(hex32 "$(g arm_goal_p_asset_pack_local_md5)")" = 1 ] || t=$((t + 1))
[ "$(hex32 "$(g arm_goal_p_asset_pack_device_md5_before)")" = 1 ] || t=$((t + 1))
[ "$(g arm_goal_p_asset_pack_local_md5)" != "$(g arm_goal_p_asset_pack_device_md5_before)" ] || t=$((t + 1))
terme asset_t2_empreintes_non_publiees "$t"

# UN DEPLOIEMENT QUI ECHOUE EST ROUGE, avant l'amorcage, sans detruire la preuve d'hier.
for a in sansapk installko; do
  t=0
  [ "$(n arm_${a}_rc)" = 6 ] || t=$((t + 1))
  [ "$(g arm_${a}_decision)" = refus ] || t=$((t + 1))
  [ "$(n arm_${a}_started)" = 0 ] || t=$((t + 1))
  [ "$(g arm_${a}_preuve_precedente)" = intacte ] || t=$((t + 1))
  [ "$(n arm_${a}_proof)" = 0 ] || t=$((t + 1))
  terme "asset_t2_echec_${a}_non_rouge" "$t"
done
# L'install ratee a bien ete TENTEE : sinon le bras mesurerait un autre refus que le sien.
t=0; [ "$(n arm_installko_installs)" = 1 ] || t=1
terme asset_t2_installko_non_tente "$t"

# ============================================ 3. CONTROLE POSITIF FABRIQUE : AVANT / APRES ====
# UN seul octet de GAME.CGO change dans le pack local, libgk.so identique dans les deux bras.
t=0
for a in goal vieux; do
  [ "$(n arm_${a}_octets_modifies_game_cgo)" = 1 ] || t=$((t + 1))
  [ "$(g arm_${a}_p_proof_binary_decision)" = identique ] || t=$((t + 1))
done
terme asset_t3_condition_non_fabriquee "$t"
# LA PORTE D'AVANT (bloc retire) : `identique`, deploy_attempted=0, et la course MESURE le pack
# N-1. Sans ce temoin, le controle positif n'aurait rien a quoi s'opposer.
t=0
[ "$(n arm_vieux_bloc_retire_lignes)" -ge 10 ] 2>/dev/null || t=$((t + 1))
[ "$(g arm_vieux_p_proof_binary_deploy_attempted)" = 0 ] || t=$((t + 1))
[ "$(n arm_vieux_installs)" = 0 ] || t=$((t + 1))
[ "$(n arm_vieux_mesure_sur_pack_perime)" = 1 ] || t=$((t + 1))
terme asset_t3_temoin_avant_absent "$t"
pub asset_verdict_avant "$(g arm_vieux_p_proof_binary_decision)/deploy_attempted=$(g arm_vieux_p_proof_binary_deploy_attempted)/pack_mesure_perime=$(g arm_vieux_mesure_sur_pack_perime)"
# LA PORTE D'APRES : elle deploie, elle le dit, et la course mesure le pack LOCAL.
t=0
[ "$(g arm_goal_decision)" = deploye ] || t=$((t + 1))
[ "$(g arm_goal_p_asset_pack_decision)" = deploye ] || t=$((t + 1))
[ "$(g arm_goal_p_asset_pack_deploy_attempted)" = 1 ] || t=$((t + 1))
[ "$(n arm_goal_installs)" = 1 ] || t=$((t + 1))
[ "$(g arm_goal_pack_dev_final)" = "$(g arm_goal_pack_local)" ] || t=$((t + 1))
[ "$(n arm_goal_proof)" = 1 ] || t=$((t + 1))
[ "$(n arm_goal_mesure_sur_pack_perime)" = 0 ] || t=$((t + 1))
terme asset_t3_porte_apres_ne_deploie_pas "$t"
pub asset_verdict_apres "$(g arm_goal_p_asset_pack_decision)/deploy_attempted=$(g arm_goal_p_asset_pack_deploy_attempted)/pack_mesure_perime=$(g arm_goal_mesure_sur_pack_perime)"

# ========================================================= 4. CONTROLE NEGATIF ===============
# Pack identique ET un APK conforme a portee : la porte ne doit RIEN installer, et la course
# doit tourner. Une porte qui repousse le pack a chaque essai coute un install par course.
t=0
[ "$(g arm_egaux_decision)" = identique ] || t=$((t + 1))
[ "$(n arm_egaux_installs)" = 0 ] || t=$((t + 1))
[ "$(n arm_egaux_rc)" = 0 ] || t=$((t + 1))
[ "$(n arm_egaux_started)" = 1 ] || t=$((t + 1))
[ "$(n arm_egaux_proof)" = 1 ] || t=$((t + 1))
[ "$(n arm_egaux_mesure_sur_pack_perime)" = 0 ] || t=$((t + 1))
terme asset_t4_negatif_en_defaut "$t"

# ================================================= 5. AUCUNE LIVRAISON A LA MAIN =============
# Le bras `goal` EST l'essai 17 de hud-eco-gauge : binaire identique, pack neuf dans l'APK du
# constructeur. Sans `notes/essai17-livraison.sh`, il est livre et mesure : le geste manuel
# n'a plus d'objet.
t=0
{ [ "$(g arm_goal_decision)" = deploye ] && [ "$(n arm_goal_mesure_sur_pack_perime)" = 0 ]; } || t=1
terme asset_manual_delivery_needed "$t"

# ================================================= 1. LE COUT D'AVANT, CHIFFRE ===============
# Les preuves appareil archivees (transcripts d'essai qui embarquent proof.txt, et les copies
# posees sous reports/) ou la garde binaire a dit `identique` sans rien tenter, rattachees au
# dernier commit `[autoport/<item>]` atteignable depuis `proof_head_at_start` (le HEAD de depart
# est tres souvent un commit de comptabilite du superviseur, pas celui de l'essai).
COUT=$(python3 - "$ROOT" <<'PY' 2>/dev/null
import os, re, subprocess, sys
root = sys.argv[1]
ap = os.path.join(root, '.autoport')
KV = re.compile(r'^(?:[^\s:=]+:)?([A-Za-z_][A-Za-z0-9_]*)=(\S*)$')
fichiers = []
for base in ('logs', 'reports'):
    for dp, _dn, fn in os.walk(os.path.join(ap, base)):
        for f in fn:
            if f.endswith(('.jsonl', '.txt', '.log')):
                fichiers.append(os.path.join(dp, f))
vus = {}
for p in fichiers:
    try:
        b = open(p, 'rb').read()
    except OSError:
        continue
    if b'proof_binary_decision=identique' not in b:
        continue
    t = b.decode('utf-8', 'replace').replace('\\n', '\n')
    # Un bloc = une suite de lignes cle=valeur (un `cat proof.txt`) ; il se ferme sur une ligne
    # qui n'en est pas une.
    bloc = {}
    def ferme(bloc):
        if (bloc.get('proof_binary_decision') == 'identique'
                and bloc.get('proof_binary_deploy_attempted') == '0'
                and bloc.get('source', 'device') == 'device'
                and '@' in bloc.get('proof_attempt_id', '')
                and re.match(r'^[0-9a-f]{7,40}$', bloc.get('proof_head_at_start', ''))):
            item, reste = bloc['proof_attempt_id'].split('@', 1)
            essai = reste.split('#', 1)[0]
            vus.setdefault((item, essai), bloc['proof_head_at_start'])
    for ligne in t.split('\n'):
        m = KV.match(ligne.strip())
        if m:
            bloc[m.group(1)] = m.group(2)
        else:
            if bloc:
                ferme(bloc)
            bloc = {}
    if bloc:
        ferme(bloc)

def git(*a):
    return subprocess.run(['git', '-C', root] + list(a), capture_output=True, text=True).stdout
CODE = re.compile(r'^(game|common|goalc|android|decompiler|third-party)/.*\.(cpp|h|hpp|c|cc|java|kt|vert|frag|glsl|txt)$')
classes = {'goal-ou-asset': [], 'cpp': [], 'autre': [], 'sans-commit': []}
for (item, essai), head in sorted(vus.items()):
    c = git('log', '-F', '--grep=[autoport/%s]' % item, '-n1', '--format=%H', head).strip()
    if not c:
        classes['sans-commit'].append((item, essai, '-')); continue
    fs = [f for f in git('diff-tree', '--no-commit-id', '--name-only', '-r', c).split('\n') if f]
    code = [f for f in fs if not f.startswith('.autoport/')]
    if any(CODE.match(f) for f in code):
        k = 'cpp'
    elif code and all(f.startswith('goal_src/') or 'asset' in f for f in code):
        k = 'goal-ou-asset'
    else:
        k = 'autre'
    classes[k].append((item, essai, c[:10]))
print('asset_avant_courses_identiques=%d' % len(vus))
for k, v in classes.items():
    print('asset_avant_%s=%d' % (k.replace('-', '_'), len(v)))
g = classes['goal-ou-asset']
print('asset_avant_goal_only=%d' % len(g))
print('asset_avant_goal_only_hud_eco_gauge=%d' % sum(1 for x in g if x[0] == 'hud-eco-gauge'))
print('asset_avant_goal_only_liste=%s' % (','.join('%s@%s:%s' % x for x in g) or '-'))
print('asset_avant_ran=1')
PY
)
printf '%s\n' "$COUT"
c(){ printf '%s\n' "$COUT" | sed -n "s/^$1=//p" | tail -1; }
t=0
[ "$(c asset_avant_ran)" = 1 ] || t=$((t + 1))
[ "$(c asset_avant_goal_only)" -ge 1 ] 2>/dev/null || t=$((t + 1))
terme asset_t1_cout_non_chiffre "$t"

# ========================================== TEMOIN REEL, EN LECTURE SEULE (hors somme) ========
# Le banc prouve la logique ; le telephone branche prouve que la LECTURE marche sur un vrai
# Android (`unzip` et `md5sum` du systeme). `--no-deploy` : rien n'est installe. Hors somme : un
# telephone debranche n'est pas un defaut de cette porte.
BIN_LOC="$ROOT/build-android/lib/arm64-v8a/libgk.so"
LIVE=$(AUTOPORT_ASSET_GATE_REGISTRY="$AP/logs/device-asset-gate.tsv" \
       bash "$AP/lib/deploy_verify_assets.sh" --gate --no-deploy --item "${AUTOPORT_CENSUS_ID:-recensement}" \
       --arm sonde-lecture --binary "$BIN_LOC" 2>/dev/null)
l(){ printf '%s\n' "$LIVE" | sed -n "s/^$1=//p" | tail -1; }
pub asset_live_decision "$(l asset_pack_decision)"
pub asset_live_reason "$(l asset_pack_reason)"
pub asset_live_serial "$(l asset_pack_serial)"
pub asset_live_pack_local_md5 "$(l asset_pack_local_md5)"
pub asset_live_pack_device_md5 "$(l asset_pack_device_md5)"
pub asset_live_pack_local_version "$(l asset_pack_local_version)"
pub asset_live_pack_device_stamp "$(l asset_pack_device_stamp)"
SER=$(l asset_pack_serial)
if [ -n "$SER" ] && [ "$SER" != "-" ]; then
  ADBX="${ADB:-/home/emeric/Android/platform-tools/adb}"
  DP=$(timeout 20 "$ADBX" -s "$SER" shell pm path org.opengoal.gk.jak1 2>/dev/null | sed 's/package://' | tr -d '\r' | head -1)
  LSO=$(timeout 60 "$ADBX" -s "$SER" shell "md5sum $(dirname "${DP:-/x}")/lib/arm64/libgk.so" 2>/dev/null | tr -d '\r' | awk '{print $1}')
  pub asset_live_libgk_device_md5 "${LSO:--}"
fi
pub asset_live_libgk_local_md5 "$( [ -s "$BIN_LOC" ] && md5sum "$BIN_LOC" | cut -d' ' -f1)"

# ===================================================================== LA SOMME ==============
pub asset_deploy_ungated "$DEFAUTS"
pub asset_census_ran 1
