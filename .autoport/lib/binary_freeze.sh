#!/usr/bin/env bash
# lib/binary_freeze.sh — LE BINAIRE QUE LA COURSE A MESURE, FIGE.
#
# POURQUOI CE FICHIER EXISTE (harness-judge-binary-race-with-builder, 2026-09-20).
# `validators/generic.sh` comparait `sha=` de la preuve a `sha256sum` du binaire SUR LE DISQUE,
# au moment du VERDICT. Entre la fin d'une course et son jugement, `auto_build_apk.sh` peut
# produire plusieurs builds — QUATRE le 20/09 entre 14:16 et 14:26, un par commit — et le
# binaire du disque n'est alors plus celui que la course a mesure. Mesure : l'essai 4 de
# `grass-blade-variants` refuse sur « sha=f1f2c5ece3ac69e4 n'est pas celui de
# build-android/lib/arm64-v8a/libgk.so sur le disque » alors que sa propre preuve publiait
# `proof_binary_decision=identique` et deux md5 egaux : au moment de la COURSE, disque, APK et
# appareil portaient le meme binaire. L'essai a ete debite pour de la plomberie.
#
# CE QU'IL FAIT. Au DEPART de la course, le binaire est COPIE dans un magasin adresse par son
# contenu, et le dossier de l'item recoit un temoin qui nomme cette copie. Le juge ne relit plus
# le disque : il recalcule l'empreinte DES OCTETS DE LA COPIE et la compare a ce que la preuve
# annonce. Le constructeur peut alors construire quand il veut.
#
# CE QUI RESTE NON VIDE DE SENS. Une empreinte recopiee d'un fichier dans un autre ne prouverait
# que la recopie : ce sont les OCTETS qui sont gardes, et `verify` les rehache. Une preuve dont
# le `sha=` ne decrit pas le binaire de sa course reste donc ROUGE — c'est le controle du banc.
#
# Le magasin est adresse par contenu : deux items qui mesurent le meme binaire partagent une
# seule copie, et sur btrfs `cp --reflink=auto` ne consomme rien tant que l'original vit.
#
# Usage :
#   lib/binary_freeze.sh freeze <id> <bras> <chemin-du-binaire>   -> `cle=valeur` sur stdout
#   lib/binary_freeze.sh path   <id> [bras]                       -> le chemin de la copie figee
#   lib/binary_freeze.sh verify <id> <bras> <sha16> [preuve]      -> 0 = la preuve dit vrai
#   lib/binary_freeze.sh gc                                       -> retire les copies orphelines
#
# Codes : 0 = d'accord. 1 = defaut nomme (message sur stderr). 2 = usage.
set -uo pipefail
export LC_ALL=C

ROOT=$(git rev-parse --show-toplevel 2>/dev/null) || { echo "binary_freeze: pas dans un depot git" >&2; exit 2; }
cd "$ROOT" || exit 2
AP=.autoport
STORE="$AP/binfreeze"

# LE NOM DU TEMOIN SORT DE L'AUTORITE DE NOMMAGE (NOMMAGE/un-seul-endroit), jamais d'un litteral
# pose ici : un nom fabrique a deux endroits diverge en silence, et le lecteur qui cherche le nom
# qu'il a reecrit de son cote lit « fichier absent » — c'est-a-dire « rien a redire ».
nom_temoin(){ python3 "$AP/lib/impossible.py" name binary "${1:-}" 2>/dev/null; }

temoin_de(){  # temoin_de <id> <bras>
  local n; n=$(nom_temoin "${2:-}") || return 1
  [ -n "$n" ] || return 1
  printf '%s/reports/%s/%s' "$AP" "$1" "$n"
}

champ(){ sed -n "s/^$2=//p" "$1" 2>/dev/null | tail -1; }

cmd=${1:-}; shift 2>/dev/null || true

case "$cmd" in

