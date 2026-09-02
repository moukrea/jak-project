#!/usr/bin/env bash
# Gcutscene-npc-flicker-2 — CAMPAGNE x86 SUR LES CINEMATIQUES DE PNJ, LA CINEMATIQUE DU MAIRE
# EN TETE.
#
# POURQUOI UNE SECONDE CAMPAGNE. Celle du cycle 1 (npcf_x86_campagne.sh) n'atteint que les
# cinematiques qu'un `continue-flags` declenche tout seul (engine/target/target-death.gc:230-271) :
# cinq scenes, toutes de Sandover, AUCUNE du maire. L'owner (2026-09-01) : « le pire cas que j'ai
# observé c'est la cinématique avec MAIRE (la première) ». Trois scenes qui ne sont pas celle qui
# echoue ne prouvent rien — c'est exactement ce que le validateur refuse desormais.
#
# CE QUI CHANGE : on part du continue `beach-start`, puis le hook `OG_CINE_KICK` envoie
# `'play-anim` aux PNJ taskables demandes, l'un apres l'autre, dans le MEME demarrage. Une seule
# course rend plusieurs cinematiques.
#
# POURQUOI `beach-start` ET PAS `village1-hut`. Le maire n'est PAS un acteur de village1 : c'est
# l'entite `mayor-5` du niveau **beach** (decompiler_out/jak1/entities/beach-actors.json ;
# all_objs.json : `mayor-ag` -> DGO `BEA`). `beach-start` est le SEUL point de reprise de jak1 qui
# met beach ET village1 en 'active avec `display` (engine/level/level-info.gc:292-310) ; sur
# `village1-hut`, beach est `:disp1 #f` (level-info.gc:151-167), `entity-by-name "mayor-5"` rend
# #f et le maire ne nait jamais. Le spawn est a ~101 m du maire, donc SOUS la borne de naissance
# de 220 m (engine/entity/entity-h.gc:144) : il nait sans qu'on touche a la borne. Et z = -54,6 m
# < 59,9 m, donc sa surcharge `should-display?` (levels/beach/mayor.gc:587-590) le laisse en
# `idle` et non en `hidden` — sans quoi le kick partirait dans le vide.
set -uo pipefail
cd "$(git rev-parse --show-toplevel)"

