#!/usr/bin/env bash
# Ghd-skin-origin-stretch — COURSE DE DIAGNOSTIC x86.
#
# But : faire PARLER le detecteur pose dans `fill-jak-hd-bones!` (marqueurs HDEPISODE/HDEPX/
# HDEPY/HDEPZ/HDHB) et trancher, PAR LA MESURE :
#   (a) la CIBLE de l'etirement est-elle l'origine du monde ou un lieu ? (HDEPX cible_*)
#   (b) le pilote porte-t-il encore la position monde quand un os HD part ? (HDEPZ atrans)
#   (c) le LOD du pilote calcule-t-il moins de joints que son squelette n'en porte ?
#       (HDLOD : le nombre de joints de CHAQUE LOD, lu sur le modele livre)
#
# Le tour de niveaux couvre 246 m -> 5388 m de l'origine : c'est l'axe de la correlation que
# la phase demande (la longueur de l'etirement doit suivre la distance a l'origine).
#
# Verrou de livraison : ce script REFUSE de tourner si un verrou vivant qui n'est pas le notre
# est pose (l'auto-constructeur efface out/jak1/obj et reecrit l'iso en ARM64 sur tout changement
# de source). gk tourne sur une COPIE PRIVEE de l'iso.
set -uo pipefail
cd "$(git rev-parse --show-toplevel)"
OUT=.autoport/reports/Ghd-skin-origin-stretch; mkdir -p "$OUT"
GOALC=build-x86/goalc/goalc; GK=build-x86/game/gk
ISO=out/jak1/iso; SNAP=/home/emeric/.autoport-scratch/ghso-iso
SETTINGS=build/game/OpenGOAL/jak1/settings/settings.ini
TAG="${TAG:-diag}"
LOG="$OUT/$TAG.log"; GCLOG="$OUT/$TAG-goalc.log"; DRV="$OUT/$TAG-driver.log"
: > "$LOG"; : > "$GCLOG"; : > "$DRV"
say(){ echo "$(date +%H:%M:%S) $*" | tee -a "$DRV"; }

LOCK=.autoport/.deploy-in-progress
if [ -f "$LOCK" ]; then
  P=$(sed -n 's/.*pid=\([0-9]*\).*/\1/p' "$LOCK" | head -1)
  if [ -n "$P" ] && kill -0 "$P" 2>/dev/null; then
    if grep -q '^ghso' "$LOCK"; then say "verrou ghso deja tenu par pid=$P — on le remplace par le notre"
    else say "VERROU TENU par pid=$P (pas le notre) — abandon"; exit 2; fi
  fi
fi
printf 'ghso_diag pid=%s started=%s\n' "$$" "$(date -Is)" > "$LOCK"

cp -f "$SETTINGS" "$SETTINGS.ghso-bak"
cleanup(){
  exec 3>&- 2>/dev/null || true
  [ -n "${GKPID:-}" ] && kill "$GKPID" 2>/dev/null
  [ -n "${GCPID:-}" ] && kill "$GCPID" 2>/dev/null
  sleep 1
  [ -f "$SETTINGS.ghso-bak" ] && mv -f "$SETTINGS.ghso-bak" "$SETTINGS"
  rm -f "${FIFO:-/nonexistent}" "$LOCK"
}
trap cleanup EXIT

