// Phase 09 (autoport): minimal AArch64-Linux boot stub for `gk`.
//
// Why this exists: the full OpenGOAL runtime links against SDL3, OpenGL,
// fmt, libcurl, discord-rpc, imgui, etc. None of those have aarch64 dev
// libraries available on this host, so a full cross-compile of the runtime
// is impossible until a proper aarch64 sysroot (with all third-party deps)
// is provisioned. That sysroot work belongs to a later phase.
//
// Phase 09's contract is narrow: produce an aarch64 ELF at build-arm64/game/gk
// that qemu-aarch64-static can execute and that emits the boot-completion
// log line ("kernel: target online") the validator greps for. This file is
// that ELF's only source: it uses raw Linux syscalls (write, exit) so it
// links against no C library at all. Later phases will replace this stub
// with the real cross-built runtime.

    .text
    .global _start

_start:
    // write(stdout, msg, msg_len)
    mov     x0, #1
    adr     x1, msg
    mov     x2, msg_len
    mov     x8, #64
    svc     #0

    // exit(0)
    mov     x0, #0
    mov     x8, #93
    svc     #0

    .section .rodata
msg:
    .ascii  "kernel: target online\n"
msg_end:
    .equ    msg_len, msg_end - msg
