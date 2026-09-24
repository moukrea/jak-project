#!/usr/bin/env bash
# lib/acquis_device.sh — SOCLE BASH DES ACQUIS APPAREIL (harness-device-acquis-hardening, 24/09).
# Sourceable sans effet : il ne definit que des fonctions. Il vit HORS de `acquis/`, parce que la
# porte des acquis lance tout `acquis/*.sh`. La garde de preuve elle-meme est l'unique exemplaire
# de `lib/acquis_device_guard.py` ; un acquis appareil n'y ajoute que ce qui lui est propre.

# acq_device_guard <options de la garde...> : 0 + journal sur stdout, 2 = a reacquerir, 1 = defaut.
acq_device_guard(){
  python3 .autoport/lib/acquis_device_guard.py --ttl "${ACQ_CACHE_TTL:-1800}" "$@"
}

# acq_device_main <etiquette> <fonction de controle> <arguments de proof_run...> -- <arguments du script>
# Juge la preuve en place ; UNE course proof_run seulement si elle est absente ou perimee (2),
# aucune si un defaut est mesure (1).
acq_device_main(){
  local tag="$1" check="$2"
  shift 2
  local -a run=()
  while [ "$#" -gt 0 ] && [ "$1" != -- ]; do run+=("$1"); shift; done
  [ "$#" -gt 0 ] && shift
  if [ "$#" -gt 1 ] || [[ "${1:-}" == --* ]]; then
    echo "usage: $tag.sh [serial]" >&2
    return 1
  fi
  local root log status
  local ANDROID_SERIAL="${1:-${ANDROID_SERIAL:-}}"
  export ANDROID_SERIAL
  if [[ "$ANDROID_SERIAL" == *:* || "$ANDROID_SERIAL" == *_adb-tls-* || "$ANDROID_SERIAL" =~ [[:space:]] || "$ANDROID_SERIAL" =~ [0-9]+\.[0-9]+\.[0-9]+\.[0-9]+ ]]; then
    echo "[acquis/$tag] NON PROUVE : serial USB requis" >&2
    return 1
  fi
  root=$(git rev-parse --show-toplevel) || return 1
  cd "$root" || return 1
  log=$("$check") && status=0 || status=$?
  if [ "$status" = 2 ]; then
    bash .autoport/lib/proof_run.sh "${run[@]}" || {
      echo "[acquis/$tag] NON PROUVE : course proof_run echouee" >&2
      return 1
    }
    log=$("$check") || return 1
  elif [ "$status" != 0 ]; then
    return 1
  fi
  printf '[acquis/%s] TENU : %s\n' "$tag" "$log"
}
