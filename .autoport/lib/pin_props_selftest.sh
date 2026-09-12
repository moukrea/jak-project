#!/usr/bin/env bash
# pin_props_selftest.sh — LE BAC A SABLE DE L'EPINGLAGE (harness-proof-props-pin).
#
# CE QU'IL FABRIQUE. Un depot jetable, un FAUX `adb` (un fichier de proprietes et un journal),
# un backlog d'un seul item qui porte `proof_props`, et une propriete posee « depuis l'hote »
# AVANT la course — exactement le geste qui se perdait. Puis il lance le VRAI `lib/proof_run.sh`
# en mode `device` contre ce faux appareil, et lit le `proof.txt` qui en sort.
#
# POURQUOI UN BAC A SABLE. L'item est `device: false` : aucune course telephone n'est autorisee,
# et les DIRECTIVES refusent une campagne d'appareil qu'on n'a pas demandee. Attendre la
# prochaine course appareil pour savoir si l'epinglage tient, c'est ne jamais le savoir. Ici on
# FABRIQUE la condition — un worker qui pose sa propriete a la main — au lieu de l'attendre.
#
# LES DEUX BRAS. `neuf` = les scripts du disque. `vieux` = les MEMES scripts, pris au dernier
# commit qui ne portait pas le correctif (trouve par son marqueur, pas par une date : le bras
# d'ablation doit survivre au commit de ce chantier). Sans le bras vieux, un zero se lirait
# « rien ne se perd » alors qu'il voudrait dire « personne n'a regarde ».
#
# Sortie : des `cle=valeur` sur stdout, les explications sur stderr. Il ne JUGE rien : la somme
# et la polarite « inconnu = defaut » sont dans lib/census/harness-proof-props-pin.sh.
set -uo pipefail

ROOT=$(git rev-parse --show-toplevel 2>/dev/null) || { echo "selftest_ran=0"; exit 1; }
AP="$ROOT/.autoport"
SERIAL_FAKE="SANDBOXPIN01"
PKG="org.opengoal.gk.jak1"
ITEM="sandbox-pin"

# LES NOMS DES FICHIERS D'UNE COURSE SORTENT DE L'AUTORITE DE NOMMAGE, jamais d'un litteral tape
# ici : un banc qui cherche un nom qu'il a reecrit de son cote ne trouve plus rien le jour ou le
# nom bouge, et « fichier absent » se lit exactement comme « la course n'a rien produit ».
eval "$(python3 "$AP/lib/impossible.py" names "")"

# Les deux proprietes que l'item declare, et la valeur que l'appareil doit rendre.
DECL1="debug.opengoal.hdr.out=2"
DECL2="debug.opengoal.recharged=1"
# Ce qu'un worker pose A LA MAIN avant la course, et qui disparaissait sans un mot.
HOST1="debug.opengoal.hdr=1"
HOST2="debug.opengoal.cpad_inject=1"

SB=$(mktemp -d -t pinprops.XXXXXX) || { echo "selftest_ran=0"; exit 1; }
trap 'rm -rf "$SB"' EXIT
note(){ printf '[selftest] %s\n' "$*" >&2; }
kv(){ printf '%s=%s\n' "$1" "$2"; }

