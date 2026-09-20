#pragma once

// glsl_compat.h — LE MINIMUM DE GLSL QU'UN COMPILATEUR C++ SAIT LIRE.
//
// POURQUOI. `game/graphics/opengl_renderer/shaders/grass_shade.glsl` et
// `grass_shade_face.glsl` portent le modele de couleur de l'herbe. La porte de l'item
// `grass-shading` doit publier l'ecart de luminance entre la racine et la pointe d'un brin, et
// entre ses deux faces : des grandeurs que seul ce modele produit. Le recalculer en C++ aurait
// fabrique un MIROIR — deux textes libres de diverger, dont la mesure n'aurait decrit que la
// copie. On compile donc le MEME FICHIER une seconde fois, en C++, derriere cet en-tete.
//
// CE QU'IL EST, ET SURTOUT CE QU'IL N'EST PAS. Ce n'est pas une bibliotheque de math : c'est le
// sous-ensemble EXACT que les chunks partages emploient (vec2, vec3, mix, clamp, max, dot,
// fract, sin, cos).
// Rien n'y entre qu'un chunk partage n'utilise. Un chunk qui aurait besoin d'autre chose doit
// AJOUTER ici la fonction correspondante, jamais contourner par une copie C++.
//
// LES DEUX LANGAGES NE SONT PAS LE MEME. GLSL evalue `0.72 * x` en float, C++ en double avant de
// retomber en float : les deux resultats different de quelques ULP. Les grandeurs que la porte
// lit sont des ECARTS DE LUMINANCE compares a des planchers de l'ordre du centieme — la
// difference est de six ordres de grandeur en dessous. Aucune comparaison au bit n'est faite
// entre les deux compilations, et aucune ne doit l'etre.
//
// SANS SWIZZLE. Les chunks partages s'ecrivent en `.x/.y/.z`, jamais en `.r/.g/.b` ni en `.rgb` :
// un swizzle GLSL n'a pas d'equivalent C++ portable (une union de structs anonymes est une
// extension). C'est une contrainte d'ecriture, pas une limite de cet en-tete.

#include <cmath>  // impose par `sin`/`cos` ci-dessous — voir le commentaire qui les porte

