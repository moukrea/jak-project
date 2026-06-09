// goalc-diff-runner: differential test harness for the OpenGOAL backends.
//
// Phase A2: real compilation + execution.
//
//   x86   : compiles each input with the x86 goalc backend and EXECUTES it on
//           an in-process gk runtime (kernel + engine loaded), capturing the
//           single printed line via the listener.
//   arm64 : compiles each input with the ARM64 goalc backend (real codegen),
//           then attempts execution under the aarch64-linux cross runtime via
//           qemu-aarch64-static. That cross runtime is a boot-driver, not a
//           Deci2 listener, so it cannot run an arbitrary compiled object and
//           capture format output — this is recorded as an HONEST failure with
//           a captured boot probe, never stubbed green.
//
// Because building the engine + booting the runtime is expensive, the heavy
// work is done once over ALL inputs (`--all-inputs`), writing per-input
// captures. ctest then runs one cheap `--check` per (input, backend) that
// compares the captured final_state against the input's `;; expect:` directive.
//
// Capture-artifact layout (written into the capture dir):
//   exit_code   -- integer status of the executed program (or runner stage)
//   stdout      -- complete captured stdout of the executed program
//   stderr      -- diagnostics / failure reason
//   final_state -- last non-empty line of stdout (the "answer")
//
// Runner exit codes:
//   0  -- success (capture written, or --check matched)
//   1  -- failure (CLI/IO error, --check mismatch, or honest exec failure)
//   2  -- input unreadable or missing required directive

#include <algorithm>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <filesystem>
#include <fstream>
#include <iostream>
#include <optional>
#include <sstream>
#include <string>
#include <string_view>
#include <thread>
#include <vector>

#include "common/util/FileUtil.h"
#include "common/versions/versions.h"

#include "game/common/game_common_types.h"
#include "game/runtime.h"
#include "goalc/compiler/Compiler.h"
#include "goalc/emitter/InstructionSet.h"

// note: `namespace fs = std::filesystem;` is already provided by FileUtil.h

