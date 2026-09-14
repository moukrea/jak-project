#!/usr/bin/env bash
# stale_binary_selftest.sh — LE BAC A SABLE DE LA GARDE BINAIRE
# (harness-proof-run-device-deploys-or-refuses-first).
#
# POURQUOI FABRIQUER LA CONDITION AU LIEU DE LA DETERRER. Le recensement des courses archivees
# rend ZERO, et ce zero ne dit rien : `proof.txt` est ECRASE a chaque course, donc la preuve qui
# SURVIT est toujours celle de la course reussie. 258 paires (local_lib_md5, device_lib_md5)
# lues sur le disque, 258 egales. La population « course mesuree sur un binaire perime » est
# VIDE PAR CONSTRUCTION, pas parce que le defaut n'existe pas. Le cout d'avant qui se COMPTE,
# lui, est ailleurs : 37 scripts prives de deploiement ecrits en 11 jours sous
# `reports/*/notes/`, dont 25 refont la MEME comparaison de md5 avec cinq codes de sortie
# differents (1, 3, 4, 5, 7).
#
# CE BANC FABRIQUE DONC LES DEUX ETATS, dans un depot jetable, avec un FAUX `adb` dont on
# choisit le md5 rendu — et il lance le VRAI `lib/proof_run.sh` en mode appareil contre lui.
#
# LES QUATRE BRAS :
#   egaux    md5 identiques                      -> la course MESURE (une garde qui bloque une
#                                                   course saine est un defaut, pas une garde)
#   perime   md5 differents, aucun APK conforme  -> REFUS immediat, avant l'amorcage, et la
#                                                   preuve de la course precedente reste INTACTE
#   deploye  md5 differents, un APK du            -> le binaire local est LIVRE, puis la course
#            constructeur porte le binaire local    mesure
#   vieux    md5 differents, GARDE RETIREE        -> le bras d'ABSENCE : la couche n'est pas la,
#                                                   et la course mesure 400 s sur le mauvais
#                                                   binaire. C'est le temoin « avant », fabrique.
#
# LE BRAS D'ABSENCE EST FABRIQUE PAR RETRAIT DE BLOC, PAS PAR UN COMMIT. `OFF doit egaler
# l'ABSENCE` : on retire du `proof_run.sh` du bac le bloc `GARDE-BINAIRE/debut..fin`, la couche
# n'est donc pas COMPILEE dans ce bras. Un ancrage git rendrait le bras introuvable tant que le
# correctif n'est pas commite — et un `HEAD:` s'accuserait lui-meme des le commit.
#
# Sortie : des `cle=valeur` sur stdout, les explications sur stderr. Il ne JUGE rien : la somme
# et la polarite « inconnu = defaut » sont dans lib/census/<item>.sh.
set -uo pipefail

ROOT=$(git rev-parse --show-toplevel 2>/dev/null) || { echo "selftest_ran=0"; exit 1; }
AP="$ROOT/.autoport"
SERIAL_FAKE="SANDBOXBIN01"
PKG="org.opengoal.gk.jak1"
ITEM="sandbox-binaire"

# Les noms des fichiers d'une course sortent de l'AUTORITE DE NOMMAGE, jamais d'un litteral
# tape ici : « fichier absent » se lirait exactement comme « la course n'a rien produit ».
eval "$(python3 "$AP/lib/impossible.py" names "")"

SB=$(mktemp -d -t stalebin.XXXXXX) || { echo "selftest_ran=0"; exit 1; }
trap 'rm -rf "$SB"' EXIT
note(){ printf '[banc-binaire] %s\n' "$*" >&2; }
kv(){ printf '%s=%s\n' "$1" "${2:--}"; }

