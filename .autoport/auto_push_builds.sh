#!/usr/bin/env bash
# --- GARDE SHIELD (owner 2026-08-26) : ce demon fait son travail normalement,
# mais il ne doit JAMAIS parler a la NVIDIA Shield. Elle s'etait reconnectee
# toute seule au serveur adb et l'owner a exige l'arret total :
#   « TU TOUCHES PLUS A LA SHIELD TANT QUE JE TE LE DIT PAS »
# On la sort du serveur adb a chaque tour, sans rien changer au reste.
SHIELD_ADDR="192.168.1.32:5555"   # Shield INTERDITE — adresse gardee UNIQUEMENT pour la deconnecter
shield_keep_out() {
  # INTERDICTION OWNER 2026-08-30 : « Interdit de toucher a la SHIELD a nouveau. »
  # Appelee a CHAQUE tour de boucle, plus seulement au demarrage : une reconnexion
  # faite par un tiers ne doit jamais laisser la Shield visible d'un tour a l'autre.
  "${ADB:-adb}" disconnect "$SHIELD_ADDR" >/dev/null 2>&1 || true
}
shield_keep_out



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
  shield_keep_out   # owner 2026-08-30 : la Shield ne doit jamais etre visible d'un tour a l'autre
  sleep 300
  [ -f "$APK" ] || continue
  # settle: size must be stable across two reads, otherwise gradle is still writing
  s1=$(stat -c %s "$APK"); sleep 20; s2=$(stat -c %s "$APK")
  [ "$s1" = "$s2" ] || continue
  h=$(md5sum "$APK" | cut -d' ' -f1)
  # NE JAMAIS PUBLIER DU TRAVAIL INACHEVE A L'OWNER (constate le 2026-08-30 17:32 : le build
  # publie embarquait le pas de temps fixe dont le validateur avait ECHOUE six minutes plus
  # tot ; l'owner aurait telecharge, pour reparer un plantage, un binaire portant un chantier
  # non valide sur les sauts et la camera). Le publieur declenchait sur le seul hash de l'APK,
  # sans aucune notion d'etat du chantier. On saute tant que HEAD est un point d'etape.
  # FAILLE MESUREE LE 2026-08-30 19:08 : la garde ci-dessous ne regardait que le MESSAGE de
  # HEAD. A 19:06 un commit valide est arrive, mais l'APK sur le disque datait encore de
  # 17h27 — le publieur a donc renvoye l'ANCIEN binaire (hash 6bb5f1b6, pas de temps fixe
  # arme) sous une etiquette fraiche. L'owner pouvait telecharger un build perime croyant
  # avoir le correctif. On exige donc que l'artefact ait ete CONSTRUIT depuis HEAD.
  HEADSHA=$(git rev-parse HEAD 2>/dev/null || echo "")
  INFOSHA=$(sed -n 's/.*commit: \([0-9a-f]\{7,\}\).*/\1/p' out/artifacts/BUILD-INFO.txt 2>/dev/null | head -1)
  # 2026-08-31 02:05 : la regle « APK == HEAD » etait TROP STRICTE. Le framework commite en
  # continu, donc HEAD avance pendant la construction et l'APK du correctif d'herbe s'est
  # fait refuser 4 fois de suite alors qu'il etait BON. Ce qu'on veut interdire, c'est de
  # republier un artefact PLUS ANCIEN que ce qui est deja en ligne (le bug du 19:08). La
  # bonne regle est donc : le commit de l'APK doit etre un ANCETRE de HEAD (donc pas d'une
  # branche divergente) ET ne pas etre anterieur au commit deja publie.
  if [ -n "$HEADSHA" ] && [ -n "$INFOSHA" ]; then
    if ! git merge-base --is-ancestor "$INFOSHA" "$HEADSHA" 2>/dev/null; then
      echo "$(date +%H:%M:%S) SKIP publication : l'APK vient de $INFOSHA, qui n'est pas un ancetre de HEAD" >> "$LOG"
      continue
    fi
    if [ -n "${LASTINFO:-}" ] && [ "$INFOSHA" != "$LASTINFO" ] \
       && git merge-base --is-ancestor "$INFOSHA" "$LASTINFO" 2>/dev/null; then
      echo "$(date +%H:%M:%S) SKIP publication : l'APK ($INFOSHA) est ANTERIEUR au build deja publie ($LASTINFO)" >> "$LOG"
      continue
    fi
    LASTINFO="$INFOSHA"
  fi
  HEADMSG=$(git log -1 --format=%s 2>/dev/null || echo "")
  case "$HEADMSG" in
    *"WIP checkpoint"*|*"validator FAILED"*)
      echo "$(date +%H:%M:%S) SKIP publication : HEAD est un point d'etape non valide — $HEADMSG" >> "$LOG"
      continue ;;
  esac
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
    # DESCRIPTION A JOUR A CHAQUE PUBLICATION (owner 2026-09-01) : il ne doit jamais avoir
    # a deviner ce qu'il y a a tester dans le build en ligne.
    bash .autoport/release_notes.sh >> "$LOG" 2>&1 || true
    echo "$(date +%H:%M:%S) PUSHED apk=${h:0:8} zip=${zh:0:8} ($(numfmt --to=iec "$s2" 2>/dev/null || echo "$s2"))" >> "$LOG"
    # 2026-08-19 : le declencheur owner_testable.py n'etait appele PAR PERSONNE. Il compare le build
    # courant a un JALON qu'il n'avance qu'en tournant ; ne tournant qu'a la main, le jalon datait de
    # la veille et il a attribue au build de 20:00 un changement de rayon fait le 08-18 a 14:23. Un
    # « a tester » sur un build dont la physique est IDENTIQUE a celui qu'il a deja, c'est exactement
    # le bruit que ce script existe pour eviter. Il tourne desormais a CHAQUE publication, donc le
    # jalon avance build par build et un delta ne peut plus etre impute au mauvais.
    python3 .autoport/owner_testable.py >> "$LOG" 2>&1 || true
  else
    echo "$(date +%H:%M:%S) upload FAILED ${h:0:8}" >> "$LOG"
  fi
done
