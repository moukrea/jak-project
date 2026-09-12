#!/usr/bin/env bash
# lib/freshness.sh — LE SEUL COMPARATEUR DE FRAICHEUR DU HARNAIS (cote shell).
#
# POURQUOI CE FICHIER EXISTE (harness-subsecond-freshness-is-blind, 2026-09-12). Quatre
# signalements du meme jour ont trouve la MEME faute a trois endroits : une comparaison de
# fraicheur qui lit ses deux cotes a la SECONDE ENTIERE, et qui accepte l'EGALITE comme une
# preuve de fraicheur. Les deux erreurs vont du cote PERMISSIF — elles declarent frais un
# artefact perime — et une fraicheur fausse est le defaut le plus cher du projet : une preuve
# qui decrit un autre binaire que celui qu'on croit.
#
# LES DEUX REGLES, ET RIEN D'AUTRE :
#
#   1. LA MEME RESOLUTION DES DEUX COTES. `stat -c %Y` et `find -printf %T@ | cut -d. -f1`
#      jettent la sous-seconde. Un lien saute dont l'entree est reecrite 0,4 s plus tard porte
#      alors le MEME entier que sa sortie. On lit donc en nanosecondes ENTIERES, des deux cotes,
#      toujours. `fr_resolution` rend la resolution EFFECTIVEMENT lue d'une valeur, pour qu'une
#      troncature d'un seul cote se compte au lieu de se deviner.
#
#   2. L'EGALITE NE VAUT PAS FRAICHEUR. A horodatage egal, on ne SAIT PAS lequel des deux a ete
#      ecrit en premier : le verdict est `douteux`, et l'appelant refuse. Ce n'est pas de la
#      prudence de principe, c'est mesure — sur le btrfs de cette machine, deux fichiers ecrits
#      a la suite recoivent le MEME horodatage a la nanoseconde pres (l'horloge de l'inode
#      n'avance que par tics d'environ 300 us). L'egalite arrive donc pour de vrai.
#
# LA VIRGULE EST UN SEPARATEUR DECIMAL. `stat -c %.9Y` rend `1789236416,611605185` sous une
# locale francaise. `LC_ALL=C` est pose ici, et les deux separateurs sont acceptes de toute
# facon : un comparateur qui depend de la locale de celui qui l'appelle ne compare rien.
#
# LES NANOSECONDES SE COMPARENT COMME DES ENTIERS BASH (64 bits, donc jusqu'en 2262) — JAMAIS
# en awk, dont les doubles perdent les trois derniers chiffres d'un entier a 19 chiffres.
#
# Usage : `. lib/freshness.sh` puis
#   fr_ns_de "<sec>[.,]<frac>"   -> nanosecondes entieres (0 si illisible, rc 1)
#   fr_mtime_ns <fichier>        -> mtime en nanosecondes (0 si absent, rc 1)
#   fr_plus_recent_ns            -> lit des `%T@` sur stdin, rend le PLUS RECENT en ns (0 si vide)
#   fr_verdict <art_ns> <src_ns> -> imprime frais|perime|douteux ; rc 0|1|2
#   fr_resolution <ns>           -> `ns` si la sous-seconde est non nulle, `s` sinon
#
# LE POINT D'APPEL SE COMPTE (AUTOPORT_FRESHNESS_TRACE). Une liste de sites ne prouve que la
# liste : le banc pose `AUTOPORT_FRESHNESS_TRACE=<fichier>` et `FR_SITE=<nom>`, et CHAQUE verdict
# s'y ecrit avec ses deux valeurs et leurs deux resolutions. C'est ce qui fait la difference
# entre « le script cite le comparateur » et « le script a COMPARE, avec ces chiffres-la ».
export LC_ALL=C

# "<secondes>[.,]<fraction>" -> nanosecondes entieres. La fraction est completee ou TRONQUEE a
# neuf chiffres : GNU `find -printf %T@` en rend DIX (un zero de remplissage en queue), et les
# coller tels quels decalerait tout d'un facteur dix.
fr_ns_de(){
  local v="${1:-}" s f
  case "$v" in ''|*[!0-9.,]*) echo 0; return 1 ;; esac
  s=${v%%[.,]*}
  case "$s" in ''|*[!0-9]*) echo 0; return 1 ;; esac
  f=${v#"$s"}; f=${f#[.,]}
  case "$f" in *[!0-9]*) echo 0; return 1 ;; esac
  f="${f}000000000"; f=${f:0:9}
  printf '%s%s\n' "$s" "$f"
}

fr_mtime_ns(){
  local v
  v=$(stat -c %.9Y "${1:-}" 2>/dev/null) || { echo 0; return 1; }
  [ -n "$v" ] || { echo 0; return 1; }
  fr_ns_de "$v"
}

# Le PLUS RECENT d'un flux de `%T@`. La comparaison est faite sur des CHAINES de meme longueur
# (19 chiffres depuis 2001 et jusqu'en 2286) : `awk` en arithmetique perdrait les nanosecondes.
fr_plus_recent_ns(){
  awk '{
    n = $1
    sub(/[.,].*/, "", n)
    if (n !~ /^[0-9]+$/) next
    f = $1; sub(/^[0-9]*([.,])?/, "", f)
    if (f !~ /^[0-9]*$/) f = ""
    f = substr(f "000000000", 1, 9)
    v = n f
    if (m == "" || length(v) > length(m) || (length(v) == length(m) && v > m)) m = v
  } END { print (m == "" ? "0" : m) }'
}

# `ns` = la sous-seconde porte de l'information ; `s` = elle est nulle, donc soit l'horodatage
# tombe pile sur la seconde (1 chance sur 1e9), soit QUELQU'UN L'A TRONQUE. C'est la grandeur
# qui permet de compter une troncature d'un seul cote au lieu de la supposer.
fr_resolution(){
  case "${1:-0}" in
    0) echo absent ;;
    *000000000) echo s ;;
    *) echo ns ;;
  esac
}

fr_trace(){
  [ -n "${AUTOPORT_FRESHNESS_TRACE:-}" ] || return 0
  printf 'site=%s verdict=%s art_ns=%s src_ns=%s res_art=%s res_src=%s\n' \
    "${FR_SITE:-inconnu}" "$1" "$2" "$3" "$(fr_resolution "$2")" "$(fr_resolution "$3")" \
    >> "$AUTOPORT_FRESHNESS_TRACE" 2>/dev/null || true
}

# LE VERDICT. STRICTEMENT plus recent = frais. Egal = DOUTEUX, et l'appelant refuse : a
# horodatage egal, rien ne dit lequel a ete ecrit en premier.
fr_verdict(){
  local a="${1:-0}" s="${2:-0}" v rc
  case "$a$s" in *[!0-9]*) fr_trace illisible "$a" "$s"; echo illisible; return 3 ;; esac
  if   [ "$a" -gt "$s" ]; then v=frais;   rc=0
  elif [ "$a" -lt "$s" ]; then v=perime;  rc=1
  else                        v=douteux; rc=2
  fi
  fr_trace "$v" "$a" "$s"
  printf '%s\n' "$v"
  return "$rc"
}
