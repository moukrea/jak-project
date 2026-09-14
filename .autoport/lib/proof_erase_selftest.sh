#!/usr/bin/env bash
# proof_erase_selftest.sh — LE BAC A SABLE DU POINT D'EFFACEMENT
# (harness-proof-run-erases-proof-only-once-it-runs).
#
# CE QU'IL FABRIQUE. Un depot jetable portant une preuve PRECEDENTE de contenu connu
# (`proof.txt` + son sceau), et le VRAI `lib/proof_run.sh` lance contre lui en mode x86, avec un
# faux `build/game/gk` qui NOTE qu'il a demarre. Quatre bras, quatre sorties :
#
#   garde_binaire  `build/game/gk` absent          -> die3 binaire-absent (3), AVANT tout
#                                                     amorcage : la preuve doit etre INTACTE.
#   garde_build    un APK vient d'etre reecrit et  -> die3 build-en-cours (3) : c'est la cause
#                  la borne d'attente vaut 0          EXACTE citee par le signalement du 13/09.
#                                                     La preuve doit etre INTACTE, a l'octet.
#   amorce         rien ne bloque                  -> le moteur DEMARRE : la preuve d'avant est
#                                                     effacee, archivee en `proof-prev.txt`, et
#                                                     remplacee par celle de cette course.
#   vieux          le MEME cas que `garde_build`,  -> le temoin d'AVANT, FABRIQUE : la preuve de
#                  correctif DEFAIT                   la veille est DETRUITE par une course qui
#                                                     n'a jamais rien mesure.
#
# POURQUOI FABRIQUER LE DEFAUT AU LIEU DE LE DETERRER. `proof.txt` n'est pas versionne
# (`.gitignore` ligne 173) et il est REMPLACE a chaque course : la preuve qui survit sur le
# disque est toujours celle de la derniere course REUSSIE. La population « preuve detruite par
# une course qui n'a pas amorce » est donc VIDE PAR CONSTRUCTION sur le disque — un zero qui ne
# dit rien. Le bras `vieux` la fabrique, avec le VRAI producteur, et elle se compte.
#
# LE BRAS D'AVANT EST FABRIQUE PAR TRANSFORMATION DU SCRIPT, PAS PAR UN DRAPEAU. On DEFAIT les
# deux lignes du correctif dans la copie du bac : le `rm` nu de `die3`, et l'appel a
# `amorcage_efface_la_preuve` remis a son ancienne place. Le nombre de lignes transformees est
# PUBLIE : une transformation qui ne change rien serait une ablation vide, et son zero se lirait
# « rien ne se perd » alors qu'il voudrait dire « personne n'a regarde ».
#
# Sortie : des `cle=valeur` sur stdout, les explications sur stderr. Il ne JUGE rien : la somme
# et la polarite « inconnu = defaut » sont dans lib/census/<item>.sh.
set -uo pipefail

ROOT=$(git rev-parse --show-toplevel 2>/dev/null) || { echo "selftest_ran=0"; exit 1; }
AP="$ROOT/.autoport"
ITEM="sandbox-effacement"

# Les noms des fichiers d'une course sortent de l'AUTORITE DE NOMMAGE, jamais d'un litteral tape
# ici : « fichier absent » se lirait exactement comme « la course n'a rien produit ».
eval "$(python3 "$AP/lib/impossible.py" names "")" || { echo "selftest_ran=0"; exit 1; }
for _k in proof seal prev_proof prev_seal impossible; do
  eval "_v=\${AP_NAME_$_k:-}"
  [ -n "$_v" ] || { echo "selftest_ran=0"; exit 1; }
done

SB=$(mktemp -d -t proof-erase.XXXXXX) || { echo "selftest_ran=0"; exit 1; }
trap 'rm -rf "$SB"' EXIT
note(){ printf '[banc-effacement] %s\n' "$*" >&2; }
kv(){ printf '%s=%s\n' "$1" "${2:--}"; }

# LA PREUVE PRECEDENTE, DE CONTENU CONNU. Son empreinte est calculee une fois : c'est elle que
# chaque bras doit rendre a l'octet, ou pas du tout.
PREUVE_AVANT="$SB/preuve-de-la-veille.txt"
{
  echo "source=x86"
  echo "sha=0000000000000000"
  echo "frames=31337"
  echo "crash=0"
  echo "hdr_shadow_range_defects=0"
  printf 'bourrage %s\n' $(seq 1 400)
} > "$PREUVE_AVANT"
SHA_AVANT=$(sha256sum "$PREUVE_AVANT" | cut -c1-16)
OCTETS_AVANT=$(stat -c %s "$PREUVE_AVANT")
kv banc_preuve_avant_octets "$OCTETS_AVANT"
kv banc_preuve_avant_sha "$SHA_AVANT"

