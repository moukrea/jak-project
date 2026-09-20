#pragma once

// grass-blade-variants / SPEC-refonte-herbe.md section 18 — LE PROFIL DE BIOME EST UNE DONNEE.
//
// « Un profil est une DONNEE, pas du code : il se cuit, il se lit, il se remplace sans
// recompiler. » (SPEC section 18.) Et l'owner, 20/09 20:40, photo a l'appui : « Une herbe MARRON
// qui n'a rien a faire dans Geyser Rock (HS le biome, regarde la spec putain) ».
//
// CE QUE CE FICHIER CORRIGE. Jusqu'a l'essai 7 la couleur d'une espece etait une COULEUR ABSOLUE
// ecrite dans `kGrassSpecies` (et recopiee en dur dans `grass.vert`). Les six especes ont donc ete
// choisies pour se DISTINGUER entre elles, jamais pour APPARTENIR a un lieu : mesure sur les
// sommets emis, leurs teintes s'etalaient sur 146 degres, de 29,5 (le brun de `faux`) a 175,3 (le
// cyan de `fine`). C'est ce que l'owner voit sur sa photo.
//
// LA REGLE QUI REMPLACE. La couleur vient du PROFIL DE BIOME ; l'espece ne porte qu'un ECART
// autour de lui (teinte en degres, saturation et valeur en fraction). Aucune espece ne peut donc
// sortir de la coque de teinte du lieu : c'est une propriete de la STRUCTURE, pas d'un reglage
// bien choisi. Geyser Rock devient un jeu de verts, et la meme table donnera la jungle sans
// recompiler quoi que ce soit — c'est le socle que `grass-biome-profiles` composera.
//
// AUCUNE INCLUSION DU MOTEUR, ET AUCUN .cpp. Ce fichier est lu par le moteur, par
// `tools/grass_bake` (outil de bureau, sans GL) et par le recensement, comme
// `grass_blade_variants.h` a cote. Tout est `inline` : rien a declarer dans les DEUX
// `CMakeLists.txt`, donc pas d'`undefined symbol` arm64 pendant que x86 passe sa preuve.

#include <cmath>
#include <cstdio>
#include <cstring>
#include <string>

