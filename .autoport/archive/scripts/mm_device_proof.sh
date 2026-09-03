#!/usr/bin/env bash
# mm_device_proof.sh — Grecharged-materials-modern-parity, device proof on the Redmi.
#
# PROOF ECONOMY (owner standing order): prove only what would break SILENTLY, with the cheapest
# instrument that already exists. So this reuses .autoport/pbr_device_capture.sh's `run` stage
# verbatim for the warp+record and adds only the four checks this phase actually owes:
#   1. FRESHNESS  — the APK on the device is the one just built (flag marker + the new FFI symbol).
#   2. EXTERNAL   — surfaces.json is read from the EXTERNAL dir, not from the installed asset
#                   pack, because a tuning edit has to cost a kilobyte and not a 581 MB APK.
#                   (Gpbr-material-props: the file used to be recharged_assets/materials.txt
#                   shipped INSIDE the APK. The owner ruled that out — the properties now ride
#                   the asset release. So this leg also asserts the APK ships ZERO copy.)
#   3. ACTIVE     — the modern chunk really executed on device: per-channel draw counters, not a
#                   screenshot somebody has to squint at. No visual measurement (permanently banned).
#   4. OFF==STOCK — the same boot with the master off registers ZERO opted-in materials and ZERO
#                   active draws, i.e. the layer is not merely subtle, it is absent.
# Quality is the OWNER's call: the two clips exist so HE can look, not so this script can grade them.
#
# Stages:  all | deploy | on | off | harvest
set -uo pipefail
cd "$(git rev-parse --show-toplevel)"
ADB="${ADB:-$HOME/Android/platform-tools/adb}"
S="${S:-eae4df44}"; PKG=org.opengoal.gk.jak1
OUT=.autoport/reports/Grecharged-materials-modern-parity/device; mkdir -p "$OUT"
PROOF="$OUT/device_proof.txt"
EXT=/storage/emulated/0/OpenGOAL/jak1/assets/recharged_assets
CAP=.autoport/reports/Grecharged-pbr-materials/device
adbs(){ "$ADB" -s "$S" "$@"; }
say(){ echo "$*" | tee -a "$PROOF"; }
die(){ say "[mm-device FAIL] $*"; exit 1; }

# The owner's PBR vantage (registered in the pbr phase): the sage stone wall + straw roof.
# TOD 7 is a LOW sun — subsurface transmission is a BACK-LIT effect, so a noon sun would hide the
# one channel this phase is named for.
export PBR_POS="${PBR_POS--112.0 42.0 205.0}"
export PBR_TOD_HOUR="${PBR_TOD_HOUR:-7}"
export PBR_WALK_STYLE="${PBR_WALK_STYLE:-arc}"

