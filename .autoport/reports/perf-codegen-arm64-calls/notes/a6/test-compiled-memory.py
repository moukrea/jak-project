# Reuse the existing A3 compiler/extraction/execution helpers without editing them.
import importlib.util
import sys
from pathlib import Path
root = Path.cwd()
notes = Path(__file__).resolve().parent
spec = importlib.util.spec_from_file_location("a3", root / ".autoport/lib/build_a3_diff.py")
a3 = importlib.util.module_from_spec(spec)
sys.modules[spec.name] = a3
spec.loader.exec_module(a3)
for name, expected in [("cg-memory-shared", 142), ("cg-memory-branch", 168)]:
    results = {}
    for arch, goalc in [("x86", a3.GOALC_X86), ("arm64", a3.GOALC_ARM64)]:
        obj = notes / f"{name}.{arch}.o"
        command = [str(goalc), "--user-auto", "--game", "jak1", "--disable-ansi", "-c",
                   f'(asm-file "{notes / (name + ".gc")}" :output-file "{obj}" :disassemble "{notes / (name + "." + arch + ".asm")}")']
        compiled = a3.run(command, cwd=root)
        (notes / f"{name}.{arch}.compile.log").write_text(compiled.stdout + compiled.stderr)
        code = notes / f"{name}.{arch}.bin"
        code.write_bytes(a3.extract_last_function_bytes(obj))
        elf = notes / f"{name}.{arch}.elf"
        if arch == "arm64":
            a3.build_arm_elf(code, elf)
            (notes / f"{name}.objdump").write_text(a3.disasm_arm_elf(elf))
            results[arch] = a3.run_arm_qemu(elf)
        else:
            a3.build_x86_elf(code, elf)
            results[arch] = a3.run_x86(elf)
    print(f"{name} expected={expected} x86={results['x86']} arm64={results['arm64']}", flush=True)
    assert results['x86'] == results['arm64'] == expected
