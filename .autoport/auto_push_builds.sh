#!/usr/bin/env bash
# Continuously ship intermediate builds to jak-builds so the owner never waits.
# Owner 2026-08-06: "n'hésite pas à pousser les builds intermédiaires au fil de l'eau que je teste aussi"
# Uploads only when the APK's content hash actually changed, and never while a build is mid-write.
set +e -o pipefail
trap 'echo "$(date +%H:%M:%S) trapped err at line $LINENO, continuing" >> .autoport/logs/auto_push_builds.txt' ERR
cd "$(dirname "$0")/.." || exit 1

# PID FILE — le superviseur teste l'EXISTENCE du processus, jamais une correspondance de
# motif : `ps | grep motif` compte le grep lui-meme, piege tombe quatre fois en 24h et qui a
# fait tuer la chaine de livraison toute la nuit du 2026-08-11.
PIDFILE=".autoport/.auto_push_builds.pid"
echo $$ > "$PIDFILE"
trap 'rm -f "$PIDFILE"' EXIT
APK=android/app/build/outputs/apk/jak1/debug/app-jak1-debug.apk
# The HD asset pack is a SEPARATE deliverable: the reskin (skin-authority fix) is baked
# into the HD models, so it ships in this zip and NOT in the APK. Watching only the APK
# once shipped an "updated" build whose main change the owner could not possibly see.
ZIP=out/artifacts/jak1_hd_assets.zip
DIST=.autoport/dist/app-jak1-HD-recharged.apk
LOG=.autoport/logs/auto_push_builds.txt
LAST=""
[ -f "$APK" ] && LAST=$(md5sum "$APK" | cut -d' ' -f1)
echo "$(date +%H:%M:%S) watcher started (baseline ${LAST:0:8})" >> "$LOG"
while true; do
  sleep 300
  [ -f "$APK" ] || continue
  # settle: size must be stable across two reads, otherwise gradle is still writing
  s1=$(stat -c %s "$APK"); sleep 20; s2=$(stat -c %s "$APK")
  [ "$s1" = "$s2" ] || continue
  h=$(md5sum "$APK" | cut -d' ' -f1)
  # LE PACK HD EST UN LIVRABLE A PART ENTIERE, PAS UNE PIECE JOINTE DE L'APK.
  # Bug mesure le 2026-08-13 : cette garde ne testait QUE le hash de l'APK, donc un cycle qui ne
  # corrige QUE le mesh (reskin -> GAME.fr3 -> jak1_hd_assets.zip) ne partait JAMAIS, quel que
  # soit le changement du zip. Constate ce jour-la : le pack HD publie a 07:14 precedait le
  # GAME.fr3 de 07:48 — le correctif de nuque n'avait pas ete livre, et rien ne le signalait.
  # On sort donc quand les DEUX sont inchanges, jamais quand un seul l'est.
  zh=""; [ -f "$ZIP" ] && zh=$(md5sum "$ZIP" | cut -d' ' -f1)
  [ "$h" = "$LAST" ] && [ "$zh" = "${LASTZIP:-}" ] && continue
  # Never upload a partially-written artifact. Match an ACTIVE build only:
  # the long-lived Gradle DAEMON must not count (it runs for hours and would
  # block every upload forever - that bug held back the 20:20 APK).
  # Match a real build process only. Two traps already hit: the long-lived Gradle
  # DAEMON (runs for hours), and the worker's own `claude -p` whose PROMPT TEXT
  # contains the literal words "cmake --build" — ps sees the prompt, so the watcher
  # thought a build was running forever and never uploaded anything.
  if ps -eo comm,args | grep -vE '^claude ' \
       | grep -qE '^(cmake|ninja|cc1plus|java)[^\n]*(--build|assemble|GradleWrapperMain)'; then continue; fi
  UP=()
  # On n'envoie que ce qui a CHANGE : re-televerser un APK de 581 Mo identique pour un correctif
  # de mesh de 47 Mo ferait payer a l'owner un telechargement qui ne lui apporte rien.
  if [ "$h" != "$LAST" ]; then
    cp "$APK" "$DIST" || continue
    UP+=("$DIST")
  fi
  # Owner 2026-08-11: on publie meme quand ce n'est PAS vert, pour qu'il puisse tester et
  # renvoyer des retours. BUILD-INFO.txt part avec, pour qu'il sache exactement ce qu'il a
  # entre les mains (commit, branche, ce qui est rouge) au lieu de deviner.
  [ -f out/artifacts/BUILD-INFO.txt ] && UP+=("out/artifacts/BUILD-INFO.txt")
  # `LASTZIP` n'est PAS pose ici : il ne l'est qu'apres un televersement REUSSI, plus bas. Le poser
  # avant ferait oublier un zip dont l'envoi a echoue — il ne repartirait plus jamais.
  [ -n "$zh" ] && [ "$zh" != "${LASTZIP:-}" ] && UP+=("$ZIP")
  [ ${#UP[@]} -gt 0 ] || continue
  if timeout 1800 gh release upload jak1-rtlight-wip "${UP[@]}" \
       --repo moukrea/jak-builds --clobber >>"$LOG" 2>&1; then
    LAST="$h"; LASTZIP="$zh"
    echo "$(date +%H:%M:%S) PUSHED apk=${h:0:8} zip=${zh:0:8} ($(numfmt --to=iec "$s2" 2>/dev/null || echo "$s2"))" >> "$LOG"
  else
    echo "$(date +%H:%M:%S) upload FAILED ${h:0:8}" >> "$LOG"
  fi
done
