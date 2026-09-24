#pragma once

// lighting-bake (SPEC-refonte-lumiere §5) : le compagnon <niveau>.lightbake.
//
// Le bake de Naughty Dog est decompose, par index de couleur et par creneau de mood, en
//   bakedᵢ = [ ambᵢ + lgtᵢ·max(N·Lᵢ,0)·visᵢ ] × artᵢ     (ambiante plate : voir phys())
// La lumiere de chaque creneau est CONNUE (mood-lights-table, SPEC §3.1) : la decomposition a une
// forme close. La palette B est l'indirect (ambᵢ·artᵢ) ; le direct est ce que le temps reel
// refera. La palette A (le fr3) n'est jamais reecrite : le compagnon vit A COTE.
//
// Ce fichier est partage par l'outil hors ligne (tools/light_bake) et par le moteur, qui relit le
// compagnon au chargement et VERIFIE que B + direct redonne A (porte `bake_reconstruction_maxdelta`).

#include <string>
#include <vector>

#include "common/common_types.h"
#include "common/custom_data/Tfrag3Data.h"

namespace tfrag3 {
namespace lightbake {

constexpr u32 kMagic = 0x4B41424C;  // 'LBAK'
// incremente a CHAQUE changement de semantique, jamais reutilise.
constexpr u32 kVersion = 1;
constexpr int kSlots = 8;

// artᵢ est borne a [0,25 ; 4,0] (SPEC §5.2). Stocke en u16 : art = q / kArtScale. q = 0 veut dire
// « borne depassee » : indirect = A, direct = 0, le sommet reste tel quel.
constexpr float kArtMin = 0.25f;
constexpr float kArtMax = 4.0f;
constexpr float kArtScale = 16383.f;
// la palette est lue par le shader avec un facteur 2 : 128 = 1,0.
constexpr float kPaletteOne = 128.f;

enum Section : u32 {
  kSecPaletteB = 1,
  kSecSkyvis = 2,
  kSecAo = 3,
  kSecBentN = 4,
  kSecRegime = 5,
  kSecProbes = 6,
  kSecLights = 7,
  kSecLightVis = 8,
  kSecStats = 9,
  // Ajouts a la liste du §5.4 : sans eux le moteur ne peut pas recalculer le direct, donc pas
  // verifier la reconstruction qu'exige le §5.5.7.
  kSecKeyVis = 10,  // par arbre : u8[color_count][8] = max(N·Lᵢ,0)·visᵢ agrege sur l'index
  kSecArt = 11,     // par arbre : u16[color_count][8][3] = artᵢ quantifie, 0 = borne depassee
};

struct MoodLight {
  float direction[3] = {0, 0, 0};
  float lgt[3] = {0, 0, 0};
  float amb[3] = {0, 0, 0};
  float shadow[3] = {0, 0, 0};
};

struct MoodTable {
  MoodLight slot[kSlots];
};

// FNV-1a sur les 8 × (direction, lgt-color, amb-color, shadow), arrondis a 1e-4 (SPEC §5.4).
u32 mood_hash(const MoodTable& t);

enum Regime : u8 {
  kRegKey = 0,         // cle dure / cle normale
  kRegDome = 1,        // dome couvert
  kRegAmbient = 2,     // ambiante dominante
  kRegLow = 3,         // source basse (lave)
  kRegAmbOnly = 4,     // ambiante seule
  kRegSourceOnly = 5,  // source pure
};
u8 classify_regime(const MoodLight& m);
const char* regime_name(u8 r);

// Un arbre dessinable du niveau, dans l'ordre DETERMINISTE partage par l'outil et le moteur :
// tfrag_trees[geom] puis tie_trees[geom] puis shrub_trees.
struct TreeRef {
  u8 system = 0;  // 0 tfrag, 1 tie, 2 shrub
  u8 geom = 0;
  const PackedTimeOfDay* colors = nullptr;
  const u8* verts = nullptr;
  size_t vcount = 0;
  size_t vstride = 0;
  const std::vector<u32>* indices = nullptr;
  bool use_strips = true;
  // decalages dans le sommet (PreloadedVertex et ShrubGpuVertex n'ont pas la meme disposition)
  size_t off_nor = 0;
  size_t off_color_index = 0;
};
std::vector<TreeRef> collect_trees(const Level& lev);
const char* system_name(u8 s);

inline size_t palette_offset(u32 color, int slot, int ch) {
  return (size_t)(color / 4) * 128 + (size_t)slot * 16 + (size_t)(color % 4) * 4 + (size_t)ch;
}
u64 palette_hash(const PackedTimeOfDay& p);

struct TreeBake {
  u8 system = 0;
  u8 geom = 0;
  u32 color_count = 0;
  u64 palette_a_hash = 0;  // empreinte de la palette A contre laquelle ce bake a ete cuit
  u32 vert_count = 0;
  std::vector<u8> palette_b;  // meme disposition et taille que PackedTimeOfDay::data
  std::vector<u8> skyvis;     // [color_count]
  std::vector<u8> ao;         // [color_count]
  std::vector<u8> keyvis;     // [color_count * 8]
  std::vector<u16> art;       // [color_count * 8 * 3]
  std::vector<u8> bent_n;     // [2 * vert_count], octaedrique
};

struct Bake {
  std::string level_name;
  u32 tfrag3_version = 0;
  u32 mood_hash = 0;
  MoodTable mood;
  u8 regime[kSlots] = {};
  std::vector<TreeBake> trees;
  std::string stats;
};

std::string lightbake_name(const std::string& level_name);
std::vector<u8> serialize(const Bake& b);
bool deserialize(const std::vector<u8>& data, Bake& b, std::string* err);

// Le calcul que l'outil ET le moteur font a l'identique.
// MESURE (reports/lighting-bake/notes/modele-mesure.md) : l'ambiante du bake de ND n'est PAS occultee
// par le ciel, le soleil l'est. Avec amb·skyvis (SPEC §5.2 a la lettre) la mediane de art vaut 3,45 sur
// village1 et 76 % des valeurs sortent des bornes ; avec l'ambiante plate elle vaut 0,954. skyvis est
// donc livre (AO, classement interieur) mais n'entre pas dans la de-illumination.
inline float phys(const MoodLight& m, int ch, u8 keyvis_q) {
  return m.amb[ch] + m.lgt[ch] * (keyvis_q / 255.f);
}

struct VerifyResult {
  bool accepted = false;
  std::string reject_reason;
  u32 trees_checked = 0;
  u32 trees_rejected = 0;
  u64 indices_checked = 0;
  u64 values_checked = 0;
  // |B + direct - A| en unites 1/255 : la porte.
  float maxdelta = 0.f;
  // |round(indirect) - B| : la palette B livree est bien l'indirect recalcule.
  float maxdelta_b = 0.f;
  // valeurs a borne depassee (B == A exige)
  u64 clamped_checked = 0;
};

// Verifie `b` contre le niveau `lev` (palette A en memoire) et la table de mood `live` vue par le
// moteur. `stride` = 1 : tous les index ; 64 : un sur 64 (SPEC §5.5.7) ; `cap` plafonne le compte.
VerifyResult verify(const Level& lev, const Bake& b, const MoodTable& live, u32 stride, u64 cap);

}  // namespace lightbake
}  // namespace tfrag3
