/*
 * Phase A3 — x86_64 host-side oracle harness.
 *
 * The companion to qemu_harness_arm64.S: for each per-cluster test we
 * compile the GOAL source with the x86 backend and link a flat blob of
 * its function bytes against this C harness. We then run the resulting
 * ELF natively (no qemu — x86 host) and capture the function's int
 * return value in stdout.
 *
 * Why a separate harness:
 *   1. Mmap a fixed-address scratch region at 0x40000000 (matches the
 *      arm64 harness) so tests can use absolute pointers.
 *   2. Zero the GOAL offset register (R15 on x86) before the call. GOAL's
 *      load/store pattern is `mov rdx, [r15 + rbase + offset]` which
 *      requires R15 == 0 when we're not running with the GOAL runtime.
 *
 * The test function bytes are linked in as an opaque symbol `goal_fn`
 * (see build_a3_diff.sh). It MUST end with `ret` (GOAL epilogue emits
 * `c3` on x86, so this is always true).
 */

#include <stdio.h>
#include <stdlib.h>
#include <stdint.h>
#include <sys/mman.h>

extern long goal_fn(void);

int main(void) {
    /* Match the arm64 harness's scratch buffer. */
    void* p = mmap((void*)0x40000000, 0x10000,
                   PROT_READ | PROT_WRITE,
                   MAP_PRIVATE | MAP_ANONYMOUS | MAP_FIXED,
                   -1, 0);
    if (p == MAP_FAILED) {
        fprintf(stderr, "mmap failed\n");
        return 2;
    }

    /* GOAL ABI: 0-arg call, return in RAX. We must zero R15 (GOAL
     * offset reg) before entering the function. Clobber-list keeps the
     * compiler from assuming any GOAL-side reg is preserved. */
    long r;
    __asm__ volatile(
        "xor %%r15, %%r15\n\t"
        "call goal_fn\n\t"
        : "=a"(r)
        :
        : "r15", "r14", "r13", "r12", "r11", "r10", "r9", "r8",
          "rcx", "rdx", "rsi", "rdi", "memory", "cc"
    );

    printf("%ld\n", r);
    /* Exit codes are u8, so the orchestrator parses stdout for the
     * full int value. */
    return (int)(r & 0xff);
}