OUT=.autoport/reports/Gcutscene-npc-flicker; mkdir -p "$OUT"
R="$OUT/x86_campagne2.txt"
GK=build/game/gk; ISO=out/jak1/iso
INI=build/game/OpenGOAL/jak1/settings/settings.ini
# Les PNJ taskables de village1 : le maire d'abord, c'est le cas que l'owner nomme.
KICKS="${KICKS:-mayor,sculptor,bird-lady-beach,farmer,explorer}"
WARP="${WARP:-beach-start}"
WATCH="${WATCH:-330}"
LEGS="${LEGS:-hd1 hd0}"
SKIP_BUILD="${SKIP_BUILD:-0}"
RUNTAG="${RUNTAG:-$(date +%H%M%S)}"
INJECT="${INJECT:-}"
# POSITION DE SPAWN. Sans elle, le maire n'existe PAS : mesure de la course de 02:40 —
# 29 tentatives, toutes `CINEKICK type=mayor envoye=0 raison=absent-du-pool-actif`. Le spawn de
# `beach-start` est a ~101 m du maire ; la naissance d'un acteur n'est pas bornee par la seule
# distance mais par la VISIBILITE (engine/entity/entity.gc:1167-1206, `is-object-visible?` quand
# `ps2-actor-vis?` est arme, ce qui est le defaut pc/pckernel-h.gc:472). Et la levee de borne de
# secours de `pc-cine-kick!` est ANNULEE a l image suivante par pc-settings::update
# (pc/pckernel-common.gc:548-550, « the original caps at 220m »), ce que la trace montre :
# `ancienne_unites=901120` (= 220 m) a CHACUN des 29 appels.
# On pose donc Jak devant le maire — entite `mayor-5`, trans (-116,15 ; 10,90 ; 45,91) m
# (decompiler_out/jak1/entities/beach-actors.json:1721-1765). C est aussi la position REELLE du
# joueur quand il declenche cette cinematique : la mesure y gagne en fidelite au lieu d en perdre.
# `${POS-...}` et non `${POS:-...}` : POS="" doit vouloir dire « pas de surcharge », pas
# « reprends le defaut ». Avec la forme `:-`, une chaine vide retombait sur la valeur par defaut et
# la course publiait une position de spawn qu'on croyait avoir desactivee.
POS="${POS--116 14 40}"
# AMENER BEACH EN 'ACTIVE DEPUIS UN WARP QUI FONCTIONNE.
# `beach-start` est le seul continue qui met beach ET village1 en 'active tout seul, mais sur ce
# chemin `target-continue` ne se termine JAMAIS : `LS_HOLD_TARGET` reste arme (mesure :
# `LOADSCREEN-SHOW arm=4 frames=6120`), donc Jak n'est pas saisissable, donc `process-grab?` rend
# #f et le `:trans` de `idle` ne part pas — le PNJ reste `etat=idle` sur 24 envois avec
# `progress=0 autrecam=0`, c'est-a-dire que les deux conditions lisibles sont bonnes et que seule
# celle-la echoue. Le lanceur, lui, est PROUVE : depuis `village1-hut` il ferme
# `farmer-introduction` (1200 images) et `farmer-reminder-1` (402 images).
# On part donc de `village1-hut` — ou beach est deja CHARGE (`:lev1 beach :disp1 #f`,
# engine/level/level-info.gc:151-167) mais pas affiche — et on l amene en active avec les deux
# crochets de debug qui existent deja (Gcrash-rockvillage, kmachine.cpp:5826-5829).
WANTLEV="${WANTLEV:-}"
WANTDISP="${WANTDISP:-}"
KICKDELAY="${KICKDELAY:-900}"

# AFFICHAGE : LE COOKIE SE DECOUVRE, IL NE SE DEVINE PAS.
# Poser `DISPLAY=:0` ne suffit pas sous GNOME/Wayland : le serveur Xwayland exige un cookie
# d'autorisation dont le FICHIER porte un suffixe aleatoire, tire a chaque ouverture de session
# (/run/user/1000/.mutter-Xwaylandauth.XXXXXX). Sans lui, gk sort en
# « SDL Error: Could not initialize SDL - Cause: x11 not available » et la campagne rend zero
# ligne — ce qui se lirait comme « aucun clignotement » alors que le jeu n'a jamais demarre.
# On lit donc DISPLAY/XAUTHORITY dans l'environnement d'un processus VIVANT de la session
# graphique, au lieu de coder en dur un nom qui changera au prochain redemarrage.
if [ -z "${DISPLAY:-}" ] || [ -z "${XAUTHORITY:-}" ]; then
  for _p in $(pgrep -u "$(id -u)" -f 'gnome-shell|Xwayland|gnome-session' 2>/dev/null | head -8); do
    _e=$(tr '\0' '\n' < "/proc/$_p/environ" 2>/dev/null | grep -E '^(DISPLAY|XAUTHORITY)=' || true)
    if echo "$_e" | grep -q '^XAUTHORITY='; then
      eval "export $(echo "$_e" | tr '\n' ' ')"
      break
    fi
  done
fi
export DISPLAY="${DISPLAY:-:0}"
export SDL_VIDEODRIVER=x11 LANG=en_US.UTF-8 LC_ALL=en_US.UTF-8

say(){ echo "$*" | tee -a "$R"; }
: > "$R"
say "===== campagne x86 cycle 2 — $(date -Is) ====="
say "warp: $WARP   kicks: $KICKS   jambes: $LEGS   watch=${WATCH}s   inject='$INJECT'"
say "affichage: DISPLAY=$DISPLAY XAUTHORITY=${XAUTHORITY:-<aucun>}   runtag=$RUNTAG"
say "spawn(m)='${POS}' want-levels='$WANTLEV' want-display='$WANTDISP' kickdelay=$KICKDELAY"