stage_deploy() {
  APK=$(find android -name 'app-jak1-debug.apk' -printf '%T@ %p\n' | sort -rn | head -1 | cut -d' ' -f2-)
  [ -n "$APK" ] || die "no APK built"
  say "APK: $APK ($(stat -c%s "$APK") bytes, built $(date -d @"$(stat -c%Y "$APK")" +%F' '%T))"
  unzip -p "$APK" lib/arm64-v8a/libgk.so > /tmp/mm_apk_libgk.so || die "cannot read libgk from APK"
  MARK=$(strings /tmp/mm_apk_libgk.so | grep -m1 '^ogflags:' || true)
  say "APK libgk flag marker: $MARK"
  # FEATURE-STALE GUARD, at the artifact and not at the run: a marker can be identical across two
  # builds of the same flag set, so also require the SYMBOLS this phase adds. If either is missing
  # the APK predates this work no matter what the marker says.
  for sym in pc-set-modern-materials! u_mm_flags tex_PBR_TH surfaces.json; do
    n=$(strings /tmp/mm_apk_libgk.so | grep -cF "$sym" || true)
    [ "${n:-0}" -ge 1 ] || die "APK libgk lacks '$sym' — stale build"
    say "  APK libgk carries '$sym' (x$n)"
  done
  # the modern shader chunks must be inside the GLES blob compiled into libgk
  for chunk in u_mm_sss mm_ggx_d_aniso mm_tonemap_aces; do
    n=$(strings /tmp/mm_apk_libgk.so | grep -cF "$chunk" || true)
    [ "${n:-0}" -ge 1 ] || die "APK libgk GLES blob lacks '$chunk' — the companion chunks never reached the Android blob (file(GLOB) staleness)"
    say "  APK GLES blob carries '$chunk' (x$n)"
  done
  rm -f /tmp/mm_apk_libgk.so
  # the ORM demonstrator must be in the packaged custom pack
  unzip -p "$APK" assets/bundle/jak1_custom.zip > /tmp/mm_custom.zip 2>/dev/null || true
  if [ -s /tmp/mm_custom.zip ]; then
    n=$(unzip -l /tmp/mm_custom.zip | grep -c '_orm\.png' || true)
    say "  APK custom pack ships $n _orm.png file(s)"
    # INVERTED on purpose (Gpbr-material-props): the properties must NOT be in the app. A copy
    # here would be a second source of truth that wins or loses by loader tier order.
    n=$(unzip -l /tmp/mm_custom.zip | grep -cE 'recharged_assets/(materials\.txt|surfaces\.json)' || true)
    say "  APK custom pack ships a material-property file: $n (MUST be 0)"
    [ "${n:-0}" -eq 0 ] || die "the APK still carries a material-property file — owner 2026-08-29: they belong to the asset repo, not the APK"
  fi
  rm -f /tmp/mm_custom.zip

  adbs devices | grep -qE "^${S}[[:space:]]+device$" || die "device $S not connected"
  adbs shell input keyevent KEYCODE_WAKEUP >/dev/null 2>&1 || true
  if adbs shell dumpsys trust 2>/dev/null | grep -a '(current)' | grep -q 'deviceLocked=1'; then
    die "device PIN-LOCKED — wait for the owner"
  fi
  adbs shell am force-stop $PKG >/dev/null 2>&1 || true
  say "installing..."
  adbs install -r -d "$APK" >/dev/null 2>&1 || die "adb install failed"
  say "install ok"

  # EXTERNAL-OVERRIDE PROOF. JSON has no comments, so the marker is a VALUE nobody else could
  # produce: one material's relief is set to 7.777 and the device must PRINT 7.777 back on its
  # own [pbrmat] line. That is strictly stronger than the comment marker this used to push — a
  # comment proves a file was opened, a changed number proves it was parsed AND applied.
  adbs shell mkdir -p "$EXT" </dev/null
  SRC=$(adbs shell "run-as $PKG cat files/managed_assets/jak1/surfaces.json" </dev/null 2>/dev/null)
  [ -n "$SRC" ] || die "no installed surfaces.json on device — run the asset download first"
  printf '%s' "$SRC" | python3 -c "
import json,sys
d=json.load(sys.stdin)
k='village1-vis-tfrag/vil-beach-01'
d['materials'][k]['relief']=7.777
json.dump(d,sys.stdout,separators=(',',':'),sort_keys=True)" > /tmp/mm_surfaces.json || die "cannot mark surfaces.json"
  adbs push /tmp/mm_surfaces.json "$EXT/surfaces.json" >/dev/null || die "push surfaces.json failed"
  say "pushed surfaces.json -> $EXT (external override, vil-beach-01 relief=7.777)"
  # ===== RETRAIT GARANTI DU MARQUEUR (Gpbr-props-reach-draw, 2026-09-02) =========================
  # Ce fichier BAT la table installee (CustomTextureReplacements.cpp:1031-1038) et ce script ne le
  # retirait JAMAIS — ni `rm`, ni `trap`. Mesure : le Redmi a tourne du 2026-08-31 03:26 au
  # 2026-09-02 10:00 avec `vil-beach-01 relief = 7.777`, donc TOUTE course appareil de cette
  # fenetre a mesure une table trafiquee, y compris la premiere jambe de la phase
  # Gpbr-props-reach-draw (`PARAMSRC=external-override`).
  # Regle de l'owner : quand une perte se repete, on la rend impossible AU POINT DE PRODUCTION,
  # pas detectable au point de controle. Le retrait est donc arme ICI, au moment de la pose, et il
  # survit a une sortie par erreur ou par Ctrl-C.
  trap 'adbs shell "rm -f \"$EXT/surfaces.json\"" </dev/null >/dev/null 2>&1 || true' EXIT INT TERM
  # CONTROLES DE DEBUG EPINGLES SUR L'APPAREIL — c'est TOUTE la raison pour laquelle la
  # tentative 1 (2026-08-08) a publie `[cover] disp_pom=0 disp_none=22 coverage_pct=0.0`.
  # Le settings.ini VIVANT portait encore, le 2026-08-31 :
  #     pbr-displacement = 0   (defaut livre 1 = PARALLAX, pckernel-impl.gc:318)
  #     pbr-isolate      = 3   (defaut livre 0 = BOTH,     pckernel-impl.gc:321)
  # autrement dit la bisection DEBUG en menu forcait la carte de normales ET la parallaxe a
  # OFF. Une course prise dans cet etat mesure le MODE DEBUG, pas la fonctionnalite. On
  # RETABLIT LES DEFAUTS LIVRES (on ne regle rien) et on publie l'avant/apres pour audit.
  # Le correctif est pose au PRODUCTEUR de la course, pas en note de bas de page.
  SETTINGS_DEV=/storage/emulated/0/OpenGOAL/jak1/settings.ini
  adbs shell cat "$SETTINGS_DEV" </dev/null > /tmp/mm_settings.ini 2>/dev/null || die "no settings.ini on device"
  [ -s /tmp/mm_settings.ini ] || die "empty settings.ini on device"
  cp /tmp/mm_settings.ini "$OUT/settings-prerun.ini"
  say "  settings BEFORE: $(grep -aE '^(pbr-displacement|pbr-isolate|pbr-materials.|modern-materials.|load-custom-assets.|realtime-lighting.|recharged-master.) =' /tmp/mm_settings.ini | tr '\n' ' ')"
  sed -i 's/^pbr-displacement = .*/pbr-displacement = 1/' /tmp/mm_settings.ini
  sed -i 's/^pbr-isolate = .*/pbr-isolate = 0/' /tmp/mm_settings.ini
  adbs push /tmp/mm_settings.ini "$SETTINGS_DEV" >/dev/null || die "cannot push settings.ini"
  adbs shell cat "$SETTINGS_DEV" </dev/null > /tmp/mm_settings_after.ini 2>/dev/null || true
  say "  settings AFTER : $(grep -aE '^(pbr-displacement|pbr-isolate) =' /tmp/mm_settings_after.ini | tr '\n' ' ')"
  cp /tmp/mm_settings_after.ini "$OUT/settings-used.ini" 2>/dev/null || true
}

