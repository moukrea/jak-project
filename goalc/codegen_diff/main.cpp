// goalc-codegen-diff
//
// Phase A1 of the ARM64 differential-codegen harness. Compiles a single GOAL
// form (or .gc file) to IR ONCE, then runs the full color + codegen pipeline
// through BOTH the x86-64 and ARM64 backends inside this single x86 process and
// prints a per-IR-node side-by-side disassembly diff (Zydis vs Capstone),
// flagging structural anomalies (unbalanced stack spills and undeclared /
// unprotected writes to allocatable registers — the "live-register clobber"
// class behind the A17 idiv-spill / X8 bug).
//
// IMPORTANT honesty note that this tool surfaces in its own output:
//   The GOAL register allocator is parametrised on x86 at COMPILE TIME
//   (emitter::gRegInfo is always the x86 register file; the arm64-only
//   allocator tweaks in Allocator_v2.cpp are behind #ifdef GOALC_BACKEND_ARM64
//   and are compiled OUT of this x86 binary). The ARM64 emitter then maps the
//   x86 register ids directly onto AArch64 registers (id & 0x1f). So in this
//   binary the SAME (x86-shaped) coloring feeds both backends. We still run the
//   full color pipeline before each backend's codegen, but the two colorings
//   are identical here. For call-adjacent / function-crosser nodes the on-device
//   ARM64 build may color differently than what this tool shows.
//
// This tool only CONSTRUCTS CodeGenerator and READS DebugInfo; it never modifies
// the codegen emit path.

#include <algorithm>
#include <cctype>
#include <filesystem>
#include <fstream>
#include <map>
#include <set>
#include <string>
#include <unordered_map>
#include <vector>

#include "common/log/log.h"
#include "common/util/FileUtil.h"
#include "common/versions/versions.h"

#include "goalc/compiler/CodeGenerator.h"
#include "goalc/compiler/Compiler.h"
#include "goalc/compiler/Env.h"
#include "goalc/compiler/IR.h"
#include "goalc/compiler/Val.h"
#include "goalc/debugger/DebugInfo.h"
#include "goalc/debugger/disassemble.h"
#include "goalc/emitter/InstructionSet.h"
#include "goalc/emitter/Register.h"
#include "goalc/regalloc/Allocator.h"
#include "goalc/regalloc/Allocator_v2.h"
#include "goalc/regalloc/allocator_interface.h"

#include "fmt/format.h"

