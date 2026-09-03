#!/usr/bin/env bash
# alive.sh <motif> — compte les processus REELS portant le motif, sans se compter soi-meme.
#
# Piege rencontre TROIS fois le 2026-08-11 : `ps -eo args | grep -c '[a]uto_build_apk.sh'` compte
# aussi le `bash -c` du superviseur qui execute la commande, puisque la ligne de commande de ce
# shell contient le motif en clair. Le truc des crochets ne protege QUE le grep lui-meme, pas le
# wrapper. On exclut donc explicitement soi-meme et ses ancetres.
pat="$1"
self=$$
ancestors=""
p=$self
while [ -n "$p" ] && [ "$p" != "1" ]; do
  ancestors="$ancestors $p"
  p=$(ps -o ppid= -p "$p" 2>/dev/null | tr -d ' ')
done
# exclure aussi tout processus qui ne fait que PARLER du motif : le helper lui-meme, les shells
# qui l'invoquent, et les commandes de supervision. Seule une invocation `bash <chemin>/<motif>`
# compte comme une instance reelle.
ps -eo pid,args | grep -F "$pat" | grep -v grep | grep -v alive.sh | while read -r pid rest; do
  case "$rest" in *"bash "*"$pat"*|*"/bin/sh "*"$pat"*) : ;; *) continue ;; esac
  case " $ancestors " in *" $pid "*) continue ;; esac
  echo "$pid"
done | grep -c . || true
