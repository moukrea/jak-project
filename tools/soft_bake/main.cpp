// Read-only, deterministic baseline of extracted Jak 1 geometry. Units are GOAL units.
#include <algorithm>
#include <array>
#include <cmath>
#include <fstream>
#include <iostream>
#include <map>
#include <numeric>
#include <set>
#include <tuple>

#include "common/custom_data/Tfrag3Data.h"
#include "common/util/FileUtil.h"
#include "common/util/Serializer.h"
#include "common/util/compress.h"

#include "third-party/json.hpp"
using J = nlohmann::json;
constexpr double M = 4096.;
struct P {
  double x, y, z;
  P operator-(P b) const { return {x - b.x, y - b.y, z - b.z}; }
};
P cross(P a, P b) {
  return {a.y * b.z - a.z * b.y, a.z * b.x - a.x * b.z, a.x * b.y - a.y * b.x};
}
double norm(P a) {
  return std::sqrt(a.x * a.x + a.y * a.y + a.z * a.z);
}
struct Tri {
  P a, b, c;
  int mat = 0, mode = 0;
};
P mid(const Tri& t) {
  return {(t.a.x + t.b.x + t.c.x) / 3, (t.a.y + t.b.y + t.c.y) / 3, (t.a.z + t.b.z + t.c.z) / 3};
}
bool height(const Tri& t, P p, double& y) {
  double d = (t.b.z - t.c.z) * (t.a.x - t.c.x) + (t.c.x - t.b.x) * (t.a.z - t.c.z);
  if (std::abs(d) < 1e-8)
    return false;
  double a = ((t.b.z - t.c.z) * (p.x - t.c.x) + (t.c.x - t.b.x) * (p.z - t.c.z)) / d;
  double b = ((t.c.z - t.a.z) * (p.x - t.c.x) + (t.a.x - t.c.x) * (p.z - t.c.z)) / d;
  if (a < -1e-6 || b < -1e-6 || a + b > 1.000001)
    return false;
  y = a * t.a.y + b * t.b.y + (1 - a - b) * t.c.y;
  return true;
}
J stats(std::vector<double> v) {
  if (v.empty())
    return nullptr;
  std::sort(v.begin(), v.end());
  double med = (v[(v.size() - 1) / 2] + v[v.size() / 2]) / 2;
  double avg = std::accumulate(v.begin(), v.end(), 0.) / v.size();
  double ab = 0, sq = 0;
  for (double x : v) {
    ab += std::abs(x);
    sq += x * x;
  }
  ab /= v.size();
  sq = std::sqrt(sq / v.size());
  return {
      {"samples", v.size()},  {"mean_abs_u", ab},       {"mean_abs_m", ab / M}, {"rms_u", sq},
      {"rms_m", sq / M},      {"min_u", v.front()},     {"median_u", med},      {"mean_u", avg},
      {"max_u", v.back()},    {"min_m", v.front() / M}, {"median_m", med / M},  {"mean_m", avg / M},
      {"max_m", v.back() / M}};
}
template <class F>
void indices(const std::vector<u32>& ind, size_t start, size_t count, bool strip, F f) {
  std::vector<u32> run;
  for (size_t i = start; i < start + count; i++) {
    u32 x = ind.at(i);
    if (x == UINT32_MAX) {
      run.clear();
      continue;
    }
    run.push_back(x);
    size_t n = run.size();
    if (strip && n >= 3) {
      u32 a = run[n - 3], b = run[n - 2], c = x;
      if (n % 2 == 0)
        std::swap(a, b);
      if (a != b && a != c && b != c)
        f(a, b, c);
    } else if (!strip && n == 3) {
      f(run[0], run[1], run[2]);
      run.clear();
    }
  }
}
template <class V>
Tri triangle(const V& vs, u32 a, u32 b, u32 c) {
  const auto& x = vs.at(a);
  const auto& y = vs.at(b);
  const auto& z = vs.at(c);
  return {{x.x, x.y, x.z}, {y.x, y.y, y.z}, {z.x, z.y, z.z}};
}
struct Instance {
  int tree, mat, proto;
  std::string name;
  std::vector<Tri> tris;
};
J analyze(const std::string& path, const std::string& name) {
  auto raw = file_util::read_binary_file(path);
  auto data = compression::decompress_zstd(raw.data(), raw.size());
  Serializer ser(data.data(), data.size());
  tfrag3::Level lev;
  lev.serialize(ser);
  J out = {{"level", name}, {"census", J::array()}};
  std::array<size_t, 64> counts{};
  std::array<double, 64> areas{};
  std::vector<Tri> coll, deep;
  const auto& cv = lev.collision.vertices;
  for (size_t i = 0; i + 2 < cv.size(); i += 3) {
    Tri t = triangle(cv, i, i + 1, i + 2);
    t.mat = (cv[i].pat >> 6) & 63;
    t.mode = (cv[i].pat >> 3) & 7;
    counts[t.mat]++;
    areas[t.mat] += norm(cross(t.b - t.a, t.c - t.a)) / 2;
    coll.push_back(t);
    if (t.mat == 10)
      deep.push_back(t);
  }
  for (int m = 0; m < 64; m++)
    out["census"].push_back({{"pat_material", m},
                             {"triangles", counts[m]},
                             {"area_u2", areas[m]},
                             {"area_m2", areas[m] / (M * M)}});
  if (name == "snow" || name == "beach" || name == "training" || name == "village1") {
    // Spatial hash contains all collision faces, including noneligible blockers.
    std::map<std::pair<int, int>, std::vector<size_t>> grid;
    auto cell = [](double x) { return int(std::floor(x / (8 * M))); };
    for (size_t i = 0; i < coll.size(); i++) {
      auto& t = coll[i];
      for (int x = cell(std::min({t.a.x, t.b.x, t.c.x}));
           x <= cell(std::max({t.a.x, t.b.x, t.c.x})); x++)
        for (int z = cell(std::min({t.a.z, t.b.z, t.c.z}));
             z <= cell(std::max({t.a.z, t.b.z, t.c.z})); z++)
          grid[{x, z}].push_back(i);
    }
    std::vector<double> edges;
    size_t eligible = 0, candidates = 0, unsupported = 0;
    for (auto& t : lev.tfrag_trees[0]) {
      t.unpack();
      for (auto& d : t.draws) {
        if (d.tree_tex_id < 0 || size_t(d.tree_tex_id) >= lev.textures.size())
          continue;
        auto tex = lev.textures[d.tree_tex_id].debug_name;
        bool semantic = tex.find("snow") != std::string::npos ||
                        tex.find("sand") != std::string::npos ||
                        tex.find("beach") != std::string::npos;
        if (!semantic)
          continue;
        size_t n = 0;
        for (auto& g : d.vis_groups)
          n += g.num_inds;
        indices(t.unpacked.indices, d.unpacked.idx_of_first_idx_in_full_buffer, n, t.use_strips,
                [&](u32 a, u32 b, u32 c) {
                  Tri q = triangle(t.unpacked.vertices, a, b, c);
                  P normal = cross(q.b - q.a, q.c - q.a);
                  double len = norm(normal);
                  if (len == 0 || std::abs(normal.y) / len < 0.7)
                    return;
                  candidates++;
                  P p = mid(q);
                  double closest = 1e100;
                  const Tri* support = nullptr;
                  for (size_t k : grid[{cell(p.x), cell(p.z)}]) {
                    double y;
                    if (height(coll[k], p, y) && std::abs(p.y - y) < closest) {
                      closest = std::abs(p.y - y);
                      support = &coll[k];
                    }
                  }
                  if (!support || closest > 0.5 * M) {
                    unsupported++;
                    return;
                  }
                  if ((support->mat != 5 && support->mat != 9) || support->mode == 1)
                    return;
                  eligible++;
                  edges.push_back(norm(q.a - q.b));
                  edges.push_back(norm(q.b - q.c));
                  edges.push_back(norm(q.c - q.a));
                });
      }
    }
    out["density"] = {{"geom", 0},
                      {"eligible_triangles", eligible},
                      {"texture_slope_candidates", candidates},
                      {"no_support_within_0_5m", unsupported},
                      {"edge", stats(edges)}};
  }
  if (name == "snow" || name == "ogre") {
    std::vector<int> parent(deep.size());
    std::iota(parent.begin(), parent.end(), 0);
    auto root = [&](int i) {
      while (parent[i] != i) {
        parent[i] = parent[parent[i]];
        i = parent[i];
      }
      return i;
    };
    std::map<std::tuple<double, double, double>, int> vmap;
    for (size_t i = 0; i < deep.size(); i++)
      for (P p : {deep[i].a, deep[i].b, deep[i].c}) {
        auto key = std::make_tuple(p.x, p.y, p.z);
        auto [it, newv] = vmap.emplace(key, i);
        if (!newv)
          parent[root(i)] = root(it->second);
      }
    std::map<int, std::vector<Tri>> islands;
    for (size_t i = 0; i < deep.size(); i++)
      islands[root(i)].push_back(deep[i]);
    std::vector<Instance> inst;
    // Geometry 0 only: the other geometry arrays are alternate LODs, not additional instances.
    int ti = 0;
    for (auto& t : lev.tie_trees[0]) {
      t.unpack();
      std::vector<int> vm(t.unpacked.vertices.size(), -1);
      size_t vi = 0;
      for (auto& g : t.packed_vertices.matrix_groups)
        for (u32 k = g.start_vert; k < g.end_vert; k++)
          vm.at(vi++) = g.matrix_idx;
      std::map<std::pair<int, int>, size_t> imap;
      for (auto& d : t.static_draws) {
        size_t start = d.unpacked.idx_of_first_idx_in_full_buffer;
        for (auto& g : d.vis_groups) {
          int proto = g.tie_proto_idx;
          indices(t.unpacked.indices, start, g.num_inds, t.use_strips, [&](u32 a, u32 b, u32 c) {
            int mi = vm.at(a);
            if (mi < 0 || mi != vm.at(b) || mi != vm.at(c))
              return;
            std::string pn = proto < int(t.proto_names.size()) ? t.proto_names[proto] : "UNKNOWN";
            // Keep every prototype: attribution must not depend on a guessed snow-name lexicon.
            auto [it, fresh] = imap.emplace(std::make_pair(mi, proto), inst.size());
            if (fresh)
              inst.push_back({ti, mi, proto, pn, {}});
            inst[it->second].tris.push_back(triangle(t.unpacked.vertices, a, b, c));
          });
          start += g.num_inds;
        }
      }
      ti++;
    }
    out["drifts"] = J::array();
    int id = 0;
    size_t gaps = 0;
    for (auto& [r, tris] : islands) {
      (void)r;
      std::vector<P> samples;
      for (auto& t : tris)
        samples.push_back(mid(t));
      struct Hit {
        size_t idx;
        std::vector<double> dist;
      };
      std::vector<Hit> hits;
      for (size_t ii = 0; ii < inst.size(); ii++) {
        auto& in = inst[ii];
        std::vector<double> dist;
        for (P p : samples) {
          double best = 1e100;
          for (auto& t : in.tris) {
            double y;
            if (height(t, p, y) && std::abs(y - p.y) < std::abs(best))
              best = y - p.y;
          }
          if (std::abs(best) < 10 * M)
            dist.push_back(best);
        }
        if (dist.size() * 2 >= samples.size())
          hits.push_back({ii, std::move(dist)});
      }
      size_t full = std::count_if(hits.begin(), hits.end(),
                                  [&](const Hit& h) { return h.dist.size() == samples.size(); });
      auto score = [](const Hit& h) {
        double v = 0;
        for (double x : h.dist)
          v += x * x;
        return std::sqrt(v / h.dist.size());
      };
      std::stable_sort(hits.begin(), hits.end(), [&](const Hit& a, const Hit& b) {
        if (a.dist.size() != b.dist.size())
          return a.dist.size() > b.dist.size();
        return score(a) < score(b);
      });
      J row = {{"island", id++},
               {"collision_triangles", tris.size()},
               {"samples", samples.size()},
               {"fully_covering_instances", full},
               {"candidates", J::array()}};
      for (auto& h : hits) {
        auto& in = inst[h.idx];
        row["candidates"].push_back({{"tree", in.tree},
                                     {"matrix", in.mat},
                                     {"proto", in.proto},
                                     {"prototype", in.name},
                                     {"matched_samples", h.dist.size()},
                                     {"vertical_gap", stats(h.dist)}});
      }
      // Dominance is geometric and exposed, never guessed from prototype names.
      bool dominant =
          !hits.empty() &&
          (hits.size() == 1 ||
           (hits[0].dist.size() > hits[1].dist.size() && score(hits[0]) < score(hits[1])) ||
           (hits[0].dist.size() == hits[1].dist.size() && score(hits[1]) > 2 * score(hits[0]) &&
            score(hits[1]) - score(hits[0]) > 0.05 * M));
      row["attributed"] = dominant && inst[hits[0].idx].name != "UNKNOWN";
      row["absent_surface_samples"] =
          hits.empty() ? samples.size() : samples.size() - hits[0].dist.size();
      row["attribution_method"] =
          "maximum vertical coverage then RMS-distance dominance (2x and 0.05m margin)";
      row["runner_up_rms_margin_m"] =
          hits.size() > 1 ? J((score(hits[1]) - score(hits[0])) / M) : J(nullptr);
      if (!row["attributed"].get<bool>())
        gaps++;
      out["drifts"].push_back(row);
    }
    out["drift_attribution_gaps"] = gaps;
    out["tie_instances_decoded"] = inst.size();
  }
  return out;
}
int main(int argc, char** argv) {
  if (argc != 4) {
    std::cerr << "usage: soft_bake_bin FR3 LEVEL JSON\n";
    return 2;
  }
  file_util::setup_project_path({});
  auto j = analyze(argv[1], argv[2]);
  std::ofstream f(argv[3]);
  f << j.dump(2) << '\n';
  if (!f)
    return 1;
  return 0;
}
