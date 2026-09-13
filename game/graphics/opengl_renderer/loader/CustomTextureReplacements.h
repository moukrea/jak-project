#pragma once

// Runtime PNG texture replacements from TWO sources.
//
// Textures uploaded by the loader are looked up against two PNG indexes and, on a
// hit, the PNG is uploaded in place of the baked fr3 texture:
//   1. the USER drop dir (get_custom_assets_replacements_dir), gated by
//      Gfx::settings().load_custom_assets, and
//   2. the package-BUNDLED first-party set under
//      custom_assets/<game>/recharged_textures (get_bundled_recharged_textures_dir):
//      base swaps gated by Gfx::settings().recharged_textures.
// Precedence is user > bundled > stock, and every gate is composed with the Recharged
// master via Gfx::recharged_active().

#include <optional>
#include <string>
#include <vector>

#include "common/common_types.h"

#include "game/graphics/opengl_renderer/loader/ManagedAssets.h"

namespace custom_tex {

struct ReplacementImage {
  std::vector<u8> rgba;
  int w = 0;
  int h = 0;
  const char* src = "";  // which index the file came from: "user"/"bundled"
};

// Which source won the base texture (deterministic mirror of lookup()).
enum class BaseSource { Stock, User, Bundled };

// Look up a replacement for a given texture. Returns nullopt when custom
// assets are disabled or no matching PNG exists.
std::optional<ReplacementImage> lookup(const std::string& tpage_name, const std::string& tex_name);

// Report which source would win the BASE texture for this key, without loading pixels.
BaseSource base_source(const std::string& tpage_name, const std::string& tex_name);

// ===== Gfont-regression (owner 2026-09-02) — LA POLICE N'EST PAS UNE « TEXTURE RECHARGED » =====
// « t'as complètement niqué la font (Urbanist) ça utilise des glyphs chinois de la font par
// défaut du jeu ». Mesure : les deux atlas Urbanist (gamefontnew/ascii.12lo, ascii.24lo)
// voyagent comme des remplacements de textures LIVRES, donc derriere les MEMES portes que les
// textures HD : `recharged-master?`, `recharged-textures?`, et la precedence joueur > telecharge
// > livre > stock de add_texture. Or le TEXTE, lui, est converti en casse mixte SANS porte
// (banques de texte, cycle Gfont-urbanist). Une seule de ces portes fermee — ou un PNG
// `gamefontnew` pose par le joueur, ou un pack telecharge qui porterait cette page — et le jeu
// dessine des minuscules avec l'atlas D'ORIGINE, dont les cellules a-z de la GRANDE police
// sont 26 KANJI (mesure cellule par cellule, project_jak1_two_font_code_pages). C'est mot pour
// mot ce qu'il decrit, et le Redmi ne le montrait pas : toutes ses portes sont a #t.
// Le texte et l'atlas sont UNE unite : l'un ne se livre pas sans l'autre. La page de police se
// resout donc SANS AUCUNE porte, depuis le paquet livre uniquement, et rien ne peut la masquer.
bool is_font_atlas(const std::string& tpage_name);  // tpage_name == "gamefontnew"

// lighting-origin-bitexact : nombre de fois ou la page de police a ete resolue MAITRE
// ETEINT. Publie sous `origin_font_master_bypass`. Non nul = la porte bit-a-bit ne couvre
// pas la police (banc de texte et chasses vivent dans la donnee partagee, voir le .cpp).
uint64_t font_master_bypass_count();

// Registre des atlas de police REELLEMENT TELEVERSES (add_texture) et REELLEMENT LIES au dessin
// (DirectRenderer::update_gl_texture) — la preuve se prend au point de LECTURE, pas au chargement.
struct FontAtlasRec {
  std::string key;     // "gamefontnew/ascii.24lo"
  std::string source;  // "bundled-police" (Urbanist) | "stock" (atlas d'origine = kanji)
  int w = 0;
  int h = 0;
  u32 gl = 0;
  u64 binds = 0;  // fois ou le dessin direct a lie cette texture
};
void note_font_atlas_upload(const std::string& key, const char* source, u32 gl_id, int w, int h);
// nullptr si ce GL id n'est pas un atlas de police connu.
FontAtlasRec* font_atlas_by_gl(u32 gl_id);
// Lignes `FONTATLAS ...` pour le fichier de diag natif (files/font_atlas.txt sur Android, ou
// logcat est muet sur le Honor de l'owner).
std::string font_atlas_section();

// ===== Gshield-load-and-crash: the PRE-BAKED tier ==============================================
// Grecharged / Gshield-load-and-crash : niveau PRE-CUIT (baked). Les memes images
// que le niveau PNG, mais deja compressees GPU (ASTC) et deja mipmappees hors ligne.
// Aucun stbi_load, aucun glGenerateMipmap, aucune passe de mesure CPU : les
// statistiques viennent du sidecar produit par la cuisson.
//
// Measured cause this tier exists for (SHIELD, 2026-08-26): one `add_texture` on a heavy
// material costs `stage texture took 1799 ms` on the PNG path — a 2048x2048 stbi_load per
// image (151-330 ms), each decoded TWICE (probe pass + re-fetch), then glGenerateMipmap
// (68-235 ms). The already-proven KTX2 path serves the same material in 87 ms.
//
// Source ranking is UNCHANGED apart from the new rung:
//   user PNG > managed KTX2 > BAKED KTX2 > bundled PNG > stock.
// The baked tier replaces the BUNDLED PNG tier and therefore carries the bundled tier's
// gates: the base swap follows `recharged_textures`
// (exactly like lookup()). It is INERT unless the GPU's PREFERRED PROFILE is
// the ASTC one — not merely unless the GPU can read ASTC, which a desktop GL 4.6 driver also
// advertises (measured 2026-08-26: 28 `custom texture BAKED` lines in an x86 run, against what
// this comment used to claim). With the profile gate the desktop path is what it was.
std::optional<managed_assets::CompressedTex> lookup_baked_base(const std::string& tpage_name,
                                                               const std::string& tex_name);
// At least one baked material indexed AND a GPU that reads ASTC.
bool baked_available();


// ===== Grecharged-texture-hotreload — BASCULER LES TEXTURES RECHARGED SANS REDEMARRER ========
// Le contrat d'avant etait ecrit noir sur blanc dans le pousseur GOAL (hud-classes-pc.gc) :
// « a flip applies on the next level load ». `add_texture` consulte la porte UNE FOIS, au
// televersement, et rien ne repasse jamais dessus : GAME.fr3 n'est de surcroit JAMAIS evince
// (Loader.cpp), donc ses textures ne pouvaient revenir par aucun rechargement. Basculer la
// rangee du menu ne changeait donc rien tant que le jeu n'avait pas ete relance.
//
// `hotreload_regime()` est LE mot qui resume l'etat des portes qui decident la source de la
// texture de BASE — exactement les trois booleens que `lookup()` et `base_source()` relisent a
// chaque appel. Le chargeur le compare a celui sous lequel chaque niveau resident a ete
// televerse ; une difference declenche une re-resolution budgetee de ce niveau.
//   bit 0 : user_on    = recharged_active(load_custom_assets)
//   bit 1 : bundled_on = recharged_active(recharged_textures)
//   bit 2 : master     = recharged_master_active()
u32 hotreload_regime();

// LE STIMULUS DE PREUVE, pose sur le SEUL ecrivain de `recharged_textures` (kmachine.cpp
// pc_set_recharged_textures, appele par la rangee du menu ET par `update-to-os` a chaque image).
// Identite — donc rigoureusement aucun effet — sauf quand le harnais mesure l'item
// `recharged-texture-hotreload` ET qu'il est arme. Il ne peut pas etre pose ailleurs : GOAL
// repousse la valeur de son champ a CHAQUE image, donc un forcage ecrit en aval serait efface
// a l'image suivante. Ce qui atterrit dans `g_global_settings` est bit pour bit ce qu'un geste
// de l'owner sur la rangee y aurait mis ; tout ce qui suit est le chemin reel.
bool hotreload_stimulus(bool on);

// Force a rescan of the replacements directory on the next lookup().
void invalidate();

// Key-dump helper: when the marker file <root>/custom_assets/dump_keys exists,
// append the "tpage/name" key for every texture seen to texture_keys_dump.txt
// (deduped). No-op otherwise.
void dump_key(const std::string& tpage_name, const std::string& tex_name);

}  // namespace custom_tex