freeze)
  ID=${1:-}; ARM=${2:-}; SRC=${3:-}
  [ -n "$ID" ] && [ -n "$SRC" ] || { echo "usage: binary_freeze.sh freeze <id> <bras> <binaire>" >&2; exit 2; }
  [ -s "$SRC" ] || { echo "binary_freeze: '$SRC' est absent ou vide : rien a figer" >&2; exit 1; }
  T=$(temoin_de "$ID" "$ARM") || { echo "binary_freeze: l'autorite de nommage ne nomme pas le temoin du bras '${ARM:-livre}'" >&2; exit 1; }
  mkdir -p "$(dirname "$T")" "$STORE" || exit 1
  SHA=$(sha256sum "$SRC" 2>/dev/null | cut -d' ' -f1)
  case "$SHA" in ''|*[!0-9a-f]*) echo "binary_freeze: sha256sum n'a rien rendu sur '$SRC'" >&2; exit 1 ;; esac
  DEST="$STORE/$SHA"
  if [ ! -s "$DEST" ]; then
    TMP="$DEST.tmp.$$"
    # `--reflink=auto` : partage d'extents sur btrfs, copie pleine ailleurs. Le `mv` final rend
    # l'apparition de la copie ATOMIQUE — un lecteur ne voit jamais une copie a moitie ecrite.
    cp --reflink=auto -- "$SRC" "$TMP" 2>/dev/null || cp -- "$SRC" "$TMP" || {
      rm -f -- "$TMP"; echo "binary_freeze: la copie de '$SRC' a echoue" >&2; exit 1; }
    chmod a-w -- "$TMP" 2>/dev/null || true
    mv -f -- "$TMP" "$DEST" || { rm -f -- "$TMP"; echo "binary_freeze: '$DEST' non pose" >&2; exit 1; }
  fi
  # LA COPIE EST RELUE, PAS SUPPOSEE. Un magasin corrompu ou tronque doit se voir ICI, au point
  # de production, jamais au verdict — c'est la ou la perte se rend impossible.
  REL=$(sha256sum "$DEST" 2>/dev/null | cut -d' ' -f1)
  [ "$REL" = "$SHA" ] || { echo "binary_freeze: la copie figee ne rend pas l'empreinte de sa source ($REL != $SHA)" >&2; exit 1; }
  SZ=$(stat -c %s "$DEST" 2>/dev/null)
  MT=$(stat -c %Y "$SRC" 2>/dev/null)
  {
    echo "binary_frozen=1"
    echo "binary_frozen_item=$ID"
    echo "binary_frozen_arm=${ARM:-livre}"
    echo "binary_frozen_src=$SRC"
    echo "binary_frozen_store=$DEST"
    echo "binary_frozen_sha256=$SHA"
    echo "binary_frozen_sha=${SHA:0:16}"
    echo "binary_frozen_size=${SZ:-0}"
    echo "binary_frozen_src_mtime=${MT:-0}"
    echo "binary_frozen_at=$(date -u +%Y-%m-%dT%H:%M:%SZ)"
    echo "binary_frozen_pid=$$"
  } > "$T" || exit 1
  # Ce que la course publiera dans proof.txt : le prefixe `proof_` separe ce que la MACHINE dit
  # de ce que le temoin porte, et aucune de ces cles n'est reservee par le moissonneur.
  sed 's/^/proof_/' "$T"
  exit 0
  ;;

path)
  ID=${1:-}; ARM=${2:-}
  [ -n "$ID" ] || { echo "usage: binary_freeze.sh path <id> [bras]" >&2; exit 2; }
  T=$(temoin_de "$ID" "$ARM") || exit 1
  [ -s "$T" ] || { echo "binary_freeze: aucun temoin de binaire fige pour '$ID' bras '${ARM:-livre}' ($T)" >&2; exit 1; }
  DEST=$(champ "$T" binary_frozen_store)
  [ -n "$DEST" ] && [ -s "$DEST" ] || { echo "binary_freeze: le temoin de '$ID' nomme '$DEST', qui n'est plus la" >&2; exit 1; }
  printf '%s\n' "$DEST"
  exit 0
  ;;