namespace {

constexpr int kExitOk = 0;
constexpr int kExitFail = 1;
constexpr int kExitInputError = 2;

struct Args {
  fs::path input;
  std::string backend;
  fs::path capture_dir;
  fs::path capture_root;
  fs::path all_inputs;
  bool check = false;
};

void print_usage(std::ostream& os) {
  os << "usage:\n"
        "  goalc-diff-runner --all-inputs <dir> --backend <x86|arm64> "
        "--capture-root <dir>\n"
        "  goalc-diff-runner --check --input <path.gc> --backend <x86|arm64> "
        "--capture <dir>\n";
}

std::optional<Args> parse_args(int argc, char** argv) {
  Args a;
  for (int i = 1; i < argc; ++i) {
    std::string_view arg = argv[i];
    auto need_value = [&](const char* name) -> const char* {
      if (i + 1 >= argc) {
        std::cerr << "goalc-diff-runner: missing value for " << name << "\n";
        return nullptr;
      }
      return argv[++i];
    };
    if (arg == "--input") {
      const char* v = need_value("--input");
      if (!v) return std::nullopt;
      a.input = v;
    } else if (arg == "--backend") {
      const char* v = need_value("--backend");
      if (!v) return std::nullopt;
      a.backend = v;
    } else if (arg == "--capture") {
      const char* v = need_value("--capture");
      if (!v) return std::nullopt;
      a.capture_dir = v;
    } else if (arg == "--capture-root") {
      const char* v = need_value("--capture-root");
      if (!v) return std::nullopt;
      a.capture_root = v;
    } else if (arg == "--all-inputs") {
      const char* v = need_value("--all-inputs");
      if (!v) return std::nullopt;
      a.all_inputs = v;
    } else if (arg == "--check") {
      a.check = true;
    } else if (arg == "-h" || arg == "--help") {
      print_usage(std::cout);
      std::exit(kExitOk);
    } else {
      std::cerr << "goalc-diff-runner: unknown argument: " << arg << "\n";
      print_usage(std::cerr);
      return std::nullopt;
    }
  }
  if (a.backend != "x86" && a.backend != "arm64") {
    std::cerr << "goalc-diff-runner: backend must be x86 or arm64\n";
    return std::nullopt;
  }
  return a;
}

std::string trim(std::string_view s) {
  size_t b = 0, e = s.size();
  while (b < e && std::isspace(static_cast<unsigned char>(s[b]))) ++b;
  while (e > b && std::isspace(static_cast<unsigned char>(s[e - 1]))) --e;
  return std::string(s.substr(b, e - b));
}

std::optional<std::string> read_expect_directive(const fs::path& input) {
  std::ifstream in(input);
  if (!in) {
    std::cerr << "goalc-diff-runner: cannot open input: " << input << "\n";
    return std::nullopt;
  }
  std::string line;
  const std::string prefix = ";; expect:";
  while (std::getline(in, line)) {
    auto pos = line.find(prefix);
    if (pos != std::string::npos) {
      return trim(std::string_view(line).substr(pos + prefix.size()));
    }
  }
  std::cerr << "goalc-diff-runner: input missing `;; expect:` directive: " << input << "\n";
  return std::nullopt;
}

bool write_file(const fs::path& path, std::string_view contents) {
  std::error_code ec;
  fs::create_directories(path.parent_path(), ec);
  std::ofstream out(path, std::ios::binary | std::ios::trunc);
  if (!out) {
    std::cerr << "goalc-diff-runner: cannot write: " << path << "\n";
    return false;
  }
  out.write(contents.data(), static_cast<std::streamsize>(contents.size()));
  return out.good();
}

std::string read_file(const fs::path& path) {
  std::ifstream in(path, std::ios::binary);
  std::stringstream ss;
  ss << in.rdbuf();
  return ss.str();
}

// The program's printed line (typically `(format #t "~D~%" ...)`) is emitted
// before the listener echoes the return value of the `(main)` call we issue, so
// the answer is the FIRST non-empty captured line, not the last.
std::string first_non_empty_line(const std::string& s) {
  std::stringstream ss(s);
  std::string line;
  while (std::getline(ss, line)) {
    std::string t = trim(line);
    if (!t.empty()) {
      return t;
    }
  }
  return "";
}

struct CaptureResult {
  int exit_code = 0;
  std::string stdout_text;
  std::string stderr_text;
  std::string final_state;
};

void write_capture(const fs::path& dir, const CaptureResult& r) {
  std::error_code ec;
  fs::create_directories(dir, ec);
  write_file(dir / "exit_code", std::to_string(r.exit_code) + "\n");
  write_file(dir / "stdout", r.stdout_text);
  write_file(dir / "stderr", r.stderr_text);
  write_file(dir / "final_state", r.final_state + "\n");
}

std::vector<fs::path> gather_inputs(const fs::path& dir) {
  std::vector<fs::path> out;
  if (fs::is_directory(dir)) {
    for (const auto& e : fs::directory_iterator(dir)) {
      if (e.is_regular_file() && e.path().extension() == ".gc") {
        out.push_back(e.path());
      }
    }
  }
  std::sort(out.begin(), out.end());
  return out;
}

// In-process x86 gk runtime: kernel + engine, headless. Mirrors the proven
// test/goalc with-game fixture (runtime_with_kernel_jak1).
void x86_runtime_thread() {
  const char* argv[] = {"", "-fakeiso", "-debug", "-nosound"};
  GameLaunchOptions opts;
  opts.disable_display = true;
  exec_runtime(opts, 4, argv);
}

// ---- x86: real compile + execute + capture -------------------------------

int run_all_x86(const Args& a) {
  if (!file_util::setup_project_path(std::nullopt)) {
    std::cerr << "goalc-diff-runner: could not locate jak-project dir\n";
    return kExitFail;
  }
  auto inputs = gather_inputs(a.all_inputs);
  if (inputs.empty()) {
    std::cerr << "goalc-diff-runner: no .gc inputs under " << a.all_inputs << "\n";
    return kExitFail;
  }

  Compiler compiler(GameVersion::Jak1, emitter::InstructionSet::X86);
  std::thread runtime_thread;
  try {
    // Build the engine in-compiler (populates the type system; matches the
    // with-game test setup) and boot the runtime.
    compiler.run_test_no_load("test/goalc/source_templates/with_game/test-build-game.gc");
    runtime_thread = std::thread(x86_runtime_thread);
    compiler.run_test_from_file("test/goalc/source_templates/with_game/test-load-game.gc");
    compiler.run_test_from_string("(set! *use-old-listener-print* #t)");
  } catch (std::exception& e) {
    std::cerr << "goalc-diff-runner: x86 runtime setup failed: " << e.what() << "\n";
    if (runtime_thread.joinable()) {
      try {
        compiler.shutdown_target();
      } catch (...) {
      }
      runtime_thread.join();
    }
    return kExitFail;
  }

  int failures = 0;
  for (const auto& in : inputs) {
    const std::string name = in.stem().string();
    fs::path dir = a.capture_root / "x86" / name;
    CaptureResult r;
    try {
      // Load the input (defines main), then invoke it and capture the output.
      compiler.run_test_from_file(in.string());
      auto msgs = compiler.run_test_from_string("(main)");
      std::string out;
      for (const auto& m : msgs) {
        out += m;
      }
      r.stdout_text = out;
      r.final_state = first_non_empty_line(out);
      r.exit_code = 0;
      if (r.final_state.empty()) {
        r.exit_code = 1;
        r.stderr_text = "no output captured from (main)";
        failures++;
      }
    } catch (std::exception& e) {
      r.exit_code = 1;
      r.stderr_text = std::string("x86 compile/exec error: ") + e.what();
      failures++;
    }
    write_capture(dir, r);
    std::cout << "[x86] " << name << " -> "
              << (r.final_state.empty() ? "<none>" : r.final_state) << "\n";
  }

  try {
    compiler.shutdown_target();
  } catch (...) {
  }
  if (runtime_thread.joinable()) {
    runtime_thread.join();
  }
  std::cout << "x86: " << inputs.size() << " inputs, " << failures << " failures\n";
  return kExitOk;  // setup itself succeeded; per-input results are in captures
}

// ---- arm64: real compile, honest exec-unavailable ------------------------

std::string arm64_boot_probe(const fs::path& capture_root) {
  // One-time evidence: actually launch the aarch64-linux cross runtime under
  // qemu-aarch64-static and capture what it does. It is a boot-driver, not a
  // Deci2 listener, so it cannot accept and run compiled test objects.
  fs::path gk = fs::path("build-arm64-linux") / "game" / "linux-arm64" / "gk";
  fs::path probe = capture_root / "arm64" / "_boot_probe.txt";
  std::error_code ec;
  fs::create_directories(probe.parent_path(), ec);

  if (!fs::exists(gk)) {
    std::string msg = "arm64 cross runtime not found at " + gk.string() +
                      " (build with -DOG_LINUX_ARM64=ON)\n";
    write_file(probe, msg);
    return "missing cross runtime: " + gk.string();
  }
  // The cross gk is dynamically linked, so qemu needs the aarch64 sysroot to
  // find ld-linux-aarch64 and the shared libs.
  std::string sysroot = "/usr/aarch64-linux-gnu";
  std::string ld_prefix = fs::exists(sysroot) ? (" -L " + sysroot) : "";
  std::string cmd = "timeout 25 qemu-aarch64-static" + ld_prefix + " " + gk.string() +
                    " -fakeiso -nosound > " + probe.string() + " 2>&1";
  int rc = std::system(cmd.c_str());
  return "cross runtime boots under qemu-aarch64-static but does not run a Deci2 listener "
         "(it crashes during boot — see autoport arm64 status); qemu probe rc=" +
         std::to_string(rc) + ", evidence in " + probe.string();
}

int run_all_arm64(const Args& a) {
  if (!file_util::setup_project_path(std::nullopt)) {
    std::cerr << "goalc-diff-runner: could not locate jak-project dir\n";
    return kExitFail;
  }
  auto inputs = gather_inputs(a.all_inputs);
  if (inputs.empty()) {
    std::cerr << "goalc-diff-runner: no .gc inputs under " << a.all_inputs << "\n";
    return kExitFail;
  }

  // Compiler in ARM64 mode: proves the ARM64 backend really emits code for each
  // input (full color + codegen). all-types supplies the library symbol types
  // (format, ...) so the inputs type-check and codegen.
  Compiler compiler(GameVersion::Jak1, emitter::InstructionSet::ARM64);
  try {
    compiler.run_test_no_load("decompiler/config/jak1/all-types.gc");
  } catch (std::exception& e) {
    std::cerr << "goalc-diff-runner: arm64 prelude load failed: " << e.what() << "\n";
    return kExitFail;
  }

  const std::string probe_note = arm64_boot_probe(a.capture_root);

  int compiled = 0, compile_failed = 0;
  for (const auto& in : inputs) {
    const std::string name = in.stem().string();
    fs::path dir = a.capture_root / "arm64" / name;
    CaptureResult r;
    bool arm64_codegen_ok = false;
    std::string compile_err;
    try {
      compiler.run_full_compiler_on_string_no_save(read_file(in), name);
      arm64_codegen_ok = true;
      compiled++;
    } catch (std::exception& e) {
      compile_err = e.what();
      compile_failed++;
    }

    r.exit_code = 1;  // honest failure: no execution was possible
    r.final_state = arm64_codegen_ok ? "<arm64-exec-unavailable>" : "<arm64-compile-failed>";
    r.stderr_text =
        (arm64_codegen_ok
             ? "ARM64 codegen succeeded, but execution is unavailable: " + probe_note + "\n"
             : "ARM64 codegen failed: " + compile_err + "\n");
    write_capture(dir, r);
    std::cout << "[arm64] " << name << " -> " << r.final_state << "\n";
  }

  std::cout << "arm64: " << inputs.size() << " inputs, " << compiled << " codegen-ok, "
            << compile_failed << " codegen-failed, 0 executed (no arm64 listener runtime)\n";
  return kExitOk;
}

// ---- cheap per-(input,backend) check -------------------------------------

int run_check(const Args& a) {
  if (a.input.empty() || a.capture_dir.empty()) {
    std::cerr << "goalc-diff-runner: --check needs --input and --capture\n";
    return kExitFail;
  }
  auto expected = read_expect_directive(a.input);
  if (!expected) return kExitInputError;

  fs::path fs_path = a.capture_dir / "final_state";
  if (!fs::exists(fs_path)) {
    std::cerr << "goalc-diff-runner: missing capture (setup fixture did not run?): " << fs_path
              << "\n";
    return kExitFail;
  }
  std::string actual = trim(read_file(fs_path));
  std::string exp = trim(*expected);
  if (actual == exp) {
    std::cout << a.backend << " PASS: " << exp << "\n";
    return kExitOk;
  }
  std::string err = trim(read_file(a.capture_dir / "stderr"));
  std::cout << a.backend << " FAIL: expected '" << exp << "' got '" << actual << "'\n";
  if (!err.empty()) {
    std::cout << "  reason: " << err << "\n";
  }
  return kExitFail;
}

}  // namespace

int main(int argc, char** argv) {
  auto args = parse_args(argc, argv);
  if (!args) return kExitFail;

  if (args->check) {
    return run_check(*args);
  }
  if (!args->all_inputs.empty()) {
    return args->backend == "x86" ? run_all_x86(*args) : run_all_arm64(*args);
  }
  std::cerr << "goalc-diff-runner: nothing to do; use --all-inputs or --check\n";
  print_usage(std::cerr);
  return kExitFail;
}