# ================================================================= fabrication d'un bras =====
# $1 = nom ; $2 = dossier ; $3 = 1 si le faux gk doit exister ; $4 = 1 si la garde de build doit
# mordre ; $5 = 1 si le correctif doit etre DEFAIT (bras d'absence).
monte_bras(){
  local nom=$1 dir=$2 avec_gk=$3 busy=$4 sans_fix=$5 rel
  mkdir -p "$dir/.autoport/lib" "$dir/build/game" "$dir/apks" || return 1

  git -C "$dir" init -q >/dev/null 2>&1 || return 1        # git-sandbox-ok
  git -C "$dir" config user.email erase@sandbox >/dev/null 2>&1   # git-sandbox-ok
  git -C "$dir" config user.name erase >/dev/null 2>&1           # git-sandbox-ok

  # CE QUE LE BAC COPIE SORT DU NOMMEUR DU VERDICT, jamais d'une enumeration tapee ici : un bac
  # qui declare sa propre liste diverge du depot a chaque dependance que la porte gagne.
  while IFS= read -r rel; do
    [ -n "$rel" ] || continue
    mkdir -p "$dir/$(dirname "$rel")" || return 1
    cp "$ROOT/$rel" "$dir/$rel" || return 1
  done < <(bash "$AP/lib/verdict_sources.sh" "$ITEM" list)
  chmod +x "$dir/.autoport/lib/"*.sh 2>/dev/null
  chmod +x "$dir/.autoport/acquis/"*.sh "$dir/.autoport/validators/"*.sh 2>/dev/null

  # LE BRAS D'ABSENCE : LE CORRECTIF DEFAIT, LIGNE PAR LIGNE, ET LE COMPTE PUBLIE.
  if [ "$sans_fix" = 1 ]; then
    sed -e 's|^  \[ "$PROOF_ERASED" = 1 \] && rm -f "$OUTFILE"$|  rm -f "$OUTFILE"|' \
        -e 's|^# AMORCAGE-TARDIF/point-d-avant.*|amorcage_efface_la_preuve demarrage-avant-les-gardes|' \
        "$dir/.autoport/lib/proof_run.sh" > "$dir/pr.tmp" || return 1
    kv "arm_${nom}_transform_lignes" \
       "$(diff "$dir/.autoport/lib/proof_run.sh" "$dir/pr.tmp" | grep -c '^[<>]')"
    mv -f "$dir/pr.tmp" "$dir/.autoport/lib/proof_run.sh" || return 1
    bash -n "$dir/.autoport/lib/proof_run.sh" || { note "bras $nom : script defait non valide"; return 1; }
  fi

  cat > "$dir/.autoport/backlog.yaml" <<YAML
version: 1
items:
  - id: $ITEM
    status: in-progress
    device: false
    owner_test: false
    feature: bac a sable du point d effacement
    proof_timeout: 20
YAML

  # LA PREUVE DE LA VEILLE, ET SON SCEAU : sans le sceau, la paire est incomplete et le filet
  # `proof-prev.txt` ne s'ecrit pas — on mesurerait alors l'absence de paire, pas l'effacement.
  local d="$dir/.autoport/reports/$ITEM"
  mkdir -p "$d" || return 1
  cp "$PREUVE_AVANT" "$d/$AP_NAME_proof" || return 1
  printf 'seal_sha=%s\nseal_bytes=%s\nexit_sha=%s\n' "$SHA_AVANT" "$OCTETS_AVANT" "$SHA_AVANT" \
    > "$d/$AP_NAME_seal"

  # LE FAUX MOTEUR. Il NOTE son demarrage dans un fichier a lui : « la course a amorce » se lit
  # alors sur une trace que le moteur SEUL peut ecrire, jamais sur le code de retour du script.
  if [ "$avec_gk" = 1 ]; then
    cat > "$dir/build/game/gk" <<GK_EOF
#!/usr/bin/env bash
printf 'demarre\n' > "$dir/temoin-amorcage"
i=0
while [ \$i -lt 640 ]; do printf 'AUTOPORT-FRAMES n=%s\n' "\$i"; i=\$((i+1)); done
printf 'FEATURE $ITEM armed=1 hits=7\n'
printf 'proof_feature_id=$ITEM\n'
printf 'proof_feature_state=absent\n'
printf 'proof_feature_own_hits=0\n'
printf 'proof_feature_global_hits=7\n'
printf 'banc_effacement_temoin=1\n'
exit 0
GK_EOF
    chmod +x "$dir/build/game/gk"
  fi

  # LA GARDE DE BUILD, FORCEE PAR LA DONNEE QU'ELLE LIT. `busy_reason` regarde l'age du dernier
  # APK : on lui en designe un, ecrit a l'instant, et on met la borne d'attente a zero. Rien
  # n'est simule — c'est la VRAIE garde, sur une VRAIE lecture.
  if [ "$busy" = 1 ]; then
    : > "$dir/apks/app-jak1-debug.apk"
  else
    # Un APK VIEUX, pour que le glob ne tombe jamais sur celui du depot reel.
    : > "$dir/apks/app-jak1-debug.apk"
    touch -d '1970-01-02' "$dir/apks/app-jak1-debug.apk"
  fi
  return 0
}

