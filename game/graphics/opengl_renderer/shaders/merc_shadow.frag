#version 410 core
// lighting-shadows essai 10 : fondu d'un acteur en bout de portee d'ombre. Trame ordonnee 4x4
// (sans hash flottant : exacte en mediump) ; le PCF 16 taps de la lecture la moyenne en demi-teinte.
// 1.0 = draw plein (le cas general, aucun fragment rejete).
uniform float u_merc_shadow_fade;
const float BAYER4[16] = float[16](0.0, 8.0, 2.0, 10.0, 12.0, 4.0, 14.0, 6.0,
                                   3.0, 11.0, 1.0, 9.0, 15.0, 7.0, 13.0, 5.0);
void main() {
  if (u_merc_shadow_fade < 0.999) {
    int ix = int(gl_FragCoord.x) & 3;
    int iy = int(gl_FragCoord.y) & 3;
    if ((BAYER4[iy * 4 + ix] + 0.5) / 16.0 >= u_merc_shadow_fade) {
      discard;
    }
  }
}
