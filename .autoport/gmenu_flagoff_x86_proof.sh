#!/bin/bash
# Gmenu-flag-off: x86 OFF-build binding proof (owner rule: state dumps, no visuals).
# Proves, on the RESTORED pre-overhaul menu (FLAG_MENU_OVERHAUL off):
#   1. the *recharged-options-pc* row table is FULL (24 rows, hd-models+pbr) and every
#      direct-bound row's value-to-modify points at the RIGHT *pc-settings* field (address
#      equality), uniquely (no two rows share a field); carousell rows all point at the
#      shared *progress-carousell* int-backup scratch BY DESIGN (type ids disambiguate).
#   2. the DISPLACEMENT carousell row (type pbr-displacement) really drives the runtime
#      value: driven through the REAL respond-common path via the menu-touch synthetic
#      token queue (CONFIRM/RIGHT/CONFIRM), (-> *pc-settings* pbr-displacement) changes.
#   3. HD (ENHANCED MODELS) and PBR MATERIALS rows are togglable the same way.
# Template: .autoport/rhud2_x86_verify2.sh (proven boot/listener recipe).
set -u
cd "$(git rev-parse --show-toplevel)"
R=.autoport/reports/Gmenu-flag-off
OUT=/tmp/gmenu_flagoff
mkdir -p "$R" "$OUT"
LOG="$R/x86_binding_proof.log"
: > "$LOG"
say(){ echo "$*" | tee -a "$LOG"; }

# ---- 0. fresh canonical x86 OFF build (hd-models+pbr, NO --menu-overhaul) ----
if [ "${SKIP_BUILD:-0}" != 1 ]; then
  ./build.sh linux-x86_64 --hd-models --pbr > "$OUT/build.log" 2>&1 \
    || { say "RESULT: FAIL (x86 build.sh failed)"; tail -20 "$OUT/build.log" | tee -a "$LOG"; exit 1; }
fi
grep -q "FLAG_MENU_OVERHAUL #f" goal_src/jak1/pc/recharged-flags.gc \
  || { say "RESULT: FAIL (generated flags file does not have FLAG_MENU_OVERHAUL #f)"; exit 1; }
MARK=$(strings build/game/gk | grep -m1 '^ogflags:' || true)
say "BUILD gk marker: $MARK (expect ogflags:009eadd8b50c:linux-x86_64 = hd-models,pbr, overhaul OFF)"
[ "$MARK" = "ogflags:009eadd8b50c:linux-x86_64" ] || { say "RESULT: FAIL (marker mismatch)"; exit 1; }
[ -f out/jak1/fr3/enhanced/GAME.fr3 ] || { say "RESULT: FAIL (no enhanced/GAME.fr3 -> table would collapse)"; exit 1; }

pkill -f 'build/game/gk' 2>/dev/null; sleep 2
pkill -f 'goalc --user-auto' 2>/dev/null; sleep 2

# ---- 1. boot gk (proven combo: -boot -debug-mem, XWayland, stdbuf) ----
DISPLAY=:0 XAUTHORITY=/run/user/1000/.mutter-Xwaylandauth.RKSTQ3 \
LANG=en_US.UTF-8 LC_ALL=en_US.UTF-8 \
stdbuf -oL -eL ./build/game/gk --game jak1 --portable -fakeiso --verbose --disable-ansi \
  -iso-data out/jak1/iso -- -boot -debug-mem > "$OUT/gk.log" 2>&1 &
GK_PID=$!
say "gk pid $GK_PID"
deadline=$(( $(date +%s) + 150 ))
while [ "$(date +%s)" -lt "$deadline" ]; do
  kill -0 "$GK_PID" 2>/dev/null || { say "RESULT: FAIL (gk exited early)"; tail -20 "$OUT/gk.log" | tee -a "$LOG"; exit 1; }
  grep -qa "machine started" "$OUT/gk.log" && break
  sleep 2
done
grep -qa "machine started" "$OUT/gk.log" || { say "RESULT: FAIL (never booted)"; exit 1; }
say "machine started; settling 25s toward title"
sleep 25