# COUT D'IMAGE ABAISSE, ET C'EST DECLARE. Aucun de ces reglages n'est sur le chemin sous test
# (le reciblage lit des matrices d'os, pas des pixels) ; ils achetent des images par seconde.
sed -i "s/^game-size = .*/game-size = 640 480/" "$SETTINGS"
sed -i "s/^render-scale = .*/render-scale = 25.0000/" "$SETTINGS"
sed -i "s/^min-render-scale = .*/min-render-scale = 25.0000/" "$SETTINGS"
sed -i "s/^recharged-grass? = .*/recharged-grass? = #f/" "$SETTINGS"
sed -i "s/^pbr-materials? = .*/pbr-materials? = #f/" "$SETTINGS"
sed -i "s/^physics-quality = .*/physics-quality = 0/" "$SETTINGS"
sed -i "s/^recharged-enhanced-models? = .*/recharged-enhanced-models? = #t/" "$SETTINGS"
sed -i "s/^hd-look-jak = .*/hd-look-jak = 1/" "$SETTINGS"
sed -i "s/^hd-look-daxter = .*/hd-look-daxter = 1/" "$SETTINGS"
sed -i "s/^hd-look-keira = .*/hd-look-keira = 1/" "$SETTINGS"
sed -i "s/^hd-look-samos = .*/hd-look-samos = 1/" "$SETTINGS"
sed -i "s/^vsync = .*/vsync = #f/" "$SETTINGS"

# les art-groups HD vivent dans le pack externe : sans cette copie il n'y a AUCUN compagnon,
# et le detecteur rendrait zero en silence.
for c in jak dax keira samos jak2 jak3 daxp keira3 ysamos jakm jakp; do
  cp -f "recharged_assets/hd_anim/$c-hd-ag.go" out/jak1/obj/ 2>/dev/null
done
say "art-groups HD copies : $(ls out/jak1/obj/*-hd-ag.go 2>/dev/null | wc -l)"

