#pragma once

/*!
 * @file versions.h
 * Version numbers for GOAL Language, Kernel, etc...
 */

#include <map>
#include <mutex>
#include <string>
#include <vector>

#include "common/common_types.h"

namespace versions {
// language version (OpenGOAL)
constexpr s32 GOAL_VERSION_MAJOR = 1;
constexpr s32 GOAL_VERSION_MINOR = 0;

namespace jak1 {
// these versions are from the game
constexpr u32 ART_FILE_VERSION = 6;
constexpr u32 LEVEL_FILE_VERSION = 30;
constexpr u32 DGO_FILE_VERSION = 1;
constexpr u32 RES_FILE_VERSION = 1;
constexpr u32 TX_PAGE_VERSION = 7;
}  // namespace jak1

namespace jak2 {
constexpr u32 ART_FILE_VERSION = 7;
constexpr u32 LEVEL_FILE_VERSION = 36;
constexpr u32 DGO_FILE_VERSION = 1;
constexpr u32 TX_PAGE_VERSION = 8;
}  // namespace jak2

namespace jak3 {
constexpr u32 ART_FILE_VERSION = 8;
constexpr u32 LEVEL_FILE_VERSION = 36;
constexpr u32 DGO_FILE_VERSION = 1;
constexpr u32 TX_PAGE_VERSION = 8;
}  // namespace jak3

namespace jakx {
constexpr u32 ART_FILE_VERSION = 8;
constexpr u32 LEVEL_FILE_VERSION = 36;
constexpr u32 DGO_FILE_VERSION = 1;
constexpr u32 TX_PAGE_VERSION = 8;
}  // namespace jakx

}  // namespace versions

// GOAL kernel version (OpenGOAL changes this version from the game's version)
constexpr int KERNEL_VERSION_MAJOR = 2;
constexpr int KERNEL_VERSION_MINOR = 0;

// OVERLORD version returned by an RPC
constexpr int IRX_VERSION_MAJOR = 2;
constexpr int IRX_VERSION_MINOR = 0;

enum class GameVersion { Jak1 = 1, Jak2 = 2, Jak3 = 3, JakX = 4 };

// TODO: most usages of this are currently stubs for jak 3
template <typename T>
struct PerGameVersion {
  constexpr PerGameVersion(T jak1, T jak2, T jak3, T jakx) : data{jak1, jak2, jak3, jakx} {}
  constexpr const T& operator[](GameVersion v) const { return data[(int)v - 1]; }
  T data[4];
};

constexpr PerGameVersion<const char*> game_version_names = {"jak1", "jak2", "jak3", "jakx"};

GameVersion game_name_to_version(const std::string& name);
bool valid_game_version(const std::string& name);
std::string version_to_game_name(GameVersion v);
std::string version_to_game_name_external(GameVersion v);

// recharged-naming — LE NOM PRODUIT, pour le code qui n'a pas de `GameVersion` sous la main.
//
// Le mixeur audio de l'OS et le titre de la fenetre Android nomment le jeu a l'utilisateur
// depuis des couches (989snd, le lanceur SDL Android) qui ne connaissent pas la version en
// cours. Leur donner un litteral de plus, c'est un endroit de plus a oublier au prochain
// renommage : `set_external_product_name` est appele une fois au demarrage, la ou la version
// est decidee, et tous ces sites lisent LA MEME chaine.
//
// La valeur par defaut est celle de Jak 1 et pas une chaine vide : un appelant qui s'execute
// avant le demarrage doit nommer le produit, pas afficher du vide.
const char* external_product_name();
void set_external_product_name(GameVersion v);

// LE RELEVE DES SITES DE NOMMAGE, cote `common`.
//
// `naming_census` (game/system) juge chaque endroit ou le jeu se nomme. Il doit lire la chaine
// REELLEMENT passee au site, pas la recalculer : une porte qui recalcule son attendu est un
// miroir, elle ne peut pas echouer. Mais certains sites vivent dans des cibles que le moteur ne
// lie pas (la lib `sound` sert aussi l'outil `sndplay`, qui n'a ni `game/system` ni moteur) :
// leur donner une dependance vers le recensement casserait leur lien. Ce couple de fonctions
// vit donc dans `common`, que tout le monde lie deja, et le recensement vient y lire.
void note_product_name_use(const char* where, const char* shown);
const std::map<std::string, std::string>& product_name_uses();

std::vector<std::string> valid_game_version_names();

std::string build_revision();
