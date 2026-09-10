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
// hdr-display-output, refus owner du 10/09 (« quasi 0 diff entre off vs on ... juste un yota au
// niveau des trucs qui brillent »). LE PLAFOND SEUL NE SUFFIT PAS : avec la courbe SDR appliquee
// sur [0, plafond], tout ce qui est sous 0,96 x plafond (= 1,387 pour un plafond de 1,445)
// traverse a l'IDENTIQUE. Seuls les pixels deja au-dessus de 1,387 changeaient — un yota.
// La sortie HDR a donc sa PROPRE courbe : au lieu de comprimer, elle ETIRE la fenetre
// [ancre, sommet] de la scene vers [ancre, plafond]. Trois parametres, tous pilotes par le
// CONTENU de la scene image par image (adaptation facon Dolby Vision, pas un filtre unique) :
//   u_hdr_anchor : ou l'etirement commence. En dessous, la sortie est BIT A BIT celle du SDR.
//   u_hdr_top    : la valeur de scene qui sort AU plafond. Borne a <= plafond cote C++ ; cette
//                  borne est ce qui garantit une pente >= ... voir hdr_expand.
//   u_hdr_toe    : relevement du PIED, pour le detail des ombres. Nul en scene claire.
// u_hdr_anchor >= 1,0 (ou plafond == 1,0) => l'ancien chemin, strictement inchange.
uniform float u_hdr_anchor;
uniform float u_hdr_top;
uniform float u_hdr_toe;

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

// L'ETIREMENT DES HAUTES LUMIERES. Cubique de Hermite sur t = (x-a)/(T-a), avec
//   f(0)=0, f(1)=1, f'(0)=p, f'(1)=0   ou p = (T-a)/(C-a)
// soit f(t) = p.t + (3-2p).t^2 + (p-2).t^3. Trois proprietes, toutes voulues :
//   * pente 1 EXACTEMENT a l'ancre — aucun coude, aucun contour visible a la jointure ;
//   * pente 0 au sommet — le plafond est atteint tangentiellement, l'ecretage au-dela est C1 ;
//   * f(t) - p.t = t^2.[(3-2p) + (p-2).t] > 0 pour p <= 1 : la sortie n'est JAMAIS sous
//     l'identite, donc jamais sous le SDR (qui est <= identite partout). C'est la raison de la
//     borne T <= C posee cote C++ : elle rend l'assombrissement IMPOSSIBLE, pas seulement rare.
// Chaque canal s'etire seul : une haute lumiere coloree garde sa couleur au lieu de blanchir.
vec3 hdr_expand(vec3 x, float a, float T, float C) {
  float r = max(C - a, 1e-4);
  float w = max(T - a, 1e-4);
  float p = clamp(w / r, 1e-3, 1.0);
  for (int c = 0; c < 3; c++) {
    float v = x[c];
    if (v <= a) {
      continue;
    }
    if (v >= T) {
      x[c] = C;
      continue;
    }
    float t = (v - a) / w;
    x[c] = a + r * (p * t + (3.0 - 2.0 * p) * t * t + (p - 2.0) * t * t * t);
  }
  return x;
}

// LE PIED. Releve les ombres sans toucher au noir : l'apport est v.(1 - v/s)^2, nul en 0 (le
// noir reste noir, pas de voile laiteux) et nul en s avec une derivee continue. Toujours >= 0 :
// un relevement ne peut pas assombrir.
vec3 hdr_toe_lift(vec3 x, float amt) {
  const float s = 0.25;
  for (int c = 0; c < 3; c++) {
    float v = x[c];
    if (v > 0.0 && v < s) {
      float u = 1.0 - v / s;
      x[c] = v + amt * v * u * u;
    }
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
  vec3 c = max(src.rgb * u_hdr_exposure, vec3(0.0));
  if (ceiling > 1.0 && u_hdr_anchor > 0.0 && u_hdr_anchor < 1.0 && u_hdr_top > u_hdr_anchor) {
    // SORTIE HDR : on ETIRE, on ne comprime pas. Toujours une seule compression de plage dans
    // la chaine — celle-ci n'en est pas une, elle est bornee par le plafond de l'ecran.
    c = hdr_expand(c, u_hdr_anchor, u_hdr_top, ceiling);
    c = hdr_toe_lift(c, u_hdr_toe);
    // L'alpha traverse INTACT : la passe 2D qui suit melange contre le dst-alpha de ce tampon.
    color = vec4(min(c, vec3(ceiling)), src.a);
  } else {
    c = c / ceiling;
    c = (u_hdr_curve == 1) ? hdr_neutral(c) : hdr_shoulder(c, u_hdr_knee);
    color = vec4(min(c, vec3(1.0)) * ceiling, src.a);
  }
}
