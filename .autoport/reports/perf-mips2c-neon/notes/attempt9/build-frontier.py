"""Compile complete archived translation units; never extract an arithmetic block.

DIRECTIVES vaff5c1afea. Local laboratory only. The external GOAL-call boundary
is intercepted by frontier-parity.cpp and never returns a fabricated result.
"""
import argparse
import hashlib
import json
import pathlib
import shlex
import subprocess

ROOT = pathlib.Path(__file__).resolve().parents[5]
OUT = pathlib.Path(__file__).resolve().parent
NOTES = OUT.parent
OLD = NOTES / "attempt7"


def sha(path):
    return hashlib.sha256(pathlib.Path(path).read_bytes()).hexdigest()


def command(args, log):
    with open(log, "w") as f:
        f.write("$ " + shlex.join(map(str, args)) + "\n")
        f.flush()
        result = subprocess.run(list(map(str, args)), cwd=ROOT, stdout=f, stderr=subprocess.STDOUT)
        f.write(f"\nEXIT {result.returncode}\n")
    if result.returncode:
        raise RuntimeError(f"exit {result.returncode}: {log}")


def build(arch):
    # Preserve the desktop compiler/options/includes; redirect only its outputs.
    if arch == "x86":
        original = shlex.split((OLD / "before-x86-compile-command.txt").read_text())
        base = []
        skip = False
        for token in original:
            if skip:
                skip = False
            elif token in ("-c", "-o", "-MT", "-MF"):
                skip = True
            elif token != "-MD":
                base.append(token)
        nm, objcopy, objdump = "nm", "objcopy", "objdump"
    else:
        old = json.loads((NOTES / "supervisor-clang-20260915/manifest.json").read_text())
        original = old["build_command"]
        base = original[:original.index(".autoport/reports/perf-mips2c-neon/notes/attempt7/block-parity.cpp")]
        nm, objcopy, objdump = ["aarch64-linux-gnu-" + x for x in ("nm", "objcopy", "objdump")]
    base += ["-ffunction-sections", "-fdata-sections"]
    manifest = {"directives": "DIRECTIVES vaff5c1afea", "arch": arch,
                "scope": "complete archived TUs, entry to first external GOAL call only",
                "base_options": base, "objects": {}, "commands": []}
    manifest_path = OUT / f"{arch}-manifest.json"
    manifest["driver_sha256"] = sha(OUT / "frontier-parity.cpp")
    command([base[0], "--version"], OUT / f"{arch}-compiler.txt")
    linked = []
    for variant, filename in [("before", "before-sparticle.cpp"), ("after", "candidate-sparticle.cpp")]:
        source = OLD / filename
        prefix = OUT / f"{arch}-{variant}"
        obj = pathlib.Path(str(prefix) + ".o")
        dep = pathlib.Path(str(prefix) + ".d")
        cmd = base + ["-MD", "-MF", str(dep), "-c", str(source), "-o", str(obj)]
        manifest["commands"].append(cmd)
        command(cmd, str(prefix) + "-build.log")
        command([nm, "-S", str(obj)], str(prefix) + "-nm.txt")
        command([objdump, "-drwC", str(obj)], str(prefix) + "-full.asm")
        command(["readelf", "-Wr", str(obj)], str(prefix) + "-relocations.txt")
        # Rename strong exported definitions only, after compilation. No source
        # namespace macro or arithmetic edit changes optimization context.
        symbols = subprocess.check_output([nm, "--defined-only", "--extern-only", str(obj)], text=True)
        mapping = []
        for line in symbols.splitlines():
            fields = line.split()
            if len(fields) != 3 or fields[1] in ("W", "V", "u"):
                continue
            name = fields[2]
            if name == "_ZN6Mips2C4jak119sp_process_block_3d7executeEPv":
                new = f"full_{variant}_execute"
            elif name == "_ZN6Mips2C4jak119sp_process_block_3d5cacheE":
                new = f"full_{variant}_cache"
            else:
                new = f"full_{variant}_" + name
            mapping.append(name + " " + new)
        rename = pathlib.Path(str(prefix) + "-rename.txt")
        rename.write_text("\n".join(mapping) + "\n")
        renamed = pathlib.Path(str(prefix) + "-linked.o")
        command([objcopy, "--redefine-syms=" + str(rename), str(obj), str(renamed)], str(prefix) + "-rename.log")
        linked.append(str(renamed))
        # Compiler dependency file covers the actual headers used by this TU.
        deps = shlex.split(dep.read_text().replace("\\\n", " ").split(":", 1)[1])
        dependencies = {str(p): sha(ROOT / p) for p in deps}
        manifest["objects"][variant] = {
            "source": str(source), "source_sha256": sha(source),
            "object_sha256": sha(obj), "linked_object_sha256": sha(renamed),
            "dependencies": dependencies, "rename_sha256": sha(rename)}
        manifest_path.write_text(json.dumps(manifest, indent=2) + "\n")
    before_deps = dict(manifest["objects"]["before"]["dependencies"])
    after_deps = dict(manifest["objects"]["after"]["dependencies"])
    before_deps.pop(str(OLD / "before-sparticle.cpp"))
    after_deps.pop(str(OLD / "candidate-sparticle.cpp"))
    if before_deps != after_deps:
        raise RuntimeError("paired compiler dependencies differ")
    manifest["paired_dependencies_equal"] = True
    binary = OUT / f"frontier-{arch}"
    cmd = base + [str(OUT / "frontier-parity.cpp"), str(OLD / "assert-fail-fast.cpp")] + linked + [
        "-Wl,--gc-sections", "-Wl,-Map," + str(OUT / f"{arch}-link.map"), "-o", str(binary)]
    manifest["commands"].append(cmd)
    command(cmd, OUT / f"{arch}-link.log")
    command([nm, "-S", str(binary)], OUT / f"{arch}-binary-nm.txt")
    command([objdump, "-drwC", str(binary)], OUT / f"{arch}-binary-full.asm")
    command(["readelf", "-W", "-a", str(binary)], OUT / f"{arch}-binary-elf.txt")
    manifest["binary_sha256"] = sha(binary)
    manifest["assert_source_sha256"] = sha(OLD / "assert-fail-fast.cpp")
    manifest["build_exit"] = 0
    manifest_path.write_text(json.dumps(manifest, indent=2) + "\n")
    print(f"BUILD arch={arch} exit=0 binary_sha256={manifest['binary_sha256']}", flush=True)


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("arch", choices=["x86", "arm-clang"])
    build(parser.parse_args().arch)