# ---------------------------------------------------------------- le commit d'AVANT le correctif
# Par MARQUEUR, jamais par date : apres le commit de ce chantier, HEAD porte le correctif et un
# `git show HEAD:` rendrait deux bras identiques — une ablation vide qui passe au vert.
#
# LA FENETRE N'EST PLUS UN NOMBRE DE COMMITS (harness-verdict-integrity, 2026-09-12). Ce bloc
# balayait les 60 DERNIERS commits du chemin. `orchestrator.py` en porte deja 61 et en gagne
# tous les jours : le jour ou l'introduction du marqueur sortait de la fenetre, l'ablation
# devenait introuvable et la porte virait au ROUGE sans qu'aucun defaut existe. On ancre
# desormais sur la REVISION QUI A INTRODUIT le marqueur (`lib/ablation_anchor.sh`, pioche sur le
# contenu, historique complet), et on publie la methode retenue et la profondeur.
# Le sha part dans une variable GLOBALE, jamais sur stdout : cette fonction publie deja des
# `cle=valeur` la-bas, et une substitution de commande emporterait les deux dans le meme sac.
ANCRE_COMMIT=""
ancre() {  # ancre <chemin> <marqueur> <prefixe-de-cle> -> $ANCRE_COMMIT
  local out c
  out=$(bash "$AP/lib/ablation_anchor.sh" "$ROOT" "$1" "$2" kv 2>/dev/null) || true
  kv "ablation_${3}_method" "$(printf '%s\n' "$out" | sed -n 's/^anchor_method=//p' | tail -1)"
  kv "ablation_${3}_depth"  "$(printf '%s\n' "$out" | sed -n 's/^anchor_depth=//p'  | tail -1)"
  kv "ablation_${3}_legacy_window" "$(printf '%s\n' "$out" | sed -n 's/^anchor_legacy_window=//p' | tail -1)"
  c=$(printf '%s\n' "$out" | sed -n 's/^anchor_commit=//p' | tail -1)
  [ "$c" = "-" ] && c=""
  ANCRE_COMMIT="$c"
}
ancre .autoport/lib/proof_run.sh 'proof_props_effective' proof;        C_PROOF="$ANCRE_COMMIT"
ancre .autoport/lib/device_teardown.sh 'AUTOPORT_TEARDOWN_REPORT' teardown; C_TEAR="$ANCRE_COMMIT"
kv ablation_proof_commit "${C_PROOF:0:12}"
kv ablation_teardown_commit "${C_TEAR:0:12}"

