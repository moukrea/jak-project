#!/usr/bin/env python3
"""Conservative source guard, not a C++/GLSL parser or a runtime verdict.

Small contiguous blocks pin the delivered control flow. Equivalent refactors may
require review. Comments and string literals cannot supply matching source code.
"""

from pathlib import Path
import re
import sys


def normalize(source):
    tokens = r'//[^\n]*|/\*[\s\S]*?\*/|"(?:\\.|[^"\\])*"|\'(?:\\.|[^\'\\])*\''
    source = re.sub(tokens, lambda m: " " if m[0].startswith("/") else '""', source)
    return re.sub(r"\s+", "", source)


def check_sources(root):
    """Return structural defects found in the source tree rooted at root."""
    root = Path(root) / "game/graphics/opengl_renderer"
    defects = []
    cache = {}

    def require(path, label, snippet):
        if path not in cache:
            try:
                cache[path] = normalize((root / path).read_text())
            except (OSError, UnicodeError) as error:
                defects.append(f"{path}: source unreadable: {error}")
                cache[path] = ""
        # Require a unique contiguous block, including its branch braces.
        if cache[path].count(normalize(snippet)) != 1:
            defects.append(f"{path}: {label} block missing, changed or duplicated")

    require("background/Shrub.cpp", "carried pivot and positive span", """
        const bool carried = si.carried && autoport_proof::armed_for(kTrunkItemId);
        const float pivot_y = carried ? si.contact_pin_y : si.base_y;
        if (!(si.ymax > pivot_y)) { continue; }
        const bool trunk = si.load_bearing && autoport_proof::armed_for(kTrunkItemId);
        foliage_wind::trunk_note_anchor(si, !trunk, pivot_y);
        if (trunk) { continue; }
        float* anchor = &contact_lut[(n_mat + mi) * 4];
        anchor[0] = si.x;
        anchor[1] = si.base_y;
        anchor[2] = si.z;
        anchor[3] = si.ymax - pivot_y;
        if (carried) {
          float* attachment = &contact_lut[(2 * n_mat + mi) * 4];
          attachment[0] = pivot_y;
          attachment[1] = 1.f;
        }
        ++contact_instances;
    """)
    # TIE tables are produced in LoaderStages.cpp, not Tie3.cpp.
    require("loader/LoaderStages.cpp", "TIE trunk exclusion and attachment", """
        const bool trunk = si_it->second->load_bearing && trunk_armed;
        if (trunk) { contact_vi += count; continue; }
        for (size_t k = 0; k < count && contact_vi + k < contact_nv; ++k) {
          if (contact_flags[contact_vi + k] != 1) continue;
          auto inserted = contact_lut_index.emplace((u32)group.matrix_idx,
                                                    (u32)contact_anchors.size());
          if (inserted.second) {
            const auto& si = *si_it->second;
            const float pivot_y = si.carried && trunk_armed ? si.contact_pin_y : si.base_y;
            contact_anchors.push_back({si.x, si.base_y, si.z, si.ymax - pivot_y});
            contact_pins.push_back(si.carried && trunk_armed
                ? std::array<float, 4>{pivot_y, 1.f, 0.f, 0.f}
                : std::array<float, 4>{0.f, 0.f, 0.f, 0.f});
          }
          contact_indices[contact_vi + k] = inserted.first->second;
          ++contact_verts;
        }
    """)
    require("loader/LoaderStages.cpp", "TIE positive span", """
        for (const auto& si : in_tree.sway_instances) {
          const float pivot_y = si.carried && trunk_armed ? si.contact_pin_y : si.base_y;
          if (si.valid && si.ymax > pivot_y) contact_instances[si.matrix_idx] = &si;
        }
    """)
    # TIE shares tie_sway.glsl; there is no tie.vert in this renderer.
    for path, enabled, fetch, position, output in (
        ("shaders/shrub.vert", "u_shrub_contact_on == 1",
         "tex_T18, ivec2(shrub_inst_in, ROW), 0", "position_in", "wpos"),
        ("shaders/tie_sway.glsl", "u_tie_contact_on == 1 && tie_contact_index != 0u",
         "u_tie_contact_tex, ivec2(int(tie_contact_index), ROW), 0", "original", "bent"),
    ):
        anchor_row = "1" if position == "position_in" else "0"
        pin_row = "2" if position == "position_in" else "1"
        require(path, "contact branch preserves carried plane", f"""
          if ({enabled}) {{
            vec4 anchor = texelFetch({fetch.replace('ROW', anchor_row)});
            if (anchor.w > 0.0) {{
              vec4 attachment = texelFetch({fetch.replace('ROW', pin_row)});
              bool carried = attachment.y > 0.0;
              float dy = carried ? max(0.0, {position}.y - attachment.x)
                                 : {position}.y - anchor.y;
              if (!carried || dy > 0.0) {{
                float heightMul;
                vec3 trample;
                float debug_contact = 0.0;
                vegetation_contact(anchor.xyz, anchor.w, 0, heightMul, trample, debug_contact);
                {output}.y += dy * (heightMul - 1.0);
                {output} += trample * (dy / anchor.w);
              }}
            }}
          }}
        """)
    require("background/foliage_wind.cpp", "classification entry", """
        void classify_load_bearing(tfrag3::Level& lev) {
          std::vector<VegInst> veg;
          gather_contact_instances(lev, veg);
    """)
    require("background/foliage_wind.cpp", "trunk classification and initial pin", """
        for (auto& v : veg) {
          v.si->load_bearing = trunk_protos.count(*v.proto) != 0;
          v.si->carried = false;
          v.si->contact_pin_y = v.si->ymin;
          if (v.si->load_bearing) {
            trunk_instances++;
            trunk_verts += v.si->n_verts;
          }
        }
    """)
    require("background/foliage_wind.cpp", "carried pin from support geometry", """
        for (size_t i = 0; i < all_veg.size(); i++) {
          const auto& carrier = all_veg[i];
          if (!carrier.si->load_bearing) continue;
          for (size_t j = 0; j < all_veg.size(); j++) {
            const auto& target = all_veg[j];
            if (supports(carrier, target)) {
              target.si->carried = true;
              target.si->contact_pin_y = std::max(target.si->contact_pin_y, carrier.si->ymax);
              if (i < veg.size() && j < veg.size()) joint_pairs++;
            }
          }
        }
    """)
    require("background/foliage_wind.cpp", "final geometry height production", """
        auto inserted = final_ymax.emplace(si, v.y);
        if (!inserted.second) inserted.first->second = std::max(inserted.first->second, v.y);
    """)
    require("background/foliage_wind.cpp", "post-weld contact pin", """
        for (const auto& carrier : veg) {
          if (!carrier.si->load_bearing) continue;
          const auto ymax = final_ymax.find(carrier.si);
          if (ymax == final_ymax.end()) continue;
          for (const auto& target : veg) {
            if (supports(carrier, target)) {
              target.si->contact_pin_y = std::max(target.si->contact_pin_y, ymax->second);
            }
          }
        }
    """)
    require("loader/Loader.cpp", "classification after sidecar", """
        tfrag3::foliage_wind_finalize_level(*result);
        foliage_wind::classify_load_bearing(*result);
    """)
    require("loader/Loader.cpp", "final geometry call", """
        {
          auto p = scoped_prof("foliage-contact-final-geometry");
          foliage_wind::finalize_contact_geometry(*result);
        }
    """)
    return defects


def main():
    root = Path(sys.argv[1]) if len(sys.argv) > 1 else Path(__file__).resolve().parents[3]
    print("[shrub-trunk-contact] Invariants STRUCTURELS source uniquement; "
          "aucun résultat GPU/Android/mouvement.")
    defects = check_sources(root)
    for defect in defects:
        print(f"FAIL: {defect}")
    if not defects:
        print("PASS: blocs source conservés (garde locale de non-régression).")
    return int(bool(defects))


if __name__ == "__main__":
    sys.exit(main())