namespace {

struct Options {
  std::string input;     // path to a .gc file
  std::string form;      // inline GOAL form (wrapped in a function)
  std::string function;  // only report this function (default: all)
  std::string out;       // output file (default: stdout)
  bool fail_on_anomaly = false;
  bool prelude = true;    // load all-types so library symbols (format, ...) resolve
  bool all_inputs = false;  // run across test/diff/inputs/*.gc
  bool strip_spill = false;  // negative control: simulate removal of arm64 spill save/restore
  std::string game = "jak1";
};

void print_usage() {
  fmt::print(
      "goalc-codegen-diff — per-IR x86 vs ARM64 codegen differ\n"
      "Usage:\n"
      "  goalc-codegen-diff --form \"<goal form>\" [options]\n"
      "  goalc-codegen-diff --input <file.gc> [options]\n"
      "  goalc-codegen-diff --all-inputs [options]\n"
      "Options:\n"
      "  --function <name>     only report this function (default: all)\n"
      "  --out <file>          write report to file (default: stdout)\n"
      "  --fail-on-anomaly     exit non-zero if any anomaly is flagged\n"
      "  --no-prelude          do not load all-types (library symbols won't resolve)\n"
      "  --game <jak1|jak2|jak3>  game version for the type system (default jak1)\n"
      "  --strip-spill         NEGATIVE CONTROL: ignore arm64 spill save/restore in the\n"
      "                        hazard analysis, to confirm the clobber detector fires\n");
}

// AArch64 register name for an x86-model GPR id (the allocator's id() is mapped
// onto AArch64 by the emitter as id & 0x1f). Returns "" for non-GPR ids.
std::string arm64_gpr_name(int x86_id) {
  if (x86_id >= emitter::RAX && x86_id <= emitter::R15) {
    return "x" + std::to_string(x86_id);
  }
  return "";
}

// The set of AArch64 GPR names the register allocator is able to assign a live
// value to (derived from the x86 spill allocation order). A write to one of
// these that the IR's to_rai() does not declare, and that is not save/restore
// balanced, is a potential live-register clobber.
std::set<std::string> allocatable_arm64_gprs() {
  std::set<std::string> s;
  for (auto r : emitter::gRegInfo.get_gpr_spill_alloc_order()) {
    auto n = arm64_gpr_name(r.id());
    if (!n.empty()) {
      s.insert(n);
    }
  }
  return s;
}

bool is_arm64_gpr_name(const std::string& n) {
  if (n.size() < 2 || n[0] != 'x') {
    return false;
  }
  for (size_t i = 1; i < n.size(); i++) {
    if (!std::isdigit((unsigned char)n[i])) {
      return false;
    }
  }
  return true;
}

// Replicates Compiler::color_object_file (which is private) using the public
// regalloc entry points, and returns a copy of each function's allocation so we
// can interpret the emitted code against the allocator's model.
std::unordered_map<std::string, AllocationResult> color_file(FileEnv* env) {
  std::unordered_map<std::string, AllocationResult> results;
  for (auto& f : env->functions()) {
    AllocationInput input;
    input.is_asm_function = f->is_asm_func;
    for (auto& i : f->code()) {
      input.instructions.push_back(i->to_rai());
    }
    for (auto& reg_val : f->reg_vals()) {
      if (reg_val->forced_on_stack()) {
        input.force_on_stack_regs.insert(reg_val->ireg().id);
      }
    }
    input.max_vars = f->max_vars();
    input.constraints = f->constraints();
    input.stack_slots_for_stack_vars = f->stack_slots_used_for_stack_vars();
    input.function_name = f->name();

    AllocationResult result = allocate_registers_v2(input);
    if (!result.ok) {
      result = allocate_registers(input);
    }
    results[f->name()] = result;
    f->set_allocations(std::move(result));
  }
  return results;
}

struct GroupKey {
  int kind = 0;     // 0 prologue, 1 IR, 2 epilogue
  int ir_idx = -1;  // valid for kind == 1
  bool operator<(const GroupKey& o) const {
    if (kind != o.kind) {
      return kind < o.kind;
    }
    return ir_idx < o.ir_idx;
  }
  bool operator==(const GroupKey& o) const { return kind == o.kind && ir_idx == o.ir_idx; }
};

// Map each decoded machine instruction to the IR node / prologue / epilogue it
// belongs to, by walking the per-emitter-instruction offsets in DebugInfo.
std::vector<GroupKey> assign_groups(const std::vector<DecodedInstr>& decoded,
                                    const std::vector<InstructionInfo>& iinfo) {
  std::vector<GroupKey> keys;
  keys.reserve(decoded.size());
  int cur = -1;
  for (const auto& di : decoded) {
    while (cur + 1 < (int)iinfo.size() && iinfo[cur + 1].offset == di.offset) {
      cur++;
    }
    GroupKey k;
    if (cur >= 0 && cur < (int)iinfo.size()) {
      const auto& ii = iinfo[cur];
      if (ii.kind == InstructionInfo::Kind::PROLOGUE) {
        k = {0, -1};
      } else if (ii.kind == InstructionInfo::Kind::EPILOGUE) {
        k = {2, -1};
      } else {
        k = {1, ii.ir_idx};
      }
    }
    keys.push_back(k);
  }
  return keys;
}

std::string join(const std::vector<std::string>& v, const std::string& sep) {
  std::string out;
  for (size_t i = 0; i < v.size(); i++) {
    if (i) {
      out += sep;
    }
    out += v[i];
  }
  return out;
}

std::string truncate(std::string s, size_t w) {
  if (s.size() > w) {
    s = s.substr(0, w - 2) + "..";
  }
  return s;
}

void render_side_by_side(std::string& out,
                         const std::vector<std::string>& left,
                         const std::vector<std::string>& right) {
  const size_t W = 50;
  size_t n = std::max(left.size(), right.size());
  if (n == 0) {
    out += "    (no machine code)\n";
    return;
  }
  for (size_t i = 0; i < n; i++) {
    std::string l = i < left.size() ? truncate(left[i], W) : "";
    std::string r = i < right.size() ? right[i] : "";
    out += fmt::format("    {:<50} | {}\n", l, r);
  }
}

// Physical AArch64 GPR names declared by an IR node's allocation model: the
// destination/operand registers (mapped through the allocation) plus the
// explicit clobber/exclude registers from to_rai.
std::set<std::string> declared_gprs_for_node(IR* ir,
                                             const AllocationResult& alloc,
                                             int ir_idx) {
  std::set<std::string> declared;
  RegAllocInstr rai = ir->to_rai();
  auto add_vreg = [&](const IRegister& vr) {
    if (vr.id < 0 || vr.id >= (int)alloc.ass_as_ranges.size()) {
      return;
    }
    const auto& range = alloc.ass_as_ranges.at(vr.id);
    if (!range.has_info_at(ir_idx)) {
      return;
    }
    const auto& a = range.get(ir_idx);
    if (a.kind == Assignment::Kind::REGISTER) {
      auto n = arm64_gpr_name(a.reg.id());
      if (!n.empty()) {
        declared.insert(n);
      }
    }
  };
  for (const auto& w : rai.write) {
    add_vreg(w);
  }
  for (const auto& r : rai.read) {
    add_vreg(r);
  }
  for (const auto& c : rai.clobber) {
    auto n = arm64_gpr_name(c.id());
    if (!n.empty()) {
      declared.insert(n);
    }
  }
  for (const auto& e : rai.exclude) {
    auto n = arm64_gpr_name(e.id());
    if (!n.empty()) {
      declared.insert(n);
    }
  }
  return declared;
}

// Result of analyzing one IR node's ARM64 emission.
struct NodeAnomalies {
  std::vector<std::string> messages;
};

NodeAnomalies analyze_node(const std::vector<DecodedInstr>& arm_instrs,
                           IR* ir,
                           const AllocationResult& alloc,
                           int ir_idx,
                           const std::set<std::string>& allocatable,
                           bool strip_spill) {
  NodeAnomalies res;

  std::set<std::string> saved, restored, written;
  for (const auto& di : arm_instrs) {
    bool is_spill_op = di.is_store_to_stack || di.is_load_from_stack || di.sp_delta != 0;
    if (strip_spill && is_spill_op) {
      // Negative control: pretend the spill save/restore wrapper is absent.
      continue;
    }
    if (di.is_store_to_stack) {
      for (const auto& r : di.stack_xfer_regs) {
        if (is_arm64_gpr_name(r)) {
          saved.insert(r);
        }
      }
    }
    if (di.is_load_from_stack) {
      for (const auto& r : di.stack_xfer_regs) {
        if (is_arm64_gpr_name(r)) {
          restored.insert(r);
        }
      }
    }
    for (const auto& r : di.regs_written) {
      if (is_arm64_gpr_name(r)) {
        written.insert(r);
      }
    }
  }

  // A register that is both stored to and loaded from the stack within this
  // node is a save/restore-balanced scratch (e.g. the A17 idiv X8 spill); its
  // value is preserved across the node. Note we deliberately do NOT flag a
  // lone stack store as "unbalanced": storing a stack-homed variable to its
  // home slot is normal codegen and has no matching same-node load.
  std::set<std::string> balanced;
  std::set_intersection(saved.begin(), saved.end(), restored.begin(), restored.end(),
                        std::inserter(balanced, balanced.begin()));

  // Live-register clobber: a write to an allocatable GPR that the IR's
  // allocation model does not declare and that is not save/restore balanced.
  std::set<std::string> declared = declared_gprs_for_node(ir, alloc, ir_idx);
  std::vector<std::string> hazards;
  for (const auto& w : written) {
    if (allocatable.count(w) && !declared.count(w) && !balanced.count(w)) {
      hazards.push_back(w);
    }
  }
  if (!hazards.empty()) {
    std::sort(hazards.begin(), hazards.end());
    res.messages.push_back(fmt::format(
        "LIVE_CLOBBER: writes allocatable register(s) {} that this IR's to_rai() does not "
        "declare and that are not save/restore-balanced — any live value the allocator placed "
        "there is corrupted{}",
        join(hazards, ", "), strip_spill ? " [negative control: spill removed]" : ""));
  }

  return res;
}

// Compile a single unit (already-read goos code) and emit the diff report.
// Returns the number of anomalies flagged, or -1 on compile failure.
int process_unit(Compiler& compiler,
                 const std::string& label,
                 goos::Object code,
                 GameVersion version,
                 const Options& opts,
                 std::string& out) {
  FileEnv* fe = nullptr;
  try {
    fe = compiler.compile_object_file(label, code, true);
  } catch (std::exception& e) {
    out += fmt::format("==== {} ====\nCOMPILE ERROR: {}\n\n", label, e.what());
    return -1;
  }
  if (!fe || fe->functions().empty()) {
    out += fmt::format("==== {} ====\n(no functions emitted)\n\n", label);
    return 0;
  }

  // Full color + codegen pipeline, once per backend. (In this x86 binary both
  // colorings are identical — see the file header note — but we run the whole
  // pipeline each time as the harness requires.)
  DebugInfo dbg_x86("codegen-diff-x86");
  DebugInfo dbg_arm("codegen-diff-arm64");
  std::unordered_map<std::string, AllocationResult> alloc;
  try {
    color_file(fe);
    CodeGenerator gen_x86(fe, &dbg_x86, version, emitter::InstructionSet::X86);
    gen_x86.run(&compiler.type_system());

    alloc = color_file(fe);  // capture allocation (identical), used for analysis
    CodeGenerator gen_arm(fe, &dbg_arm, version, emitter::InstructionSet::ARM64);
    gen_arm.run(&compiler.type_system());
  } catch (std::exception& e) {
    out += fmt::format("==== {} ====\nCODEGEN ERROR: {}\n\n", label, e.what());
    return -1;
  }

  int anomaly_count = 0;
  out += fmt::format("==== {} ====\n", label);

  for (auto& f : fe->functions()) {
    const std::string& fname = f->name();
    if (!opts.function.empty() && fname != opts.function) {
      continue;
    }

    FunctionDebugInfo* fx;
    FunctionDebugInfo* fa;
    try {
      fx = &dbg_x86.function_by_name(fname);
      fa = &dbg_arm.function_by_name(fname);
    } catch (std::exception&) {
      continue;
    }
    const auto alloc_it = alloc.find(fname);
    if (alloc_it == alloc.end()) {
      continue;
    }
    const AllocationResult& fa_alloc = alloc_it->second;

    auto dec_x86 = decode_x86(fx->generated_code.data(), (int)fx->generated_code.size(), 0);
    auto dec_arm = decode_arm64(fa->generated_code.data(), (int)fa->generated_code.size(), 0);
    auto keys_x86 = assign_groups(dec_x86, fx->instructions);
    auto keys_arm = assign_groups(dec_arm, fa->instructions);

    std::set<GroupKey> keyset;
    for (auto& k : keys_x86) {
      keyset.insert(k);
    }
    for (auto& k : keys_arm) {
      keyset.insert(k);
    }
    std::vector<GroupKey> ordered(keyset.begin(), keyset.end());

    out += fmt::format("\n  [function {}]  x86={} bytes / arm64={} bytes\n", fname,
                       fx->generated_code.size(), fa->generated_code.size());

    const auto allocatable = allocatable_arm64_gprs();

    for (const auto& k : ordered) {
      std::string header;
      if (k.kind == 0) {
        header = "PROLOGUE";
      } else if (k.kind == 2) {
        header = "EPILOGUE";
      } else {
        std::string irs = (k.ir_idx >= 0 && k.ir_idx < (int)fx->ir_strings.size())
                              ? fx->ir_strings[k.ir_idx]
                              : "?";
        header = fmt::format("IR {}: {}", k.ir_idx, irs);
      }

      std::vector<std::string> left, right;
      std::vector<DecodedInstr> arm_node;
      for (size_t i = 0; i < dec_x86.size(); i++) {
        if (keys_x86[i] == k) {
          left.push_back(dec_x86[i].text);
        }
      }
      for (size_t i = 0; i < dec_arm.size(); i++) {
        if (keys_arm[i] == k) {
          right.push_back(dec_arm[i].text);
          arm_node.push_back(dec_arm[i]);
        }
      }

      out += fmt::format("  {}\n", header);
      if ((int)left.size() != (int)right.size()) {
        out += fmt::format("    [count x86={} arm64={}]\n", left.size(), right.size());
      }
      render_side_by_side(out, left, right);

      // Anomaly analysis only on real IR nodes (not prologue/epilogue, which
      // legitimately adjust sp on their own).
      if (k.kind == 1 && k.ir_idx >= 0 && k.ir_idx < (int)f->code().size()) {
        IR* ir = f->code().at(k.ir_idx).get();
        auto an = analyze_node(arm_node, ir, fa_alloc, k.ir_idx, allocatable, opts.strip_spill);
        for (const auto& m : an.messages) {
          out += fmt::format("    !! ANOMALY: {}\n", m);
          anomaly_count++;
        }
      }
    }
    out += "\n";
  }

  return anomaly_count;
}

}  // namespace

