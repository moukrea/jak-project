#include "game/graphics/sceGraphicsInterface.h"

#include <cstdint>
#include <cstdio>
#include <cstdlib>
#include <cstring>

#include "common/goal_constants.h"
#include "common/util/Assert.h"

#include "game/graphics/gfx.h"
#include "game/kernel/common/kscheme.h"
#include "game/kernel/jak1/kscheme.h"
#include "game/runtime.h"

// A37-CAM oracle probe: dump the *math-camera* camera chain (fov/ratios ->
// perspective -> camera-rot/inv-camera-rot/trans -> camera-temp) at fixed
// frames so the x86 desktop values can be diffed field-by-field against the
// arm64 device values (same probe in android/gk_android_main.cpp). Gated by
// OG_A37_CAM=1; one fprintf block per probed frame, no behavior change.
namespace {
bool a37_rdf(uint32_t goal, float* out) {
  if (!g_ee_main_mem || goal < 0x1000 || goal >= (uint32_t)(EE_MAIN_MEM_SIZE - 4)) return false;
  *out = *reinterpret_cast<const float*>(g_ee_main_mem + goal);
  return true;
}

void a37_cam_probe_desktop() {
  static int s_enabled = -1;
  if (s_enabled < 0) s_enabled = getenv("OG_A37_CAM") ? 1 : 0;
  if (!s_enabled || g_game_version != GameVersion::Jak1) return;
  static uint64_t s_frame = 0;
  uint64_t f = ++s_frame;
  // F1a: periodic past 2400 — the title course flies between f~3000-9000 and
  // the parked-camera question is pose-over-TIME (mirrors the Android probe).
  if (f != 60 && f != 300 && (f % 600) != 0) return;
  auto s_mc = jak1::intern_from_c("*math-camera*");
  uint32_t mc = s_mc.offset ? s_mc->value : 0;
  if (!mc || mc == s7.offset) {
    printf("A37-CAM f=%llu no-math-camera\n", (unsigned long long)f);
    return;
  }
  auto rrow = [&](uint32_t off, float* v) {
    for (int k = 0; k < 4; k++) {
      v[k] = 0.f;
      a37_rdf(mc + off + 4 * k, &v[k]);
    }
  };
  float scal[6] = {0, 0, 0, 0, 0, 0};  // fov xr yr fcf smooth-step smooth-t
  a37_rdf(mc + 0x8, &scal[0]);
  a37_rdf(mc + 0xC, &scal[1]);
  a37_rdf(mc + 0x10, &scal[2]);
  a37_rdf(mc + 0x41C, &scal[3]);
  a37_rdf(mc + 0x88, &scal[4]);
  a37_rdf(mc + 0x8C, &scal[5]);
  uint32_t reset = 0;
  if (g_ee_main_mem) reset = *reinterpret_cast<const uint32_t*>(g_ee_main_mem + mc + 0x84);
  printf("A37-CAM f=%llu mc=0x%x reset=%d fov=%.3f xr=%.6f yr=%.6f fcf=%.6f smooth=%.4f/%.4f\n",
         (unsigned long long)f, mc, (int)reset, scal[0], scal[1], scal[2], scal[3], scal[4],
         scal[5]);
  struct {
    const char* name;
    uint32_t off;
  } rows[] = {
      {"persp0", 0x9C},  {"persp1", 0xAC},  {"persp2", 0xBC},  {"persp3", 0xCC},
      {"camrot0", 0x16C}, {"camrot3", 0x19C}, {"invrot0", 0x1AC}, {"invrot3", 0x1DC},
      {"trans", 0x34C},  {"ct0", 0x23C},    {"ct1", 0x24C},    {"ct2", 0x25C},
      {"ct3", 0x26C},
  };
  for (auto& r : rows) {
    float v[4];
    rrow(r.off, v);
    printf("A37-CAM f=%llu %s=(%.6f %.6f %.6f %.6f)\n", (unsigned long long)f, r.name, v[0], v[1],
           v[2], v[3]);
  }
  auto s_fc = jak1::intern_from_c("*math-camera-fog-correction*");
  uint32_t fc = s_fc.offset ? s_fc->value : 0;
  if (fc && fc != s7.offset) {
    float a = 0.f, b = 0.f;
    a37_rdf(fc, &a);
    a37_rdf(fc + 4, &b);
    printf("A37-CAM f=%llu fogcor=(%.3f %.3f)\n", (unsigned long long)f, a, b);
  }
  // Round 2: update-camera branch selectors + their sources, to name WHICH
  // cond branch feeds *math-camera* fov/inv-camera-rot and from WHERE.
  auto symval = [](const char* name, uint32_t* out) {
    auto s = jak1::intern_from_c(name);
    if (!s.offset) return false;
    *out = s->value;
    return true;
  };
  uint32_t lto = 0, ext = 0, comb = 0, cam = 0, ofov = 0, otrans = 0, omat = 0;
  symval("*camera-look-through-other*", &lto);
  symval("*external-cam-mode*", &ext);
  symval("*camera-combiner*", &comb);
  symval("*camera*", &cam);
  symval("*camera-other-fov*", &ofov);
  symval("*camera-other-trans*", &otrans);
  symval("*camera-other-matrix*", &omat);
  printf("A37-CAM f=%llu lto=%d ext=0x%x(s7=0x%x) comb=0x%x cam=0x%x ofov=0x%x otrans=0x%x "
         "omat=0x%x\n",
         (unsigned long long)f, (int)lto, ext, s7.offset, comb, cam, ofov, otrans, omat);
  float mcsan[4] = {0, 0, 0, 0};
  a37_rdf(mc + 0x0, &mcsan[0]);
  a37_rdf(mc + 0x4, &mcsan[1]);
  a37_rdf(mc + 0x14, &mcsan[2]);
  a37_rdf(mc + 0x24, &mcsan[3]);
  printf("A37-CAM f=%llu mc-sanity d=%.1f far=%.1f x-pix=%.1f y-pix=%.1f\n",
         (unsigned long long)f, mcsan[0], mcsan[1], mcsan[2], mcsan[3]);
  if (comb && comb != s7.offset) {
    float cfov = 0.f, ctr[4] = {0, 0, 0, 0}, cir[4] = {0, 0, 0, 0};
    a37_rdf(comb + 0xBC, &cfov);
    for (int k = 0; k < 4; k++) {
      a37_rdf(comb + 0x6C + 4 * k, &ctr[k]);
      a37_rdf(comb + 0x7C + 4 * k, &cir[k]);
    }
    printf("A37-CAM f=%llu comb fov=%.3f trans=(%.1f %.1f %.1f %.1f) invrot0=(%.6f %.6f %.6f "
           "%.6f)\n",
           (unsigned long long)f, cfov, ctr[0], ctr[1], ctr[2], ctr[3], cir[0], cir[1], cir[2],
           cir[3]);
  }
  if (ofov && ofov != s7.offset) {
    float v = 0.f;
    a37_rdf(ofov, &v);
    printf("A37-CAM f=%llu other-fov=%.3f\n", (unsigned long long)f, v);
  }
  if (otrans && otrans != s7.offset) {
    float v[4] = {0, 0, 0, 0};
    for (int k = 0; k < 4; k++) a37_rdf(otrans + 4 * k, &v[k]);
    printf("A37-CAM f=%llu other-trans=(%.1f %.1f %.1f %.1f)\n", (unsigned long long)f, v[0], v[1],
           v[2], v[3]);
  }
  if (omat && omat != s7.offset) {
    float r0[4] = {0, 0, 0, 0}, r3[4] = {0, 0, 0, 0};
    for (int k = 0; k < 4; k++) {
      a37_rdf(omat + 4 * k, &r0[k]);
      a37_rdf(omat + 0x30 + 4 * k, &r3[k]);
    }
    printf("A37-CAM f=%llu other-mat r0=(%.6f %.6f %.6f %.6f) r3=(%.6f %.6f %.6f %.6f)\n",
           (unsigned long long)f, r0[0], r0[1], r0[2], r0[3], r3[0], r3[1], r3[2], r3[3]);
  }
  fflush(stdout);
}

// F1b joint-bone probe (OG_F1B_JB=1): per-tick dump of the title logo
// master + camera-slave joint-chain OUTPUT — nodes 3..5 bone transform
// row3 (world pos) + row0 (rotation) + channel-0 frame-num. Desktop twin
// of the F1B-JB block in android/gk_android_main.cpp; diffing the two
// logs names which stage freezes on-device (GOAL decompress -> master
// bones -> clone -> slave bones -> othercam).
bool f1b_rd32(uint32_t goal, uint32_t* out) {
  if (!g_ee_main_mem || goal < 0x1000 || goal >= (uint32_t)(EE_MAIN_MEM_SIZE - 4)) return false;
  *out = *reinterpret_cast<const uint32_t*>(g_ee_main_mem + goal);
  return true;
}

void f1b_jb_probe_desktop() {
  static int s_enabled = -1;
  if (s_enabled < 0) s_enabled = getenv("OG_F1B_JB") ? 1 : 0;
  if (!s_enabled || g_game_version != GameVersion::Jak1) return;
  static uint64_t s_frame = 0;
  uint64_t f = ++s_frame;
  if (f != 60 && (f % 300) != 0) return;
  auto s_pool = jak1::intern_from_c("*nk-dead-pool*");
  uint32_t pool = s_pool.offset ? s_pool->value : 0;
  if (!pool || pool == s7.offset) return;
  uint32_t cur = 0;
  f1b_rd32(pool + 0x4c + 8, &cur);
  int hops = 0;
  while (cur && cur != s7.offset && hops++ < 8192) {
    uint32_t proc = 0, next = 0;
    if (!f1b_rd32(cur, &proc) || !f1b_rd32(cur + 8, &next)) break;
    if (proc && proc != s7.offset) {
      uint32_t namep = 0;
      f1b_rd32(proc + 0, &namep);
      char nm[40] = {0};
      // Process names are GOAL symbols — resolve via the symbol table
      // (same rule as gk_android_main.cpp's a40_sym_name).
      if (SymbolTable2.offset && LastSymbol.offset && namep >= SymbolTable2.offset &&
          namep < LastSymbol.offset && !(namep & 3)) {
        uint64_t info = static_cast<uint64_t>(namep) + jak1::SYM_INFO_OFFSET;
        if (info + 8 < EE_MAIN_MEM_SIZE) {
          uint32_t str_off = *reinterpret_cast<const uint32_t*>(g_ee_main_mem + info + 4);
          if (str_off && static_cast<uint64_t>(str_off) + 4 + sizeof(nm) < EE_MAIN_MEM_SIZE) {
            const char* sp = reinterpret_cast<const char*>(g_ee_main_mem + str_off + 4);
            size_t i = 0;
            for (; i + 1 < sizeof(nm) && sp[i]; i++) {
              nm[i] = (sp[i] >= 0x20 && sp[i] <= 0x7e) ? sp[i] : '?';
            }
            nm[i] = 0;
          }
        }
      }
      if (!strcmp(nm, "logo") || !strcmp(nm, "logo-slave")) {
        uint32_t nl = 0, skel = 0;
        f1b_rd32(proc + 112, &nl);    // process-drawable.node-list (deftype 116)
        f1b_rd32(proc + 120, &skel);  // .skel (deftype 124)
        float fnum = 0.f;
        uint32_t fg = 0;
        if (skel && skel != s7.offset) {
          uint32_t w = 0;
          f1b_rd32(skel + 56, &fg);  // channel0.frame-group (deftype 60)
          f1b_rd32(skel + 60, &w);   // channel0.frame-num (deftype 64)
          memcpy(&fnum, &w, 4);
        }
        // F1B-FG: channel-0 frame-group identity — art NAME is a GOAL
        // STRING (chars at name+4). Twin of the device block.
        if (fg && fg != s7.offset) {
          uint32_t fgnamep = 0;
          f1b_rd32(fg + 4, &fgnamep);  // art.name string (deftype 8)
          char fgs[48] = {0};
          if (fgnamep > 0x1000 && fgnamep < (uint32_t)(EE_MAIN_MEM_SIZE - 64)) {
            const char* sp2 = reinterpret_cast<const char*>(g_ee_main_mem + fgnamep + 4);
            size_t si = 0;
            for (; si + 1 < sizeof(fgs) && sp2[si]; si++) {
              fgs[si] = (sp2[si] >= 0x20 && sp2[si] <= 0x7e) ? sp2[si] : '?';
            }
            fgs[si] = 0;
          }
          uint32_t frames = 0, nf = 0, fixedp = 0, fr0 = 0, cb0 = 0, cb1 = 0, nj = 0, mb = 0;
          f1b_rd32(fg + 40, &frames);  // art-joint-anim.frames (deftype 44)
          if (frames && frames != s7.offset) {
            f1b_rd32(frames + 0, &nf);
            f1b_rd32(frames + 12, &fixedp);
            f1b_rd32(frames + 16, &fr0);
            if (fixedp) {
              f1b_rd32(fixedp + 0, &cb0);
              f1b_rd32(fixedp + 4, &cb1);
              f1b_rd32(fixedp + 56, &nj);
              f1b_rd32(fixedp + 60, &mb);
            }
          }
          printf("F1B-FG f=%llu %s proc=0x%x fg=0x%x name='%s' fnum=%.2f frames=0x%x nf=%d "
                 "fixed=0x%x fr0=0x%x cb=0x%08x/0x%08x nj=%d mb=0x%x\n",
                 (unsigned long long)f, nm, proc, fg, fgs[0] ? fgs : "?", fnum, frames, (int)nf,
                 fixedp, fr0, cb0, cb1, (int)nj, mb);
        }
        uint32_t nlen = 0;
        if (nl && nl != s7.offset) f1b_rd32(nl + 0, &nlen);  // cspace-array.length (deftype 4)
        for (int n = 3; n <= 5 && (uint32_t)n < nlen; n++) {
          uint32_t csp = nl + 12 + 32 * n;  // data (deftype 16), cspace stride 32
          uint32_t jw = 0, bone = 0, p0 = 0;
          f1b_rd32(csp + 8, &jw);  // joint-num int16 (deftype 12)
          f1b_rd32(csp + 16, &bone);
          f1b_rd32(csp + 20, &p0);
          float r3[3] = {0, 0, 0}, r0[3] = {0, 0, 0};
          if (bone > 0x1000 && bone < (uint32_t)(EE_MAIN_MEM_SIZE - 64)) {
            for (int k = 0; k < 3; k++) {
              uint32_t w2 = 0;
              f1b_rd32(bone + 48 + 4 * k, &w2);
              memcpy(&r3[k], &w2, 4);
              f1b_rd32(bone + 4 * k, &w2);
              memcpy(&r0[k], &w2, 4);
            }
          }
          printf("F1B-JB f=%llu %s proc=0x%x fnum=%.2f n%d j%d bone=0x%x p0=0x%x "
                 "r3=(%.1f %.1f %.1f) r0=(%.4f %.4f %.4f)\n",
                 (unsigned long long)f, nm, proc, fnum, n, (int)(int16_t)(jw & 0xffff), bone, p0,
                 r3[0], r3[1], r3[2], r0[0], r0[1], r0[2]);
        }
      }
    }
    cur = next;
  }
  fflush(stdout);
}
}  // namespace

/*!
 * Wait for rendering to complete.
 * In the PC Port, this currently does nothing.
 *
 * From my current understanding, we can get away with this and just sync everything on vsync.
 * However, there are two calls to this per frame.
 *
 * But I don't fully understand why they call sceGsSyncPath where they do (right before depth cue)
 * so maybe the depth cue looks at the z-buffer of the last rendered frame when setting up the dma
 * for the next frame?  The debug drawing also happens after this.
 *
 * The second call is right before swapping buffers/vsync, so that makes sense.
 *
 *
 */
u32 sceGsSyncPath(u32 mode, u32 timeout) {
  ASSERT(mode == 0 && timeout == 0);
  return Gfx::sync_path();
}

/*!
 * Actual vsync.
 */
u32 sceGsSyncV(u32 mode) {
  ASSERT(mode == 0);
  a37_cam_probe_desktop();
  f1b_jb_probe_desktop();
  return Gfx::vsync();
}
