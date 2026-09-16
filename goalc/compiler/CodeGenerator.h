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

// Interrupteur d'ABLATION de l'enrobage d'appel arm64 (OG_CODEGEN_LEGACY_CALLS).
// Il n'existe que pour fabriquer le bras AVANT de `codegen_gain_us` : il restitue
// l'ancienne emission d'appel (masque complet + X23 : 3 STP + BLR + 3 LDP, 8
// instructions avec l'ADD d'offset) et les sauvegardes de GPR « saved » au
// site d'appel plutot qu'une fois dans le prologue de la callee. Il est lu a la
// COMPILATION, par goalc,
// jamais a l'execution : les deux bras sont donc deux jeux de CGO DISTINCTS,
// et poser la variable devant `gk` ne change rien. Il ne bascule QUE l'enrobage
// d'appel : les autres leviers du lot (symboles a offset fixe, acces memoire
// [Xn,Xm], cache X16) restent actifs dans les deux bras.
// Variable absente, vide ou "0" = comportement ACTUEL, strictement inchange.
bool codegen_legacy_calls_enabled();

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