# ================================================================= fabrication d'un bras =====
# $1 = nom ; $2 = dossier ; $3 = md5 que le FAUX appareil rendra ('local' = celui du .so local)
# $4 = 1 si un APK conforme doit exister ; $5 = 1 si la garde doit etre RETIREE du proof_run.
monte_bras() {
  local nom=$1 dir=$2 devmd5=$3 avec_apk=$4 sans_garde=$5
  mkdir -p "$dir/.autoport/lib" "$dir/build-android/lib/arm64-v8a" || return 1
  # Un .so local UNIQUE par bras : deux bras qui partagent un md5 ne prouveraient rien.
  printf 'faux libgk du bac a sable, bras %s, %s\n' "$nom" "$RANDOM$RANDOM" \
    > "$dir/build-android/lib/arm64-v8a/libgk.so"
  local local_md5
  local_md5=$(md5sum "$dir/build-android/lib/arm64-v8a/libgk.so" | awk '{print $1}')

  git -C "$dir" init -q >/dev/null 2>&1 || return 1        # git-sandbox-ok
  git -C "$dir" config user.email bin@sandbox >/dev/null 2>&1  # git-sandbox-ok
  git -C "$dir" config user.name bin >/dev/null 2>&1           # git-sandbox-ok

  # CE QUE LE BAC COPIE SORT DU NOMMEUR DU VERDICT, jamais d'une enumeration tapee ici : un bac
  # qui declare sa propre liste diverge du depot a chaque dependance que la porte gagne.
  local rel
  while IFS= read -r rel; do
    [ -n "$rel" ] || continue
    mkdir -p "$dir/$(dirname "$rel")" || return 1
    cp "$ROOT/$rel" "$dir/$rel" || return 1
  done < <(bash "$AP/lib/verdict_sources.sh" "$ITEM" list)
  chmod +x "$dir/.autoport/lib/"*.sh 2>/dev/null
  chmod +x "$dir/.autoport/acquis/"*.sh "$dir/.autoport/validators/"*.sh 2>/dev/null
  # La garde vit dans un fichier que la derivation ne peut atteindre que par la CITATION que
  # `proof_run.sh` en fait. Si elle manque, le bras neuf n'a rien a mesurer : on le dit.
  if [ ! -s "$dir/.autoport/lib/device_binary_gate.sh" ]; then
    note "bras $nom : lib/device_binary_gate.sh n'est pas dans les sources du verdict"
    return 1
  fi

  # LE BRAS D'ABSENCE : le MEME script, prive de son bloc. `awk` borne sur les deux marqueurs.
  if [ "$sans_garde" = 1 ]; then
    awk 'index($0,"GARDE-BINAIRE/debut"){f=1} !f{print} index($0,"GARDE-BINAIRE/fin"){f=0}' \
      "$dir/.autoport/lib/proof_run.sh" > "$dir/pr.tmp" || return 1
    # Zero ligne retiree serait une ablation VIDE qui passe au vert : on le mesure.
    local avant apres
    avant=$(wc -l < "$dir/.autoport/lib/proof_run.sh"); apres=$(wc -l < "$dir/pr.tmp")
    kv "arm_${nom}_bloc_retire_lignes" "$((avant - apres))"
    mv -f "$dir/pr.tmp" "$dir/.autoport/lib/proof_run.sh" || return 1
  fi

  cat > "$dir/.autoport/backlog.yaml" <<YAML
version: 1
items:
  - id: $ITEM
    status: in-progress
    device: true
    owner_test: false
    feature: bac a sable de la garde binaire
    proof_timeout: 8
YAML

  printf 'debug.opengoal.placeholder=0\n' > "$dir/props"
  : > "$dir/logcat"
  # Le md5 que le FAUX appareil rendra pour son `libgk.so` installe.
  if [ "$devmd5" = local ]; then printf '%s\n' "$local_md5" > "$dir/md5dev"
  else printf '%s\n' "$(printf 'perime-%s' "$nom" | md5sum | awk '{print $1}')" > "$dir/md5dev"; fi
  printf '%s\n' "$local_md5" > "$dir/md5local"

  # L'APK DU CONSTRUCTEUR : un VRAI zip qui porte le .so local. La garde lit le CONTENU, pas un
  # chemin ni une date — un APK plus recent peut avoir ete bati sur un AUTRE binaire.
  mkdir -p "$dir/apks"
  if [ "$avec_apk" = 1 ]; then
    python3 - "$dir/apks/app-jak1-debug.apk" "$dir/build-android/lib/arm64-v8a/libgk.so" <<'PY' || return 1
import sys, zipfile
with zipfile.ZipFile(sys.argv[1], 'w') as z:
    z.write(sys.argv[2], 'lib/arm64-v8a/libgk.so')
PY
    # Ce que l'install fera atterrir sur le faux appareil.
    printf '%s\n' "$local_md5" > "$dir/apkmd5"
  fi

  # ------------------------------------------------------------------------- le faux adb -----
  # Il n'imite pas adb en general : il imite EXACTEMENT ce que proof_run.sh, device_teardown.sh,
  # pick_device.sh et device_binary_gate.sh envoient. Toute autre commande sort en 0 sans rien
  # faire. Les deux gestes qui comptent ici : `md5sum` rend le md5 du bras, et `install` fait
  # atterrir celui de l'APK — c'est ce qui rend le deploiement OBSERVABLE.
  cat > "$dir/adb" <<'ADB_EOF'
#!/usr/bin/env bash
D=$(cd "$(dirname "$0")" && pwd)
P="$D/props"; L="$D/logcat"
get(){ sed -n "s/^$(printf '%s' "$1" | sed 's/[.[\*^$]/\\&/g')=//p" "$P" | tail -1; }
set_(){ local k=$1 v=$2 t; t=$(mktemp); grep -v "^$(printf '%s' "$k" | sed 's/[.[\*^$]/\\&/g')=" "$P" > "$t" 2>/dev/null
        [ -n "$v" ] && printf '%s=%s\n' "$k" "$v" >> "$t"; mv -f "$t" "$P"; }
[ "${1:-}" = devices ] && { printf 'List of devices attached\nSANDBOXBIN01\tdevice\n'; exit 0; }
[ "${1:-}" = -s ] || exit 1
shift 2
case "${1:-}" in
  get-state) echo device ;;
  install)
    # `install -r -d -t <apk>` : le .so de l'APK atterrit. On note le geste, il est compte.
    echo "install" >> "$D/installs"
    [ -s "$D/apkmd5" ] && cp -f "$D/apkmd5" "$D/md5dev"
    echo Success ;;
  logcat)
    [ "${2:-}" = -c ] && { : > "$L"; exit 0; }
    exec tail -n +1 -f "$L" ;;
  shell|exec-out)
    shift
    [ "${1:-}" = run-as ] && shift 2
    [ "${1:-}" = sh ] && shift 2
    # shellcheck disable=SC2046
    set -- $(printf '%s ' "$@" | sed "s/''/ /g; s/'//g")
    case "${1:-}" in
      getprop)
        if [ -z "${2:-}" ]; then
          while IFS= read -r l; do [ -n "$l" ] && printf '[%s]: [%s]\n' "${l%%=*}" "${l#*=}"; done < "$P"
        elif [ "$2" = ro.product.model ]; then echo SANDBOX_Fake
        else get "$2"; fi ;;
      setprop) set_ "$2" "${3:-}" ;;
      pm) echo "package:/data/app/sandbox/base.apk" ;;
      md5sum) printf '%s  %s\n' "$(cat "$D/md5dev")" "${2:-}" ;;
      pidof) [ -f "$D/started" ] && echo 4242 ;;
      cmd) echo "org.opengoal.gk.jak1/org.opengoal.gk.LoaderActivity" ;;
      dumpsys) echo "mWakefulness=Awake" ;;
      appops) : ;;
      am)
        case "${2:-}" in
          start)
            # LE GESTE QUI COMPTE POUR LA PORTE : l'amorcage. Un refus qui arrive APRES lui
            # n'est pas un refus « avant l'appareil ».
            : > "$D/started"
            { for n in 60 120 180 240 300 360 420 480 540 600; do
                printf '09-14 10:00:00.000 I/GK_STDOUT( 4242): AUTOPORT-FRAMES n=%s\n' "$n"
                printf '09-14 10:00:00.000 I/GK_STDOUT( 4242): FEATURE %s armed=1 hits=%s\n' \
                       "$(get debug.opengoal.feature)" "$n"
              done
              printf '09-14 10:00:00.000 I/GK_STDOUT( 4242): sandbox_engine_md5_vu=%s\n' "$(cat "$D/md5dev")"
            } >> "$L" ;;
          force-stop) rm -f "$D/started" ;;
        esac ;;
      rm|cat|input|wm|true|:) : ;;
      *) : ;;
    esac ;;
  *) : ;;
