// cmp_oracle.cpp — arm64-vs-x86 differential for goalc FLOAT comparison codegen.
//
// goalc compiles a GOAL float (< <= > >= = !=) comparison to:
//   x86  : ucomiss a,b ; <unsigned jcc>  (LT=jb, LEQ=jbe, GT=ja, GEQ=jae, EQ=je, NE=jne)
//          (IR.cpp do_codegen_x86: is_signed=false for floats -> unsigned jcc; cmp_flt_flt=ucomiss)
//   arm64: fcmp a,b    ; b.<cond>         (CURRENT/buggy: LT=MI, LEQ=LS, GT=GT, GEQ=GE, EQ=EQ, NE=NE)
//          (IR.cpp do_codegen_arm64: condition.is_float branch, IR.cpp:1684-1701)
//   arm64 FIXED        : LT=LT, LEQ=LE (rest unchanged) — replicates x86 ucomiss NaN semantics.
//
// This harness runs the REAL instructions (inline asm) for each backend on the SAME operands,
// including the degenerate 0.0/0.0 NaN the collision reaction produces (collide-shape.gc:740).
// Build x86 (host) + arm64 (NDK), run BOTH, diff. The x86 column is the oracle (the 1-to-1 target).
#include <cstdio>
#include <cstring>
#include <cmath>
#include <cstdint>

static float bits(uint32_t u){ float f; std::memcpy(&f,&u,4); return f; }

// ---- x86 reference: ucomiss a,b then the exact goalc unsigned jcc ----
#if defined(__x86_64__)
static int x86_cmp(float a, float b, int op){
  unsigned char r=0;
  switch(op){
   case 0: __asm__ volatile("ucomiss %2,%1\n\tsetb  %0":"=r"(r):"x"(a),"x"(b):"cc"); break; // LT  jb
   case 1: __asm__ volatile("ucomiss %2,%1\n\tsetbe %0":"=r"(r):"x"(a),"x"(b):"cc"); break; // LEQ jbe
   case 2: __asm__ volatile("ucomiss %2,%1\n\tseta  %0":"=r"(r):"x"(a),"x"(b):"cc"); break; // GT  ja
   case 3: __asm__ volatile("ucomiss %2,%1\n\tsetae %0":"=r"(r):"x"(a),"x"(b):"cc"); break; // GEQ jae
   case 4: __asm__ volatile("ucomiss %2,%1\n\tsete  %0":"=r"(r):"x"(a),"x"(b):"cc"); break; // EQ  je
   case 5: __asm__ volatile("ucomiss %2,%1\n\tsetne %0":"=r"(r):"x"(a),"x"(b):"cc"); break; // NE  jne
  }
  return r&1;
}
#endif

// ---- arm64: fcmp a,b then cset cond. CURRENT uses MI/LS; FIXED uses LT/LE. ----
#if defined(__aarch64__)
static int arm_cmp(float a, float b, int op, int fixed){
  unsigned long r=0;
  switch(op){
   case 0: if(!fixed) __asm__ volatile("fcmp %s1,%s2\n\tcset %0,mi":"=r"(r):"w"(a),"w"(b):"cc");
           else        __asm__ volatile("fcmp %s1,%s2\n\tcset %0,lt":"=r"(r):"w"(a),"w"(b):"cc"); break; // LT
   case 1: if(!fixed) __asm__ volatile("fcmp %s1,%s2\n\tcset %0,ls":"=r"(r):"w"(a),"w"(b):"cc");
           else        __asm__ volatile("fcmp %s1,%s2\n\tcset %0,le":"=r"(r):"w"(a),"w"(b):"cc"); break; // LEQ
   case 2: __asm__ volatile("fcmp %s1,%s2\n\tcset %0,gt":"=r"(r):"w"(a),"w"(b):"cc"); break; // GT
   case 3: __asm__ volatile("fcmp %s1,%s2\n\tcset %0,ge":"=r"(r):"w"(a),"w"(b):"cc"); break; // GEQ
   case 4: __asm__ volatile("fcmp %s1,%s2\n\tcset %0,eq":"=r"(r):"w"(a),"w"(b):"cc"); break; // EQ
   case 5: __asm__ volatile("fcmp %s1,%s2\n\tcset %0,ne":"=r"(r):"w"(a),"w"(b):"cc"); break; // NE
  }
  return (int)(r&1);
}
#endif

int main(){
  const char* opn[6]={"LT(<)","LEQ(<=)","GT(>)","GEQ(>=)","EQ(=)","NE(!=)"};
  // operands: the degenerate NaN (0/0), ±Inf, ±0, finite. zero/zero is computed at runtime so the
  // compiler cannot fold it (matches the in-game (/ 0.0 0.0) at collide-shape.gc:740).
  volatile float zero=0.0f;
  float nan0 = zero/zero;           // 0/0 = qNaN (the real collision NaN)
  float vals[] = { nan0, INFINITY, -INFINITY, 0.0f, -0.0f, 1.0f, -1.0f, 2.0f, 0.5f, 1e30f, 1e-30f };
  const char* vn[] = {"0/0NaN","+Inf","-Inf","+0","-0","1.0","-1.0","2.0","0.5","1e30","1e-30"};
  int n = sizeof(vals)/sizeof(vals[0]);
#if defined(__x86_64__)
  const char* ARCH="x86";
#else
  const char* ARCH="arm64";
#endif
  printf("arch=%s\n", ARCH);
  for(int op=0; op<6; op++){
    for(int i=0;i<n;i++) for(int j=0;j<n;j++){
      float a=vals[i], b=vals[j];
#if defined(__x86_64__)
      int rx = x86_cmp(a,b,op);
      printf("R op=%-8s a=%-7s b=%-7s x86=%d\n", opn[op], vn[i], vn[j], rx);
#else
      int rc = arm_cmp(a,b,op,0);   // current/buggy
      int rf = arm_cmp(a,b,op,1);   // fixed
      printf("R op=%-8s a=%-7s b=%-7s arm_cur=%d arm_fix=%d\n", opn[op], vn[i], vn[j], rc, rf);
#endif
    }
  }
  return 0;
}