# ---- 2. listener ----
rm -f "$OUT/fifo"; mkfifo "$OUT/fifo"
./build/goalc/goalc --user-auto < "$OUT/fifo" > "$OUT/goalc.log" 2>&1 &
GOALC_PID=$!
exec 3>"$OUT/fifo"
snd(){ echo "$1" >&3; sleep "${2:-2}"; }
finish(){ kill -INT "$GK_PID" 2>/dev/null; sleep 2; kill "$GK_PID" "$GOALC_PID" 2>/dev/null; exec 3>&- 2>/dev/null; }
trap finish EXIT
sleep 4
CONNECTED=0
for i in 1 2 3 4 5 6 7 8; do
  snd '(lt)' 4
  grep -qa "Socket connected established" "$OUT/goalc.log" && { CONNECTED=1; break; }
done
[ "$CONNECTED" = 1 ] || { say "RESULT: FAIL (listener never connected)"; exit 1; }
snd '(build-game)' 45
# cold goalc recompiles the whole game here (~500 files, several minutes) — give it a
# real deadline; 105s killed it at 81% on 2026-08-05 (root cause of the empty-log attempts)
BG_DEADLINE=$(( $(date +%s) + 900 ))
while [ "$(date +%s)" -lt "$BG_DEADLINE" ]; do
  grep -qa "Successfully built all" "$OUT/goalc.log" && break
  sleep 10
done
grep -qa "Successfully built all" "$OUT/goalc.log" || { say "RESULT: FAIL (build-game did not finish)"; exit 1; }
snd '(format 0 "MFPROBE-ALIVE~%")' 2
GLOG=""
grep -qa "MFPROBE-ALIVE" "$OUT/gk.log" && GLOG="$OUT/gk.log"
[ -z "$GLOG" ] && grep -qa "MFPROBE-ALIVE" "$OUT/goalc.log" && GLOG="$OUT/goalc.log"
[ -n "$GLOG" ] || { say "RESULT: FAIL (format routing dead)"; exit 1; }
say "listener alive; GOAL prints route to $GLOG"

# ---- 3. open the progress menu via REAL START input, then steer to recharged-settings ----
# activate-progress from the listener thread does NOT work (proven: gmenu_pos_x86_dump.sh —
# it segfaults/no-ops; the title handler must run it in kernel context off a real START).
# The old menu also wires value-to-modify at progress activation, so a live process is
# REQUIRED before the binding dump means anything (all-zero vtm = menu never opened).
PYV="$HOME/.venv/autoport/bin/python"; [ -x "$PYV" ] || PYV=python3
for k in 1 2 3 4; do
  "$PYV" .autoport/xfocus_tap.py 28 > "$OUT/xfocus.log" 2>&1 || say "xfocus_tap warn (try $k)"
  sleep 5
  snd '(if *progress-process* (format 0 "PP-LIVE~%") (format 0 "PP-NIL~%"))' 2
  grep -qa "PP-LIVE" "$GLOG" && break
done
grep -qa "PP-LIVE" "$GLOG" || { say "RESULT: FAIL (progress menu never opened via START)"; exit 1; }
snd '(if *progress-process* (set! (-> *progress-process* 0 next-display-state) (progress-screen recharged-settings)))' 4
snd '(if *progress-process* (set! (-> *progress-process* 0 next-display-state) (progress-screen recharged-settings)))' 4
snd '(if *progress-process* (format 0 "MSCREEN ~D want ~D~%" (the-as int (-> *progress-process* 0 display-state)) (the-as int (progress-screen recharged-settings))) (format 0 "MSCREEN-NOPP~%"))' 2

