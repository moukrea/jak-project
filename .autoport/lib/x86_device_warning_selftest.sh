#!/usr/bin/env bash
# lib/x86_device_warning_selftest.sh — LE BANC DE L'AVERTISSEMENT AU LANCEMENT.
# (harness-x86-proof-for-a-device-item-must-shout-at-launch, 2026-09-22)
#
# CE QU'IL MESURE : une course x86 lancee sur un item dont le CRITERE porte `device=1`
# previent-elle le worker AVANT le moteur, ou le laisse-t-elle decouvrir au verdict que sa
# preuve ne sera jamais lue ?
#
# IL NE RECOPIE RIEN. Le bloc de decision est LEVE TEL QUEL de `lib/proof_run.sh`, entre ses
# marqueurs `X86-PREVENU-AU-LANCEMENT/debut|fin`, et execute avec les seules choses dont il
# depend : `$ID`, `$MODE`, `$AP`, `log`, `extra`. Une recopie du test mesurerait la recopie
# (test-that-slices-a-script). Le seul code ecrit ici est le PILOTE : les deux fonctions que
# `proof_run.sh` definit lui-meme, reduites a des capteurs.
#
# LES DEUX BRAS, ET L'ABLATION EST L'ABSENCE DE LA COUCHE (jamais un drapeau a zero) :
#   apres  le bloc du disque
#   avant  la MEME region levee du blob que `lib/ablation_anchor.sh` designe — le dernier
#          commit de ce chemin SANS le marqueur. La region y est VIDE : c'est le code qui
#          tournait quand hud-eco-gauge a perdu ses essais 15 et 16.
#
# LA POPULATION EST REELLE : des items du VRAI backlog, leur critere relu par le meme
# `lib/verdict_sources.sh` que le juge. Un bac a sable avec un backlog fabrique mesurerait le
# bac a sable.
#
# Sortie : des `cle=valeur` sur stdout. Aucune n'est un champ de proof.txt.
set -uo pipefail
export LC_ALL=C

N_ITEMS=5
MARQ_D='X86-PREVENU-AU-LANCEMENT/debut'
MARQ_F='X86-PREVENU-AU-LANCEMENT/fin'
CHEMIN='.autoport/lib/proof_run.sh'
# LE CONSTAT DU JUGE, EPINGLE. Garde d'EGALITE : le banc verifie qu'il est encore dans
# `validators/generic.sh`. S'il reformule, cet avertissement parlerait d'un refus mort.
CONSTAT="l'item exige l'appareil, la preuve est en source="

ROOT=$(git rev-parse --show-toplevel 2>/dev/null) || { echo "banc_panne=pas-de-depot"; exit 1; }
cd "$ROOT" || { echo "banc_panne=pas-de-cd"; exit 1; }
AP="$ROOT/.autoport"
TD=$(mktemp -d) || { echo "banc_panne=pas-de-tmp"; exit 1; }
trap 'rm -rf "$TD"' EXIT

pub(){ printf '%s=%s\n' "$1" "$(printf '%s' "${2:--}" | tr -s '[:space:]' '_')"; }

# ------------------------------------------------------------ la region, levee aux marqueurs --
leve(){ # <flux d'entree sur stdin> -> region sur stdout, VIDE si le marqueur n'y est pas
  awk -v d="$MARQ_D" -v f="$MARQ_F" 'index($0,d){inb=1} inb{print} index($0,f){inb=0}'
}

leve < "$CHEMIN" > "$TD/apres.sh"
pub bloc_apres_lignes "$(grep -c . "$TD/apres.sh" || true)"
pub bloc_apres_octets "$(wc -c < "$TD/apres.sh" | tr -d ' ')"

# ------------------------------------------- le bras d'AVANT : le blob, pas un `HEAD:` aveugle
ANC=$(bash "$AP/lib/ablation_anchor.sh" "$ROOT" "$CHEMIN" "$MARQ_D" kv 2>/dev/null)
ANCC=$(printf '%s\n' "$ANC" | sed -n 's/^anchor_commit=//p' | tail -1)
pub ancre_commit "${ANCC:--}"
pub ancre_methode "$(printf '%s\n' "$ANC" | sed -n 's/^anchor_method=//p' | tail -1)"
pub ancre_profondeur "$(printf '%s\n' "$ANC" | sed -n 's/^anchor_depth=//p' | tail -1)"
BLOB=""
if [ -n "$ANCC" ] && [ "$ANCC" != "-" ]; then BLOB=$(git -C "$ROOT" show "$ANCC:$CHEMIN" 2>/dev/null); fi
printf '%s\n' "$BLOB" > "$TD/blob.sh"
pub ancre_blob_octets "$(wc -c < "$TD/blob.sh" | tr -d ' ')"
# LE BLOB D'AVANT NE PORTE PAS CE QU'IL ABLATE : sinon les deux bras seraient le meme code.
pub ancre_blob_porte_le_marqueur "$(grep -cF -- "$MARQ_D" "$TD/blob.sh" || true)"
leve < "$TD/blob.sh" > "$TD/avant.sh"
pub bloc_avant_lignes "$(grep -c . "$TD/avant.sh" || true)"