# ======================================================================= course d'un bras ====
court_bras(){
  local nom=$1 dir=$2 busy=$3 rc=0
  local d="$dir/.autoport/reports/$ITEM"
  local journal="$SB/$nom.log"
  local waitmax=1800
  [ "$busy" = 1 ] && waitmax=0
  ( cd "$dir" && \
    AUTOPORT_BUSY_APK_GLOB="$dir/apks/*.apk" \
    AUTOPORT_BUSY_FRESH_S=86400 \
    AUTOPORT_PROOF_WAIT_MAX="$waitmax" \
    AUTOPORT_PROOF_WRITER_WAIT=5 \
    AUTOPORT_ATTEMPT_ID="banc-effacement-$nom" \
    timeout -k 20 300 bash .autoport/lib/proof_run.sh "$ITEM" x86 ) > "$journal" 2>&1
  rc=$?
  kv "arm_${nom}_rc" "$rc"
  # CE QUE LE MOTEUR SEUL PEUT ECRIRE : le temoin d'amorcage. Un code de retour ne distingue pas
  # « la course a mesure » de « la course est morte apres avoir tout casse ».
  kv "arm_${nom}_amorce" "$([ -s "$dir/temoin-amorcage" ] && echo 1 || echo 0)"
  # LA PREUVE D'AVANT : presente ? identique A L'OCTET ?
  local apres_sha="-" apres_oct=0 presente=0 identique=0
  if [ -s "$d/$AP_NAME_proof" ]; then
    presente=1
    apres_sha=$(sha256sum "$d/$AP_NAME_proof" | cut -c1-16)
    apres_oct=$(stat -c %s "$d/$AP_NAME_proof")
    [ "$apres_sha" = "$SHA_AVANT" ] && identique=1
  fi
  kv "arm_${nom}_preuve_presente" "$presente"
  kv "arm_${nom}_preuve_octets" "$apres_oct"
  kv "arm_${nom}_preuve_sha" "$apres_sha"
  kv "arm_${nom}_preuve_identique_avant" "$identique"
  kv "arm_${nom}_prev_ecrit" "$([ -s "$d/$AP_NAME_prev_proof" ] && echo 1 || echo 0)"
  kv "arm_${nom}_prev_sceau_ecrit" "$([ -s "$d/$AP_NAME_prev_seal" ] && echo 1 || echo 0)"
  # LE FILET PORTE-T-IL BIEN LA PREUVE DE LA VEILLE, et pas autre chose ?
  local prev_sha="-"
  [ -s "$d/$AP_NAME_prev_proof" ] && prev_sha=$(sha256sum "$d/$AP_NAME_prev_proof" | cut -c1-16)
  kv "arm_${nom}_prev_sha" "$prev_sha"
  kv "arm_${nom}_prev_est_la_veille" "$([ "$prev_sha" = "$SHA_AVANT" ] && echo 1 || echo 0)"
  kv "arm_${nom}_impossible_ecrit" "$([ -s "$d/$AP_NAME_impossible" ] && echo 1 || echo 0)"
  # LE REGISTRE DE LA COURSE : son point d'effacement et son code de sortie, lus dans le fichier
  # append-only que le producteur ecrit LUI-MEME, jamais recopies depuis ce banc.
  local reg="$dir/.autoport/logs/proof-erase.tsv" ligne=""
  [ -s "$reg" ] && ligne=$(tail -1 "$reg")
  kv "arm_${nom}_registre_lignes" "$([ -s "$reg" ] && grep -c . "$reg" || echo 0)"
  kv "arm_${nom}_registre_rc" "$(printf '%s' "$ligne" | cut -f5)"
  kv "arm_${nom}_registre_efface" "$(printf '%s' "$ligne" | cut -f6)"
  kv "arm_${nom}_registre_point" "$(printf '%s' "$ligne" | cut -f7)"
  kv "arm_${nom}_registre_octets_avant" "$(printf '%s' "$ligne" | cut -f8)"
  kv "arm_${nom}_registre_octets_apres" "$(printf '%s' "$ligne" | cut -f9)"
  # LA GRANDEUR DE LA PORTE, LUE SUR LES COLONNES DU REGISTRE ET SUR RIEN D'AUTRE : il y AVAIT
  # une preuve (col.8 > 0), la course n'a PAS atteint son point d'amorcage (col.6 = 0), et il
  # n'y en a PLUS (col.9 = 0). C'est cela, une preuve detruite par une course qui n'a rien
  # mesure — et c'est vrai quelle que soit la LIGNE de code qui a tenu le `rm`.
  kv "arm_${nom}_detruite_sans_course" \
     "$(printf '%s' "$ligne" | awk -F'\t' '{print ($8+0>0 && $6+0==0 && $9+0==0) ? 1 : 0}')"
  # LA CAUSE DE LA SORTIE, TELLE QUE LE PRODUCTEUR L'A NOMMEE.
  kv "arm_${nom}_raison" \
     "$(sed -n 's/.*PREUVE IMPOSSIBLE (\([a-z0-9-]*\)).*/\1/p' "$journal" | tail -1)"
  # CE QUE LA GARDE DE BUILD A LU : un bras `amorce` qui meurt parce qu'un VRAI ninja tournait
  # sur la machine doit se lire, pas se deviner.
  kv "arm_${nom}_busy_why" \
     "$(sed -n 's/.*attente : \(.*\)$/\1/p' "$journal" | tail -1 | tr ' \t' '__')"
}

