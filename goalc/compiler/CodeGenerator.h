/*!
 * @file CodeGenerator.h
 * Generate object files from a FileEnv using an emitter::ObjectGenerator.
 * Populates a DebugInfo.
 * Currently owns the logic for emitting the function prologues.
 */

#pragma once

#include <string>
#include <typeinfo>

#include "Env.h"

#include "common/versions/versions.h"

#include "goalc/emitter/ObjectGenerator.h"

class DebugInfo;
class TypeSystem;

// Phase A1 emitter inventory: per-IR-class emit counter. The counter is
// bumped from the four places in CodeGenerator that dispatch
// ir->do_codegen_{x86,arm64}() — see CodeGenerator.cpp. main.cpp wires
// --ir-emit-stats <path> by calling set_output_path() before
// compilation; dump_to_file() is then invoked after the requested
// command completes to write a JSON map of class-name -> {x86, arm64}.
namespace ir_emit_stats {
void record(const std::type_info& ti, bool is_arm64);
void set_output_path(const std::string& path);
bool dump_to_file();  // returns true if a file was written
}  // namespace ir_emit_stats

class CodeGenerator {
 public:
  CodeGenerator(FileEnv* env,
                DebugInfo* debug_info,
                GameVersion version,
                emitter::InstructionSet instruction_set);
  std::vector<u8> run(const TypeSystem* ts);
  emitter::ObjectGeneratorStats get_obj_stats() const { return m_gen.get_stats(); }

 private:
  void do_function(FunctionEnv* env, int f_idx);
  void do_goal_function_x86(FunctionEnv* env, int f_idx);
  void do_goal_function_arm64(FunctionEnv* env, int f_idx);
  void do_asm_function_x86(FunctionEnv* env, int f_idx, bool allow_saved_regs);
  void do_asm_function_arm64(FunctionEnv* env, int f_idx, bool allow_saved_regs);
  emitter::ObjectGenerator m_gen;
  FileEnv* m_fe = nullptr;
  DebugInfo* m_debug_info = nullptr;
};
