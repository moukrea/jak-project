# Gmenu-textures — arm64 vs x86 codegen forensics (manager, 2026-06-22)

## Goal
Find why the menu particle int32 field `(-> particle part matrix)` (the user-hvdf
index) reads **0** on the arm64 device while x86 gives a positive index (1..34),
causing the menu icon/texture sprites to bunch to center.

## Tooling
`(asm-file "<f.gc>" :color :disassemble "<out>")` via `build-arm64/goalc/goalc`
and `build-x86/goalc/goalc` after `(make-group "engine")`. Writes per-function
disasm; NO `.o`/CGO emitted (no `:write`/`:output-file`), so no CGO overwrite.

## Authoritative offsets (decompiler/config/jak1/all-types.gc, deftype block @14961)
`sparticle-launch-control` (inline-array-class): group@16 proc@20 local-clock@24
**fade@28  matrix@32**  last-spawn-frame@36 ...  size #x40.
COMPILED field offset = (assert offset − 4): verified in `initialize` disasm —
local-clock(assert 24)→`[base+20]`, fade(assert 28)→`[base+24]`, matrix(assert 32)
→**`[base+28]`**. So the device probe `memcpy(... s1+28 ...)` and the goalc-emitted
`[x16,#0x1c]` BOTH correctly address `matrix`. (Earlier "off-by-one to fade"
worry is resolved: compiled-28 == assert-32 == matrix.)

## Candidate A — store of −1 (progress-part.gc:826 / progress.gc:455): IDENTICAL, correct
- arm64: `movz/movk x9 = 0xFFFFFFFFFFFFFFFF` ; `str w9,[x16,#0x1c]` (32-bit store @ matrix)
- x86:   `mov r9,0xFFFFFFFFFFFFFFFF` ; `mov [r15+r8*1+0x1C],r9d`
Same IR (`move [igpr-N + 28], -1`), same store. NOT the bug.

## Candidate B — compare `(= matrix -1)` (progress.gc:652 progress-waiting): IDENTICAL, correct
- arm64: `ldrsw x9,[x16,#0x1c]` (SIGN-extend) ; `movz/movk x8=-1` ; `cmp x9,x8` ; `b.ne`
- x86:   `movsxd r9,[..+0x1C]` ; `mov r8,-1` ; `cmp r9,r8` ; `jnz`
Field is sign-extended on BOTH → 0xFFFFFFFF compares equal to literal −1. The
"LDR Wt zero-extend mismatch" theory is FALSE; the compare fires when matrix=−1.
NOT the bug.

## Candidate B' — use `(> matrix 0)` (progress.gc:522 adjust-sprites): IDENTICAL, correct
- arm64: `ldrsw x9,[x16,#0x1c]` ; `cmp x9,#0` ; `b.le`
- x86:   `movsxd r9,[..+0x1C]` ; `cmp r9,0` ; `jle`
NOT the bug.

## Candidate C — sprite-allocate-user-hvdf (sprite.gc:775): IDENTICAL, correct
Clean disasm (temp GMENU-ALLOC format removed for readability):
- loop init v1-0=0 ; body: `add x8,v1-0,control_ptr` ; `ldrsb x8,[x16]` (int8 stride-1
  read) ; `cmp x8,#0` ; `b.ne` skip ; on zero: `strb #1` ; `mov x0,v1-0` ; goto exit
  (early return of the index) ; increment ; `cmp v1-0,#0x4c(76)` ; `b.lt`.
x86 identical structure. Returns 1 on the first call (alloc[0] preset to 1).
The int8 alloc-array init (sprite.gc:50-54) uses the same stride-1 access. NOT the bug.

## Verdict
The entire goalc-compiled matrix lifecycle (store −1 → compare = −1 → allocate →
store index → use > 0) is byte-for-byte semantically identical between arm64 and
x86 and is correct on arm64. **None of A/B/C is a codegen divergence.** Therefore
matrix being 0 at the device sprite-build site is NOT a goalc bug in these funcs.

Remaining live hypotheses (require menu-SPECIFIC device measurement, since the
prior GMENU-DBG sampled mostly background title particles, not the 34 menu parts):
  (1) mips2c `sp-launch-particles-var` `bne s6,s7` 64-vs-32 #f-guard skips the
      `[s1+28]`→`flag-rot-sy.y` matrix copy (sprite index ends 0) WHILE the
      launch-control.matrix source is actually positive. Prior attempt-2 patched
      this but measured "no effect" — but that measurement read the COPIED value
      (Sprite3 vd.matrix), which is 0 under the skip regardless of source.
  (2) A pointer divergence (progress `relocate`, or sp-launch reading a different
      launch-control object) — source set positive, read from wrong object.
  (3) progress control-flow / a runtime stomp not in GOAL source.
Decisive next probe: GOAL dump of the 34 MENU particles' matrix at
initialize-particles / progress-waiting (pre+post alloc) / adjust-sprites on device.