say "== copie privee de l'iso =="
rm -rf "$SNAP"; mkdir -p "$(dirname "$SNAP")"
cp -a --reflink=auto "$ISO" "$SNAP"
cp -f out/jak1/obj/*-hd-ag.go "$SNAP/" 2>/dev/null
say "copie : GAME.CGO $(md5sum "$SNAP/GAME.CGO" | cut -c1-12)"

export DISPLAY="${DISPLAY:-:0}"
[ -n "${XAUTHORITY:-}" ] || for x in /run/user/1000/.mutter-Xwaylandauth.*; do [ -e "$x" ] && export XAUTHORITY="$x"; done
export SDL_VIDEODRIVER=x11 LANG=en_US.UTF-8 LC_ALL=en_US.UTF-8

say "== lancement de gk =="
stdbuf -oL -eL "$GK" --game jak1 --portable -fakeiso --verbose --disable-ansi \
    -iso-data "$SNAP" -- -boot -debug-mem >> "$LOG" 2>&1 &
GKPID=$!
FIFO="$(mktemp -u)"; mkfifo "$FIFO"
for i in $(seq 1 240); do grep -qa "Waiting for listener" "$LOG" && break; sleep 1; done
sleep 20
say "gk : $(grep -ac 'link finish:' "$LOG") objets lies"

timeout 3000 "$GOALC" --game jak1 --proj-path . --iso-path "$ISO" --disable-ansi < "$FIFO" > "$GCLOG" 2>&1 &
GCPID=$!
exec 3>"$FIFO"
echo '(lt)' >&3
sleep 6
echo '(build-game)' >&3
for i in $(seq 1 400); do grep -qa "Successfully built all" "$GCLOG" && { say "build-game a ~${i}s"; break; }; sleep 1; done
sleep 5

# --- SONDES REUTILISABLES -------------------------------------------------------------------
# HDLOD : combien de joints CHAQUE LOD du pilote calcule (le `num-joints` du mgeo est la borne
#         de la boucle de do-joint-math! : process-drawable.gc:255). Si les LOD different, les
#         os au-dela ne sont PAS ecrits a ce LOD.
lodprobe(){
  echo '(when *target* (format 0 "HDLOD maxlod=~D curlod=~D nj=~D~%" (-> *target* draw max-lod) (-> *target* draw cur-lod) (-> *target* draw mgeo num-joints)) (dotimes (i (+ 1 (-> *target* draw max-lod))) (let ((g (-> *target* draw lod-set lod i geo))) (format 0 "HDLODI i=~D nom=~A nj=~D dist=~f~%" i (if g (-> g name) (quote nul)) (if g (-> g num-joints) -1) (-> *target* draw lod-set lod i dist)))))' >&3
  sleep 2
}
# HDDRVZ : combien d'os du squelette du pilote portent une base NULLE (matrice jamais ecrite),
#          et combien portent une translation quasi nulle (pas de position monde).
drvprobe(){
  echo '(when *target* (let ((s (-> *target* draw skeleton)) (nz 0) (nt 0)) (dotimes (i (-> s length)) (if (< (vector-length (-> s bones i transform vector 0)) 0.001) (+! nz 1)) (if (< (vector-length (-> s bones i transform vector 3)) 400.0) (+! nt 1))) (format 0 "HDDRVZ len=~D zerobase=~D neartrans=~D nj=~D lod=~D~%" (-> s length) nz nt (-> *target* draw mgeo num-joints) (-> *target* draw cur-lod))))' >&3
  sleep 2
}
hbprobe(){
  echo '(format 0 "HDPROBE ep=~D fills=~D occ=~D pos=~f~%" *hd-stretch-episodes* *hd-stretch-fills* *hd-stretch-occ* (if *target* (/ (vector-length (-> *target* control trans)) 4096.0) -1.0))' >&3
  sleep 2
}
# le balayage HD tourne a chaque image et laisse ses comptes dans ces deux globales.
compprobe(){
  echo '(format 0 "HDCOMP compagnons=~D pilotes=~D toggle=~A~%" *hd-scan-companion-count* *hd-scan-driver-count* (-> *pc-settings* recharged-enhanced-models?))' >&3
  sleep 2
}

# --- TOUR DE NIVEAUX ------------------------------------------------------------------------
# distances a l'origine (|trans|/4096, level-info.gc) : le socle de la correlation demandee.
tour(){
  local name="$1" secs="$2"
  say "-- $name --"
  echo "(format 0 \"HDLEVEL nom=~S~%\" \"$name\")" >&3
  echo "(start (quote play) (get-continue-by-name *game-info* \"$name\"))" >&3
  sleep 45
  compprobe; lodprobe; drvprobe; hbprobe
  # IDLE : le jeu tourne, la camera vit, les PNJ jouent leurs animations.
  sleep "$secs"
  hbprobe
  # INJECTION (controle positif) : forcer le pilote a un LOD reduit. Si le defaut vient de la
  # bordure de joints non calcules, le detecteur doit MONTER ici et retomber au retrait.
  for L in 1 2; do
    echo "(when *target* (set! (-> *target* draw force-lod) $L))" >&3
    sleep 2; lodprobe; drvprobe
    sleep 10
    hbprobe
  done
  echo '(when *target* (set! (-> *target* draw force-lod) -1))' >&3
  sleep 6
  hbprobe
}

tour "village1-hut" 25
tour "jungle-start" 20
tour "village2-start" 20
tour "village3-start" 20
tour "citadel-start" 20

say "== fin de course =="
echo '(format 0 "HDFIN ep=~D fills=~D occ=~D~%" *hd-stretch-episodes* *hd-stretch-fills* *hd-stretch-occ*)' >&3
sleep 4
kill "$GKPID" 2>/dev/null; wait "$GKPID" 2>/dev/null
say "HDEPISODE=$(grep -ac '^HDEPISODE' "$LOG")  HDHB=$(grep -ac '^HDHB' "$LOG")  HDLODI=$(grep -ac '^HDLODI' "$LOG")  HDDRVZ=$(grep -ac '^HDDRVZ' "$LOG")"
grep -aE '^(HDEPISODE|HDEPX|HDEPY|HDEPZ|HDHB|HDLOD|HDLODI|HDDRVZ|HDPROBE|HDCOMP|HDLEVEL|HDFIN)' "$LOG" > "$OUT/$TAG-marqueurs.txt"
say "marqueurs -> $OUT/$TAG-marqueurs.txt ($(wc -l < "$OUT/$TAG-marqueurs.txt") lignes)"