# ---- 4. binding-table dump (GOAL calls max 8 params -> <=6 format args per line) ----
snd '(format 0 "MTYPES1 on-off ~D slider ~D menu ~D button ~D disp ~D preset ~D~%" (the-as int (game-option-type on-off)) (the-as int (game-option-type slider)) (the-as int (game-option-type menu)) (the-as int (game-option-type button)) (the-as int (game-option-type pbr-displacement)) (the-as int (game-option-type pbr-test-preset)))' 2
snd '(format 0 "MTYPES2 isolate ~D ao ~D aoq ~D aos ~D probe ~D ambm ~D~%" (the-as int (game-option-type pbr-isolate)) (the-as int (game-option-type ambient-occlusion)) (the-as int (game-option-type ao-quality)) (the-as int (game-option-type ao-strength)) (the-as int (game-option-type follow-probe)) (the-as int (game-option-type rt-ambient-model)))' 2
snd '(format 0 "MTYPES3 shq ~D~%" (the-as int (game-option-type shadow-quality)))' 2
snd '(format 0 "MLEN recharged ~D graphic-pc ~D graphic-android ~D grass ~D~%" (-> *recharged-options-pc* length) (-> *graphic-options-pc* length) (-> *graphic-options-pc-android* length) (-> *grass-options-pc* length))' 2
snd '(dotimes (i (-> *recharged-options-pc* length)) (format 0 "MROW ~D type ~D vtm #x~X ovr ~A~%" i (the-as int (-> *recharged-options-pc* i option-type)) (the-as int (-> *recharged-options-pc* i value-to-modify)) (-> *recharged-options-pc* i name-override)))' 4
snd '(format 0 "MREF master #x~X~%" (the-as int (&-> *pc-settings* recharged-master?)))' 1
snd '(format 0 "MREF load-custom #x~X~%" (the-as int (&-> *pc-settings* load-custom-assets?)))' 1
snd '(format 0 "MREF textures #x~X~%" (the-as int (&-> *pc-settings* recharged-textures?)))' 1
snd '(format 0 "MREF materials #x~X~%" (the-as int (&-> *pc-settings* pbr-materials?)))' 1
snd '(format 0 "MREF enhanced #x~X~%" (the-as int (&-> *pc-settings* recharged-enhanced-models?)))' 1
snd '(format 0 "MREF foliage #x~X~%" (the-as int (&-> *pc-settings* recharged-foliage-wind?)))' 1
snd '(format 0 "MREF rtlight #x~X~%" (the-as int (&-> *pc-settings* realtime-lighting?)))' 1
snd '(format 0 "MREF amb-strength #x~X~%" (the-as int (&-> *pc-settings* realtime-ambient-strength)))' 1
snd '(format 0 "MREF amb-contrast #x~X~%" (the-as int (&-> *pc-settings* realtime-ambient-contrast)))' 1
snd '(format 0 "MREF shadow-dist #x~X~%" (the-as int (&-> *pc-settings* realtime-shadow-dist)))' 1
snd '(format 0 "MREF relief #x~X~%" (the-as int (&-> *pc-settings* pbr-texture-relief)))' 1
snd '(format 0 "MREF specular #x~X~%" (the-as int (&-> *pc-settings* pbr-specular-intensity)))' 1
snd '(format 0 "MREF int-backup #x~X~%" (the-as int (&-> *progress-carousell* int-backup)))' 1
snd '(format 0 "MREF grass-on #x~X near #x~X card #x~X dens #x~X pre #x~X~%" (the-as int (&-> *pc-settings* recharged-grass?)) (the-as int (&-> *pc-settings* recharged-grass-near-dist)) (the-as int (&-> *pc-settings* recharged-grass-card-dist)) (the-as int (&-> *pc-settings* recharged-grass-density)) (the-as int (&-> *pc-settings* recharged-grass-precomputed?)))' 1
snd '(dotimes (i (-> *grass-options-pc* length)) (format 0 "GROW ~D type ~D vtm #x~X ovr ~A~%" i (the-as int (-> *grass-options-pc* i option-type)) (the-as int (-> *grass-options-pc* i value-to-modify)) (-> *grass-options-pc* i name-override)))' 3

