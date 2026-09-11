#include "versions.h"

#include "common/util/Assert.h"
#include "common/versions/revision.h"

#include "fmt/format.h"

GameVersion game_name_to_version(const std::string& name) {
  if (name == "jak1") {
    return GameVersion::Jak1;
  } else if (name == "jak2") {
    return GameVersion::Jak2;
  } else if (name == "jak3") {
    return GameVersion::Jak3;
  } else if (name == "jakx") {
    return GameVersion::JakX;
  } else {
    ASSERT_MSG(false, fmt::format("invalid game name: {}", name));
  }
}

bool valid_game_version(const std::string& name) {
  return name == "jak1" || name == "jak2" || name == "jak3";
}

std::string version_to_game_name(GameVersion v) {
  switch (v) {
    case GameVersion::Jak1:
      return "jak1";
    case GameVersion::Jak2:
      return "jak2";
    case GameVersion::Jak3:
      return "jak3";
    case GameVersion::JakX:
      return "jakx";
    default:
      ASSERT_MSG(false, fmt::format("no game_name for version: {} found", fmt::underlying(v)));
  }
}

std::string version_to_game_name_external(GameVersion v) {
  // Grecharged-naming (owner 2026-07-22): user-facing per-game titles (window
  // title, LSP status). Internal ids (version_to_game_name) are untouched.
  switch (v) {
    case GameVersion::Jak1:
      return "Jak and Daxter: Recharged";
    case GameVersion::Jak2:
      return "Jak II: Recharged";
    case GameVersion::Jak3:
      return "Jak 3: Recharged";
    case GameVersion::JakX:
      return "Jak X";
    default:
      ASSERT_MSG(false, fmt::format("no game_name for version: {} found", fmt::underlying(v)));
  }
}

namespace {
// Pose une fois au demarrage, lue par les couches sans `GameVersion` (voir versions.h).
std::string g_external_product_name = version_to_game_name_external(GameVersion::Jak1);
}  // namespace

const char* external_product_name() {
  return g_external_product_name.c_str();
}

void set_external_product_name(GameVersion v) {
  g_external_product_name = version_to_game_name_external(v);
}

namespace {
// `sound` construit son contexte cubeb depuis un fil a lui : le releve se fait sous
// verrou, sinon le recensement peut lire la table pendant qu'elle s'ecrit.
std::mutex g_name_use_mutex;
std::map<std::string, std::string> g_name_uses;
}  // namespace

void note_product_name_use(const char* where, const char* shown) {
  if (!where || !where[0]) {
    return;
  }
  std::lock_guard<std::mutex> lock(g_name_use_mutex);
  g_name_uses[where] = shown ? shown : "";
}

const std::map<std::string, std::string>& product_name_uses() {
  std::lock_guard<std::mutex> lock(g_name_use_mutex);
  return g_name_uses;
}

std::vector<std::string> valid_game_version_names() {
  return {game_version_names[GameVersion::Jak1], game_version_names[GameVersion::Jak2],
          game_version_names[GameVersion::Jak3], game_version_names[GameVersion::JakX]};
}

std::string build_revision() {
  if (std::string(BUILT_TAG) != "") {
    return std::string(BUILT_TAG);
  }
  if (std::string(BUILT_SHA) != "") {
    return std::string(BUILT_SHA);
  }
  return "Unknown Revision";
}