# ================================================================== fabrication d'un bras =====
# $1 = nom du bras ; $2 = dossier ; pose les scripts, le faux adb, le backlog, les proprietes.
monte_bras() {
  local nom=$1 dir=$2
  mkdir -p "$dir/.autoport/lib" "$dir/build-android/lib/arm64-v8a" || return 1
  printf 'faux libgk pour le bac a sable %s\n' "$nom" > "$dir/build-android/lib/arm64-v8a/libgk.so"
  # Un depot jetable sous /tmp : proof_run.sh exige `git rev-parse --show-toplevel`.
  git -C "$dir" init -q >/dev/null 2>&1 || return 1        # git-sandbox-ok
  git -C "$dir" config user.email pin@sandbox >/dev/null 2>&1  # git-sandbox-ok
  git -C "$dir" config user.name pin >/dev/null 2>&1           # git-sandbox-ok

  # CE QUE LE BAC A SABLE COPIE SORT DU NOMMEUR DU VERDICT, jamais d'une enumeration tapee ici
  # (harness-verdict-sources-are-incomplete, 2026-09-12). Cette liste etait ecrite a la main : le
  # jour ou `proof_run.sh` a gagne `lib/impossible.py`, la garde de nommage n'a derive aucun nom,
  # le bras neuf est sorti en 3 (« nommage-divergent ») sans produire AUCUNE preuve
  # (`arm_neuf_proof=0`, 12/09), et la porte d'un item DEJA VALIDE est restee rouge sans que
  # personne le sache. Un bac a sable qui declare sa propre liste diverge du depot a chaque
  # dependance que la porte gagne ; celui-ci ne peut plus : il copie la liste que la PORTE epingle.
  local rel
  : > "$dir/.sandbox-manifest"
  while IFS= read -r rel; do
    [ -n "$rel" ] || continue
    mkdir -p "$dir/$(dirname "$rel")" || return 1
    cp "$ROOT/$rel" "$dir/$rel" || return 1
    printf '%s\n' "$rel" >> "$dir/.sandbox-manifest"
  done < <(bash "$AP/lib/verdict_sources.sh" "$ITEM" list)
  chmod +x "$dir/.autoport/lib/"*.sh 2>/dev/null
  chmod +x "$dir/.autoport/acquis/"*.sh "$dir/.autoport/validators/"*.sh 2>/dev/null
  # CONTROLE POSITIF, SUR DEMANDE EXPLICITE. Une mutation `sed` appliquee au `proof_run.sh` de ce
  # bras. Elle ne peut qu'ABIMER la course : aucun appelant ne peut s'en servir pour rendre un
  # verdict plus vert. `lib/verdict_sources_selftest.sh` s'en sert pour ARMER le sceau — sans une
  # course ou le sceau DOIT rougir, un sceau qui ne regarderait rien passerait au vert.
  if [ -n "${AUTOPORT_PIN_SED_NEUF:-}" ] && [ "$nom" = neuf ]; then
    sed -i "$AUTOPORT_PIN_SED_NEUF" "$dir/.autoport/lib/proof_run.sh" || return 1
  fi
  # CE QUE LE BAC CONTIENT VRAIMENT, pour qui veut mesurer l'ecart avec la liste de la porte
  # (lib/census/harness-verdict-sources-are-incomplete.sh). On publie le DISQUE, pas ce que la
  # boucle ci-dessus a cru copier.
  if [ -n "${AUTOPORT_PIN_MANIFEST:-}" ] && [ "$nom" = neuf ]; then
    ( cd "$dir" && find .autoport -type f \
        \( -path '.autoport/lib/*' -o -path '.autoport/validators/*' -o -path '.autoport/acquis/*' \) \
      | LC_ALL=C sort ) > "$AUTOPORT_PIN_MANIFEST"
  fi
  # LE BRAS D'ABLATION : les MEMES fichiers, sauf les deux qu'on remonte au commit d'avant.
  if [ "$nom" != neuf ]; then
    [ -n "$C_PROOF" ] && [ -n "$C_TEAR" ] || return 1
    git -C "$ROOT" show "$C_PROOF:.autoport/lib/proof_run.sh" > "$dir/.autoport/lib/proof_run.sh" || return 1
    git -C "$ROOT" show "$C_TEAR:.autoport/lib/device_teardown.sh" > "$dir/.autoport/lib/device_teardown.sh" || return 1
  fi

  # LE BACKLOG DU BAC A SABLE : un item, deux proprietes epinglees. C'est « ce que le fichier
  # porte », le premier des trois chiffres de la trace.
  cat > "$dir/.autoport/backlog.yaml" <<YAML
version: 1
items:
  - id: $ITEM
    status: in-progress
    device: true
    owner_test: false
    feature: bac a sable de l'epinglage
    proof_timeout: 10
    proof_props:
      - $DECL1
      - $DECL2
YAML

  # LA TABLE DE PROPRIETES DU FAUX APPAREIL, et ce qu'un worker y a pose depuis l'hote.
  printf '%s\n%s\n' "$HOST1" "$HOST2" > "$dir/props"
  : > "$dir/logcat"
  md5sum "$dir/build-android/lib/arm64-v8a/libgk.so" | awk '{print $1}' > "$dir/md5"

  # ------------------------------------------------------------------------- le faux adb -----
  # Il n'imite pas adb en general : il imite EXACTEMENT les commandes que proof_run.sh,
  # device_teardown.sh et pick_device.sh envoient. Toute autre commande sort en 0 sans rien
  # faire — un faux appareil ne doit jamais faire echouer une course pour une commande qu'on
  # n'a pas modelisee, il doit rendre le chemin des proprietes observable.
  cat > "$dir/adb" <<'ADB_EOF'
#!/usr/bin/env bash
D=$(cd "$(dirname "$0")" && pwd)
P="$D/props"; L="$D/logcat"
get(){ sed -n "s/^$(printf '%s' "$1" | sed 's/[.[\*^$]/\\&/g')=//p" "$P" | tail -1; }
set_(){ local k=$1 v=$2 t; t=$(mktemp); grep -v "^$(printf '%s' "$k" | sed 's/[.[\*^$]/\\&/g')=" "$P" > "$t" 2>/dev/null
        [ -n "$v" ] && printf '%s=%s\n' "$k" "$v" >> "$t"; mv -f "$t" "$P"; }
[ "${1:-}" = devices ] && { printf 'List of devices attached\nSANDBOXPIN01\tdevice\n'; exit 0; }
[ "${1:-}" = -s ] || exit 1
shift 2
case "${1:-}" in
  get-state) echo device ;;
  logcat)
    [ "${2:-}" = -c ] && { : > "$L"; exit 0; }
    exec tail -n +1 -f "$L" ;;
  shell|exec-out)
    shift
    [ "${1:-}" = run-as ] && shift 2            # run-as PKG
    [ "${1:-}" = sh ] && shift 2                # sh -c
    # Le shell de l'appareil delimite sur les espaces et mange les quotes : `setprop k ''`
    # arrive ici en UNE chaine. Aucune valeur du bac a sable ne porte d'espace.
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
      md5sum) printf '%s  %s\n' "$(cat "$D/md5")" "${2:-}" ;;
      pidof) [ -f "$D/started" ] && echo 4242 ;;
      cmd) echo "org.opengoal.gk.jak1/org.opengoal.gk.LoaderActivity" ;;
      dumpsys) echo "mWakefulness=Awake" ;;
      appops) : ;;                              # rien : la branche MIUI reste hors du chemin
      am)
        case "${2:-}" in
          start)
            : > "$D/started"
            { for n in 60 120 180 240 300 360 420 480 540 600; do
                printf '09-12 10:00:00.000 I/GK_STDOUT( 4242): AUTOPORT-FRAMES n=%s\n' "$n"
                printf '09-12 10:00:00.000 I/GK_STDOUT( 4242): FEATURE %s armed=1 hits=%s\n' \
                       "$(get debug.opengoal.feature)" "$n"
              done
              # LE MOTEUR DIT CE QU'IL A LU. C'est le seul temoin qui ne vient pas du runner.
              # `-` quand la propriete est vide : une valeur vide ne franchit pas le moissonneur
              # (`^cle=[^espace]+$`), et une cle absente se lirait « le moteur n'a rien dit ».
              vu(){ local v; v=$(get "$1"); printf '09-12 10:00:00.000 I/GK_STDOUT( 4242): %s=%s\n' "$2" "${v:--}"; }
              vu debug.opengoal.hdr.out   sandbox_engine_saw_hdr_out
              vu debug.opengoal.recharged sandbox_engine_saw_recharged
              vu debug.opengoal.hdr       sandbox_engine_saw_hostpin
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
}