namespace glsl {

struct vec2 {
  float x = 0.f;
  float y = 0.f;
  vec2() = default;
  vec2(float a, float b) : x(a), y(b) {}
  explicit vec2(float a) : x(a), y(a) {}
};

struct vec3 {
  float x = 0.f;
  float y = 0.f;
  float z = 0.f;
  vec3() = default;
  vec3(float a, float b, float c) : x(a), y(b), z(c) {}
  vec3(float a) : x(a), y(a), z(a) {}  // NOLINT — `vec3(0.04)` est une ecriture GLSL legitime
};

inline vec3 operator+(const vec3& a, const vec3& b) {
  return vec3(a.x + b.x, a.y + b.y, a.z + b.z);
}
inline vec3 operator-(const vec3& a, const vec3& b) {
  return vec3(a.x - b.x, a.y - b.y, a.z - b.z);
}
inline vec3 operator*(const vec3& a, const vec3& b) {
  return vec3(a.x * b.x, a.y * b.y, a.z * b.z);
}
inline vec3 operator/(const vec3& a, const vec3& b) {
  return vec3(a.x / b.x, a.y / b.y, a.z / b.z);
}
inline vec3 operator*(const vec3& a, float s) {
  return vec3(a.x * s, a.y * s, a.z * s);
}
inline vec3 operator*(float s, const vec3& a) {
  return vec3(a.x * s, a.y * s, a.z * s);
}
inline vec3 operator/(const vec3& a, float s) {
  return vec3(a.x / s, a.y / s, a.z / s);
}

inline float mix(float a, float b, float t) {
  return a * (1.f - t) + b * t;
}
inline vec3 mix(const vec3& a, const vec3& b, float t) {
  return vec3(mix(a.x, b.x, t), mix(a.y, b.y, t), mix(a.z, b.z, t));
}

inline float clamp(float v, float lo, float hi) {
  return v < lo ? lo : (v > hi ? hi : v);
}
inline vec3 clamp(const vec3& v, const vec3& lo, const vec3& hi) {
  return vec3(clamp(v.x, lo.x, hi.x), clamp(v.y, lo.y, hi.y), clamp(v.z, lo.z, hi.z));
}

inline float max(float a, float b) {
  return a > b ? a : b;
}
inline vec3 max(const vec3& a, const vec3& b) {
  return vec3(max(a.x, b.x), max(a.y, b.y), max(a.z, b.z));
}
inline float min(float a, float b) {
  return a < b ? a : b;
}

inline float dot(const vec3& a, const vec3& b) {
  return a.x * b.x + a.y * b.y + a.z * b.z;
}
inline float dot(const vec2& a, const vec2& b) {
  return a.x * b.x + a.y * b.y;
}

// ---- sin / cos : LE VENT DE L'HERBE LES EXIGE ------------------------------------------------
// `game/graphics/opengl_renderer/shaders/grass_wind.glsl` (item `grass-wind`) est la loi de vent
// que le pilote splice dans `grass.vert`. Elle est faite de sinus : le cap commun, le front de
// rafale, les trois bandes de frequence, et la projection du cap (`sin`/`cos` d'un angle). Sans
// ces trois surcharges ici, l'outil hors ligne qui MESURE le vent aurait du recopier la loi en
// C++ — exactement le miroir que cet en-tete existe pour interdire.
//
// C'EST `sin`/`cos` QUI IMPOSENT `<cmath>`, ET C'EST ASSUME. Cet en-tete etait volontairement
// sans dependance (voir `fract` ci-dessous, ecrit sans `floor` pour cette raison). Il n'existe
// aucune facon raisonnable de produire un sinus sans la bibliotheque standard, et une table ou
// une serie tronquee ecrite a la main serait, elle, une divergence avec le sinus du pilote. On
// prend donc `<cmath>` : c'est un en-tete de la norme, il n'impose rien d'autre a ses clients.
//
// PIEGE, A LIRE AVANT D'APPELER. `<cmath>` pose aussi `::sin(float)` et `::cos(float)`. Sous un
// `using namespace glsl;` les deux jeux deviennent visibles au MEME niveau et l'appel non
// qualifie du chunk est AMBIGU. Toute fonction C++ qui `#include` un chunk appelant `sin`/`cos`
// doit donc ecrire, a PORTEE DE BLOC et avant l'include :
//     using glsl::sin;
//     using glsl::cos;
// Une using-DECLARATION a portee de bloc MASQUE le nom global ; c'est le geste correct. Qualifier
// dans le chunk ne l'est pas : le chunk doit rester du GLSL valide pour le pilote.
inline float sin(float a) {
  return std::sin(a);
}
inline float cos(float a) {
  return std::cos(a);
}
inline vec3 sin(const vec3& a) {
  return vec3(std::sin(a.x), std::sin(a.y), std::sin(a.z));
}

// ---- vec2 : LA LOI DE CONTACT ORIENTEE L'EXIGE ----------------------------------------------
// `game/graphics/opengl_renderer/shaders/grass_contact_dir.glsl` (item
// `grass-interaction-direction`) travaille dans le plan XZ : le cap du pas, l'ecart a son axe, la
// direction de poussee. Il n'y avait ici que `dot(vec2,vec2)` — pas une seule operation. Sans ces
// cinq lignes, l'outil qui MESURE l'angle de flexion aurait du recopier la loi en C++, c'est-a-dire
// mesurer sa propre copie.
inline vec2 operator+(const vec2& a, const vec2& b) {
  return vec2(a.x + b.x, a.y + b.y);
}
inline vec2 operator-(const vec2& a, const vec2& b) {
  return vec2(a.x - b.x, a.y - b.y);
}
inline vec2 operator*(const vec2& a, float s) {
  return vec2(a.x * s, a.y * s);
}
inline vec2 operator*(float s, const vec2& a) {
  return vec2(a.x * s, a.y * s);
}
inline vec2 operator/(const vec2& a, float s) {
  return vec2(a.x / s, a.y / s);
}

// `length` : la norme GLSL. `std::sqrt` est deja tire par `sin`/`cos` ci-dessus.
inline float length(const vec2& a) {
  return std::sqrt(a.x * a.x + a.y * a.y);
}
inline float length(const vec3& a) {
  return std::sqrt(a.x * a.x + a.y * a.y + a.z * a.z);
}

inline float fract(float v) {
  // GLSL: x - floor(x). Ecrit sans <cmath> pour que cet en-tete n'impose rien a ses clients.
  const float f = (float)(long long)v;
  return v - (v < 0.f && v != f ? f - 1.f : f);
}

}  // namespace glsl