# ---- 5. runtime toggles through the REAL respond-common path (token queue) ----
# preconditions: displacement row needs master? + materials? on (option-disabled-func)
snd '(format 0 "MPRE master ~A materials ~A hd ~A disp ~D~%" (-> *pc-settings* recharged-master?) (-> *pc-settings* pbr-materials?) (-> *pc-settings* recharged-enhanced-models?) (-> *pc-settings* pbr-displacement))' 2
snd '(if (not (-> *pc-settings* recharged-master?)) (begin (set! (-> *pc-settings* recharged-master?) #t) (format 0 "MPRE-FORCED-MASTER~%")))' 2
snd '(if (not (-> *pc-settings* pbr-materials?)) (begin (set! (-> *pc-settings* pbr-materials?) #t) (format 0 "MPRE-FORCED-MATERIALS~%")))' 2
# DISPLACEMENT: row 19, real carousell drive CONFIRM,RIGHT,CONFIRM
snd '(begin (set! (-> *progress-process* 0 option-index) 19) (set! (-> *menu-touch* seq-len) 0) (set! (-> *menu-touch* seq-pos) 0) (menu-touch-push-seq! 1) (menu-touch-push-seq! 3) (menu-touch-push-seq! 1) (set! (-> *menu-touch* seq-screen) (-> *progress-process* 0 display-state)))' 4
snd '(format 0 "DISP-A1 ~D~%" (-> *pc-settings* pbr-displacement))' 2
# and back LEFT
snd '(begin (set! (-> *menu-touch* seq-len) 0) (set! (-> *menu-touch* seq-pos) 0) (menu-touch-push-seq! 1) (menu-touch-push-seq! 2) (menu-touch-push-seq! 1) (set! (-> *menu-touch* seq-screen) (-> *progress-process* 0 display-state)))' 4
snd '(format 0 "DISP-A2 ~D~%" (-> *pc-settings* pbr-displacement))' 2
# HD ENHANCED MODELS: row 5, on-off — RIGHT = OFF, LEFT = ON
snd '(begin (set! (-> *progress-process* 0 option-index) 5) (set! (-> *menu-touch* seq-len) 0) (set! (-> *menu-touch* seq-pos) 0) (menu-touch-push-seq! 1) (menu-touch-push-seq! 3) (menu-touch-push-seq! 1) (set! (-> *menu-touch* seq-screen) (-> *progress-process* 0 display-state)))' 4
snd '(format 0 "HD-A1 ~A~%" (-> *pc-settings* recharged-enhanced-models?))' 2
snd '(begin (set! (-> *menu-touch* seq-len) 0) (set! (-> *menu-touch* seq-pos) 0) (menu-touch-push-seq! 1) (menu-touch-push-seq! 2) (menu-touch-push-seq! 1) (set! (-> *menu-touch* seq-screen) (-> *progress-process* 0 display-state)))' 4
snd '(format 0 "HD-A2 ~A~%" (-> *pc-settings* recharged-enhanced-models?))' 2
# PBR MATERIALS: row 4, on-off double flip
snd '(begin (set! (-> *progress-process* 0 option-index) 4) (set! (-> *menu-touch* seq-len) 0) (set! (-> *menu-touch* seq-pos) 0) (menu-touch-push-seq! 1) (menu-touch-push-seq! 3) (menu-touch-push-seq! 1) (set! (-> *menu-touch* seq-screen) (-> *progress-process* 0 display-state)))' 4
snd '(format 0 "PBR-A1 ~A~%" (-> *pc-settings* pbr-materials?))' 2
snd '(begin (set! (-> *menu-touch* seq-len) 0) (set! (-> *menu-touch* seq-pos) 0) (menu-touch-push-seq! 1) (menu-touch-push-seq! 2) (menu-touch-push-seq! 1) (set! (-> *menu-touch* seq-screen) (-> *progress-process* 0 display-state)))' 4
snd '(format 0 "PBR-A2 ~A~%" (-> *pc-settings* pbr-materials?))' 2
sleep 2

# ---- 6. harvest + assert ----
grep -a "MSCREEN\|MTYPES\|MLEN\|MROW\|MREF\|GROW\|MPRE\|DISP-A\|HD-A\|PBR-A\|PP-LIVE\|PP-NIL" "$GLOG" >> "$LOG" || true
finish
trap - EXIT

python3 - "$LOG" <<'PYEOF'
import sys, re
log = open(sys.argv[1]).read()
fails = []
def need(pat, msg):
    m = re.search(pat, log, re.M)
    if not m: fails.append(msg)
    return m
# screen reached
m = need(r'^MSCREEN (\d+) want (\d+)', 'no MSCREEN line')
if m and m.group(1) != m.group(2): fails.append('recharged-settings screen not reached')
# types + refs (MTYPES split across 3 lines: GOAL max 8 params per call)
types = {}
tls = re.findall(r'^MTYPES\d (.*)$', log, re.M)
if not tls: fails.append('no MTYPES')
for tl in tls:
    t = tl.split()
    types.update(dict(zip(t[0::2], [int(x) for x in t[1::2]])))
