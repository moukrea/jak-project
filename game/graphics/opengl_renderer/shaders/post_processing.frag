#version 410 core

// post_processing.frag — le quad final vers la fenetre.
//
// u_out_mode = 0 : la recopie d'origine (brightness/contrast via color_mult/color_add), au bit.
// u_out_mode = 1 : hdr-display-output. La surface est HDR10 (BT.2020, PQ, 10 bits). Le tampon UI
//   porte l'encodage d'affichage du jeu (celui de la PS2, ~gamma 2,2), avec des valeurs
//   au-dessus de 1,0 laissees par le tone map (plafond = marge de l'ecran). Ici on ENCODE, on ne
//   comprime pas : linearisation, blanc de reference en nits (BT.2408 : 203), primaires
//   BT.709 -> BT.2020, OETF PQ (SMPTE ST 2084). Aucune epaule, aucun plafond : la seule
//   compression de plage de la chaine reste tonemap.frag.

uniform sampler2D tex_T0;
out vec4 color;
in vec2 tex_coord;

uniform vec4 color_mult;
uniform vec4 color_add;
uniform int u_out_mode;
uniform float u_out_paper_white;
uniform float u_out_max_nits;

vec3 pq_oetf(vec3 nits) {
  const float m1 = 0.1593017578125;
  const float m2 = 78.84375;
  const float c1 = 0.8359375;
  const float c2 = 18.8515625;
  const float c3 = 18.6875;
  vec3 y = max(nits, vec3(0.0)) / 10000.0;
  vec3 ym = pow(y, vec3(m1));
  return pow((vec3(c1) + c2 * ym) / (vec3(1.0) + c3 * ym), vec3(m2));
}

void main() {
  vec3 base = texture(tex_T0, tex_coord).rgb * color_mult.rgb * color_mult.a;
  if (u_out_mode == 1) {
    vec3 v = base + color_add.rgb;
    vec3 lin = pow(max(v, vec3(0.0)), vec3(2.2));
    // BT.709 -> BT.2020 (colonnes = contributions de R, G, B 709).
    const mat3 to2020 = mat3(0.6274, 0.0691, 0.0164,
                             0.3293, 0.9195, 0.0880,
                             0.0433, 0.0114, 0.8956);
    vec3 nits = to2020 * (lin * u_out_paper_white);
    color = vec4(pq_oetf(nits), 1.0);
  } else {
    color = vec4(base, 1.0) + color_add;
  }
}
