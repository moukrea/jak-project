#include "OceanNear.h"

#include "common/log/log.h"
#include "game/graphics/gfx.h"
#include "game/graphics/opengl_renderer/ocean/OceanRecharged.h"

#include "third-party/imgui/imgui.h"

OceanNear::OceanNear(const std::string& name, int my_id)
    : BucketRenderer(name, my_id), m_texture_renderer(false) {
  for (auto& a : m_vu_data) {
    a.fill(0);
  }
}

void OceanNear::draw_debug_window() {}

void OceanNear::init_textures(TexturePool& pool, GameVersion version) {
  m_texture_renderer.init_textures(pool, version);
}

static bool is_end_tag(const DmaTag& tag, const VifCode& v0, const VifCode& v1) {
  return tag.qwc == 2 && tag.kind == DmaTag::Kind::CNT && v0.kind == VifCode::Kind::NOP &&
         v1.kind == VifCode::Kind::DIRECT;
}

void OceanNear::render(DmaFollower& dma,
                       SharedRenderState* render_state,
                       ScopedProfilerNode& prof) {
  const bool water_on = m_enabled && render_state->version == GameVersion::Jak1 &&
                        ocean_recharged_enabled();
  // LA DECISION DE REPRISE, REFERMEE ICI. Elle est prise au bucket 4 quand celui-ci a tourne, et
  // ici sinon (bucket 4 vide, tag CALL) ; l'appel se fait AVANT tout retour anticipe, parce
  // qu'une image qui l'ouvrirait sans la refermer la figerait pour toute la course. `water_on`
  // ne suffit pas a dessiner : il faut aussi que la clipmap ait de quoi le faire, faute de quoi
  // l'ocean d'origine reste a sa place au lieu de laisser un trou.
  const bool takeover = render_state->version == GameVersion::Jak1 &&
                        OceanRecharged::get().takeover_decision(true) && m_enabled;
  if (render_state->version == GameVersion::Jak1) {
    OceanRecharged::get().begin_near_frame(water_on);
  }

  // skip if disabled
  if (!m_enabled) {
    while (dma.current_tag_offset() != render_state->next_bucket) {
      dma.read_and_advance();
    }
    return;
  }

  // water-ocean-mesh (SPEC-refonte-eau §5.1) : sous `recharged_water`, le bucket 63 consomme son
  // DMA sans dessiner, et la clipmap prend sa place — c'est la position W2a, apres tous les
  // opaques et tous les alphas, la seule ou la profondeur de scene est lisible.
  m_common_ocean_renderer.set_suppress_draw(takeover);

  switch (render_state->version) {
    case GameVersion::Jak1:
      render_jak1(dma, render_state, prof);
      break;
    case GameVersion::Jak2:
    case GameVersion::Jak3:
    case GameVersion::JakX:
      render_jak2(dma, render_state, prof);
      break;
  }

  // Hors du `switch` A DESSEIN : `render_jak1` sort tot quand le bucket est vide, ce qui arrive
  // des que la camera passe 48 m d'altitude (`ocean.gc:543`). La clipmap doit quand meme etre
  // dessinee ces images-la, sur la derniere houle captee.
  if (takeover) {
    auto p = prof.make_scoped_child("clipmap");
    OceanRecharged::get().draw(render_state, p);
  }
}

void OceanNear::render_jak1(DmaFollower& dma,
                            SharedRenderState* render_state,
                            ScopedProfilerNode& prof) {
  // jump to bucket
  auto data0 = dma.read_and_advance();
  ASSERT(data0.vif1() == 0);
  ASSERT(data0.vif0() == 0);
  ASSERT(data0.size_bytes == 0);

  // see if bucket is empty or not
  if (dma.current_tag().kind == DmaTag::Kind::CALL) {
    // renderer didn't run, let's just get out of here.
    for (int i = 0; i < 4; i++) {
      dma.read_and_advance();
    }
    ASSERT(dma.current_tag_offset() == render_state->next_bucket);
    return;
  }

  {
    auto p = prof.make_scoped_child("texture");
    // TODO: this looks the same as the previous ocean renderer to me... why do it again?
    m_texture_renderer.handle_ocean_texture_jak1(dma, render_state, p);
  }

  if (dma.current_tag().qwc != 2) {
    lg::error("abort OceanNear::render!");
    while (dma.current_tag_offset() != render_state->next_bucket) {
      dma.read_and_advance();
    }
    return;
  }

  // direct setup
  {
    m_common_ocean_renderer.init_for_near();
    auto setup = dma.read_and_advance();
    ASSERT(setup.vifcode0().kind == VifCode::Kind::NOP);
    ASSERT(setup.vifcode1().kind == VifCode::Kind::DIRECT);
    ASSERT(setup.size_bytes == 32);
  }

  // oofset and base
  {
    auto ob = dma.read_and_advance();
    ASSERT(ob.size_bytes == 0);
    auto base = ob.vifcode0();
    auto off = ob.vifcode1();
    ASSERT(base.kind == VifCode::Kind::BASE);
    ASSERT(off.kind == VifCode::Kind::OFFSET);
    ASSERT(base.immediate == VU1_INPUT_BUFFER_BASE);
    ASSERT(off.immediate == VU1_INPUT_BUFFER_OFFSET);
  }

  while (!is_end_tag(dma.current_tag(), dma.current_tag_vif0(), dma.current_tag_vif1())) {
    auto data = dma.read_and_advance();
    auto v0 = data.vifcode0();
    auto v1 = data.vifcode1();

    if (v0.kind == VifCode::Kind::STCYCL && v1.kind == VifCode::Kind::UNPACK_V4_32) {
      ASSERT(v0.immediate == 0x404);
      auto up = VifCodeUnpack(v1);
      u16 addr = up.addr_qw + (up.use_tops_flag ? get_upload_buffer() : 0);
      ASSERT(addr + v1.num <= 1024);
      memcpy(m_vu_data + addr, data.data, 16 * v1.num);
    } else if (v0.kind == VifCode::Kind::MSCALF && v1.kind == VifCode::Kind::STMOD) {
      ASSERT(v1.immediate == 0);
      switch (v0.immediate) {
        case 0:
          run_call0_vu2c();
          break;
        case 39:
          run_call39_vu2c();
          break;
        default:
          ASSERT_MSG(false, fmt::format("unknown ocean near call: {}", v0.immediate));
      }
    }
  }

  while (dma.current_tag_offset() != render_state->next_bucket) {
    dma.read_and_advance();
  }

  // water-ocean-mesh : LA CAPTURE DE LA COUCHE A. `ocean-near-add-heights` (ocean-near.gc:297)
  // pousse `*ocean-heights*` en DEUX tags `ref` de 128 qwc vers les qw VU 32 et 160 : 2 x 2048
  // octets contigus, soit les 1024 flottants 32x32 que `ocean-get-height` lit LUI-MEME. On ne
  // recalcule donc rien — on prend les octets du gameplay, ce qui est la seule facon de tenir
  // `water_gameplay_height_maxdelta_mm == 0` autrement que par une coincidence.
  static_assert(sizeof(m_vu_data[0]) == 16, "le tampon VU doit etre contigu en qwords");
  OceanRecharged::get().note_layer_a(&m_vu_data[32]);

  m_common_ocean_renderer.flush_near(render_state, prof);
}

