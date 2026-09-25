// lighting-local-lights (SPEC-refonte-lumiere §4.9) : les lumieres locales (lampes, torches, lave).
// Lu UNIQUEMENT sous `u_lighting_on != 0 && u_ll_on != 0` (shade_body) : master OFF et
// recharged_lighting OFF ne l'evaluent jamais, l'origine reste bit-identique.
//
// La grille est remplie sur le FIL DE RENDU (ClusterGrid.cpp), une fois par image : grille alignee
// monde, centree camera, cellules cubiques de `1/u_ll_inv_cell` metres. Trois textures lues par
// texelFetch (jamais filtrees) :
//   u_ll_lights  RGBA32F  4 texels par lumiere :
//                  [pos relative camera (m), rayon (m)]
//                  [couleur x intensite x vacillement x gain, type (0 point, 1 cone, 2 surface)]
//                  [direction (cone : axe ; surface : normale), cos exterieur]
//                  [cos interieur, 0, 0, 0]
//   u_ll_cells   RG32F   par cellule : (debut dans l'index, nombre)  — 128 texels par ligne
//   u_ll_index   R32F    numeros de lumiere                          — 1024 texels par ligne
uniform int u_ll_on;
uniform int u_ll_proof;       // 1 sur l'image sondee : shade() sort un DRAPEAU (vert = eclaire)
uniform vec3 u_ll_origin;     // coin min de la grille, relatif camera, metres
uniform float u_ll_inv_cell;  // 1 / cote d'une cellule (m)
uniform ivec3 u_ll_dims;
uniform sampler2D u_ll_lights;  // unite 4
uniform sampler2D u_ll_cells;   // unite 5
uniform sampler2D u_ll_index;   // unite 6

// Au plus 16 lumieres par cellule (ClusterGrid.cpp publie `ll_cell_overflow` quand il en coupe).
const int LL_MAX_PER_CELL = 16;

// Eclairement recu en P (relatif camera, m) de normale N. Attenuation §4.9 : inverse du carre,
// plafond de proximite a 0,5 m, coupure lisse (1 - (d/r)^4)^2 : rien au-dela du rayon qui a servi
// a ranger la lumiere, donc le rangement par cellule est exact.
vec3 ll_irradiance(vec3 P, vec3 N) {
  vec3 E = vec3(0.0);
  ivec3 c = ivec3(floor((P - u_ll_origin) * u_ll_inv_cell));
  if (any(lessThan(c, ivec3(0))) || any(greaterThanEqual(c, u_ll_dims))) {
    return E;
  }
  int ci = c.x + u_ll_dims.x * (c.y + u_ll_dims.y * c.z);
  vec2 oc = texelFetch(u_ll_cells, ivec2(ci & 127, ci >> 7), 0).rg;
  int off = int(oc.x + 0.5);
  int cnt = min(int(oc.y + 0.5), LL_MAX_PER_CELL);
  for (int i = 0; i < cnt; i++) {
    int k = off + i;
    int li = int(texelFetch(u_ll_index, ivec2(k & 1023, k >> 10), 0).r + 0.5);
    vec4 a = texelFetch(u_ll_lights, ivec2(li * 4, 0), 0);
    vec3 Lv = a.xyz - P;
    float d2 = dot(Lv, Lv);
    float r2 = a.w * a.w;
    if (d2 >= r2) {
      continue;
    }
    vec4 b = texelFetch(u_ll_lights, ivec2(li * 4 + 1, 0), 0);
    vec3 L = Lv * inversesqrt(max(d2, 1e-8));
    float x2 = d2 / r2;
    float win = 1.0 - x2 * x2;
    float att = win * win / max(d2, 0.25);
    // Enroulement leger (regle 3, stylisation) : la face qui tourne le dos a la lampe garde un
    // liseré au lieu d'une coupure nette.
    float geo = clamp((dot(N, L) + 0.2) / 1.2, 0.0, 1.0);
    int type = int(b.w + 0.5);
    if (type != 0) {
      vec4 e = texelFetch(u_ll_lights, ivec2(li * 4 + 2, 0), 0);
      float cd = dot(e.xyz, -L);
      if (type == 1) {
        float ci_ = texelFetch(u_ll_lights, ivec2(li * 4 + 3, 0), 0).x;
        geo *= smoothstep(e.w, max(ci_, e.w + 1e-4), cd);
      } else {
        // surface plate (lave) : l'emetteur rayonne vers son demi-espace, jamais par-dessous.
        geo *= 0.25 + 0.75 * max(cd, 0.0);
      }
    }
    E += b.rgb * (att * geo);
  }
  return E;
}