esac
exit 0
ADB_EOF
  chmod +x "$dir/adb"

  # LA PREUVE DE LA COURSE PRECEDENTE. Sans elle, « proof.txt intact » n'aurait rien a decrire :
  # on ne peut pas constater qu'un refus ne detruit pas ce qui n'existe pas.
  mkdir -p "$dir/.autoport/reports/$ITEM"
  printf 'source=device\nframes=4242\ncrash=0\nmarqueur=preuve-de-la-course-precedente\n' \
    > "$dir/.autoport/reports/$ITEM/$AP_NAME_proof"
  printf 'seal_sha=abc\nexit_sha=abc\n' > "$dir/.autoport/reports/$ITEM/$AP_NAME_seal"
  sha256sum "$dir/.autoport/reports/$ITEM/$AP_NAME_proof" | cut -c1-64 > "$dir/proof-avant.sha"
  return 0
}

# ============================================================== la course d'un bras ===========
court_bras() {
  local nom=$1 dir=$2
  local pf="$dir/.autoport/reports/$ITEM/$AP_NAME_proof"
  local prev="$dir/.autoport/reports/$ITEM/$AP_NAME_prev_proof"
  ( cd "$dir" && ANDROID_SERIAL="$SERIAL_FAKE" ADB="$dir/adb" AUTOPORT_PKG="$PKG" \
      AUTOPORT_APK_GLOB="$dir/apks/*.apk" \
      AUTOPORT_PROOF_WAIT_MAX=60 AUTOPORT_LOGCAT_PIDDIR="$dir/.logcat" \
      timeout -k 10 240 bash .autoport/lib/proof_run.sh "$ITEM" device --timeout 8 \
  ) >"$dir/run.log" 2>&1
  local rc=$?
  note "bras $nom : proof_run sorti en $rc"
  kv "arm_${nom}_rc" "$rc"
  kv "arm_${nom}_started" "$([ -f "$dir/started" ] && echo 1 || echo 0)"
  kv "arm_${nom}_installs" "$(grep -c . "$dir/installs" 2>/dev/null || echo 0)"
  kv "arm_${nom}_local_md5" "$(cat "$dir/md5local")"
  kv "arm_${nom}_dev_md5_final" "$(cat "$dir/md5dev")"

  # LA DECISION VIENT DU REGISTRE DE LA GARDE, pas de proof.txt : sur un refus il n'y a pas de
  # proof.txt, et un temoin qui n'existe que dans le cas heureux ne mesure pas le cas malheureux.
  local reg="$dir/.autoport/logs/device-binary-gate.tsv"
  if [ -s "$reg" ]; then
    kv "arm_${nom}_registre" "$(grep -c . "$reg")"
    kv "arm_${nom}_decision" "$(tail -1 "$reg" | cut -f4)"
    kv "arm_${nom}_gate_rc"  "$(tail -1 "$reg" | cut -f5)"
    kv "arm_${nom}_raison"   "$(tail -1 "$reg" | cut -f9 | tr -d '\n')"
  else
    kv "arm_${nom}_registre" 0
    kv "arm_${nom}_decision" absent
    kv "arm_${nom}_gate_rc" -1
    kv "arm_${nom}_raison" registre-absent
  fi

  # LA PREUVE DE LA COURSE PRECEDENTE EST-ELLE INTACTE ? Deux cas legitimes, et un seul les
  # confond : soit elle est toujours la, octet pour octet (refus), soit la course l'a
  # ARCHIVEE sous le nom que l'autorite derive pour elle (mesure). Tout le reste est une perte.
  local avant apres
  avant=$(cat "$dir/proof-avant.sha")
  apres=""
  [ -s "$pf" ] && apres=$(sha256sum "$pf" | cut -c1-64)
  if [ "$apres" = "$avant" ]; then
    kv "arm_${nom}_preuve_precedente" intacte
  elif [ -s "$prev" ] && [ "$(sha256sum "$prev" | cut -c1-64)" = "$avant" ]; then
    kv "arm_${nom}_preuve_precedente" archivee
  else
    kv "arm_${nom}_preuve_precedente" perdue
  fi

  # LA COURSE A-T-ELLE PRODUIT UNE PREUVE, ET SUR QUEL BINAIRE ?
  if [ -s "$pf" ] && ! grep -q '^marqueur=preuve-de-la-course-precedente$' "$pf"; then
    kv "arm_${nom}_proof" 1
    local l d
    l=$(sed -n 's/^local_lib_md5=//p' "$pf" | tail -1)
    d=$(sed -n 's/^device_lib_md5=//p' "$pf" | tail -1)
    kv "arm_${nom}_proof_local_md5" "$l"
    kv "arm_${nom}_proof_dev_md5" "$d"
    kv "arm_${nom}_frames" "$(sed -n 's/^frames=//p' "$pf" | tail -1)"
    # LA GRANDEUR DE L'ITEM : une course qui a MESURE sur un binaire qui n'est pas le sien.
    if [ -n "$l" ] && [ -n "$d" ] && [ "$l" != "$d" ]; then
      kv "arm_${nom}_mesure_sur_perime" 1
    else
      kv "arm_${nom}_mesure_sur_perime" 0
    fi
    kv "arm_${nom}_checked" "$(sed -n 's/^proof_binary_checked_before_measure=//p' "$pf" | tail -1)"
  else
    kv "arm_${nom}_proof" 0
    kv "arm_${nom}_proof_local_md5" -
    kv "arm_${nom}_proof_dev_md5" -
    kv "arm_${nom}_frames" -1
    kv "arm_${nom}_mesure_sur_perime" 0
    kv "arm_${nom}_checked" -1
  fi
}