# ============================================================================ les 4 bras =====
COURUS=0; MONTES=0
#  nom            gk  busy  sans_fix
for spec in "garde_binaire 0 0 0" "garde_build 1 1 0" "amorce 1 0 0" "vieux 1 1 1"; do
  set -- $spec
  nom=$1; gk=$2; busy=$3; sans=$4
  dir="$SB/$nom"
  if monte_bras "$nom" "$dir" "$gk" "$busy" "$sans"; then
    MONTES=$((MONTES+1))
    court_bras "$nom" "$dir" "$busy"
    COURUS=$((COURUS+1))
  else
    note "bras $nom : montage impossible"
    kv "arm_${nom}_rc" -1
  fi
done
kv selftest_arms_montes "$MONTES"
kv selftest_arms_courus "$COURUS"

# ============================== LE COUT D'AVANT, TEL QUE LE DISQUE PEUT ENCORE LE DIRE =======
# `proof.txt` n'est pas versionne et il est REMPLACE a chaque course : la population « preuve
# detruite par une course qui n'a pas amorce » est VIDE PAR CONSTRUCTION sur le disque. Ce qu'on
# peut compter, c'est le FILET qui a du servir, et les etats « preuve impossible » qui nomment
# une course morte a la porte. On publie les deux avec leur denominateur ; le « non nul » du
# livrable vient du bras `vieux`, qui FABRIQUE le defaut avec le vrai producteur.
kv avant_dossiers_items "$(find "$AP/reports" -mindepth 1 -maxdepth 1 -type d 2>/dev/null | grep -c .)"
kv avant_filets_prev "$(find "$AP/reports" -maxdepth 2 -name "$AP_NAME_prev_proof" 2>/dev/null | grep -c .)"
kv avant_etats_impossibles "$(find "$AP/reports" -maxdepth 2 -name 'proof*impossible*.txt' 2>/dev/null | grep -c .)"
kv avant_preuves_presentes "$(find "$AP/reports" -maxdepth 2 -name "$AP_NAME_proof" 2>/dev/null | grep -c .)"
# LE REGISTRE DE LA GARDE DE BUILD : chaque `refus` est une course morte AVANT tout amorcage.
# C'est la population la plus proche du defaut que le disque porte encore, et elle est datee.
BG="$AP/logs/busy-guard.tsv"
if [ -s "$BG" ]; then
  kv avant_busy_registre_lignes "$(grep -c . "$BG")"
  kv avant_busy_registre_refus "$(awk -F'\t' '$4=="refus"' "$BG" | grep -c .)"
