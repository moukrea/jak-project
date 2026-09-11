#version 410 core

// post_processing.frag — le quad final vers la fenetre.
//
// u_out_mode = 0 : la recopie d'origine (brightness/contrast via color_mult/color_add), au bit.
// u_out_mode = 1 : hdr-display-output, HDR10 (BT.2020, PQ, 10 bits). Le tampon UI porte
//   l'encodage d'affichage du jeu (celui de la PS2, ~gamma 2,2), avec des valeurs au-dessus de
//   1,0 laissees par le tone map (plafond = marge de l'ecran). Ici on ENCODE, on ne comprime
//   pas : linearisation, blanc de reference `u_out_paper_white` en nits — LE BLANC SDR DU
//   SYSTEME (HdrCapabilities.maxLuminance sur les API < 34, qui recomposent le PQ en SDR a cette
//   echelle), jamais 203 nits : c'est ce qui rendait l'UI grise le 09/09 — primaires
//   BT.709 -> BT.2020, OETF PQ (SMPTE ST 2084). Aucune epaule, aucun plafond : la seule
//   compression de plage de la chaine reste tonemap.frag.
// u_out_mode = 2 : hdr-display-output, scRGB LINEAIRE (RGBA16F, Android 14+). Contrat du
//   compositeur : 1,0 = le blanc SDR courant de l'ecran, au-dessus = la marge accordee
//   (setExtendedRangeBrightness). Primaires BT.709 inchangees, pas d'OETF : seulement la
//   linearisation gamma 2,2 du tampon. `u_out_paper_white` vaut 1,0 ici.
// u_out_mode = 3 : hdr-display-output, BT.2020 HLG (ARIB STD-B67 / BT.2100). Transport de repli
//   pour les ecrans qui n'annoncent QUE HLG (verdict 13 : HDR10+ > HDR10 > HLG). Meme chaine que
//   le mode 1 — linearisation gamma 2,2, primaires BT.709 -> BT.2020 — mais HLG est RELATIF et
//   scene-referred : aucun nits ne traverse. Le signal encode E est dans [0,1] ou 1,0 = le pic
//   de l'ecran, et `u_out_paper_white` est donc ici la FRACTION de ce pic qu'occupe le blanc du
//   jeu (1,0 = le blanc du jeu sort AU pic). L'OETF est celle d'ARIB STD-B67, pas PQ.

uniform sampler2D tex_T0;
out vec4 color;
in vec2 tex_coord;

uniform vec4 color_mult;
uniform vec4 color_add;
uniform int u_out_mode;
uniform float u_out_paper_white;
uniform float u_out_max_nits;

// BT.709 -> BT.2020 (colonnes = contributions de R, G, B 709). Partagee par les modes 1 et 3.
const mat3 kBt709ToBt2020 = mat3(0.6274, 0.0691, 0.0164,
                                 0.3293, 0.9195, 0.0880,
                                 0.0433, 0.0114, 0.8956);

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

// OETF HLG (ARIB STD-B67 / BT.2100, table 5). E dans [0,1] (1 = pic de l'ecran) :
//   E' = sqrt(3E)/2                pour 0 <= E <= 1/12
//   E' = a.ln(12E - b) + c         au-dessus.
// `log` de GLSL est le logarithme NATUREL : c'est bien celui que la norme demande.
vec3 hlg_oetf(vec3 e) {
  const float a = 0.17883277;
  const float b = 0.28466892;
  const float c = 0.55991073;
  vec3 E = clamp(e, vec3(0.0), vec3(1.0));
  vec3 lo = sqrt(3.0 * E) * 0.5;
  vec3 hi = a * log(max(12.0 * E - b, vec3(1e-6))) + c;
  vec3 Ep = mix(hi, lo, vec3(lessThanEqual(E, vec3(1.0 / 12.0))));
  return clamp(Ep, vec3(0.0), vec3(1.0));
}

void main() {
  vec3 base = texture(tex_T0, tex_coord).rgb * color_mult.rgb * color_mult.a;
  if (u_out_mode == 1) {
    vec3 v = base + color_add.rgb;
    vec3 lin = pow(max(v, vec3(0.0)), vec3(2.2));
    vec3 nits = kBt709ToBt2020 * (lin * u_out_paper_white);
    color = vec4(pq_oetf(nits), 1.0);
  } else if (u_out_mode == 3) {
    // HLG : meme lineaire, memes primaires, mais l'echelle est RELATIVE au pic de l'ecran.
    vec3 v = base + color_add.rgb;
    vec3 lin = pow(max(v, vec3(0.0)), vec3(2.2));
    vec3 e = kBt709ToBt2020 * (lin * u_out_paper_white);
    color = vec4(hlg_oetf(e), 1.0);
  } else if (u_out_mode == 2) {
    vec3 v = base + color_add.rgb;
    color = vec4(pow(max(v, vec3(0.0)), vec3(2.2)) * u_out_paper_white, 1.0);
  } else {
    color = vec4(base, 1.0) + color_add;
  }
}
