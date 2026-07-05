/* Gswamp-fstore round-trip proof — driver + assertions (C; cross-gcc has no libstdc++).
 *
 * Exercises the REAL asm_funcs_arm64.s trampolines end-to-end on arm64 (qemu),
 * device-independently:
 *   drive_mips2c -> _mips2c_call_arm64   (seeds ExecutionContext gpr s7 from live x14)
 *        -> probe_body reads gpr s7 (+368) & gpr s6 (+352)
 *        -> replicates ExecutionContext::jalr: _call_goal8_asm_arm64(func, args, 0,
 *                                              pp=gpr_s6, st=gpr_s7, off=g_ee_main_mem)
 *        -> goal_probe returns #f = x14 - x15
 *
 * Correct fix: gpr s7 = GOAL OFFSET (x14-x15) of the symbol table, so _call_goal8
 * reconstructs x14 = st+off = host symtab, and #f = K. Buggy (pre-fix) trampoline
 * stores raw host x14 into gpr s7, so _call_goal8 RE-ADDS the EE base -> torn x14 ->
 * #f = host address (garbage) = the swamp joint-control.effect null-dispatch cause.
 */
#include <stdint.h>
#include <stdio.h>
#include <string.h>

int64_t drive_mips2c(void* body, uint64_t pp, uint64_t st_host, uint64_t off, uint64_t stack_sz);
int64_t goal_probe(void);
int64_t _call_goal8_asm_arm64(void* func, uint64_t* args, uint64_t zero, uint64_t pp, uint64_t st,
                              uint64_t off);

static uint64_t g_off = 0;
static uint64_t g_seen_s7 = 0xdeadbeefULL;
static uint64_t g_seen_s6 = 0xdeadbeefULL;
static int64_t g_jalr_ff = (int64_t)0xdeadbeefULL;

void probe_body(uint8_t* ctx) {
  memcpy(&g_seen_s6, ctx + 352, 8); /* ExecutionContext gpr s6 = pp */
  memcpy(&g_seen_s7, ctx + 368, 8); /* ExecutionContext gpr s7 = st */
  uint64_t args[8] = {0, 0, 0, 0, 0, 0, 0, 0};
  /* Faithful ExecutionContext::jalr forwarding: st = gpr s7, pp = gpr s6, off = EE base. */
  g_jalr_ff = _call_goal8_asm_arm64((void*)goal_probe, args, 0, g_seen_s6, g_seen_s7, g_off);
}

int main(void) {
  /* Large EE base so a24_x30_stack_range_check (fires when X30 - X15 >= 0x07000000)
     never trips: with -no-pie our code is well below 4 GiB. */
  const uint64_t off = 0x0000000100000000ULL;      /* EE base (g_ee_main_mem stand-in) */
  const uint64_t K = 0x00000000013b7ec0ULL;        /* plausible symbol-table GOAL offset */
  const uint64_t st_host = off + K;                /* arm64 live st register = HOST symtab addr */
  const uint64_t pp = off + 0x00000000004a1230ULL; /* plausible process host addr */
  g_off = off;

  drive_mips2c((void*)probe_body, pp, st_host, off, 256);

  const int s7_is_offset = (g_seen_s7 == K);
  const int s7_is_host = (g_seen_s7 == st_host);
  const int ff_correct = ((uint64_t)g_jalr_ff == K);
  const int pass = s7_is_offset && ff_correct;

  printf("GSF-ROUNDTRIP off=0x%llx  K(symtab_goal_offset)=0x%llx  st_host=0x%llx\n",
         (unsigned long long)off, (unsigned long long)K, (unsigned long long)st_host);
  printf("GSF-ROUNDTRIP gpr_s7_stored=0x%llx  is_goal_offset=%d  is_raw_host=%d\n",
         (unsigned long long)g_seen_s7, s7_is_offset, s7_is_host);
  printf("GSF-ROUNDTRIP gpr_s6_pp_stored=0x%llx (raw pp round-trip, unchanged)\n",
         (unsigned long long)g_seen_s6);
  printf("GSF-ROUNDTRIP jalr_callee_saw_#f=0x%llx  expect_K=0x%llx  correct=%d\n",
         (unsigned long long)(uint64_t)g_jalr_ff, (unsigned long long)K, ff_correct);
  printf("GSF-ROUNDTRIP RESULT=%s\n", pass ? "PASS" : "FAIL");
  return pass ? 0 : 1;
}
