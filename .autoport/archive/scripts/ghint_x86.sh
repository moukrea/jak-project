#!/usr/bin/env bash
# ghint_x86.sh — Gaudio-hint-voices x86 ORACLE. Boots desktop x86 gk with the
# per-source RMS meter (OPENGOAL_AUDIO_RMS=1) + HINT-PROBE (OPENGOAL_HINT_PROBE=1),
# connects goalc, warps to Geyser Rock, then triggers the IN-GAME hint VOICE path the
# SAME way ambient.gc:288 does — string->sound-name "spool-XXXX" -> sound-play-by-name
# -> (srpc.cpp) "spool-" route -> FindVAGFile -> PlayVAGStream -> 989snd stream voice.
# Captures the [HINT-PROBE] lines + AUDIODIAG rms so we can compare x86 (works) vs the
# arm64 device. Non-invasive (no tracked-source edits beyond the temp HINT-PROBE).
#
# Env: REPO GK GOALC ISO OUTLOG
set -uo pipefail
REPO="${REPO:?}"; GK="${GK:?}"; GOALC="${GOALC:?}"; ISO="${ISO:?}"; OUTLOG="${OUTLOG:?}"
export DISPLAY="${DISPLAY:-:0}"
export OPENGOAL_AUDIO_RMS=1
export OPENGOAL_HINT_PROBE=1
cd "$REPO"
mkdir -p "$(dirname "$OUTLOG")"
GKLOG="$(mktemp)"; GCLOG="$(mktemp)"; FIFO="$(mktemp -u)"; mkfifo "$FIFO"
: > "$GKLOG"; : > "$GCLOG"
echo "[ghint-x86] repo=$REPO gk=$GK gklog=$GKLOG"

"$GK" --game jak1 --portable -fakeiso --verbose --disable-ansi -iso-data "$ISO" -- -boot -debug-mem > "$GKLOG" 2>&1 &
GKPID=$!
cleanup(){ exec 3>&- 2>/dev/null||true; kill "$GKPID" "${GCPID:-0}" 2>/dev/null||true; wait 2>/dev/null||true; rm -f "$FIFO"; }
trap cleanup EXIT

for i in $(seq 1 90); do
  kill -0 "$GKPID" 2>/dev/null || { echo "[ghint-x86] gk exited during boot"; tail -30 "$GKLOG"; exit 1; }
  grep -qE "link finish: logo($|-)" "$GKLOG" && { echo "[ghint-x86] booted ~${i}s"; break; }
  sleep 1
done
sleep 3

timeout 1200 "$GOALC" --game jak1 --proj-path . --iso-path "$ISO" < "$FIFO" > "$GCLOG" 2>&1 &
GCPID=$!
exec 3>"$FIFO"
echo '(lt)' >&3
echo '(build-game)' >&3
echo "[ghint-x86] build-game sent; waiting up to 220s..."
for i in $(seq 1 220); do
  sleep 1
  grep -qiE "Successfully built all|Build Successful|\] OK" "$GCLOG" 2>/dev/null && { echo "[ghint-x86] build-game done ~${i}s"; break; }
done
sleep 4

echo "[ghint-x86] warp to NEW GAME continue 'game-start' (Geyser Rock / training)"
echo "(start 'play (get-continue-by-name *game-info* \"game-start\"))" >&3
echo "[ghint-x86] waiting 22s for training + *target*..."
sleep 22
echo '(if *target* (format 0 "GHINT-TGT ~A~%" (-> *target* type)) (format 0 "GHINT-TGT <none>~%"))' >&3
sleep 2

# Baseline marker
echo '(format 0 "GHINT-MARK baseline frame=~D~%" (-> *display* base-frame-counter))' >&3
sleep 3