verify)
  ID=${1:-}; ARM=${2:-}; DIT=${3:-}; PREUVE=${4:-}; ATTENDU=${5:-}
  [ -n "$ID" ] || { echo "usage: binary_freeze.sh verify <id> <bras> <sha16> [preuve]" >&2; exit 2; }
  T=$(temoin_de "$ID" "$ARM") || { echo "binary_freeze: pas de nom de temoin pour le bras '${ARM:-livre}'" >&2; exit 1; }
  if [ ! -s "$T" ]; then
    echo "la preuve ne porte aucune empreinte FIGEE de son binaire ($T absent) : elle sort d'un producteur qui laissait le juge relire le disque, donc un build survenu entre la course et le verdict la condamnait. Reproduis-la." >&2
    exit 1
  fi
  DEST=$(champ "$T" binary_frozen_store)
  if [ -z "$DEST" ] || [ ! -s "$DEST" ]; then
    echo "le temoin du binaire fige nomme '$DEST', qui n'est plus dans le magasin : la copie que la course a mesuree a disparu, le verdict n'a plus rien a relire" >&2
    exit 1
  fi
  # NOUS NE CROYONS PAS LE TEMOIN SUR PAROLE : l'empreinte est recalculee sur les OCTETS de la
  # copie. Un temoin dont le `sha` ne decrit pas sa propre copie est un temoin, pas une mesure.
  REL=$(sha256sum "$DEST" 2>/dev/null | cut -c1-16)
  ANN=$(champ "$T" binary_frozen_sha)
  if [ "$REL" != "$ANN" ]; then
    echo "la copie figee du binaire ($DEST) rend $REL, son temoin annonce $ANN : le magasin a ete touche depuis la course" >&2
    exit 1
  fi
  if [ -n "$PREUVE" ] && [ -s "$PREUVE" ] && [ "$T" -nt "$PREUVE" ]; then
    echo "le temoin du binaire fige ($T) est PLUS RECENT que la preuve : il ne decrit pas la course qui a ecrit cette preuve" >&2
    exit 1
  fi
  # LE GEL DOIT PORTER SUR LE BINAIRE QUE LA PREUVE NOMME. Sans cette ligne, une course x86
  # pourrait presenter le gel d'un binaire arm64 : les octets seraient coherents, et pourtant
  # personne n'aurait mesure ce que la preuve dit avoir mesure.
  SRC=$(champ "$T" binary_frozen_src)
  if [ -n "$ATTENDU" ] && [ "$SRC" != "$ATTENDU" ]; then
    echo "le binaire fige est '$SRC', la preuve dit avoir mesure '$ATTENDU' : le gel ne decrit pas cette course" >&2
    exit 1
  fi
  if [ "$DIT" != "$REL" ]; then
    echo "sha=$DIT dans la preuve, $REL sur le binaire que la COURSE a mesure ($(champ "$T" binary_frozen_src), fige le $(champ "$T" binary_frozen_at)) : cette preuve ne decrit pas le binaire de sa propre course" >&2
    exit 1
  fi
  exit 0
  ;;

subst)
  # UN RECENSEMENT LIT LE MEME BINAIRE QUE SA COURSE. Il donne le chemin VIVANT qu'il allait
  # ouvrir ; on lui rend la copie figee quand c'est bien ce binaire-la que la course a mesure, et
  # son chemin inchange sinon. Sans ce detour, un crochet qui relit `build-android/.../libgk.so`
  # apres un build juge un binaire que personne n'a mesure — c'est le meme defaut que celui du
  # juge, un etage plus bas.
  ID=${1:-}; ARM=${2:-}; VIF=${3:-}
  [ -n "$ID" ] && [ -n "$VIF" ] || { echo "usage: binary_freeze.sh subst <id> <bras> <chemin>" >&2; exit 2; }
  T=$(temoin_de "$ID" "$ARM") || { printf '%s\n' "$VIF"; exit 0; }
  if [ -s "$T" ]; then
    SRC=$(champ "$T" binary_frozen_src); DEST=$(champ "$T" binary_frozen_store)
    if [ -n "$SRC" ] && [ "$SRC" = "$VIF" ] && [ -n "$DEST" ] && [ -s "$DEST" ]; then
      printf '%s\n' "$DEST"; exit 0
    fi
  fi
  printf '%s\n' "$VIF"
  exit 0
  ;;

gc)
  # Une copie que plus aucun temoin ne nomme ne sert plus a aucun verdict. Le compte des deux
  # populations est rendu : « 0 retiree » et « rien a retirer » ne se lisent pas pareil.
  [ -d "$STORE" ] || { echo "binfreeze_gc_store=0"; echo "binfreeze_gc_removed=0"; exit 0; }
  REFS="$STORE/.refs.$$"
  : > "$REFS"
  NT=$(nom_temoin "")
  NTO=$(nom_temoin "-off")
  for n in "$NT" "$NTO"; do
    [ -n "$n" ] || continue
    for t in "$AP"/reports/*/"$n"; do
      [ -s "$t" ] || continue
      champ "$t" binary_frozen_store >> "$REFS"
    done
  done
  tot=0; rm_n=0
  for f in "$STORE"/*; do
    case "$f" in "$STORE"/.refs.*|"$STORE"/\*) continue ;; esac
    [ -f "$f" ] || continue
    tot=$((tot+1))
    grep -qxF "$f" "$REFS" 2>/dev/null && continue
    rm -f -- "$f" && rm_n=$((rm_n+1))
  done
  rm -f -- "$REFS"
  echo "binfreeze_gc_store=$tot"
  echo "binfreeze_gc_removed=$rm_n"
  exit 0
  ;;

*)
  echo "usage: lib/binary_freeze.sh {freeze|path|verify|gc} ..." >&2; exit 2 ;;
esac