namespace grass_bake {

inline constexpr int kBiomeSpeciesCount = 6;

// L'ECART D'UNE ESPECE AUTOUR DE LA COULEUR DU LIEU. Jamais une couleur absolue : c'est la
// difference entre « une espece plus jaune que l'herbe d'ici » et « une espece marron ».
struct BiomeSpecies {
  char name[16] = {0};
  float dhue_deg = 0.f;  // ecart de teinte, en degres          (perimetre owner : [-15, +15])
  float dsat = 0.f;      // ecart de saturation, en fraction    (perimetre owner : [-0.20, +0.20])
  float dval = 0.f;      // ecart de valeur, en fraction        (perimetre owner : [-0.20, +0.20])
  float axis = 0.f;      // 0 = degrade le long du brin ; 1 = modulation EN TRAVERS en plus
  float rim = 0.f;       // liseret de bord : 0 = aucun
  int weight_pm = 0;     // part de l'espece DANS CE BIOME, pour mille (la somme vaut 1000)
};

// LE PROFIL D'UN LIEU.
struct BiomeProfile {
  bool loaded = false;
  char level[32] = {0};
  float hue_deg = 0.f;    // la teinte du lieu — le centre de la coque
  float root_sat = 0.f;   // saturation / valeur a la RACINE du brin
  float root_val = 0.f;
  float tip_sat = 0.f;    // ... et a la POINTE. L'ecart des deux EST le relief le long du brin.
  float tip_val = 0.f;
  float hull_deg = 25.f;  // demi-largeur de la coque de teinte toleree autour de `hue_deg`
  float jitter_r = 0.f;   // dispersion de teinte par brin (canal rouge puis bleu). Elle vit ICI
  float jitter_b = 0.f;   // parce qu'elle DEBORDE la coque : a 0,50/0,35 elle en sortait 3,17 %.
  float across_k = 0.f;   // force de la modulation en travers des especes a `axis` = 1
  BiomeSpecies sp[kBiomeSpeciesCount];
  int fields_read = 0;  // combien de champs ont ete LUS DANS LE FICHIER — publie par la preuve
};

// --- teinte/saturation/valeur -> rouge/vert/bleu. Sans dependance, et identique des deux cotes.
inline void biome_hsv_to_rgb(float h_deg, float s, float v, float* r, float* g, float* b) {
  h_deg = std::fmod(h_deg, 360.f);
  if (h_deg < 0.f) {
    h_deg += 360.f;
  }
  s = s < 0.f ? 0.f : (s > 1.f ? 1.f : s);
  v = v < 0.f ? 0.f : (v > 1.f ? 1.f : v);
  const float c = v * s;
  const float hp = h_deg / 60.f;
  const float x = c * (1.f - std::fabs(std::fmod(hp, 2.f) - 1.f));
  float rr = 0.f, gg = 0.f, bb = 0.f;
  if (hp < 1.f) {
    rr = c;
    gg = x;
  } else if (hp < 2.f) {
    rr = x;
    gg = c;
  } else if (hp < 3.f) {
    gg = c;
    bb = x;
  } else if (hp < 4.f) {
    gg = x;
    bb = c;
  } else if (hp < 5.f) {
    rr = x;
    bb = c;
  } else {
    rr = c;
    bb = x;
  }
  const float m = v - c;
  *r = rr + m;
  *g = gg + m;
  *b = bb + m;
}

// LE PROFIL ACTIF. Une seule instance, posee au chargement du niveau. Tant qu'aucun fichier n'a
// ete lu, `loaded` est faux et l'appelant retombe sur la palette d'AVANT l'item (la seule couleur
// encore ecrite dans le code, et elle n'est pas un profil) : un profil manquant se voit, il ne
// s'invente pas. La preuve compte ce cas comme un DEFAUT, pas comme un repli silencieux.
inline BiomeProfile& active_biome_mutable() {
  static BiomeProfile g_profile;
  return g_profile;
}
inline const BiomeProfile& active_biome() {
  return active_biome_mutable();
}

// --- LE LECTEUR. Format en lignes : un mot-cle, des nombres. Les commentaires commencent par '#'.
//     Volontairement idiot : ni JSON ni dependance, et le meme texte se relit a l'oeil.
inline bool load_biome_profile(const std::string& path, BiomeProfile* out, std::string* err) {
  if (!out) {
    return false;
  }
  *out = BiomeProfile{};
  std::FILE* f = std::fopen(path.c_str(), "rb");
  if (!f) {
    if (err) {
      *err = "fichier absent : " + path;
    }
    return false;
  }
  char line[512];
  int nsp = 0;
  while (std::fgets(line, sizeof(line), f)) {
    char* p = line;
    while (*p == ' ' || *p == '\t') {
      ++p;
    }
    if (*p == '#' || *p == '\n' || *p == '\r' || *p == 0) {
      continue;
    }
    char key[64] = {0};
    if (std::sscanf(p, "%63s", key) != 1) {
      continue;
    }
    const char* rest = p + std::strlen(key);
    float a = 0.f;
    if (std::strcmp(key, "biome") == 0) {
      char nm[32] = {0};
      if (std::sscanf(rest, "%31s", nm) == 1) {
        std::snprintf(out->level, sizeof(out->level), "%s", nm);
        ++out->fields_read;
      }
      continue;
    }
    if (std::strcmp(key, "species") == 0) {
      if (nsp >= kBiomeSpeciesCount) {
        continue;
      }
      char nm[16] = {0};
      float dh = 0.f, ds = 0.f, dv = 0.f, ax = 0.f, rm = 0.f;
      int w = 0;
      if (std::sscanf(rest, "%15s %f %f %f %f %f %d", nm, &dh, &ds, &dv, &ax, &rm, &w) == 7) {
        BiomeSpecies& S = out->sp[nsp++];
        std::snprintf(S.name, sizeof(S.name), "%s", nm);
        S.dhue_deg = dh;
        S.dsat = ds;
        S.dval = dv;
        S.axis = ax;
        S.rim = rm;
        S.weight_pm = w;
        out->fields_read += 7;
      }
      continue;
    }
    if (std::sscanf(rest, "%f", &a) != 1) {
      continue;
    }
    struct Bind {
      const char* k;
      float* v;
    };
    const Bind binds[] = {
        {"hue_deg", &out->hue_deg},   {"root_sat", &out->root_sat}, {"root_val", &out->root_val},
        {"tip_sat", &out->tip_sat},   {"tip_val", &out->tip_val},   {"hull_deg", &out->hull_deg},
        {"jitter_r", &out->jitter_r}, {"jitter_b", &out->jitter_b}, {"across_k", &out->across_k},
    };
    for (const Bind& bd : binds) {
      if (std::strcmp(key, bd.k) == 0) {
        *bd.v = a;
        ++out->fields_read;
        break;
      }
    }
  }
  std::fclose(f);

  // UN PROFIL INCOMPLET N'EST PAS UN PROFIL. Mieux vaut le dire que peindre l'herbe a moitie.
  if (nsp != kBiomeSpeciesCount) {
    if (err) {
      *err = "il faut " + std::to_string(kBiomeSpeciesCount) + " lignes `species`, il y en a " +
             std::to_string(nsp);
    }
    return false;
  }
  int sum = 0;
  for (const BiomeSpecies& S : out->sp) {
    sum += S.weight_pm;
  }
  if (sum != 1000) {
    if (err) {
      *err = "les poids doivent sommer a 1000 pour mille, ils somment a " + std::to_string(sum);
    }
    return false;
  }
  if (out->hue_deg <= 0.f || out->root_val <= 0.f || out->tip_val <= 0.f) {
    if (err) {
      *err = "teinte ou valeurs de racine/pointe absentes";
    }
    return false;
  }
  out->loaded = true;
  return true;
}

}  // namespace grass_bake