# ===================================================================== les quatre bras ========
#            nom      md5 appareil   APK conforme   garde retiree
BRAS="egaux:local:0:0 perime:autre:0:0 deploye:autre:1:0 vieux:autre:0:1"
montes=0; courus=0
for spec in $BRAS; do
  IFS=: read -r nom md5 apk sansgarde <<<"$spec"
  if monte_bras "$nom" "$SB/$nom" "$md5" "$apk" "$sansgarde"; then
    montes=$((montes + 1))
    court_bras "$nom" "$SB/$nom"
    courus=$((courus + 1))
  else
    note "bras $nom : montage impossible"
    kv "arm_${nom}_rc" -1; kv "arm_${nom}_decision" montage-impossible
    kv "arm_${nom}_proof" 0; kv "arm_${nom}_started" -1
    kv "arm_${nom}_mesure_sur_perime" 0; kv "arm_${nom}_preuve_precedente" inconnue
  fi
done
kv selftest_arms_montes "$montes"
kv selftest_arms_courus "$courus"

# ==================================== LE COUT D'AVANT QUI SE COMPTE : LES GARDES PRIVEES ======
# Chaque item appareil s'est ecrit la meme garde dans son coin. On les compte par leur GESTE
# (elles comparent deux md5), pas par leur nom, et on publie combien de CODES DE SORTIE
# differents elles utilisent : c'est la mesure de ce que « pas de garde partagee » coute.
cd "$ROOT" || exit 1
avant_scripts=0; avant_md5=0
codes=""
while IFS= read -r f; do
  [ -f "$f" ] || continue
  avant_scripts=$((avant_scripts + 1))
  grep -qE 'md5(sum)?' "$f" || continue
  grep -qE '(md5|MD5)[^=]*(!=|=)|hashlib\.md5' "$f" || continue
  avant_md5=$((avant_md5 + 1))
  codes="$codes $(grep -oE 'exit [0-9]+' "$f" | awk '{print $2}' | sort -u | paste -sd, -)"
