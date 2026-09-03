#!/usr/bin/env bash
# Bancs d'essai de la garde pre-tool : faux refus d'un cote, vrais refus de l'autre.
cd /home/emeric/code/jak-project || exit 1
SHIELD="192.168.1.32"
t(){
  printf '{"tool_name":"Bash","tool_input":{"command":%s}}' \
    "$(printf '%s' "$1" | python3 -c 'import json,sys;print(json.dumps(sys.stdin.read()))')" \
    | bash .autoport/hooks/pre-tool.sh >/tmp/g.err 2>&1
  rc=$?
  if [ "$rc" = "$3" ]; then printf 'OK    (%s) %s\n' "$rc" "$2"
  else printf 'ECHEC (attendu %s, obtenu %s) %s\n      %s\n' "$3" "$rc" "$2" "$(head -1 /tmp/g.err)"; fi
}
echo "--- doivent PASSER ---"
t 'grep -nE "refuse|exit 2|pkill|cmake -B|adb|screencap|png" fichier.sh' "grep dont le motif contient adb et pkill" 0
t 'echo "il faut lancer adb -s eae4df44 puis pgrep -f truc"' "echo qui parle d adb" 0
t 'adb -s eae4df44 shell "am start -n org.opengoal.gk.jak1/.LoaderActivity"' "adb correct avec -s" 0
t 'pgrep -af "[o]rchestrator.py"' "pgrep avec classe de caracteres" 0
t 'cmake --build build --target gk -j8' "build incremental" 0
t 'python3 -c "print(1)" | head -3' "pipe simple" 0
echo "--- doivent ETRE REFUSES ---"
t 'adb shell ls /sdcard' "adb sans -s" 2
t 'pkill -f orchestrator' "pkill -f sans crochet" 2
t 'cmake -B build -DCMAKE_BUILD_TYPE=Release' "cmake -B" 2
t "adb -s $SHIELD shell ls" "adresse de la SHIELD" 2
t 'adb -s eae4df44 shell screencap -p > .autoport/reports/x/a.png' "capture d ecran" 2
t 'until ! pgrep -f gradle; do sleep 5; done' "boucle qui attend sur pgrep" 2
echo "--- cout ---"
S=$(date +%s%N)
for i in 1 2 3 4 5 6 7 8 9 10; do
  printf '{"tool_name":"Bash","tool_input":{"command":"ls -la /tmp | head -5"}}' \
    | bash .autoport/hooks/pre-tool.sh >/dev/null 2>&1
done
E=$(date +%s%N); echo "moyenne par appel : $(( (E-S)/10000000 )) ms"
