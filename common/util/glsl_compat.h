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
// sous-ensemble EXACT que ces deux blocs emploient (vec2, vec3, mix, clamp, max, dot, fract).
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

inline float fract(float v) {
  // GLSL: x - floor(x). Ecrit sans <cmath> pour que cet en-tete n'impose rien a ses clients.
  const float f = (float)(long long)v;
  return v - (v < 0.f && v != f ? f - 1.f : f);
}

}  // namespace glsl