done < <(find .autoport/reports/*/notes -type f \( -iname '*deploy*' -o -iname '*push*' \) \
           \( -name '*.sh' -o -name '*.py' \) 2>/dev/null)
kv avant_gardes_privees_scripts "$avant_scripts"
kv avant_gardes_privees_md5 "$avant_md5"
kv avant_gardes_privees_codes "$(printf '%s' "$codes" | tr ' ,' '\n\n' | grep -c '^[0-9]\+$' || echo 0)"
kv avant_gardes_privees_codes_distincts \
   "$(printf '%s' "$codes" | tr ' ,' '\n\n' | grep '^[0-9]\+$' | sort -u | paste -sd, -)"

# LE RECENSEMENT DE DISQUE, PUBLIE AVEC SON DENOMINATEUR. Il rend zero, et ce zero est une
# propriete du PRODUCTEUR (proof.txt est ecrase a chaque course), pas une absence de defaut.
paires=0; ecarts=0
while IFS= read -r f; do
  d=$(sed -n 's/^device_lib_md5=//p' "$f" | tail -1)
  l=$(sed -n 's/^local_lib_md5=//p' "$f" | tail -1)
  [ -n "$d" ] && [ -n "$l" ] || continue
  case "$d" in absent*|'') continue ;; esac
  paires=$((paires + 1))
  [ "$d" = "$l" ] || ecarts=$((ecarts + 1))
done < <(grep -rl '^device_lib_md5=' .autoport/reports 2>/dev/null)
kv disque_paires_lues "$paires"
kv disque_ecarts "$ecarts"

kv selftest_ran 1
