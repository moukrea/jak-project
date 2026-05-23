// Stub linkage for goalc/emitter/Register.cpp symbols that IGenARM64.cpp
// might transitively reference. We only need Register::print() and the
// RegisterInfo factory if anything triggers them during a test pass — none
// of the IGen::ARM64::* helpers actually invoke print(), but the linker
// still needs a definition to resolve the symbol declared in Register.h.
//
// Defining the stub here keeps the test build self-contained without
// pulling in the full goalc compiler library.

#include <string>

#include "goalc/emitter/Register.h"

namespace emitter {

std::string Register::print() const {
    // Used only by diagnostic paths in goalc; tests don't exercise this.
    return std::string("R") + std::to_string(m_id);
}

}  // namespace emitter