# (1) DIRECT voice-path trigger (faithful to ambient.gc:288): pack name at runtime and play
echo "[ghint-x86] direct sound-play-by-name spool-sagevb36 (hint VOICE path)"
echo '(format 0 "GHINT-MARK direct-sagevb36~%")' >&3
echo '(sound-play-by-name (string->sound-name "spool-sagevb36") (new-sound-id) 1024 0 0 (sound-group sfx) #t)' >&3
sleep 6
# (2) another hint VAG
echo '(format 0 "GHINT-MARK direct-sksp0009~%")' >&3
echo '(sound-play-by-name (string->sound-name "spool-sksp0009") (new-sound-id) 1024 0 0 (sound-group sfx) #t)' >&3
sleep 6

# (3) FULL process path via level-hint-spawn (the real in-game trigger)
echo "[ghint-x86] level-hint-spawn training-ironcrate sagevb36 (real hint process)"
echo '(format 0 "GHINT-MARK level-hint-spawn~%")' >&3
echo '(clear-text-seen! *game-info* (text-id training-ironcrate))' >&3
echo '(level-hint-spawn (text-id training-ironcrate) "sagevb36" (the-as entity #f) *entity-pool* (game-task none))' >&3
sleep 8

# (4) action SFX reference (non-spool, LookupSoundIndex path)
echo "[ghint-x86] action SFX (wcrate-break / buzzer-pickup / water-drop — from Gsfx report)"
echo '(format 0 "GHINT-MARK action-sfx~%")' >&3
echo '(sound-play "wcrate-break")' >&3
sleep 2
echo '(sound-play "buzzer-pickup")' >&3
sleep 2
echo '(sound-play "water-drop")' >&3
sleep 4

exec 3>&-
sleep 3

{
  echo "==================== Gaudio-hint-voices x86 ORACLE ===================="
  echo "[cmd] gk: $GK ... -iso-data $ISO -- -boot -debug-mem   (OPENGOAL_AUDIO_RMS=1 OPENGOAL_HINT_PROBE=1)"
  echo
  echo "---- GHINT-TGT / markers ----"
  grep -aE "GHINT-TGT|GHINT-MARK" "$GKLOG" 2>/dev/null || echo "(none)"
  echo
  echo "---- [HINT-PROBE] PLAY (spool=1 = streamed hint/cutscene VOICE) ----"
  grep -a "\[HINT-PROBE\] PLAY" "$GKLOG" 2>/dev/null | sed 's/.*\[HINT-PROBE\]/[HINT-PROBE]/' | sort -u || echo "(none)"
  echo
  echo "---- [HINT-PROBE] SPOOL resolve (FindVAGFile ptr; 0x0 = unresolved=silent) ----"
  grep -a "\[HINT-PROBE\] SPOOL" "$GKLOG" 2>/dev/null | sed 's/.*\[HINT-PROBE\]/[HINT-PROBE]/' | sort -u || echo "(none)"
  echo
  echo "---- AUDIODIAG rms timeline (stream=voice tag1 / sfx=tag2 / music=tag3) ----"
  grep -a "AUDIODIAG rms" "$GKLOG" 2>/dev/null | sed 's/.*AUDIODIAG/AUDIODIAG/' || echo "(none)"
  echo
  echo "---- AUDIODIAG max per source ----"
  echo "  max stream = $(grep -a 'AUDIODIAG rms' "$GKLOG" | grep -aoE 'stream=[0-9]+' | grep -oE '[0-9]+' | sort -n | tail -1)"
  echo "  max sfx    = $(grep -a 'AUDIODIAG rms' "$GKLOG" | grep -aoE 'sfx=[0-9]+'    | grep -oE '[0-9]+' | sort -n | tail -1)"
  echo "  max music  = $(grep -a 'AUDIODIAG rms' "$GKLOG" | grep -aoE 'music=[0-9]+'  | grep -oE '[0-9]+' | sort -n | tail -1)"
  echo
  echo "[ghint-x86] full gk log kept at: $GKLOG"
} | tee "$OUTLOG"
cp "$GKLOG" "${OUTLOG%.txt}-gklog.log" 2>/dev/null || true
echo "[ghint-x86] DONE -> $OUTLOG"