# ============================================================== la course d'un bras ===========
# Rend 0 si `proof.txt` a ete ecrit. Publie, prefixees par le bras, les grandeurs lues DANS ce
# proof.txt — jamais une valeur que ce script aurait choisie.
court_bras() {
  local nom=$1 dir=$2 pf="$2/.autoport/reports/$ITEM/$AP_NAME_proof"
  ( cd "$dir" && ANDROID_SERIAL="$SERIAL_FAKE" ADB="$dir/adb" AUTOPORT_PKG="$PKG" \
      AUTOPORT_PROOF_WAIT_MAX=120 AUTOPORT_LOGCAT_PIDDIR="$dir/.logcat" \
      timeout -k 10 300 bash .autoport/lib/proof_run.sh "$ITEM" device --timeout 10 \
  ) >"$dir/run.log" 2>&1
  local rc=$?
  note "bras $nom : proof_run sorti en $rc"
  if [ ! -s "$pf" ]; then
    kv "arm_${nom}_proof" 0
    return 1
  fi
  kv "arm_${nom}_proof" 1
  cp "$pf" "$dir/proof-copy.txt"
  local k
  for k in teardown_ran teardown_props_found teardown_props_list proof_props_file \
           proof_props_extracted proof_props_effective proof_props_lost proof_props_observed \
           proof_props_observed_match proof_prop_obs_hdr_out proof_prop_obs_recharged \
           frames crash sandbox_engine_saw_hdr_out sandbox_engine_saw_recharged \
           sandbox_engine_saw_hostpin \
           teardown_getprop_ok teardown_getprop_total teardown_props_source \
           teardown_fin_ran teardown_fin_props_found teardown_fin_props_list \
           teardown_fin_props_cleared teardown_fin_getprop_ok teardown_fin_getprop_total \
           teardown_fin_props_source verdict_sources_count verdict_sources_sha; do
    kv "arm_${nom}_$k" "$(sed -n "s/^$k=//p" "$pf" | tail -1 | tr ' ' '_')"
  done
  # LE GESTE DU WORKER, VU DE LA PREUVE : sa propriete posee a la main est-elle NOMMEE dans ce
  # que le teardown dit avoir trouve ? C'est toute la difference entre « efface » et « disparu ».
  if grep -q "^teardown_props_list=.*${HOST1%%=*}" "$pf"; then
    kv "arm_${nom}_host_prop_named" 1
  else
    kv "arm_${nom}_host_prop_named" 0
  fi
  # ... et a-t-elle bien ete effacee (le teardown fait toujours son travail) ?
  if [ -z "$(sed -n "s/^${HOST1%%=*}=//p" "$dir/props")" ]; then
    kv "arm_${nom}_host_prop_cleared" 1
  else
    kv "arm_${nom}_host_prop_cleared" 0
  fi
  # Combien de cles de TRACE ce bras publie-t-il ? Le bras vieux doit en publier ZERO.
  kv "arm_${nom}_trace_keys" \
     "$(grep -cE '^(teardown_|proof_props_|proof_prop_obs_)' "$pf")"
  # LE SCEAU DE LA COURSE (PROOF-SCELLE/rien-apres-le-mv, harness-verdict-sources-are-incomplete).
  # C'est le SEUL endroit du harnais ou le vrai `proof_run.sh` passe par le teardown de FIN — le
  # chemin qui ajoutait ses cles a `proof.txt` APRES son `mv` atomique. L'empreinte prise au `mv`
  # et celle relue a la sortie du processus se lisent ici, sur une course reelle : egales, rien
  # n'a ete ecrit apres le `mv`.
  local sf="$2/.autoport/reports/$ITEM/$AP_NAME_seal"
  if [ -s "$sf" ]; then
    kv "arm_${nom}_seal_lu"     1
    kv "arm_${nom}_seal_sha"    "$(sed -n 's/^seal_sha=//p' "$sf" | tail -1)"
    kv "arm_${nom}_seal_exit"   "$(sed -n 's/^exit_sha=//p' "$sf" | tail -1)"
    kv "arm_${nom}_seal_disque" "$(sha256sum "$pf" | cut -c1-64)"
  else
    kv "arm_${nom}_seal_lu" 0
  fi
  return 0
}

# ===================================================================== les deux bras ==========
ok_neuf=0; ok_vieux=0
if monte_bras neuf "$SB/neuf"; then
  court_bras neuf "$SB/neuf" && ok_neuf=1
else
  note "bras neuf : montage impossible"
fi
if [ -n "$C_PROOF" ] && [ -n "$C_TEAR" ] && monte_bras vieux "$SB/vieux"; then
  court_bras vieux "$SB/vieux" && ok_vieux=1
else
  note "bras vieux : montage impossible (commit d'avant introuvable)"
  kv arm_vieux_proof 0
fi
kv selftest_arms_ok "$((ok_neuf + ok_vieux))"
kv selftest_ran 1
