# Phase C3 — Direct-load KERNEL.CGO under qemu-aarch64; reach link finish: gstate (relocations only)

## What this phase delivers

A **runnable** aarch64-linux gk binary that, under
`qemu-aarch64-static`, drives all 8 objects of the real arm64-compiled
KERNEL.CGO from `out/jak1-arm64/iso/` through upstream
`jak1::link_and_exec`, applies all relocation tables successfully
(symbol-link, type-link, cross-seg, ptr-link), and reaches the
upstream `link finish: gstate` marker
(`game/kernel/common/klink.cpp::print_link_finish`) after the 8th and
final object's relocations complete.

C2 stopped at `Initialized GOAL heap` with `MasterUseKernel=false` and
NumSymbols=97. C3 takes the next honest step: link the kernel module's
relocation tables. After C3, NumSymbols rises into the low hundreds
(from gcommon/gkernel/gstate's type-link and symlink relocation
entries that allocate type/symbol slots) — empirically ~317 on this
build.

The phase ID is `C3-linux-arm64-title` because the supervisor's
REDESIGN §8 set this bucket's ceiling at the title screen. **This
phase does not reach the title screen, and it does not execute any
arm64-compiled GOAL bytecode either.**  Both are deferred. The honest
checkpoint C3 reaches is "all KERNEL.CGO relocations apply cleanly to
arm64 object data under qemu-aarch64." Why is bytecode execution
deferred:

## Engineering finding: ADRP+ADD link-fixup gap

A C3 diagnostic run with `LINK_FLAG_EXECUTE` enabled SIGILLs partway
through gcommon's top-level GOAL function:

```
[link and exec] gcommon            0  27531 ...
link finish: gcommon
qemu: uncaught target signal 4 (Illegal instruction) - core dumped
```

The qemu trace pinpoints the failing PC. The bytes at that location
disassemble to:

```
   c:  fc40a504    ldr  d4, [x8], #10        ; was originally adrp x9, 0
  10:  fc40a500    ldr  d0, [x8], #10        ; was originally add  x9, x9, #0
  14:  cb0f0129    sub  x9, x9, x15          ; unchanged
  18:  00005c30    udf  #23600               ; was originally str  w9, [x14]
```

Comparing with the *unlinked* gcommon top-level segment (extractable
from the on-disk CGO via the SegmentInfo table), the original pattern
was an ADRP / ADD / SUB / STR sequence — the goalc-arm64 emitter's
canonical "compute PC-relative symbol address, normalise via x15,
store" pattern.

The corruption is the relocator. `game/kernel/jak1/klink.cpp`'s
`cross_seg_dist_link_v3` / `ptr_link_v3` / `symlink_v3` /
`typelink_v3` all write relocation patches as raw u32 stores:

```cpp
*Ptr<u32>(offset_of_patch).c() = diff;        // or sym_addr, etc.
```

For x86 this works: the x86 emitter leaves 32-bit displacement slots
in `lea rax, [rip + 0]` / `mov rax, [rip + 0]` instructions where the
linker can overwrite the 4 displacement bytes without touching the
opcode bytes. For arm64 the addressing pattern is ADRP (`imm21` field
spread across bits 30:29 and 23:5) + ADD (`imm12` at bits 21:10).
Overwriting those 4 bytes with a raw u32 corrupts the opcode bits and
yields garbage.

A4 added link-time fixup support for **LDR (imm12), B/BL (imm26),
B.cond (imm19)** — but did NOT add fixups for **ADRP (imm21) + ADD
(imm12)**. That gap is the root cause. The goalc-arm64 emitter still
emits ADRP+ADD pairs for symbol/literal addressing, and klink's raw
u32 writes destroy them.

Why this wasn't caught earlier:

- **A3 (per-IR-form differential)** tested each IR form's emitted code
  in isolation — without running it through klink's relocator.
- **A4 (linker-fixups)** added handling for some instructions but
  missed ADRP+ADD. There was no end-to-end "emit + relocate + execute
  on real CGO" test gate at the time.
- **B2 (qemu decode-stress)** ran every function under qemu by
  loading the raw bytes directly into a static aarch64 ELF — no klink
  relocation at all. The functions exited cleanly OR body-SIGSEGV'd
  on nullptr derefs, but never SIGILLed because the bytes weren't
  patched.
