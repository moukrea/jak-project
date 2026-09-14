#!/usr/bin/env python3
"""Source-snapshot detectors for leftovers 3/6/7; only builds temporary CMake probes.

API: detect(root: Path) -> dict. CLI: --root PATH [--baseline REF].
Baseline reads tracked files with git show, never checking out or configuring the repo.
"""
import argparse
import json
from pathlib import Path
import re
import subprocess
import tempfile

SCRIPTS = ('d1_build.sh', 'd3_build.sh', 'c2_run.sh', 'c3_run.sh',
           'c4_run.sh', 'qemu_repro.sh', 'emitter_stress.sh')
FILES = ['third-party/discord-rpc/CMakeLists.txt',
         'third-party/discord-rpc/src/CMakeLists.txt', 'third-party/SDL/CMakeLists.txt',
         '.autoport/lib/build_x86.sh', '.autoport/lib/build_arm64.sh',
         *('.autoport/lib/' + s for s in SCRIPTS)]


def run(args, cwd):
    p = subprocess.run(args, cwd=cwd, text=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
    if p.returncode:
        raise RuntimeError(f'{args}: rc={p.returncode}\n{p.stdout}')
    return p.stdout


def detect(root):
    root = Path(root)
    with tempfile.TemporaryDirectory(prefix='leftovers-build-check-') as tmp:
        work = Path(tmp)
        discord = (root / FILES[0]).read_text()
        src = (root / FILES[1]).read_text()
        format_block = discord[discord.index('# format'):discord.index('# thirdparty stuff')]
        # Keep the source's dependency declaration, if present, including its condition.
        deps = '\n'.join(re.findall(r'if\s*\(CLANG_FORMAT_CMD\).*?endif\s*\(CLANG_FORMAT_CMD\)', src, re.S))
        probe = work / 'format'
        probe.mkdir()
        formatter = probe / 'formatter.sh'
        formatter.write_text('#!/bin/sh\necho format >> "' + str(probe / 'calls') + '"\n')
        formatter.chmod(0o755)
        (probe / 'CMakeLists.txt').write_text('cmake_minimum_required(VERSION 3.16)\nproject(probe NONE)\n'
            + f'set(CLANG_FORMAT_CMD "{formatter}")\n' + format_block
            + '\nadd_custom_target(discord-rpc ALL)\n' + deps + '\n')
        run(['cmake', '-S', '.', '-B', 'out', '-G', 'Ninja'], probe)
        run(['ninja', '-C', 'out'], probe)
        calls = probe / 'calls'
        before = len(calls.read_text().splitlines()) if calls.exists() else 0
        run(['ninja', '-C', 'out'], probe)
        after = len(calls.read_text().splitlines()) if calls.exists() else 0
        format_replays = after - before

        sdl = (root / FILES[2]).read_text()
        version = re.search(r'project\(SDL3 LANGUAGES C VERSION "([^"]+)"\)', sdl)[1]
        block = sdl[sdl.index('# If REVISION.txt exists'):sdl.index('execute_process(COMMAND "${CMAKE_COMMAND}" -E make_directory', sdl.index('# If REVISION.txt exists'))]
        script = work / 'sdl.cmake'
        script.write_text('cmake_minimum_required(VERSION 3.16)\n'
            + f'set(SDL3_VERSION "{version}")\nset(CMAKE_CURRENT_SOURCE_DIR "{work}")\n'
            + 'macro(git_describe var)\n message(STATUS "GIT_DESCRIBE_CALLED")\n set(${var} unrelated-parent-commit)\nendmacro()\n'
            + block + '\nmessage(STATUS "REVISION=${SDL_REVISION}")\n')
        output = run(['cmake', '-P', str(script)], work)
        git_calls = output.count('GIT_DESCRIBE_CALLED')
        hardcoded = len(re.findall(r"SDL_PIN=['\"]SDL-\d+\.\d+\.\d+", (root / FILES[3]).read_text()))
        bypass = []
        legacy = []
        for name in SCRIPTS:
            code = '\n'.join(line for line in (root / '.autoport/lib' / name).read_text().splitlines()
                             if not line.lstrip().startswith('#'))
            if 'build_arm64.sh' not in code or re.search(r'\bcmake\s+--build\b', code):
                bypass.append(name)
            if re.search(r'build-arm64(?![-\w])', code):
                legacy.append(name)
        return {'point3': {'defect': int(format_replays > 0), 'normal_second_build_formatter_calls': format_replays},
                'point6': {'defect': int(git_calls > 0 or hardcoded > 0), 'fresh_source_git_describe_calls': git_calls,
                           'hardcoded_version_pins': hardcoded, 'fresh_revision': output.strip().split('REVISION=')[-1]},
                'point7': {'defect': int(bool(bypass or legacy)), 'bypass_count': len(bypass),
                           'bypass_scripts': bypass, 'legacy_tree_count': len(legacy), 'legacy_scripts': legacy}}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--root', type=Path, default=Path(__file__).resolve().parents[2])
    parser.add_argument('--baseline')
    args = parser.parse_args()
    if args.baseline:
        with tempfile.TemporaryDirectory(prefix='leftovers-baseline-') as tmp:
            for name in FILES:
                p = subprocess.run(['git', 'show', f'{args.baseline}:{name}'], cwd=args.root,
                                   stdout=subprocess.PIPE, stderr=subprocess.PIPE)
                if p.returncode:
                    if name.endswith('build_arm64.sh'):
                        continue
                    raise RuntimeError(p.stderr.decode())
                dest = Path(tmp) / name
                dest.parent.mkdir(parents=True, exist_ok=True)
                dest.write_bytes(p.stdout)
            result = detect(Path(tmp))
    else:
        result = detect(args.root)
    print(json.dumps(result, indent=2, sort_keys=True))

if __name__ == '__main__':
    main()
