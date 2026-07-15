#version 410 core

// Grecharged-grass-poc: flat-color grass (no texture yet, per the PoC spec).
// NEAR blades render solid. MID cards are procedurally cut into a TUFT of blades
// (owner polish 2026-07-10): the card was a translucent rectangle that read as a
// "blurry square" and — because a blended quad still wrote depth — sometimes
// showed as a hollow "empty square". Cutting the card into blade shapes and
// DISCARDING the gaps fixes both: it reads as a bushy grass clump and the gaps
// no longer write depth, so the crossed quad shows through instead of a hole.

in vec3 v_color;
in float v_alpha;
in vec2 v_uv;            // card-local coords (x in [-1,1], y in [0,1]); class-2 = hang-texture UV
flat in int v_is_card;
in float v_seed;         // class-2 cards: hang-texture select (0/1) instead of the tuft seed

// Grecharged-grass-overhang7 ROUND 11 (design pivot): zone-3 hang cards sample the game's OWN
// hang-alpha texels — the exact texture pages the native painted strip uses (already resident).
uniform sampler2D u_hang0;  // bch-grassfringe
uniform sampler2D u_hang1;  // bch-leafyground-hang-2x1

out vec4 color;

void main() {
  float a = v_alpha;

  if (v_is_card == 2) {
    // ZONE-3 TEXTURED HANG CARD: alpha-cut sampling of the native strip texels, so the card IS the
    // game's own art (crisp ragged tips, no soft halo). u tiles along the lip (wrap); v is clamped
    // in-shader (the shared level texture object's wrap state must not be touched — tfrag uses it).
    vec2 uv = vec2(v_uv.x, clamp(v_uv.y, 0.002, 0.998));
    vec4 tx = mix(texture(u_hang0, uv), texture(u_hang1, uv), clamp(v_seed, 0.0, 1.0));
    if (tx.a < 0.45 || a < 0.02) {
      discard;
    }
    // v_color = the ground's dynamic baked light (*2 factor), matching the native strip's own draw.
    color = vec4(tx.rgb * v_color, a);
    return;
  }

  if (v_is_card == 1) {
    // Cut the card quad into a few vertical sub-blades so it reads as a tuft.
    // Each sub-blade fills its slot at the base and tapers to a point; the top
    // edge is jagged (random per-blade height) so the clump never looks like a
    // rectangle. Fragments outside a blade are discarded (no color, no depth).
    // OWNER POLISH#6: 5 -> 3 sub-blades so the cards are LESS tufted than the near
    // grass (owner: cards "font beaucoup plus touffue que la vraie herbe").
    const float NB = 3.0;
    float fu = (v_uv.x * 0.5 + 0.5) * NB;        // 0..NB across the card width
    float bi = floor(fu);
    float fp = fu - bi;                           // 0..1 within this sub-blade slot
    float r = fract(sin((bi + 1.0) * 12.9898 + v_seed) * 43758.5453);
    float bladeTop = 0.55 + 0.45 * r;             // this sub-blade's height (0.55..1.0)
    if (v_uv.y > bladeTop) {
      discard;
    }
    float hw = 0.5 * (1.0 - v_uv.y / bladeTop);   // half width in slot units, taper to tip
    float dc = abs(fp - 0.5);
    if (dc > hw) {
      discard;
    }
  }

  if (a < 0.02) {
    discard;
  }
  color = vec4(v_color, a);
}
