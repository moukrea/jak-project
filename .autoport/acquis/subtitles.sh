#!/usr/bin/env bash
# acquis/subtitles.sh — LE STYLE DES SOUS-TITRES : UNE SEULE PASSE DE TEXTE, OMBRE NON DECALEE.
#
# CE QU'ON GARDE. Deux nombres, ceux que l'owner a valides dans Gsubtitle-style-2 :
#   * `SUBDUP passes_de_texte=1` — le texte est pose UNE fois. A deux passes il est double, et
#     ca se voit comme un gras sale.
#   * `SUBSHADOW offset_x=0 offset_y=0` — l'ombre est centree sous le texte, pas decalee.
# Le moteur les publie une seule fois, au PREMIER sous-titre reellement rasterise (GOAL,
# pc/subtitle.gc, `subtitle-style-trace`). C'est le point de LECTURE, pas le chargement.
#
# COMMENT ON ATTEINT UN SOUS-TITRE. `subtitles? = #f` dans le settings.ini livre : sans rien
# faire, cette garde ne verrait jamais son instrument, et une garde qui ne peut que dire
# « je ne sais pas » ne garde rien. On ne touche PAS au fichier de l'owner : on copie son
# dossier de configuration dans le cache, on y met `subtitles? = #t`, et on lance gk avec
# `--config-path` sur la copie. Le fichier de l'owner n'est jamais ouvert en ecriture.
#
# ATTEINTE NON VERIFIEE : ce chantier n'avait pas le droit de lancer gk. Si l'intro rejouee ne
# rasterise pas de sous-titre dans la fenetre, la garde dit UNPROVABLE avec la raison exacte —
# elle ne bloque rien et elle se diagnostique toute seule. Aucun rapport n'est lu.
ACQ_NAME=subtitles
. "$(dirname "$0")/_lib.sh"

CFG="$PWD/$ACQ_CACHE/subcfg"
SRCCFG=build/game/OpenGOAL
[ -d "$SRCCFG" ] || acq_unprovable "dossier de configuration $SRCCFG absent : impossible de preparer une copie avec les sous-titres allumes"
if [ ! -f "$CFG/OpenGOAL/jak1/settings/settings.ini" ] \
   || [ "$SRCCFG/jak1/settings/settings.ini" -nt "$CFG/OpenGOAL/jak1/settings/settings.ini" ]; then
  rm -rf "$CFG"; mkdir -p "$CFG" || acq_unprovable "impossible de creer la configuration jetable $CFG"
  cp -r "$SRCCFG" "$CFG/" 2>/dev/null || acq_unprovable "copie de $SRCCFG impossible"
  sed -i 's/^subtitles? = #f/subtitles? = #t/' "$CFG/OpenGOAL/jak1/settings/settings.ini" 2>/dev/null
fi
grep -q 'subtitles? = #t' "$CFG/OpenGOAL/jak1/settings/settings.ini" 2>/dev/null \
  || acq_unprovable "la copie jetable n'a pas 'subtitles? = #t' : la ligne du settings.ini a change de forme"

ACQ_GK_ARGS="--config-path $CFG"
LOG=$(acq_x86_log intro 85 OG_ECHO_INTRO=1) \
  || acq_unprovable "pas de course x86 mesurable (gk absent, pas d'affichage, ou un build ecrit en ce moment)"
acq_norm "$LOG" > "$LOG.n"
WARP=$(grep -ac 'ECHO-INTRO-WARP' "$LOG.n" || true)
DUP=$(grep -a 'SUBDUP passes_de_texte=' "$LOG.n" | tail -1)
SHA=$(grep -a 'SUBSHADOW type=' "$LOG.n" | tail -1)
rm -f "$LOG.n"

if [ -z "$DUP" ] && [ -z "$SHA" ]; then
  acq_unprovable "aucune ligne SUBDUP/SUBSHADOW en 85 s (intro rejouee : $WARP) : aucun sous-titre n'a ete rasterise, il n'y a rien a juger"
fi
if [ -n "$DUP" ]; then
  P=$(printf '%s' "$DUP" | grep -oE 'passes_de_texte=[0-9]+' | head -1 | cut -d= -f2)
  [ "${P:-0}" = 1 ] || acq_broken "le texte des sous-titres est pose $P fois au lieu d'une : $DUP"
fi
if [ -n "$SHA" ]; then
  OX=$(printf '%s' "$SHA" | grep -oE 'offset_x=-?[0-9.]+' | head -1 | cut -d= -f2)
  OY=$(printf '%s' "$SHA" | grep -oE 'offset_y=-?[0-9.]+' | head -1 | cut -d= -f2)
  awk -v x="${OX:-0}" -v y="${OY:-0}" 'BEGIN{a=x+0;b=y+0;if(a<0)a=-a;if(b<0)b=-b;exit (a<0.001&&b<0.001)?0:1}' \
    || acq_broken "l'ombre des sous-titres est decalee (offset_x=$OX offset_y=$OY) : $SHA"
fi
acq_ok "une seule passe de texte, ombre non decalee — ${DUP:-$SHA}"
