#version 410 core

// tonemap.frag — LE SITE UNIQUE d'application du tone map (SPEC-refonte-lumiere §4.5, P9).
//
// Ce que ce shader fait, et surtout ce qu'il ne fait PAS.
// -------------------------------------------------------
// Le tampon de scene de ce moteur porte les couleurs dans l'encodage d'affichage du jeu
// (celui de la PS2) : chaque renderer y ecrit deja des valeurs pretes a afficher, et le
// melange (additif, soustractif, dst-alpha) est defini dans cet espace. Passer le tampon en
// RGBA16F ne change PAS cet encodage — il enleve seulement le plafond a 1,0. Ce shader n'est
// donc pas une OETF : il ne linearise rien et ne re-encode rien. Il fait UNE chose, la
// compression de plage, et il est le seul endroit de la chaine d'affichage a la faire.
//
// Epaule SDR a blanc fini : avec w=1-k et a=x-k, f=k+a-a*a/(4*w)
// entre k et k+2*w, puis 1. La pente rejoint 1 au genou et 0 au blanc.
// L'asymptote rationnelle exigeait x>2.2 pour retrouver du blanc 8 bits a k=.95,
// meme pour les effets additifs dont le blanc de reference du jeu est 1.
// Chaque canal est comprime independamment :
// un canal au-dessus du genou ne reduit pas la contribution des autres canaux.
//
// La courbe « Filmique » (Khronos PBR Neutral) est optionnelle et jamais le defaut. Elle est
// definie pour une entree LINEAIRE ; tant que le tampon reste en encodage d'affichage elle
// est fournie comme reglage, pas comme recommandation.
//
// @tonemap-site : marqueur lu par le recensement de `hdr.cpp`. Tout AUTRE programme fragment
// qui porterait une compression de plage ferait monter `tonemap_sites` au-dessus de 1.

uniform sampler2D tex_T0;
uniform float u_hdr_exposure;
uniform float u_hdr_knee;
uniform int u_hdr_curve;  // 0 = Fidelite (epaule C1), 1 = Filmique (Khronos PBR Neutral)
// hdr-display-output : LE PLAFOND. 1,0 en sortie SDR (rien ne change, division par 1,0 exacte).
// En sortie HDR vers l'ecran, c'est la marge de l'ecran au-dessus du blanc de reference
// (max_lum / paper_white, ~2,5 pour 500 nits) : la MEME courbe, appliquee sur [0, plafond],
// laisse les hautes lumieres monter au lieu de les ecraser a 1,0. Toujours une seule
// compression de plage, ici ; le quad final n'encode que (OETF PQ).
uniform float u_hdr_ceiling;

out vec4 color;
in vec2 tex_coord;

vec3 hdr_shoulder(vec3 x, float k) {
  float w = max(1.0 - k, 1e-4);
  for (int c = 0; c < 3; c++) {
    if (x[c] <= k) {
      continue;
    }
    float above = x[c] - k;
    x[c] = above >= 2.0 * w ? 1.0 : k + above - above * above / (4.0 * w);
  }
  return x;
}

vec3 hdr_neutral(vec3 c) {
  const float kStart = 0.76;
  const float kDesat = 0.15;
  float x = min(c.r, min(c.g, c.b));
  float offset = x < 0.08 ? x - 6.25 * x * x : 0.04;
  c -= vec3(offset);
  float peak = max(c.r, max(c.g, c.b));
  if (peak < kStart) {
    return c;
  }
  float d = 1.0 - kStart;
  float newPeak = 1.0 - d * d / (peak + d - kStart);
  c *= newPeak / max(peak, 1e-5);
  float g = 1.0 - 1.0 / (kDesat * (peak - newPeak) + 1.0);
  return mix(c, vec3(newPeak), g);
}

void main() {
  vec4 src = texture(tex_T0, tex_coord);
  float ceiling = max(u_hdr_ceiling, 1.0);
  vec3 c = max(src.rgb * u_hdr_exposure, vec3(0.0)) / ceiling;
  c = (u_hdr_curve == 1) ? hdr_neutral(c) : hdr_shoulder(c, u_hdr_knee);
  // L'alpha traverse INTACT : la passe 2D qui suit melange contre le dst-alpha de ce tampon.
  color = vec4(min(c, vec3(1.0)) * ceiling, src.a);
}
