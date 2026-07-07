#pragma once

#include "common/common_types.h"

#include "game/common/dgo_rpc_types.h"
#include "game/kernel/common/Ptr.h"

extern u32 sMsgNum;
s32 RpcCall(s32 rpcChannel,
            u32 fno,
            bool async,
            void* sendBuff,
            s32 sendSize,
            void* recvBuff,
            s32 recvSize);
u64 RpcCall_wrapper(void* _args);
u32 RpcBusy(s32 channel);
void RpcSync(s32 channel);
void LoadDGOTest();
void kdgo_init_globals();
u32 InitRPC();
void StopIOP();

extern u32 sShowStallMsg;

// Gjak2-render forensic breadcrumb: the name of the DGO object currently being
// linked/exec'd (set by link_and_exec right before each object; reset to
// "<between objects>" after link finish). Read by the arm64 crash handler so a
// pc=0 crash can be attributed to a specific object's link/exec or to the gap
// between two objects. Cheap, always-on, no env gate. extern "C" so the
// unmangled symbol is reachable from the android crash-diag TU.
extern "C" const char* g_gk_current_link_object;