# ---------------------------------------------------------------------------- le pilote --------
# `log` et `extra` sont les DEUX seules fonctions de `proof_run.sh` que le bloc appelle ; leur
# definition est ici reduite a un capteur (stderr d'un cote, bloc `cle=valeur` de l'autre).
cat > "$TD/pilote.sh" <<'PILOTE'
set -uo pipefail
log(){ printf '[proof_run %s] %s\n' "$ID" "$*" >&2; }
EXTRA=""
extra(){ EXTRA="${EXTRA:+$EXTRA
}$*"; }
. "$BLOC"
printf '%s\n' "$EXTRA"
PILOTE

# --------------------------------------------------------- la population : de VRAIS items ------
# `hud-eco-gauge` (celui qui a paye) et cet item-ci d'abord ; le reste vient du backlog, dans
# l'ordre, pour que la population ne soit pas un cas unique.
LISTE=$(python3 - "$N_ITEMS" <<'PY'
import sys
sys.path.insert(0, '.autoport/lib')
try:
    items = list(__import__('backlog').load().values())
except Exception:
    import yaml
    items = (yaml.safe_load(open('.autoport/backlog.yaml', encoding='utf-8')) or {}).get('items') or []
n = int(sys.argv[1])
tete_d, tete_n = 'hud-eco-gauge', 'harness-x86-proof-for-a-device-item-must-shout-at-launch'
dev = [i['id'] for i in items if i.get('device') and i.get('id') != tete_d]
nod = [i['id'] for i in items if not i.get('device') and i.get('id') != tete_n]
print('DEV=%s' % ' '.join(([tete_d] + dev)[:n]))
print('NOD=%s' % ' '.join(([tete_n] + nod)[:n]))
PY
) || LISTE=""
DEV_IDS=$(printf '%s\n' "$LISTE" | sed -n 's/^DEV=//p' | tail -1)
NOD_IDS=$(printf '%s\n' "$LISTE" | sed -n 's/^NOD=//p' | tail -1)
pub banc_items_device "$(printf '%s' "$DEV_IDS" | tr ' ' '+')"
pub banc_items_nondevice "$(printf '%s' "$NOD_IDS" | tr ' ' '+')"

# ------------------------------------------------------------------------------ les jambes -----
# Une jambe = UNE course simulee jusqu'au point de decision. Elle rend, separes :
#   cle      ce que le bloc a publie (`-` = rien : le bras d'avant)
#   mots     le nombre de lignes d'avertissement sorties au journal
#   remede   le journal nomme-t-il la course a refaire (`proof_run.sh <id> device`)
#   constat  le journal cite-t-il le refus exact du juge
ATT=0; AVERTIS=0; MUETS=0; SANS_REMEDE=0; SANS_CONSTAT=0; CLES_FAUSSES=0
NON_ATT=0; NON_CLE0=0; NON_MOTS=0
DM_ATT=0; DM_CLE0=0; DM_MOTS=0
AV_ATT=0; AV_NONAVERTIS=0
CRIT_FAUX=0
jambe(){ # <bloc> <id> <mode>
  local bloc="$1" id="$2" mode="$3"
  ID="$id" MODE="$mode" AP="$AP" BLOC="$bloc" bash "$TD/pilote.sh" >"$TD/o" 2>"$TD/e"
  J_CLE=$(sed -n 's/^proof_will_not_be_judged=//p' "$TD/o" | tail -1); J_CLE=${J_CLE:--}
  J_DEV=$(sed -n 's/^proof_device_criterion=//p' "$TD/o" | tail -1); J_DEV=${J_DEV:--}
  J_MOTS=$(grep -c 'CETTE COURSE NE SERA PAS JUGEE' "$TD/e" || true)
  J_REMEDE=$(grep -cF -- "proof_run.sh $id device" "$TD/e" || true)
  J_CONSTAT=$(grep -cF -- "$CONSTAT" "$TD/e" || true)
}

for id in $DEV_IDS; do
  # LE CRITERE DE CET ITEM EST BIEN CELUI QU'ON CROIT, lu par la source du juge.
  case "$(bash "$AP/lib/verdict_sources.sh" "$id" criterion 2>/dev/null)" in
    *device=1*) ;; *) CRIT_FAUX=$((CRIT_FAUX+1)) ;;
  esac
  ATT=$((ATT+1))
  jambe "$TD/apres.sh" "$id" x86
  [ "$J_CLE" = 1 ] && AVERTIS=$((AVERTIS+1))
  [ "${J_MOTS:-0}" -gt 0 ] || MUETS=$((MUETS+1))
  [ "${J_REMEDE:-0}" -gt 0 ] || SANS_REMEDE=$((SANS_REMEDE+1))
  [ "${J_CONSTAT:-0}" -gt 0 ] || SANS_CONSTAT=$((SANS_CONSTAT+1))
  [ "$J_DEV" = 1 ] || CLES_FAUSSES=$((CLES_FAUSSES+1))
  # LE MEME ITEM, EN MODE device : la course SERA jugee, donc pas un mot.
  DM_ATT=$((DM_ATT+1))
  jambe "$TD/apres.sh" "$id" device
  [ "$J_CLE" = 0 ] && DM_CLE0=$((DM_CLE0+1))
  DM_MOTS=$((DM_MOTS + ${J_MOTS:-0}))
  # LE BRAS D'AVANT, sur la MEME course : rien de publie, donc rien qui previenne.
  AV_ATT=$((AV_ATT+1))
  jambe "$TD/avant.sh" "$id" x86
  [ "$J_CLE" = 1 ] || AV_NONAVERTIS=$((AV_NONAVERTIS+1))