int main(int argc, char** argv) {
  lg::set_stdout_level(lg::level::warn);
  lg::set_flush_level(lg::level::warn);
  lg::initialize();

  Options opts;
  for (int i = 1; i < argc; i++) {
    std::string a = argv[i];
    auto next = [&](const char* name) -> std::string {
      if (i + 1 >= argc) {
        fmt::print("error: {} requires an argument\n", name);
        std::exit(2);
      }
      return argv[++i];
    };
    if (a == "--input") {
      opts.input = next("--input");
    } else if (a == "--form") {
      opts.form = next("--form");
    } else if (a == "--function") {
      opts.function = next("--function");
    } else if (a == "--out") {
      opts.out = next("--out");
    } else if (a == "--game") {
      opts.game = next("--game");
    } else if (a == "--fail-on-anomaly") {
      opts.fail_on_anomaly = true;
    } else if (a == "--no-prelude") {
      opts.prelude = false;
    } else if (a == "--all-inputs") {
      opts.all_inputs = true;
    } else if (a == "--strip-spill") {
      opts.strip_spill = true;
    } else if (a == "--help" || a == "-h") {
      print_usage();
      return 0;
    } else {
      fmt::print("error: unknown argument '{}'\n", a);
      print_usage();
      return 2;
    }
  }

  if (opts.input.empty() && opts.form.empty() && !opts.all_inputs) {
    print_usage();
    return 2;
  }

  if (!file_util::setup_project_path(std::nullopt)) {
    fmt::print("error: could not locate jak-project directory\n");
    return 1;
  }

  GameVersion version = game_name_to_version(opts.game);

  std::unique_ptr<Compiler> compiler;
  try {
    compiler = std::make_unique<Compiler>(version, emitter::InstructionSet::X86);
  } catch (std::exception& e) {
    fmt::print("error: failed to construct compiler: {}\n", e.what());
    return 1;
  }

  if (opts.prelude) {
    std::string all_types = fmt::format("decompiler/config/{}/all-types.gc", opts.game);
    try {
      compiler->run_test_no_load(all_types);
    } catch (std::exception& e) {
      fmt::print("warning: failed to load prelude {} ({}); library symbols may not resolve\n",
                 all_types, e.what());
    }
  }

  std::string report;
  report += fmt::format(
      "goalc-codegen-diff report (game={})\n"
      "NOTE: register allocation in this binary is compile-time x86; ARM64 codegen maps\n"
      "      x86 register ids onto AArch64 (id & 0x1f). Both backends share this coloring\n"
      "      here, so call-adjacent nodes may differ from the on-device ARM64 build.\n\n",
      opts.game);

  int total_anomalies = 0;
  int compile_failures = 0;
  int units = 0;

  auto run_form = [&](const std::string& form) {
    // Wrap a bare form in a function so it has args (arg0..arg3 : int), a
    // prologue/epilogue, and real codegen.
    std::string wrapped = fmt::format(
        "(defun codegen-diff-fn ((arg0 int) (arg1 int) (arg2 int) (arg3 int)) {})", form);
    goos::Object code = compiler->get_goos().reader.read_from_string(wrapped);
    int n = process_unit(*compiler, "form:" + form, code, version, opts, report);
    units++;
    if (n < 0) {
      compile_failures++;
    } else {
      total_anomalies += n;
    }
  };

  auto run_file = [&](const std::string& path) {
    goos::Object code;
    try {
      code = compiler->get_goos().reader.read_from_file({path});
    } catch (std::exception& e) {
      report += fmt::format("==== {} ====\nREAD ERROR: {}\n\n", path, e.what());
      units++;
      compile_failures++;
      return;
    }
    int n = process_unit(*compiler, path, code, version, opts, report);
    units++;
    if (n < 0) {
      compile_failures++;
    } else {
      total_anomalies += n;
    }
  };

  if (!opts.form.empty()) {
    run_form(opts.form);
  }
  if (!opts.input.empty()) {
    run_file(opts.input);
  }
  if (opts.all_inputs) {
    std::string dir = file_util::get_file_path({"test", "diff", "inputs"});
    std::vector<std::string> files;
    if (std::filesystem::is_directory(dir)) {
      for (const auto& ent : std::filesystem::directory_iterator(dir)) {
        if (ent.is_regular_file() && ent.path().extension() == ".gc") {
          files.push_back(ent.path().string());
        }
      }
    }
    std::sort(files.begin(), files.end());
    for (const auto& f : files) {
      run_file(f);
    }
  }

  report += fmt::format(
      "==== SUMMARY ====\nunits: {}\ncompile/codegen failures: {}\nanomalies: {}\n", units,
      compile_failures, total_anomalies);

  if (opts.out.empty()) {
    fmt::print("{}", report);
  } else {
    std::ofstream f(opts.out);
    f << report;
    f.close();
    fmt::print("wrote report to {} ({} units, {} anomalies, {} failures)\n", opts.out, units,
               total_anomalies, compile_failures);
  }

  if (opts.fail_on_anomaly && total_anomalies > 0) {
    return 1;
  }
  return 0;
}