- **C2** never executed GOAL bytecode at all (MasterUseKernel=false).

C3 is the first phase that combines emit + relocate + execute end-to-
end. That's why it surfaces the bug. **The strict-validator discipline
is working as intended.**

## What C3 fixing this bug looks like (NOT in scope here)

A follow-up phase — call it A5 or B3 — needs to either:

1. **Teach klink to recognise the arm64 ADRP+ADD pattern.** The
   relocator would detect the placeholder bits in the ADRP+ADD pair
   at the patch site and rewrite them with the correct immediate
   encoding split (imm21 for ADRP, imm12 for ADD). Requires touching
   `game/kernel/jak1/klink.cpp` + per-link-form helper functions,
   which is C3's read-only zone.

2. **Change the arm64 emitter to use a different addressing pattern.**
   Emit `LDR Xn, [pc + literal_pool_offset]` instead of ADRP+ADD,
   where the literal-pool entry is a u32 that klink CAN safely patch
   (since LDR-immediate uses an imm19 slot the existing A4 fixup
   handles). Requires touching `goalc/emitter/IGenARM64.cpp`, which
   is also C3's read-only zone.

Either fix is a significant engineering effort. Doing it inside C3
would balloon the phase scope and violate the read-only constraints
on goalc/ and game/kernel/. The supervisor's standing rule is "do
the smallest honest step"; for C3 that step is "verify the linker
infrastructure works for arm64-compiled CGO data, document the
codegen-linker integration gap, defer the gap's fix to its own
phase."

## What C3 does (revised scope)

C3's runnable artefact:

- Drives the arm64 KERNEL.CGO from `out/jak1-arm64/iso/` through 8
  invocations of `jak1::link_and_exec` (via a new
  `linux_arm64::direct_load_dgo` helper).
- Each link runs **state 0 (segment copy)** and **state 1
  (relocations)** of jak1_work_v3. Symbols and types referenced by
  the link table are interned via `intern_from_c` /
  `intern_type_from_c`. NumSymbols grows from C2's 97 to ~317 (the
  exact number is a check the validator anchors on, ±20).
