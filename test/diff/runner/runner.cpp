// goalc-diff-runner: differential test harness for the OpenGOAL backends.
//
// Phase 00 deliverable: this is the harness scaffolding. It defines the CLI
// surface, the capture-artifact layout, and the skip protocol for backends
// that are not yet implemented. Later phases will wire the x86 path to the
// real `goalc` entry point and the arm64 path to the new emitter.
//
// For now:
//   - --backend x86   : reads the `;; expect: <text>` directive from the input
//                       and writes that as captured stdout (exit_code=0).
//   - --backend arm64 : prints a clear "not implemented" message to stderr and
//                       exits with code 77 (ctest SKIP_RETURN_CODE convention).
//
// Capture-artifact layout (written into --capture <dir>):
//   exit_code   -- single integer, trailing newline
//   stdout      -- complete stdout of the executed program
//   stderr      -- complete stderr of the executed program
//   final_state -- last non-empty line of stdout (convention: tests end with
//                  `(format #t "~D~%" <result>)`, so this is the answer)
//
// Exit codes:
//   0  -- run succeeded, capture written
//   1  -- CLI / IO error
//   2  -- input file unreadable or missing required directive
//   77 -- backend not implemented (skip)

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

namespace fs = std::filesystem;

namespace {

constexpr int kExitOk = 0;
constexpr int kExitCliError = 1;
constexpr int kExitInputError = 2;
constexpr int kExitNotImplemented = 77;

struct Args {
  fs::path input;
  std::string backend;
  fs::path capture_dir;
};

void print_usage(std::ostream& os) {
  os << "usage: goalc-diff-runner --input <path.gc> --backend <x86|arm64> "
        "--capture <output-dir>\n";
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
    } else if (arg == "-h" || arg == "--help") {
      print_usage(std::cout);
      std::exit(kExitOk);
    } else {
      std::cerr << "goalc-diff-runner: unknown argument: " << arg << "\n";
      print_usage(std::cerr);
      return std::nullopt;
    }
  }
  if (a.input.empty() || a.backend.empty() || a.capture_dir.empty()) {
    std::cerr << "goalc-diff-runner: --input, --backend, and --capture are required\n";
    print_usage(std::cerr);
    return std::nullopt;
  }
  if (a.backend != "x86" && a.backend != "arm64") {
    std::cerr << "goalc-diff-runner: unsupported backend: " << a.backend << "\n";
    return std::nullopt;
  }
  return a;
}

std::string trim(std::string_view s) {
  size_t b = 0;
  size_t e = s.size();
  while (b < e && std::isspace(static_cast<unsigned char>(s[b]))) ++b;
  while (e > b && std::isspace(static_cast<unsigned char>(s[e - 1]))) --e;
  return std::string(s.substr(b, e - b));
}

// Pull a `;; expect: <value>` directive from the .gc source. This is the
// convention documented in test/diff/README.md: every input ends with a
// single line of stdout, and the directive records what that line should be.
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
  std::cerr << "goalc-diff-runner: input is missing `;; expect: <value>` directive: "
            << input << "\n";
  return std::nullopt;
}

bool write_file(const fs::path& path, std::string_view contents) {
  std::ofstream out(path, std::ios::binary | std::ios::trunc);
  if (!out) {
    std::cerr << "goalc-diff-runner: cannot write: " << path << "\n";
    return false;
  }
  out.write(contents.data(), static_cast<std::streamsize>(contents.size()));
  return out.good();
}

int run_x86(const Args& a) {
  auto expected = read_expect_directive(a.input);
  if (!expected) return kExitInputError;

  std::error_code ec;
  fs::create_directories(a.capture_dir, ec);
  if (ec) {
    std::cerr << "goalc-diff-runner: cannot create capture dir: " << ec.message() << "\n";
    return kExitCliError;
  }

  // Phase 00: harness only. Future phases replace this block with a real
  // invocation of goalc (x86 backend) followed by executing the produced
  // image. The capture contract below is what those phases must honour.
  const std::string stdout_capture = *expected + "\n";
  const std::string stderr_capture;
  const std::string final_state = *expected;

  if (!write_file(a.capture_dir / "exit_code", "0\n")) return kExitCliError;
  if (!write_file(a.capture_dir / "stdout", stdout_capture)) return kExitCliError;
  if (!write_file(a.capture_dir / "stderr", stderr_capture)) return kExitCliError;
  if (!write_file(a.capture_dir / "final_state", final_state + "\n")) return kExitCliError;

  std::cout << "x86 capture written to " << a.capture_dir << "\n";
  std::cout << "final_state=" << final_state << "\n";
  return kExitOk;
}

int run_arm64(const Args& a) {
  std::error_code ec;
  fs::create_directories(a.capture_dir, ec);
  // Best-effort: leave a breadcrumb so a human inspecting the capture dir
  // sees why the run was skipped.
  if (!ec) {
    write_file(a.capture_dir / "stderr",
               "arm64 backend not implemented (phase 00 stub)\n");
  }
  std::cerr << "arm64 backend not implemented (phase 00 stub)\n";
  return kExitNotImplemented;
}

}  // namespace

int main(int argc, char** argv) {
  auto args = parse_args(argc, argv);
  if (!args) return kExitCliError;
  if (args->backend == "x86") return run_x86(*args);
  return run_arm64(*args);
}
