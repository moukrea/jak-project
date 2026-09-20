// grass_contact_dir.glsl — LA LOI DE CONTACT ORIENTEE (SPEC refonte-herbe, section 11).
//
// CE CHUNK EST COMPILE DEUX FOIS. Le pilote le splice dans `vegetation_contact.glsl` ; le C++ le
// `#include` derriere `common/util/glsl_compat.h` (`GrassBakeCore.cpp`). C'est le MEME TEXTE des
// deux cotes : la porte qui publie l'angle de flexion ne mesure donc pas un miroir, elle mesure
// la loi que le pilote execute. Un recalcul C++ de la loi serait exactement l'erreur que
// `glsl_compat.h` existe pour interdire.
//
// SOUS-ENSEMBLE COMMUN, ET POURQUOI. Pas de swizzle (`.xz` n'a pas d'equivalent C++ portable).
// Pas de `abs`, pas de `min`, pas de `max` : `<cmath>` pose leurs homonymes au niveau global et
// l'appel non qualifie deviendrait AMBIGU sous le `using namespace glsl`. Pas de
// `normalize(mix(...))` : ce motif se miscompile sur l'Adreno 618 (SPEC section 0), la division
// est ecrite en clair et gardee. Aucun tableau, donc aucune lecture a index dynamique.
//
// LE CONTRAT
//   gcd_d     brin MOINS point de contact, plan XZ, unites de jeu (4096 = 1 m).
//   gcd_dir   cap du deplacement, XZ, UNITAIRE. L'appelant le garantit ; (0,0) retombe sur (1,0).
//   gcd_speed 0 = loi radiale d'origine, 1 = pleine orientation. Rien entre les deux n'est interdit.
//   gcd_R     rayon de contact.
//   gcd_str   force temporelle de l'echantillon (fondu d'altitude x force de trainee).
//   rend      x = flexion 0..1 ; yz = direction unitaire de poussee, plan XZ.
//
// LE REPLI EST EXACT, PAS APPROCHE. A `gcd_speed = 0` : les deux rayons valent `gcd_R`, la base
// (gcd_u, gcd_perp) est orthonormee donc `gcd_ns^2 + gcd_nt^2 = |gcd_d|^2 / gcd_R^2` et la
// flexion redevient `(1 - |d|/R) * str` ; le poids `gcd_w` est nul donc la poussee redevient
// radiale. C'est le repli que l'item doit aux paliers bas — il est egal, pas seulement proche.
vec3 grass_contact_dir(vec2 gcd_d, vec2 gcd_dir, float gcd_speed, float gcd_R, float gcd_str) {
  const float GCD_AHEAD = 0.55;   // l'empreinte s'allonge DEVANT le pas
  const float GCD_BEHIND = 0.30;  // et se raccourcit derriere : ce n'est plus un disque
  const float GCD_SIDE = 0.18;    // et se resserre sur les cotes
  const float GCD_LEAN = 0.85;    // part de la poussee qui suit le pas au lieu de fuir le centre
  const float GCD_SPLAY = 1.35;   // degagement lateral, croissant avec l'ecart a l'axe du pas
  // Un uniforme jamais televerse vaut (0,0) : sans ce garde la base ne serait pas orthonormee et
  // TOUT le rayon flechirait a fond. Un cap unitaire donne exactement 1.0, donc le garde ne mord
  // jamais sur une entree valide.
  float gcd_dd = dot(gcd_dir, gcd_dir);
  vec2 gcd_u = gcd_dd > 0.5 ? gcd_dir : vec2(1.0, 0.0);
  vec2 gcd_perp = vec2(-gcd_u.y, gcd_u.x);
  float gcd_s = dot(gcd_d, gcd_u);
  float gcd_t = dot(gcd_d, gcd_perp);
  float gcd_side = gcd_t < 0.0 ? -1.0 : 1.0;
  float gcd_rs = gcd_R * (1.0 + (gcd_s < 0.0 ? -GCD_BEHIND : GCD_AHEAD) * gcd_speed);
  float gcd_rt = gcd_R * (1.0 - GCD_SIDE * gcd_speed);
  float gcd_ns = gcd_s / gcd_rs;
  float gcd_nt = gcd_t / gcd_rt;
  float gcd_q = length(vec2(gcd_ns, gcd_nt));
  float gcd_k = (1.0 - clamp(gcd_q, 0.0, 1.0)) * gcd_str;
  float gcd_dl = length(gcd_d);
  vec2 gcd_radial = gcd_dl > 1.0 ? gcd_d / gcd_dl : vec2(0.0, 1.0);
  // LE DEGAGEMENT LATERAL. `gcd_nt * gcd_side` est la valeur absolue de l'ecart a l'axe du pas,
  // ecrite sans `abs`. `gcd_f` vaut 0 sur l'axe et 1 au bord, et la visee TOURNE entre les deux :
  // droit devant pour le brin que Jak enjambe, PLEINEMENT DE COTE pour celui qu'il epaule. C'est
  // le « glissement lateral proportionnel a la distance au centre du contact » de la SPEC.
  // Une visee `gcd_u + gcd_lat` plafonnait a 45 degres et rendait la loi MOINS laterale que le
  // disque qu'elle remplace : la porte etait verte sous les deux regimes, donc elle ne mesurait
  // rien. Ici le bord atteint la perpendiculaire, et l'ecart au disque se mesure brin a brin.
  float gcd_f = clamp(gcd_nt * gcd_side * GCD_SPLAY, 0.0, 1.0);
  vec2 gcd_aim = gcd_u * (1.0 - gcd_f) + gcd_perp * (gcd_side * gcd_f);
  float gcd_w = GCD_LEAN * gcd_speed;
  vec2 gcd_m = gcd_radial * (1.0 - gcd_w) + gcd_aim * gcd_w;
  float gcd_ml = length(gcd_m);
  vec2 gcd_push = gcd_ml > 0.0001 ? gcd_m / gcd_ml : gcd_radial;
  return vec3(gcd_k, gcd_push.x, gcd_push.y);
}