refs = dict(re.findall(r'^MREF (\S+) #x([0-9a-fA-F]+)', log, re.M))
refs = {k: int(v,16) for k,v in refs.items()}
mlen = need(r'^MLEN recharged (\d+) graphic-pc (\d+) graphic-android (\d+) grass (\d+)', 'no MLEN')
if mlen and int(mlen.group(1)) != 24: fails.append(f'recharged length {mlen.group(1)} != 24 (full hd+pbr table)')
rows = {}
for mm in re.finditer(r'^MROW (\d+) type (\d+) vtm #x([0-9a-fA-F]+) ovr (.*)$', log, re.M):
    rows[int(mm.group(1))] = (int(mm.group(2)), int(mm.group(3),16), mm.group(4).strip())
if len(rows) < 24: fails.append(f'only {len(rows)} MROW lines')
# expected direct bindings idx -> ref key
direct = {0:'master',2:'load-custom',3:'textures',4:'materials',5:'enhanced',6:'foliage',
          10:'rtlight',13:'amb-strength',14:'amb-contrast',15:'shadow-dist',17:'relief',18:'specular'}
for idx,key in direct.items():
    if idx in rows and key in refs:
        if rows[idx][1] != refs[key]: fails.append(f'row {idx} vtm {rows[idx][1]:#x} != {key} {refs[key]:#x}')
    else: fails.append(f'missing row {idx} or ref {key}')
# uniqueness among direct-bound rows
seen = {}
for idx in direct:
    if idx in rows:
        a = rows[idx][1]
        if a in seen: fails.append(f'DUPLICATE binding: rows {seen[a]} and {idx} share {a:#x}')
        seen[a] = idx
# carousell rows all -> int-backup
if 'int-backup' in refs:
    for idx in (7,8,9,11,12,16,19,20,21):
        if idx in rows and rows[idx][1] != refs['int-backup']:
            fails.append(f'carousell row {idx} vtm != int-backup')
# displacement row type
if types and 19 in rows and rows[19][0] != types.get('disp',-1): fails.append('row 19 type != pbr-displacement')
if types and 20 in rows and rows[20][0] != types.get('preset',-1): fails.append('row 20 type != pbr-test-preset')
if types and 21 in rows and rows[21][0] != types.get('isolate',-1): fails.append('row 21 type != pbr-isolate')
# runtime toggles
mpre = need(r'^MPRE master (\S+) materials (\S+) hd (\S+) disp (\d+)', 'no MPRE')
d1 = need(r'^DISP-A1 (\d+)', 'no DISP-A1'); d2 = need(r'^DISP-A2 (\d+)', 'no DISP-A2')
if mpre and d1 and int(d1.group(1)) == int(mpre.group(4)):
    fails.append('displacement did not change after CONFIRM/RIGHT/CONFIRM')
if d1 and d2 and int(d2.group(1)) == int(d1.group(1)):
    fails.append('displacement did not change back after CONFIRM/LEFT/CONFIRM')
h1 = need(r'^HD-A1 (\S+)', 'no HD-A1'); h2 = need(r'^HD-A2 (\S+)', 'no HD-A2')
if h1 and h1.group(1) != '#f': fails.append(f'HD after RIGHT should be #f, got {h1.group(1)}')
if h2 and h2.group(1) != '#t': fails.append(f'HD after LEFT should be #t, got {h2.group(1)}')
p1 = need(r'^PBR-A1 (\S+)', 'no PBR-A1'); p2 = need(r'^PBR-A2 (\S+)', 'no PBR-A2')
if p1 and p1.group(1) != '#f': fails.append(f'PBR after RIGHT should be #f, got {p1.group(1)}')
if p2 and p2.group(1) != '#t': fails.append(f'PBR after LEFT should be #t, got {p2.group(1)}')
out = open(sys.argv[1], 'a')
if fails:
    for f in fails: print('ASSERT-FAIL:', f); out.write('ASSERT-FAIL: %s\n' % f)
    out.write('RESULT: FAIL\n'); print('RESULT: FAIL'); sys.exit(1)
out.write('BINDING-AUDIT: all direct rows bind the right pc-settings field, unique; carousells on int-backup; row19=pbr-displacement\n')
out.write('RESULT: PASS\n'); print('RESULT: PASS')
PYEOF
RC=$?
say "proof exit $RC (log: $LOG)"
exit $RC