else
  kv avant_busy_registre_lignes 0
  kv avant_busy_registre_refus 0
fi
kv avant_disque_vide_par_construction 1

# ================== LE COUT D'AVANT, NOMME ET DATE, DANS LES JOURNAUX D'ESSAIS ARCHIVES ======
# Une course morte a la porte ne laisse AUCUN artefact sur le disque — c'est le defaut lui-meme.
# Ce qu'elle laisse, c'est SA LIGNE dans le journal de l'essai : `[proof_run <item>] PREUVE
# IMPOSSIBLE (<raison>)`, ecrite par le producteur. Le prefixe `[proof_run <item>]` est ce qui
# separe l'EVENEMENT de la CITATION : les fichiers qui portent la chaine « PREUVE IMPOSSIBLE »
# sont pour l'essentiel des prompts et des diffs qui recopient le code source, et aucun d'eux ne
# porte ce prefixe avec un identifiant d'item devant. Sans ce filtre : 68 occurrences. Avec : 11,
# toutes issues d'UN evenement.
# `verrou-ecrivain` est EXCLU : il n'appelle pas `die3` et n'a jamais rien efface. Toutes les
# autres raisons passent par `die3`, dont le `rm` etait NU — donc chacune detruisait.
EV=$(python3 - "$AP" <<'AVANT_PY'
import os, re, sys
ap = sys.argv[1]
logs = os.path.join(ap, 'logs')
motif = re.compile(r'\[proof_run ([a-z0-9][a-z0-9-]{2,})\] PREUVE IMPOSSIBLE \(([a-z0-9-]+)\)')
evts, fichiers, raisons, croisees = set(), 0, {}, []
for dp, _dn, fn in os.walk(logs):
    for f in fn:
        if not f.startswith('attempt-') or not f.endswith('.jsonl'):
            continue
        fichiers += 1
        try:
            texte = open(os.path.join(dp, f), encoding='utf-8', errors='replace').read()
        except OSError:
            continue
        for item, raison in motif.findall(texte):
            if raison == 'verrou-ecrivain':
                continue
            # UN EVENEMENT APPARTIENT A L'ITEM DONT C'EST LE JOURNAL. Le journal d'essai de CET
            # item-ci CITE l'evenement de `hdr-shadow-range` — son prompt le porte, et la ligne
            # citee est identique au caractere pres. Comptee, elle ferait DEUX destructions la
            # ou il y en a une, et le compte grossirait a chaque item qui reparle du defaut.
            if item != os.path.basename(dp):
                croisees.append('%s@%s' % (item, os.path.basename(dp)))
                continue
            # UN ESSAI = UN EVENEMENT, quel que soit le nombre de recopies dans son journal.
            evts.add((item, os.path.basename(dp), f, raison))
            raisons[raison] = raisons.get(raison, 0) + 1
# CELUI QUI A PERDU UNE PORTE TENUE. Un verdict `[<item> ok]` archive prouve qu'il y avait une
# preuve JUGEE a detruire — c'est la machine qui l'a ecrit, pas le recit d'un worker.
tenues = set()
for item, dossier, _f, _r in evts:
    d = os.path.join(logs, dossier)
    for v in sorted(os.listdir(d)) if os.path.isdir(d) else []:
        if not v.startswith('validator-'):
            continue
        try:
            if ('[%s ok]' % item) in open(os.path.join(d, v), encoding='utf-8', errors='replace').read():
                tenues.add(item)
        except OSError:
            pass
print('avant_journaux_essais_lus=%d' % fichiers)
print('avant_evenements_sans_amorcage=%d' % len(evts))
print('avant_occurrences_brutes=%d' % sum(raisons.values()))
print('avant_citations_croisees=%d' % len(croisees))
print('avant_citations_croisees_liste=%s' % (','.join(sorted(set(croisees))) or '-'))
print('avant_items_touches=%d' % len({e[0] for e in evts}))
print('avant_items_avec_porte_tenue_archivee=%d' % len(tenues))
print('avant_raisons=%s' % (','.join('%s:%d' % kv for kv in sorted(raisons.items())) or '-'))
print('avant_evenements_liste=%s' % (','.join(sorted('%s/%s:%s' % (e[1], e[2], e[3]) for e in evts)) or '-'))
AVANT_PY
) || EV="avant_evenements_sans_amorcage=-1"
printf '%s\n' "$EV"
kv avant_verdicts_archives "$(find "$AP/logs" -name 'validator-*.txt' 2>/dev/null | grep -c .)"

kv selftest_ran 1