void OceanNear::render_jak2(DmaFollower& dma,
                            SharedRenderState* render_state,
                            ScopedProfilerNode& prof) {
  // jump to bucket
  auto data0 = dma.read_and_advance();
  ASSERT(data0.vif1() == 0 || data0.vifcode1().kind == VifCode::Kind::NOP);
  ASSERT(data0.vif0() == 0 || data0.vifcode0().kind == VifCode::Kind::MARK);
  ASSERT(data0.size_bytes == 0);

  // see if bucket is empty or not
  if (dma.current_tag_offset() == render_state->next_bucket) {
    // fmt::print("ocean-near: early exit!\n");
    return;
  }

  {
    auto p = prof.make_scoped_child("texture");
    m_texture_renderer.handle_ocean_texture_jak2(dma, render_state, p);
  }

  if (dma.current_tag().qwc != 2) {
    lg::error("abort OceanNear::render!");
    while (dma.current_tag_offset() != render_state->next_bucket) {
      dma.read_and_advance();
    }
    return;
  }

  // direct setup
  {
    m_common_ocean_renderer.init_for_near();
    auto setup = dma.read_and_advance();
    ASSERT(setup.vifcode0().kind == VifCode::Kind::NOP);
    ASSERT(setup.vifcode1().kind == VifCode::Kind::DIRECT);
    ASSERT(setup.size_bytes == 32);
  }

  // offset and base
  {
    auto ob = dma.read_and_advance();
    ASSERT(ob.size_bytes == 0);
    auto base = ob.vifcode0();
    auto off = ob.vifcode1();
    ASSERT(base.kind == VifCode::Kind::BASE);
    ASSERT(off.kind == VifCode::Kind::OFFSET);
    ASSERT(base.immediate == VU1_INPUT_BUFFER_BASE);
    ASSERT(off.immediate == VU1_INPUT_BUFFER_OFFSET);
  }

  while (!is_end_tag(dma.current_tag(), dma.current_tag_vif0(), dma.current_tag_vif1())) {
    auto data = dma.read_and_advance();
    auto v0 = data.vifcode0();
    auto v1 = data.vifcode1();

    if (v0.kind == VifCode::Kind::STCYCL && v1.kind == VifCode::Kind::UNPACK_V4_32) {
      ASSERT(v0.immediate == 0x404);
      auto up = VifCodeUnpack(v1);
      u16 addr = up.addr_qw + (up.use_tops_flag ? get_upload_buffer() : 0);
      ASSERT(addr + v1.num <= 1024);
      memcpy(m_vu_data + addr, data.data, 16 * v1.num);
    } else if (v0.kind == VifCode::Kind::MSCALF && v1.kind == VifCode::Kind::STMOD) {
      ASSERT(v1.immediate == 0);
      switch (v0.immediate) {
        case 0:
          run_call0_vu2c_jak2();
          break;
        case 39:
          run_call39_vu2c_jak2();
          break;
        default:
          ASSERT_MSG(false, fmt::format("unknown ocean near call: {}", v0.immediate));
      }
    }
  }

  while (dma.current_tag_offset() != render_state->next_bucket) {
    dma.read_and_advance();
  }

  m_common_ocean_renderer.flush_near(render_state, prof);
}

void OceanNear::xgkick(u16 addr) {
  m_common_ocean_renderer.kick_from_near((const u8*)&m_vu_data[addr]);
}