- **Does NOT pass `LINK_FLAG_EXECUTE`.** The top-level GOAL function
  produced by jak1_work_v3 (`m_entry = code_infos[TOP_LEVEL_SEGMENT].offset + 4`)
  is computed and stored on the heap, but `jak1_finish` does not
  call it. The "[link and exec]" log line is still emitted per
  object (it's printed before the optional execute), as is the
  "link finish: <name>" marker after relocations apply.

## What C3 does NOT do (still later-bucket / later-phase work)

- **Execute any arm64-compiled GOAL bytecode.** Blocked by the
  ADRP+ADD link-fixup gap documented above. A5/B3 unblocks this.
- **Spawn IOP / EE / DECI2 threads** (libco-threaded overlord + RPC).
  C3 bypasses this with the direct-from-disk DGO loader.
- **Load GAME.CGO** (depends on graphics + sound stubs that don't
  yet exist).
- **Reach the rendered title screen** (graphics work; D bucket).

## Concrete deliverables

### 1. `game/linux-arm64/linux_arm64_main.cpp` — extend C2's driver

After C2's `InitHeapAndSymbol()` returns 0 and the driver banners
the `NumSymbols=97` line:

1. Locate `out/jak1-arm64/iso/KERNEL.CGO`. If absent, print a clear
   diagnostic and exit with code 30 (validator catches that).
2. Call `linux_arm64::direct_load_dgo("...", kglobalheap,
   LINK_FLAG_OUTPUT_LOAD | LINK_FLAG_PRINT_LOGIN, 0x100000)`. Note
   the missing `LINK_FLAG_EXECUTE` — see the engineering finding
   above. The link flags are wrapped in a `constexpr` with a
   detailed comment block explaining why EXECUTE is omitted, for
   future readers and for validator anti-cheat scans.
3. After the load returns, print
   `linux-arm64: C3 KERNEL.CGO link complete (NumSymbols={N}, delta=+{D} from C2)`
   followed by `linux-arm64: C3 NumSymbols={N}`.
4. Exit 0.

The driver does NOT emit any `link finish: <name>` strings itself
(those come from upstream `klink.cpp::jak1_finish`). The driver
does NOT emit `Got DGO file header for KERNEL.CGO` (that's the
overlord's marker — we use `[Direct DGO]` instead).

### 2. `game/linux-arm64/linux_arm64_direct_dgo.cpp` — new TU

A single function `direct_load_dgo` that:

1. `fopen(dgo_path, "rb")`.
2. Read `DgoHeader` (per `common/link_types.h`): `{object_count, name}`.
   Log `[Direct DGO] Got DGO file header for {name} with {n} objects`.
3. Allocate one DGO read buffer at `heap->top` (`KMALLOC_TOP |
   KMALLOC_ALIGN_64`, size `buffer_size`, name "dgo-buffer-direct"
   — distinct from upstream "dgo-buffer-2").
4. `++(*EnableMethodSet)` (matches upstream kscheme.cpp:1755).
5. For each of the `object_count` objects:
   - Read 64-byte `ObjectHeader` (`{size, name}`).
   - Read `size` bytes of object data into `buffer + 0x40`.
   - **Skip padding to 16-byte alignment.** DgoWriter
     (`common/util/DgoWriter.cpp:35`) zero-pads each object to a
     16-byte boundary; the overlord's RPC layer handles this
     internally but our direct FILE* reader has to do it explicitly,
     or the next ObjectHeader read will start partway into the
     padding and parse as `{size=0, name=""}`. Use `ftell` +
     `fseek(fp, 16-byte-pad, SEEK_CUR)`.
   - Emit the upstream-shape `[link and exec]` log line via
     `lg::debug` (same call site as kdgo.cpp:148).
   - Call `jak1::link_and_exec(buffer + 0x40, name, size, heap,
     link_flags, /*jump_from_c_to_goal=*/true)`. (The
     `jump_from_c_to_goal` flag still matters even without
     LINK_FLAG_EXECUTE — it's passed through but only consulted
     by jak1_finish when EXECUTE is set.)
6. `--(*EnableMethodSet)`.
7. Restore `heap->top` to the pre-buffer value (frees the dgo-buffer-
   direct allocation).
8. `fclose(fp)`. Return 0.

If any step fails (fopen, short read, allocation), return a distinct
negative code (-1..-8) and let the caller exit with `40 - rc` so the
validator can pinpoint the failure mode.

### 3. `.autoport/lib/c3_run.sh` — reproducible run wrapper

Same shape as `c2_run.sh`:
1. Configure (delegate to `c1_configure.sh`).
2. Build `gk` (`cmake --build build-arm64-linux --target gk -j`).
3. Sanity-check `out/jak1-arm64/iso/KERNEL.CGO` exists; fail-fast
   with a clear error if not.
4. Invoke `qemu-aarch64-static -L /usr/aarch64-linux-gnu` on the
   binary with a 120 s timeout.
5. Capture stdout+stderr to `.autoport/reports/C3-boot.log`.
6. Capture exit code to `.autoport/reports/C3-exit.txt`.

### 4. `.autoport/reports/C3-title.md` — headline report

Records:
- Exit code under qemu.
- NumSymbols before and after KERNEL.CGO link.
- The 8 `link finish:` lines extracted from the boot log, in order.
- A clear "engineering finding" section explaining the ADRP+ADD
  link-fixup gap (mirrors §Engineering finding here).
- The C3 caveat: title screen NOT reached, AND arm64 GOAL bytecode
  NOT executed. Both are A5/D-bucket follow-ups.

### 5. Validator at `.autoport/validators/phase-C3-linux-arm64-title.sh`

Strict superset of C2: re-runs all 25 C2 invariants unchanged, then
adds 13 C3-specific reality checks (numbered 26-38). The
authoritative list lives in §Done-definition.

## Anti-cheat constraints

The supervisor's standard set, plus the specific patterns the
previous orchestrator's claude would reach for given this scope:

1. **No `__attribute__((weak))` declarations.** Carried.

2. **No fabricated `link finish:` strings.** Must come from
   `klink.cpp::print_link_finish`. Validator §36 forbids the
   string in our driver / direct-dgo / compat sources.

3. **No fabricated `Got DGO file header for` string.** Our direct
   loader emits `[Direct DGO] Got DGO file header for ...`, *not*
   the `[Overlord DGO] ...` upstream form. The `[Direct DGO]`
   prefix is the explicit signal of an alternate code path.

4. **No re-enabling `LINK_FLAG_EXECUTE` to make NumSymbols inflate
   under a "swallow the SIGILL" handler.** Adding a `signal()`
   handler that catches SIGILL and longjmps past the bad bytecode
   would technically let us claim NumSymbols=2000+, but it would
   defeat the engineering integrity that uncovered the codegen-linker
   gap. The validator's check 34 verifies the boot log does NOT
   contain `qemu: uncaught target signal` AND ALSO verifies the
   link flags constant in the source is `LINK_FLAG_OUTPUT_LOAD |
   LINK_FLAG_PRINT_LOGIN` (no `LINK_FLAG_EXECUTE`).

5. **No softening of the NumSymbols floor below empirical reality.**
   On this build, post-link NumSymbols is 317. The validator floor
   is 250 — well below the empirical value but well above C2's 97.
   Future emitter changes that legitimately change the symbol-table
   shape can raise the empirical and the floor together; lowering
   the floor below 250 to mask a regression is forbidden.

6. **No `kStateSeq`, `kSyntheticBootSequence`, `engine: state=`.**
   Carried.

7. **No edit to `goalc/`** — codegen-locked since A4.

8. **No edit to upstream `game/kernel/`, `game/overlord/`,
   `game/runtime.{h,cpp}`.** C3's work is purely additive in
   `game/linux-arm64/`.

9. **No regression on C2 invariants.** Validator's first 25 checks
   are byte-identical to C2's.

10. **No edit to validator scripts under `.autoport/validators/`
    that LOOSENS a check** beyond the documented "ADRP+ADD gap" path.

## Files you will create / modify

| Path | Purpose |
|---|---|
| `game/linux-arm64/linux_arm64_main.cpp` | extend — call direct-DGO load after InitHeapAndSymbol |
| `game/linux-arm64/linux_arm64_direct_dgo.cpp` | new — direct-from-disk DGO load wrapping upstream link_and_exec |
| `game/linux-arm64/linux_arm64_direct_dgo.h` | new — declaration only |
| `game/linux-arm64/CMakeLists.txt` | extend — add new TU |
| `.autoport/lib/c3_run.sh` | new — reproducible qemu run wrapper |
| `.autoport/reports/C3-title.md` | new — headline report + engineering finding |
| `.autoport/prompts/phase-C3-linux-arm64-title.md` | this file |
| `.autoport/validators/phase-C3-linux-arm64-title.sh` | new — strict superset of C2 |

Read-only: everything in `goalc/`, `game/kernel/`, `game/overlord/`,
`game/runtime.{h,cpp}`, `cmake/aarch64-linux-toolchain.cmake`, root
`CMakeLists.txt`, and `game/linux-arm64/linux_arm64_runtime_compat.cpp`.

## Pitfalls

- **`heap->top` lifetime.** Same as kdgo.cpp: snapshot
  `oldHeapTop = heap->top` before allocating the dgo-buffer; restore
  `heap->top = oldHeapTop` at the end (or on any error path). Mirror
  upstream behaviour exactly.

- **16-byte object padding.** Documented in DgoWriter.cpp:35 — easy
  to miss if you don't read the writer. Validator §32 implicitly
  catches a missed padding (the boot log would show object names
  parsing as empty strings, which fails the per-object `link finish:`
  greps).

- **`buffer_size` budget.** Use `0x100000` (1 MB). KERNEL.CGO's
  largest object (`gkernel`) is ~45 KB; 1 MB is generous headroom.

- **`EnableMethodSet` wrapping.** Match upstream kscheme.cpp:1755 —
  wrap the entire load with `(*EnableMethodSet)++/--`. The link
  engine reads this global during type interning.

- **`kheapused(kdebugheap)`** — guard with `kdebugheap.offset != 0`,
  exactly as kdgo.cpp does. `kdebugheap.offset == 0` in our setup
  (MasterDebug=false). Calling kheapused on a null heap deref-faults.

- **`mips2c_table_jak1` empty.** C1's compat declared this map
  empty. KERNEL.CGO doesn't use mips2c (those live in GAME.CGO+).

## Reading list

- `game/kernel/jak1/kdgo.cpp::load_and_link_dgo_from_c` — the
  upstream pattern C3's direct loader mirrors (minus RPC).
- `game/kernel/jak1/klink.cpp::jak1_work_v3` (state 0+1) — what
  the link engine actually does to each object.
- `game/kernel/jak1/klink.cpp::cross_seg_dist_link_v3` /
  `ptr_link_v3` / `symlink_v3` / `typelink_v3` — the per-link-form
  patch sites that turn ADRP+ADD into garbage on arm64.
- `goalc/emitter/IGenARM64.cpp` — the goalc-arm64 emitter that
  emits the ADRP+ADD pairs.
- `common/util/DgoWriter.cpp` — the DGO file format: header (4+60),
  per-object header (4+60), data, 16-byte pad.
- `common/link_types.h::DgoHeader` / `ObjectHeader` — struct shapes.
- `.autoport/oracle/jak1-desktop-trace.txt` lines 86-110 — the
  KERNEL.CGO link sequence on desktop. Same `link finish:` order;
  size differences are due to x86 vs arm64 codegen.
- `.autoport/validators/phase-C2-linux-arm64-symbols.sh` — the
  25 invariants C3 re-runs.

## Done definition

`.autoport/validators/phase-C3-linux-arm64-title.sh` exits 0.

Checks 1-25 are C2's invariants, byte-identical and re-run unchanged
(toolchain + cmake + ELF shape + glibc interp + nm symbols + smoke
test + reconfigure idempotency + qemu c2_run + Initialized GOAL heap
marker + C2 driver banner + no SIGSEGV/SIGILL + no synthetic markers
+ reports + anti-forgery + C2 NumSymbols floor).

C3-specific (26-38):

26. arm64 KERNEL.CGO at `out/jak1-arm64/iso/KERNEL.CGO` exists,
    ≥50 KB.
27. `.autoport/lib/c3_run.sh` exists, executable, exits 0; qemu run
    completes within 120 s with gk exit code 0.
28. C3 boot log contains `[Direct DGO] Got DGO file header for KERNEL.CGO with 8 objects`.
29. C3 boot log contains `link finish: gcommon` (first object).
30. C3 boot log contains `link finish: gkernel`.
31. C3 boot log contains `link finish: gstate` (last KERNEL.CGO
    object — proves all 8 link entries cleared).
32. C3 boot log contains `linux-arm64: C3 KERNEL.CGO link complete`.
33. C3 boot log free of qemu crash markers (SIGSEGV/SIGILL/abort/
    terminate/Assertion failed/bus error). The ADRP+ADD bug is
    avoided by skipping LINK_FLAG_EXECUTE — if the validator sees
    a SIGILL despite that, something else has regressed.
34. The link flags constant in `linux_arm64_main.cpp` is
    `LINK_FLAG_OUTPUT_LOAD | LINK_FLAG_PRINT_LOGIN` — NOT containing
    `LINK_FLAG_EXECUTE`. (Anti-cheat: re-enabling EXECUTE under a
    signal handler is forbidden.)
35. C3 boot log free of Overlord-pretend forgery markers
    (`[Overlord DGO]`, `[OVERLORD] FS Open KERNEL`, etc.).
36. C3 boot log free of synthetic-state markers (kStateSeq,
    engine: state=, weak_jak1_).
37. `linux_arm64_main.cpp` / `linux_arm64_direct_dgo.cpp` /
    `linux_arm64_direct_dgo.h` source-text contains none of:
    `link finish:`, `Got DGO file header for`, `[Overlord DGO]`,
    `[OVERLORD] FS`, `Initialized GOAL heap`,
    `__attribute__((weak))`, `kStateSeq`, `weak_jak1_`,
    `engine: state=`.
38. C3-title.md exists, contains the engineering finding section
    (`ADRP+ADD` keyword expected) and the per-object size table.
39. C3 boot log records `linux-arm64: C3 NumSymbols=<N>` with
    N ≥ 250 (empirical 317; floor catches "link silently no-op'd"
    regressions while leaving headroom for legitimate codegen
    changes).

When all 39 pass, the C3 deliverable is reproducible: arm64 KERNEL.CGO
relocations apply cleanly under qemu, the linker infrastructure works
end-to-end for our build, and the codegen-linker integration gap is
documented for a follow-up phase to close.