leg() {  # $1 = on|off
  local want="$1" tag="mm_$1"
  adbs shell "setprop debug.opengoal.mm.on '$([ "$want" = on ] && echo 1 || echo 0)'" </dev/null
  say "--- leg $want (debug.opengoal.mm.on=$([ "$want" = on ] && echo 1 || echo 0)) ---"
  bash .autoport/pbr_device_capture.sh run "$tag" 2>&1 | tee -a "$PROOF"
  [ -f "$CAP/pbr_$tag.mp4" ] || die "no clip for leg $want"
  cp "$CAP/pbr_$tag.mp4" "$OUT/$tag.mp4"
  cp "$CAP/logcat_$tag.log" "$OUT/logcat_$tag.log" 2>/dev/null || true
  say "clip: $OUT/$tag.mp4 ($(stat -c%s "$OUT/$tag.mp4") bytes)"
  # the pullable diag carries the per-channel ACTIVE-DRAW counters
  adbs shell "run-as $PKG cat files/pbr_tan_diag.txt" </dev/null > "$OUT/diag_$tag.txt" 2>/dev/null || true
  say "diag_$tag.txt: $(wc -l < "$OUT/diag_$tag.txt") lines"
}

stage_harvest() {
  say ""
  say "================ HARVEST ================"
  for tag in mm_on mm_off; do
    L="$OUT/logcat_$tag.log"; D="$OUT/diag_$tag.txt"
    say "--- $tag ---"
    [ -f "$L" ] && {
      grep -a '\[mm\] PARAMSRC' "$L" | tail -2 | sed 's/^/  /' | tee -a "$PROOF" >/dev/null
      grep -a '\[mm\] PARAMSRC' "$L" | tail -2 | sed 's/^/  /'
      grep -a '\[mm\] surfaces.json parsed' "$L" | tail -1 | sed 's/^/  /' | tee -a "$PROOF" >/dev/null
      grep -a '\[mm\] surfaces.json parsed' "$L" | tail -1 | sed 's/^/  /'
      say "  external-override marker (vil-beach-01 relief=7.777): $(grep -ca 'vil-beach-01 family=sand relief=7.777' "$L" || true)"
      grep -a '\[surfaces\]' "$L" | tail -1 | sed 's/^/  /'
      say "  ORM unpack lines: $(grep -ca 'pbr ORM unpack' "$L" || true)"
      grep -a 'pbr ORM unpack' "$L" | tail -1 | sed 's/^/  /'
      # CONTROLE PAR ABSENCE — CORRIGE 2026-08-31 (Grecharged-materials-modern-parity).
      # L'ancienne ligne comptait  grep -cav 'mm_flags=0x0 '  sur TOUTES les lignes
      # 'pbr binding'. Or 2090 d'entre elles sont des 'maps=NONE (same-source pairing
      # / no maps)' qui ne portent AUCUN champ mm_flags= : elles passaient le grep
      # INVERSE quoi qu'il arrive et etaient comptees comme '!=0'. La jambe OFF du
      # 2026-08-08 publiait donc 2090 alors que ses 8 materiaux etaient TOUS a 0x0 —
      # un faux rouge, qui coute autant qu'un faux vert. On compare desormais a la
      # CLE (mm_flags=) en entier, et on publie les TROIS nombres pour que le lecteur
      # puisse refaire le compte.
      _bind_all=$(grep -ac 'pbr binding' "$L" || true)
      _bind_flagged=$(grep -a 'pbr binding' "$L" | grep -ac 'mm_flags=' || true)
      _bind_zero=$(grep -a 'pbr binding' "$L" | grep -ac 'mm_flags=0x0' || true)
      _bind_nonzero=$(( _bind_flagged - _bind_zero ))
      say "  pbr binding: total=$_bind_all carrying-mm_flags=$_bind_flagged  of-those mm_flags=0x0 -> $_bind_zero  mm_flags!=0 -> $_bind_nonzero"
      grep -a 'pbr binding' "$L" | grep -a 'mm_flags=' | grep -av 'mm_flags=0x0' | tail -4 | sed 's/^/  /'
      say "  crash signals: $(grep -caE 'signal (4|6|7|11) \(SIG' "$L" || true)"
      # SAMPLER BUDGET. The world fragment stage now declares 15 samplers against a GLES floor of
      # 16, so the failure this phase could plausibly introduce is a LINK failure, not a wrong
      # pixel — and a failed link is a black screen, which a clip would show but a counter would
      # not. Must be 0.
      # FAUX POSITIF CORRIGE 2026-08-31. L'ancien motif etait
      #     grep -caiE 'shader (compile|link)|ERROR: .*sampler|too many'
      # et il matchait la BANNIERE DU PILOTE, identique dans les deux jambes :
      #     I AdrenoGLES-0: OpenGL ES Shader Compiler Version: EV031.32.02.16
      # ('Shader Compiler' matche 'shader (compile|link)' en -i). Le compte valait donc 1
      # QUOI QU'IL ARRIVE, et le garde-fou « budget de samplers » qu'il pretendait surveiller
      # n'a jamais ete exerce une seule fois. On compte desormais des ECHECS, et on publie a
      # cote la contre-preuve positive que le pilote imprime lui-meme.
      say "  shader compile/link FAILURES: $(grep -acE 'Failed to compile|Failed to link|FAILED to compile|FAILED to LINK|shaders FAILED|GL_INVALID_OPERATION|ERROR: .*sampler|too many .*sampler' "$L" || true)"
      grep -aE 'Failed to compile|Failed to link|FAILED to compile|FAILED to LINK|shaders FAILED|too many .*sampler' "$L" | head -3 | sed 's/^/    /'
      say "  shader positive control: $(grep -a 'shaders compiled under GLES' "$L" | tail -1 | sed 's/^.*opengoal-gk: //')"
      grep -a 'tfrag3_tess. program LINKED' "$L" | tail -1 | sed 's/^/    /'
      grep -a 'MM-MENU' "$L" | tail -1 | sed 's/^/  /'
      # TROISIEME MECANISME QUI PEUT DESARMER LA PARALLAXE, ET IL EST A NOUS.
      # kmachine.cpp:434 `recharged_crash_loop_guard_boot()` compte les demarrages qui
      # MEURENT AVANT 60 s ; a 2, il REECRIT settings.ini (`pbr-displacement -> 0`) et
      # CLAMPE la valeur pour la session (kmachine.cpp:3114), quoi que GOAL pousse. Une
      # campagne de captures courtes arme donc elle-meme la garde qui desarme le canal
      # qu'elle mesure. On publie la ligne : « healthy boot, sentinel cleared » = la course
      # a dure plus de 60 s et la garde s'est desarmee ; « settings reset » = CETTE JAMBE
      # NE PEUT RIEN DIRE de la parallaxe.
      say "  crash-loop guard: $(grep -a 'crash-loop guard' "$L" | tail -1 | sed 's/^.*opengoal-gk: //' || echo 'ABSENTE (ni sentinelle posee ni effacee)')"
    }
    # GARDE CONTRE UN CONTROLE EPINGLE + PREUVE DE DEPLACEMENT. Une course dont le carrousel
    # DISPLACEMENT est sur Off, ou dont PBR-ISOLATE n'est pas BOTH, ne peut RIEN dire de la
    # parallaxe : elle mesure le mode debug. On publie les deux gates A COTE du taux de
    # couverture, pour qu'un 0,0 % ne puisse plus jamais se lire « le POM ne marche pas ».
    if [ -s "$D" ]; then
      _disp=$(grep -ao 'displacement=[0-9]*' "$D" | head -1 | cut -d= -f2)
      _bis=$(grep -ao 'bisect=[0-9]*' "$D" | head -1 | cut -d= -f2)
      if [ "${_disp:-9}" != "0" ] && [ "${_bis:-9}" = "0" ]; then
        say "  pinned-control guard: OK (displacement=${_disp:-?} bisect=${_bis:-?}) — parallax is answerable"
      else
        say "  pinned-control guard: FAIL (displacement=${_disp:-?} bisect=${_bis:-?}) — need displacement!=0 AND bisect=0; this leg CANNOT judge parallax/POM"
      fi
      grep -a '^\[cover\] frame=' "$D" | tail -1 | sed 's/^/  DISPLACEMENT COVERAGE: /' | tee -a "$PROOF"
      grep -a '^\[cover\] renderer=' "$D" | sed 's/^/  /' | tee -a "$PROOF"
    fi
    [ -s "$D" ] && grep -a '^\[mm\]' "$D" | tail -12 | sed 's/^/  /' | tee -a "$PROOF" >/dev/null
    [ -s "$D" ] && grep -a '^\[mm\]' "$D" | tail -12 | sed 's/^/  /'
  done
  # LECTURE ARRIERE DU FICHIER REELLEMENT UTILISE. On a pousse les defauts livres AVANT la
  # course ; si quoi que ce soit les a reecrits PENDANT (garde anti-boucle, menu, GOAL), le
  # verdict de parallaxe porterait sur une valeur qu'on n'a pas mesuree. On republie donc les
  # deux cles telles qu'elles sont A LA FIN, a cote de ce qu'on avait pousse.
  SETTINGS_DEV=/storage/emulated/0/OpenGOAL/jak1/settings.ini
  adbs shell cat "$SETTINGS_DEV" </dev/null > "$OUT/settings-postrun.ini" 2>/dev/null || true
  if [ -s "$OUT/settings-postrun.ini" ]; then
    say "  settings PUSHED  : $(grep -aE '^(pbr-displacement|pbr-isolate) =' "$OUT/settings-used.ini" 2>/dev/null | tr '\n' ' ')"
    say "  settings POSTRUN : $(grep -aE '^(pbr-displacement|pbr-isolate) =' "$OUT/settings-postrun.ini" | tr '\n' ' ')"
  fi
  say "========================================="
}

case "${1:-all}" in
  deploy) stage_deploy;;
  on) leg on;;
  off) leg off;;
  harvest) stage_harvest;;
  all)
    : > "$PROOF"
    say "=== Grecharged-materials-modern-parity device proof $(date -Is) ==="
    say "HEAD: $(git rev-parse --short HEAD)  vantage: $PBR_POS  tod_hour: $PBR_TOD_HOUR"
    stage_deploy; leg on; leg off; stage_harvest
    # never leave the TOD pinned — the owner reads a pinned clock as a broken day/night cycle
    adbs shell "setprop debug.opengoal.tod.hour ''" </dev/null || true
    adbs shell "setprop debug.opengoal.mm.on ''" </dev/null || true
    adbs shell am force-stop $PKG >/dev/null 2>&1 || true
    say "props cleared, app stopped."
    ;;
  *) echo "usage: $0 [all|deploy|on|off|harvest]"; exit 2;;
esac