done

for id in $NOD_IDS; do
  case "$(bash "$AP/lib/verdict_sources.sh" "$id" criterion 2>/dev/null)" in
    *device=0*) ;; *) CRIT_FAUX=$((CRIT_FAUX+1)) ;;
  esac
  NON_ATT=$((NON_ATT+1))
  jambe "$TD/apres.sh" "$id" x86
  [ "$J_CLE" = 0 ] && NON_CLE0=$((NON_CLE0+1))
  NON_MOTS=$((NON_MOTS + ${J_MOTS:-0}))
done

# 3. LE TERME, DES DEUX COTES, AVEC SON DENOMINATEUR.
pub x86_unwarned_denominateur "$ATT"
pub x86_unwarned_runs_after "$((ATT - AVERTIS))"
pub x86_unwarned_runs_before "$AV_NONAVERTIS"
pub x86_unwarned_before_denominateur "$AV_ATT"
pub banc_device_muets "$MUETS"
pub banc_device_sans_remede "$SANS_REMEDE"
pub banc_device_sans_constat "$SANS_CONSTAT"
pub banc_device_critere_non_publie "$CLES_FAUSSES"
pub banc_critere_inattendu "$CRIT_FAUX"
# 4. LE CONTROLE NEGATIF, LES DEUX COTES.
pub banc_nondevice_denominateur "$NON_ATT"
pub banc_nondevice_cle_a_zero "$NON_CLE0"
pub banc_nondevice_mots "$NON_MOTS"
pub banc_devicemode_denominateur "$DM_ATT"
pub banc_devicemode_cle_a_zero "$DM_CLE0"
pub banc_devicemode_mots "$DM_MOTS"

# ------------------------------------- LE SITE D'APPEL EST DANS LA PRODUCTION, ET IL EST AVANT --
# Un bloc juste apres le moteur previendrait apres la depense. Les rangs sont publies, pas
# resumes en un booleen : « avant » sans les deux nombres ne se verifie pas.
lign(){ grep -n -- "$1" "$CHEMIN" 2>/dev/null | head -1 | cut -d: -f1; }
L_DEB=$(grep -nF -- "$MARQ_D" "$CHEMIN" | head -1 | cut -d: -f1)
L_FIN=$(grep -nF -- "$MARQ_F" "$CHEMIN" | head -1 | cut -d: -f1)
L_STARTED=$(lign '^STARTED=')
L_MOTEUR=$(grep -n 'timeout -k 5 "\$TIMEOUT" "\$BIN"' "$CHEMIN" | head -1 | cut -d: -f1)
L_ECRIT=$(lign '^  echo "source=\$MODE"')
pub site_ligne_debut "${L_DEB:--1}"
pub site_ligne_fin "${L_FIN:--1}"
pub site_ligne_started "${L_STARTED:--1}"
pub site_ligne_moteur "${L_MOTEUR:--1}"
pub site_ligne_ecriture_preuve "${L_ECRIT:--1}"
pub site_occurrences_debut "$(grep -cF -- "$MARQ_D" "$CHEMIN" || true)"
pub site_occurrences_fin "$(grep -cF -- "$MARQ_F" "$CHEMIN" || true)"
pub site_publie_la_cle "$(grep -cF -- 'extra "proof_will_not_be_judged=' "$CHEMIN" || true)"
# COMBIEN DE LIGNES DE JOURNAL INCONDITIONNELLES LE PRECEDENT : 0 = c'est la premiere.
pub site_logs_inconditionnels_avant \
  "$(awk -v l="${L_DEB:-0}" 'NR<l && /^log "/ {n++} END{print n+0}' "$CHEMIN")"
# LE CONSTAT EPINGLE EST ENCORE CELUI DU JUGE (garde d'egalite, pas un refactor).
pub juge_porte_le_constat "$(grep -cF -- "$CONSTAT" "$AP/validators/generic.sh" || true)"
# ET LE JUGE N'A PAS ETE ASSOUPLI : sa ligne refuse toujours une preuve x86 sur item device.
pub juge_refuse_toujours \
  "$(grep -cF -- '[ "$DEV" = 0 ] || [ "$src" = device ] ||' "$AP/validators/generic.sh" || true)"
pub banc_ran 1