# UN SEUL ECRIVAIN PAR FICHIER. Mesure du 2026-09-02 02:49 : deux campagnes et deux gk tournaient
# en meme temps et ecrivaient LE MEME `gk2-hd1.log`, chacune basculant `settings.ini` sous l'autre.
# Une trace ecrite a deux mains n'est pas une mesure — et le tell etait un `LOADSCREEN-SHOW
# arm=4 frames=3780` impossible sur une course unique. La garde est ici, pas dans la tete de
# l'appelant.
# NOTE SUR CE QUE J'AI D'ABORD ECRIT ICI, PARCE QUE C'ETAIT UN FAUX ROUGE : compter
# `pgrep -f npcf2_x86_campagne.sh` rend 3 sur une invocation HONNETE (le `timeout`, le `bash`, le
# sous-shell) — la garde se comptait elle-meme et refusait la premiere course. La serialisation des
# campagnes est deja assuree par `.deploy-in-progress` juste en dessous, qui porte un PID et se
# verifie par `kill -0`. Il ne reste ici que la moitie PRECISE : aucun gk ne doit tourner, parce
# que c'est LUI qui ecrit le journal qu'on va lire.
# `pgrep -x gk` et pas `pgrep -f "build/game/gk ..."` : la forme -f compare la LIGNE DE COMMANDE
# entiere, donc elle attrape aussi tout shell de surveillance qui porte ce motif dans son propre
# argument — la garde se serait comptee elle-meme une seconde fois. -x compare le NOM du
# processus, qui ne vaut `gk` que pour le moteur.
if pgrep -x gk >/dev/null 2>&1; then
  echo "FAIL: un gk tourne deja — arrete-le avant de mesurer (il ecrit dans le meme journal)" >&2
  exit 1
fi

LOCK=.autoport/.deploy-in-progress
if [ "${NPCF_LOCK_HELD:-0}" = "1" ]; then
  say "verrou de livraison tenu par l'appelant ($(cat "$LOCK" 2>/dev/null))"
elif [ -f "$LOCK" ]; then
  H=$(sed -n 's/.*pid=\([0-9]*\).*/\1/p' "$LOCK" | head -1)
  if [ -n "$H" ] && kill -0 "$H" 2>/dev/null; then
    say "FAIL: livraison en cours (pid=$H) — on ne construit pas par-dessus"; exit 1
  fi
  say "verrou orphelin ($(cat "$LOCK")) — le detenteur est mort, on continue"
fi
if [ "${NPCF_LOCK_HELD:-0}" = "1" ]; then
  trap '[ -n "${GKPID:-}" ] && kill -9 "$GKPID" 2>/dev/null; [ -f "$OUT/.ini2.pre" ] && cp "$OUT/.ini2.pre" "$INI"' EXIT
else
  printf 'npcf2_x86_campagne pid=%s started=%s\n' "$$" "$(date -Is)" > "$LOCK"
  # LE gk DOIT MOURIR AVEC LA CAMPAGNE. Mesure du 2026-09-02 02:55 : une campagne tuee de
  # l'exterieur laissait son gk vivant, et la course SUIVANTE ecrivait dans le meme journal —
  # c'est la course a deux ecrivains que la garde du haut refuse. La garde et ce trap sont les
  # deux moities du meme verrou : l'une detecte, l'autre empeche.
  trap 'rm -f "$LOCK"; [ -n "${GKPID:-}" ] && kill -9 "$GKPID" 2>/dev/null; [ -f "$OUT/.ini2.pre" ] && cp "$OUT/.ini2.pre" "$INI"' EXIT
fi
cp "$INI" "$OUT/.ini2.pre"

if [ "$SKIP_BUILD" != 1 ]; then
  say "-- (make-group \"iso\") en x86 (out/jak1/iso porte peut-etre de l'arm64)"
  if ! timeout 1800 ./build/goalc/goalc --user-auto --cmd '(make-group "iso")' > "$OUT/goal_build2.log" 2>&1; then
    say "FAIL: compilation GOAL"; tail -30 "$OUT/goal_build2.log" | tee -a "$R"; exit 1
  fi
  say "   GOAL x86 OK ($(grep -ac . "$OUT/goal_build2.log") lignes)"
