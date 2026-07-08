#include "RechargedHudTextures.h"

#include "common/log/log.h"
#include "common/util/FileUtil.h"

#include "third-party/stb_image/stb_image.h"

// Names in slot order, base slot 7900, +1 each.
static const char* kRechargedHudNames[] = {
    "jak_heart_100",         "jak_heart_66",        "jak_heart_33",
    "jak_heart_0",           "jak_gauge_empty",     "jak_gauge_blue_full",
    "jak_gauge_red_full",    "jak_gauge_yellow_full", "jak_gauge_blue_end",
    "jak_gauge_red_end",     "jak_gauge_yellow_end",
};

void load_recharged_hud_textures(TexturePool& pool, GameVersion version) {
  if (version != GameVersion::Jak1) {
    return;
  }

  auto dir = file_util::get_jak_project_dir() / "recharged_assets";

  for (int i = 0; i < (int)(sizeof(kRechargedHudNames) / sizeof(kRechargedHudNames[0])); i++) {
    const int slot = 7900 + i;
    std::string name = kRechargedHudNames[i];
    auto path = dir / (name + ".png");

    if (!fs::exists(path)) {
      lg::warn("recharged-hud: missing texture {}", path.string());
      continue;
    }

    int w, h;
    auto* data = stbi_load(path.string().c_str(), &w, &h, nullptr, STBI_rgb_alpha);
    if (!data) {
      lg::warn("recharged-hud: failed to load texture {}", path.string());
      continue;
    }

    u64 tex_id = upload_to_gpu(data, w, h);

    TextureInput in;
    in.gpu_texture = tex_id;
    in.w = w;
    in.h = h;
    in.debug_page_name = "PC-RHUD";
    in.debug_name = name;
    in.id = pool.allocate_pc_port_texture(GameVersion::Jak1);
    pool.give_texture_and_load_to_vram(in, slot);

    stbi_image_free(data);

    lg::info("recharged-hud: loaded {} ({}x{}) -> vram slot {}", name, w, h, slot);
  }
}
