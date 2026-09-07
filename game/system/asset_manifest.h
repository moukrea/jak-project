#pragma once

#include <cstddef>
#include <cstdint>
#include <string>

// Passive provenance of supplied, consumed buffers. Checkpoints describe a
// cumulative set, not consumption order, replay state, or GPU draws.
namespace asset_manifest {
// Configuration is read once, on first use. A nonempty manifest path requires
// OG_REFSET=capture or replay; absent/empty path leaves all calls as no-ops.
bool enabled();
// kind: nonempty ASCII [A-Za-z0-9_.-]+; logical_name: nonempty arbitrary bytes.
// The caller must keep bytes stable throughout this call.
void record(const char* kind,
            const std::string& logical_name,
            uint64_t offset,
            const void* bytes,
            size_t size);
void checkpoint(const std::string& label);
}  // namespace asset_manifest