fi

mkdir -p out/jak1/obj
for c in jak dax keira samos; do
  cp -f "recharged_assets/hd_anim/$c-hd-ag.go" out/jak1/obj/ 2>/dev/null || true
done

set_ini(){ if grep -q "^$1 = " "$INI"; then sed -i "s|^$1 = .*|$1 = $2|" "$INI"; else printf '%s = %s\n' "$1" "$2" >> "$INI"; fi; }

run_one(){ # $1 leg
  local leg="$1"
  # UN NOM DE JOURNAL PAR COURSE. Le nom fixe `gk2-<jambe>.log` etait ecrase au demarrage de la
  # course SUIVANTE (`: > "$log"`), et une archive prise un instant trop tard ramassait un fichier
  # deja vide — c'est arrive, et ca a coute la trace brute d'une mesure reussie. Le TAG rend chaque
  # course adressable ; rien ne peut plus effacer la precedente.
  local log="$OUT/gk2-$leg-$RUNTAG.log"; : > "$log"
  ln -sf "$(basename "$log")" "$OUT/gk2-$leg.log" 2>/dev/null || true
  OG_LEVEL_WARP="$WARP" OG_LEVEL_WARP_POS="$POS" OG_CINE_KICK="$KICKS" OG_NPCF_INJECT="$INJECT" \
    OG_WANT_LEVELS="$WANTLEV" OG_WANT_DISPLAY="$WANTDISP" OG_CINE_KICK_DELAY="$KICKDELAY" \
    "$GK" --game jak1 --portable -fakeiso --verbose --disable-ansi \
      -iso-data "$ISO" -- -boot -debug-mem > "$log" 2>&1 &
  local pid=$!
  GKPID=$pid
  local booted=0
  for i in $(seq 1 240); do
    kill -0 "$pid" 2>/dev/null || break
    grep -aq 'LEVEL-WARP-SPAWN' "$log" && { booted=1; break; }
    sleep 1
  done
  if [ "$booted" = 1 ]; then
    say "   [$leg] warp parti — observation ${WATCH}s"
    sleep "$WATCH"
  else
    say "   [$leg] AUCUN warp (gk mort ou delai) — on publie quand meme ce qui est sorti"
  fi
  kill "$pid" 2>/dev/null || true; wait "$pid" 2>/dev/null || true
  say "   [$leg] CINEKICK: $(grep -ac '^CINEKICK ' "$log" || true) envoi(s), $(grep -a '^CINEKICK ' "$log" | grep -ac 'envoye=1' || true) reussi(s)"
  grep -a '^CINEKICK\|^CINEKICK-' "$log" | head -20 >> "$R" || true
  say "   [$leg] scenes vues: $(grep -a '^NPCSCENE ' "$log" | sed -n 's/.*scene=\([^ ]*\).*/\1/p' | sort -u | tr '\n' ' ')"
  say "   [$leg] NPCFLICK=$(grep -ac '^NPCFLICK ' "$log" || true) evenements=$(grep -ac '^NPCFLICK-EV ' "$log" || true)"
  grep -a '^NPCSCENE \|^NPCFLICK \|^NPCFLICK-EV \|^NPCFLICK-LONG ' "$log" >> "$R" || true
}

for leg in $LEGS; do
  case "$leg" in
    hd1) set_ini 'recharged-enhanced-models?' '#t'; set_ini 'recharged-master?' '#t'
         set_ini 'hd-look-jak' '1'; set_ini 'hd-look-daxter' '1'
         set_ini 'hd-look-keira' '1'; set_ini 'hd-look-samos' '1'
         say "-- JAMBE hd1 : modeles HD ACTIFS" ;;
    hd0) set_ini 'recharged-enhanced-models?' '#f'
         say "-- JAMBE hd0 : modeles HD ETEINTS (ablation, meme binaire)" ;;
  esac
  run_one "$leg"
done
say "===== fin — $(date -Is) ====="
