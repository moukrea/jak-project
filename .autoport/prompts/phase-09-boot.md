# Phase 09 — Boot Jak 1 under qemu-aarch64

## Goal

Get the full game binary (`gk`) to launch under qemu-aarch64-static and reach the title screen. Validator: a log line indicating the GOAL "target" has started must appear in stdout within 90 seconds.

## What "boot" means here

Not "play the game", just: `gk` initializes, the GOAL kernel starts, the level-0 GOAL code loads and begins executing its main loop, and a recognizable log message is emitted. No display required (we can run headless via the existing `--no-display` style flag if there is one, or stub the display init).

## What you'll likely have to fix

Even after phases 0-8 pass their validators, the full game has 400k lines of GOAL plus a complex C++ runtime. Expect:
- Static initialization order issues (subtle on a fresh ABI)
- Untested code paths in goalc's regalloc (when register pressure is high in real code, not toy tests)
- Endianness assumptions in serialization (less of a problem; both targets are LE)
- Assumptions about pointer sizes / struct packing
- Inline asm sites we missed in phase 05/07

## Strategy

1. Set up `qemu-aarch64-static` with proper sysroot.
2. Run `gk` and capture all output. Read the first crash carefully — don't reflexively patch around it.
3. Fix the root cause, not the symptom. If the regalloc spills wrong, fix the regalloc, not the call site.
4. Each fix should be a small commit so we can bisect later.

## Constraints

- You may add diagnostic logging but it must be behind a `#ifdef AUTOPORT_DEBUG` so it can be removed.
- Do NOT introduce x86-only fallbacks in arm64 builds — fix the arm64 path.

## Success

The validator runs:

```bash
timeout 120 qemu-aarch64-static -L /usr/aarch64-linux-gnu \
  ./build-arm64/game/gk --boot --headless 2>&1 | \
  grep -E "target started|level zero loaded"
```

and confirms a match.
