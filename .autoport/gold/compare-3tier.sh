#!/usr/bin/env bash
# compare-3tier.sh — the 3-tier comparison harness for the OpenGOAL Android port.
#
# WHY THIS EXISTS
# ---------------
# We modified the compiler (goalc) to add an arm64 backend. Our *own* x86 build
# is therefore NOT a trustworthy reference: a bug our compiler mods introduced
# into x86 codegen would live in BOTH our x86 and our Android output, invisible
# to a 2-way "our-x86 vs our-Android" diff. So we keep a PRISTINE gold standard
# built from the unmodified upstream merge-base (704972dd6) and compare in three
# tiers:
#
#   Original (pristine upstream x86)  --TierA-->  Our x86  --TierB-->  Our Android
#
#   * Tier A (gold vs our-x86): catches bugs our goalc mods leaked into x86 (the
#     insidious ones). goal_src is byte-identical across the fork, so a Tier-A
#     CGO byte-difference is a PURE compiler signal. "Identical" PROVES our 46
#     goalc commits are arm64-gated.
#   * Tier B (our-x86 vs our-arm64): the legitimate arm64 porting surface.
#     arm64 code is wider than x86, so Tier-B objects are EXPECTED to diverge;
#     this tier is for tracking/inspecting that divergence, not gating on it.
#
# PATHS
#   gold (pristine):  .autoport/gold/cgo/<OBJ.CGO>   .autoport/gold/dgo/<OBJ.DGO>
#   our x86:          out/jak1/iso/<OBJ>
#   our arm64:        out/jak1-arm64/iso/<OBJ>
#
# USAGE
#   compare-3tier.sh <OBJECT>            # one object, e.g. KERNEL.CGO / TIT.DGO
#   compare-3tier.sh --all               # every CGO + DGO present in gold
#   compare-3tier.sh --cgo               # the 3 code CGOs only (KERNEL/ENGINE/GAME)
#   compare-3tier.sh --boot GOLD OTHER   # compare two boot-sequence logs by the
#                                        # canonical state-marker chain (Tier A if
#                                        # OTHER is our-x86 log, Tier B if android
#                                        # logcat). Reports markers MISSING in OTHER.
#   compare-3tier.sh --help
#
# EXIT STATUS
#   0  comparison ran (divergences are reported, not failed — this is a measuring
#      stick, not a gate). Non-zero only on usage/path errors.
#
# Later chronological-fix phases invoke this to turn "Android looks wrong" into a
# precise diff against the pristine ground truth.

set -uo pipefail
cd "$(git rev-parse --show-toplevel 2>/dev/null || echo .)"

GOLD_CGO=".autoport/gold/cgo"
GOLD_DGO=".autoport/gold/dgo"
OUR_X86="out/jak1/iso"
OUR_ARM64="out/jak1-arm64/iso"
STRUCT="$(git rev-parse --show-toplevel 2>/dev/null)/.autoport/lib/cgo_structure_check.py"

c_red=$'\033[31m'; c_grn=$'\033[32m'; c_yel=$'\033[33m'; c_dim=$'\033[2m'; c_off=$'\033[0m'
# Honor --disable-ansi-style plain output when not a tty.
[ -t 1 ] || { c_red=; c_grn=; c_yel=; c_dim=; c_off=; }

usage() { sed -n '2,46p' "$0" | sed 's/^# \{0,1\}//'; }

gold_path() {
  local obj="$1"
  if   [ -f "$GOLD_CGO/$obj" ]; then echo "$GOLD_CGO/$obj"
  elif [ -f "$GOLD_DGO/$obj" ]; then echo "$GOLD_DGO/$obj"
  elif [ -f ".autoport/gold/$obj" ]; then echo ".autoport/gold/$obj"
  else echo ""; fi
}

# Byte-compare two files. Echoes a one-line verdict.
#   $1 tier label   $2 left file   $3 right file
cmp_pair() {
  local label="$1" a="$2" b="$3"
  if [ ! -f "$a" ]; then echo "    $label: ${c_yel}n/a${c_off} (missing $a)"; return; fi
  if [ ! -f "$b" ]; then echo "    $label: ${c_yel}n/a${c_off} (missing $b)"; return; fi
  local sa sb; sa=$(stat -c %s "$a"); sb=$(stat -c %s "$b")
  if cmp -s "$a" "$b"; then
    echo "    $label: ${c_grn}IDENTICAL${c_off}  (${sa} bytes)"
  else
    local off; off=$(LC_ALL=C cmp "$a" "$b" 2>/dev/null | grep -oE '(char|byte) [0-9]+' | grep -oE '[0-9]+' | head -1)
    echo "    $label: ${c_red}DIVERGENT${c_off}  first-diff byte=${off:-?}  sizes ${sa} vs ${sb} (Δ$((sb - sa)))"
  fi
}

compare_object() {
  local obj="$1"
  local g; g=$(gold_path "$obj")
  echo "${c_dim}== $obj ==${c_off}"
  if [ -z "$g" ]; then
    echo "    ${c_yel}no gold copy${c_off} for $obj under .autoport/gold/{cgo,dgo}/"
  else
    cmp_pair "Tier-A gold  vs our-x86  " "$g" "$OUR_X86/$obj"
  fi
  cmp_pair "Tier-B x86   vs our-arm64 " "$OUR_X86/$obj" "$OUR_ARM64/$obj"
}

# Optional structural snapshot for CGOs (object/function counts, ret-opcode
# density) per tier, using the existing v3 object parser. Best-effort: gold,
# x86 and arm64 share a basename, so each is parsed into its own json to avoid
# key collisions.
struct_one() {  # $1 tier-label  $2 file
  local label="$1" f="$2"
  [ -f "$f" ] || { echo "    ${label}: (missing)"; return; }
  local tmp; tmp=$(mktemp)
  if python3 "$STRUCT" "$tmp" "$f" >/dev/null 2>&1; then
    python3 - "$tmp" "$label" <<'PY' 2>/dev/null || echo "    ${label}: (parse failed)"
import json,sys
d=json.load(open(sys.argv[1])); label=sys.argv[2]
for _,v in d.items():
    print(f"    {label:18s} objs={v.get('object_count','?'):>4} fns={v.get('function_count','?'):>5} "
          f"bytes={v.get('total_bytes','?'):>9} arm64_ret={v.get('arm64_ret_count','?'):>6} "
          f"x86_ret={v.get('x86_ret_count','?'):>7}")
PY
  else
    echo "    ${label}: (parse failed)"
  fi
  rm -f "$tmp"
}

struct_dump() {
  local obj="$1"
  [ -f "$STRUCT" ] || return 0
  case "$obj" in *.CGO) ;; *) return 0;; esac
  local g; g=$(gold_path "$obj")
  echo "    ${c_dim}-- structural metrics per tier --${c_off}"
  [ -n "$g" ] && struct_one "gold  ($obj)" "$g"
  struct_one "our-x86  ($obj)" "$OUR_X86/$obj"
  struct_one "our-arm64($obj)" "$OUR_ARM64/$obj"
}

# ---- boot-sequence comparison ------------------------------------------------
# The canonical jak1 boot->title->cinematic state chain (source ground truth,
# goal_src/jak1). Each entry: "regex|human label". Order is chronological.
boot_markers() {
  cat <<'EOF'
link finish: logo|engine link milestone (link finish: logo)
has been called|(play ...) entry
title-start|continue-point title-start
target-title\b|STATE target-title (title control)
ndi-intro|ND logo spool-anim (ndi-intro)
logo-intro|Jak&Daxter title-logo flythrough (logo-intro)
target-title-play|STATE target-title-play (attract)
target-title-wait|STATE target-title-wait (press-start attract)
press.?start|press-start text
activate-progress|title menu opened (activate-progress)
intro-start|continue-point intro-start (New Game)
set-master-mode|set-master-mode transition
start-sequence-a|start-sequence-a (village1 intro)
sequenceA-village1|village1 Geyser-Rock cinematic
EOF
}

compare_boot() {
  local gold="$1" other="$2"
  [ -f "$gold" ]  || { echo "boot: gold log not found: $gold" >&2; return 2; }
  [ -f "$other" ] || { echo "boot: other log not found: $other" >&2; return 2; }
  echo "Boot-sequence marker comparison"
  echo "  GOLD  = $gold"
  echo "  OTHER = $other"
  echo "  (a marker present in GOLD but MISSING in OTHER is a chronological regression)"
  echo ""
  printf "  %-46s %-6s %-6s %s\n" "STATE / MARKER" "GOLD" "OTHER" "VERDICT"
  local miss=0
  while IFS='|' read -r re label; do
    [ -n "$re" ] || continue
    local gc oc
    gc=$(grep -aciE -- "$re" "$gold"  2>/dev/null); gc=${gc:-0}
    oc=$(grep -aciE -- "$re" "$other" 2>/dev/null); oc=${oc:-0}
    local verdict="ok"
    if [ "$gc" -gt 0 ] && [ "$oc" -eq 0 ]; then verdict="${c_red}MISSING in OTHER${c_off}"; miss=$((miss+1));
    elif [ "$gc" -eq 0 ] && [ "$oc" -gt 0 ]; then verdict="${c_yel}extra in OTHER${c_off}";
    elif [ "$gc" -eq 0 ] && [ "$oc" -eq 0 ]; then verdict="${c_dim}absent both${c_off}"; fi
    printf "  %-46s %-6s %-6s %b\n" "$label" "$gc" "$oc" "$verdict"
  done < <(boot_markers)
  echo ""
  if [ "$miss" -eq 0 ]; then
    echo "  ${c_grn}No GOLD markers missing in OTHER.${c_off}"
  else
    echo "  ${c_red}$miss GOLD marker(s) missing in OTHER — chronological divergence.${c_off}"
  fi
}

# ---- dispatch ----------------------------------------------------------------
case "${1:---help}" in
  --help|-h) usage; exit 0;;
  --boot)
    [ $# -eq 3 ] || { echo "usage: $0 --boot GOLD_LOG OTHER_LOG" >&2; exit 2; }
    compare_boot "$2" "$3"; exit 0;;
  --all|--cgo)
    if [ "$1" = "--cgo" ]; then
      objs="KERNEL.CGO ENGINE.CGO GAME.CGO"
    else
      objs=$( { ls "$GOLD_CGO" 2>/dev/null; ls "$GOLD_DGO" 2>/dev/null; } | sort -u )
      [ -n "$objs" ] || objs=$(ls "$OUR_X86"/*.CGO "$OUR_X86"/*.DGO 2>/dev/null | xargs -n1 basename | sort -u)
    fi
    echo "3-tier comparison  (Tier-A = gold vs our-x86 = pure compiler signal; Tier-B = our-x86 vs our-arm64 = arm64 surface)"
    echo ""
    for o in $objs; do compare_object "$o"; [ "$1" = "--cgo" ] && struct_dump "$o"; echo; done
    exit 0;;
  -*)
    echo "unknown option: $1" >&2; usage; exit 2;;
  *)
    compare_object "$1"
    case "$1" in *.CGO) struct_dump "$1";; esac
    exit 0;;
esac
