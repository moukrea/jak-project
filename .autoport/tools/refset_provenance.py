#!/usr/bin/env python3
"""Seal and recheck local refset inputs; this does not publish a proof or gate."""
import argparse
import hashlib
import json
import os
import re
from pathlib import Path
import subprocess
import tempfile

ANCHOR = 'a9ea15a69062a57335278db7680cd647df3c1e1d'
MAIN_ROOT = Path(__file__).resolve().parents[2]
BASELINE_PATCH = MAIN_ROOT / '.autoport/reports/lighting-census/notes/essai33-roi/full-baseline.patch'
RENDERER = 'game/graphics/opengl_renderer'
SHADERS = RENDERER + '/shaders'
PORTABLE_SETTINGS = ('misc/debug-settings.json', 'settings/display-settings.json',
                     'settings/input-settings.json', 'settings/settings.ini')
SOURCE_ROOTS = ('game/graphics', 'game/kernel', 'game/system', 'common', 'goal_src/jak1/pc')


def git(root, *args):
    return subprocess.check_output(['git', '-C', str(root), *args], stderr=subprocess.PIPE)


def paths(root, *args):
    return [os.fsdecode(p) for p in git(root, *args).split(b'\0') if p]


def fnv64(data):
    value = 1469598103934665603  # refset::hash_file historical offset, deliberately not standard FNV.
    for byte in data:
        value = ((value ^ byte) * 1099511628211) & 0xffffffffffffffff
    return value


def fingerprint(path):
    data = Path(path).read_bytes()
    return fnv64(data), hashlib.sha256(data).hexdigest()


def diff(root, base='HEAD'):
    patch = git(root, '-c', 'core.quotePath=false', 'diff', '--no-ext-diff', '--no-textconv',
                '--binary', '--no-renames', '--src-prefix=a/', '--dst-prefix=b/', base, '--',
                'game', 'common', 'goal_src/jak1/pc', 'CMakeLists.txt', 'android/CMakeLists.txt')
    for name in sorted(paths(root, 'ls-files', '--others', '--exclude-standard', '-z', '--', *SOURCE_ROOTS, 'game')):
        result = subprocess.run(['git', '-c', 'core.quotePath=false', 'diff', '--no-index',
                                 '--binary', '--src-prefix=a/', '--dst-prefix=b/', '/dev/null', name],
                                cwd=root, capture_output=True)
        if result.returncode not in (0, 1):
            raise ValueError(result.stderr.decode(errors='replace'))
        patch += result.stdout
    return patch


def canonical_diff(patch):
    """Ignore section ordering and object-ID abbreviations, preserving modes and all hunks."""
    sections = []
    for section in patch.split(b'diff --git ')[1:]:
        sections.append(re.sub(rb'(?m)^index [0-9a-f]+\.\.[0-9a-f]+', b'index OBJECTS', section))
    return sorted(sections)


def renderer_diff(patch):
    sections = {}
    for section in patch.split(b'diff --git ')[1:]:
        header = section.split(b'\n', 1)[0]
        if header.startswith(('a/' + RENDERER + '/').encode()):
            # Object IDs vary with git's abbreviation settings; code/context must match exactly.
            sections[header] = b'\n'.join(line for line in section.split(b'\n')
                                            if not line.startswith(b'index '))
    return sections


def baseline_check(root, baseline_patch, patch, *, anchor=ANCHOR, main_root=MAIN_ROOT):
    if root == Path(main_root).resolve():
        raise ValueError('baseline must use a distinct worktree')
    if git(root, 'rev-parse', 'HEAD').decode().strip() != anchor:
        raise ValueError('baseline HEAD does not match historical anchor')
    expected = paths(root, 'ls-tree', '-r', '--name-only', '-z', 'HEAD', '--', SHADERS)
    present = {str(p.relative_to(root)) for p in (root / SHADERS).rglob('*') if p.is_file() or p.is_symlink()}
    if present != set(expected):
        raise ValueError('baseline shader inventory differs from HEAD')
    for name in expected:
        if (root / name).is_symlink() or (root / name).read_bytes() != git(root, 'show', 'HEAD:' + name):
            raise ValueError('baseline shader differs from HEAD: ' + name)
    if renderer_diff(patch) != renderer_diff(Path(baseline_patch).read_bytes()):
        raise ValueError('baseline renderer differs from acquired baseline patch')
    # Ignored renderer additions must not escape the diff comparison.
    known = set(paths(root, 'ls-files', '-z', '--', RENDERER))
    known.update(paths(root, 'ls-files', '--others', '--exclude-standard', '-z', '--', RENDERER))
    actual = {str(p.relative_to(root)) for p in (root / RENDERER).rglob('*') if p.is_file() or p.is_symlink()}
    if actual - known:
        raise ValueError('unrecorded baseline renderer files')


def source_files(root, base='HEAD'):
    names = set(paths(root, 'ls-files', '-z', '--', *SOURCE_ROOTS))
    names.update(paths(root, 'ls-files', '--others', '--exclude-standard', '-z', '--', *SOURCE_ROOTS, 'game'))
    names.update(paths(root, 'diff', '--name-only', '--diff-filter=A', '-z', base, '--', 'game'))
    # Deleted tracked sources are represented by the archived patch and inventory comparison.
    result = {str(root / name) for name in names if (root / name).exists()}
    for name in ('build/CMakeCache.txt', 'build/compile_commands.json', 'compile_commands.json'):
        if (root / name).exists():
            result.add(str(root / name))
    for name in PORTABLE_SETTINGS:
        path = root / 'build/game/OpenGOAL/jak1' / name
        if not path.is_file():
            raise ValueError('missing portable setting: ' + str(path))
        result.add(str(path))
    return result


def exclusive_write(path, data):
    """Publish a fully written file via an exclusive hard link, never overwrite."""
    path = Path(path)
    fd, temporary = tempfile.mkstemp(prefix='.' + path.name + '.', dir=path.parent)
    try:
        with os.fdopen(fd, 'wb') as stream:
            stream.write(data)
            stream.flush()
            os.fsync(stream.fileno())
        os.link(temporary, path)
    finally:
        os.unlink(temporary)


def seal(root, role, output, baseline_patch=BASELINE_PATCH, *, anchor=ANCHOR, main_root=MAIN_ROOT):
    root = Path(root).resolve(strict=True)
    if role not in ('baseline', 'candidate'):
        raise ValueError('invalid provenance role')
    if Path(os.fsdecode(git(root, 'rev-parse', '--show-toplevel')).strip()).resolve() != root:
        raise ValueError('root must be the worktree root')
    output = Path(output).absolute()
    archive = output.with_suffix('.patch')
    if output.exists() or output.is_symlink() or archive.exists() or archive.is_symlink():
        raise FileExistsError('output certificate or patch already exists')
    patch = diff(root)
    baseline_patch = Path(baseline_patch).resolve()
    if role == 'baseline':
        baseline_check(root, baseline_patch, patch, anchor=anchor, main_root=main_root)
    binary = root / 'build/game/gk'
    bin_hash, bin_sha = fingerprint(binary)
    files = source_files(root)
    if role == 'baseline':
        files.add(str(baseline_patch))
    hashes = {p: fingerprint(p) for p in sorted(files)}
    hashes[str(archive)] = (fnv64(patch), hashlib.sha256(patch).hexdigest())
    document = dict(version=1, role=role, root=str(root),
                    base_commit=git(root, 'rev-parse', 'HEAD').decode().strip(),
                    binary_path=str(binary), bin=bin_hash, binary_sha256=bin_sha,
                    source_patch=str(archive), files={p: h[0] for p, h in hashes.items()},
                    sha256={p: h[1] for p, h in hashes.items()}, baseline_renderer_verified=False)
    if role == 'baseline':
        acquired_hash, acquired_sha = fingerprint(baseline_patch)
        document.update(baseline_anchor=anchor, baseline_patch=str(baseline_patch),
                        baseline_patch_hash=acquired_hash, baseline_patch_sha256=acquired_sha,
                        baseline_renderer_verified=True)
    if patch != diff(root):
        raise ValueError('source patch changed during sealing')
    exclusive_write(archive, patch)
    # A failed final publication leaves its patch archived, and still never overwrites anything.
    verify_document(document, anchor=anchor, main_root=main_root)
    exclusive_write(output, (json.dumps(document, indent=2, sort_keys=True) + '\n').encode())
    return document


def verify_document(document, *, anchor=ANCHOR, main_root=MAIN_ROOT):
    if document['version'] != 1 or document['role'] not in ('baseline', 'candidate'):
        raise ValueError('unsupported certificate')
    root = Path(document['root']).resolve(strict=True)
    if str(root) != document['root']:
        raise ValueError('noncanonical root')
    base = document['base_commit']
    if not isinstance(base, str) or re.fullmatch(r'[0-9a-f]{40}', base) is None:
        raise ValueError('invalid base commit')
    git(root, 'cat-file', '-e', base + '^{commit}')
    if document['role'] == 'baseline' and git(root, 'rev-parse', 'HEAD').decode().strip() != base:
        raise ValueError('HEAD changed')
    binary = root / 'build/game/gk'
    if document['binary_path'] != str(binary) or fingerprint(binary) != (document['bin'], document['binary_sha256']):
        raise ValueError('binary changed')
    archive = Path(document['source_patch'])
    expected_files = source_files(root, base) | {str(archive)}
    if document['role'] == 'baseline':
        expected_files.add(document['baseline_patch'])
    if not archive.is_absolute() or set(document['files']) != expected_files:
        raise ValueError('source inventory changed')
    for path, expected in document['files'].items():
        if fingerprint(path) != (expected, document['sha256'][path]):
            raise ValueError('file changed: ' + path)
    patch = diff(root, base)
    if canonical_diff(patch) != canonical_diff(archive.read_bytes()):
        raise ValueError('working patch changed')
    if document['role'] == 'baseline':
        if document['baseline_anchor'] != anchor or document['baseline_renderer_verified'] is not True:
            raise ValueError('invalid baseline lineage')
        acquired = Path(document['baseline_patch'])
        if fingerprint(acquired) != (document['baseline_patch_hash'], document['baseline_patch_sha256']):
            raise ValueError('acquired baseline patch changed')
        baseline_check(root, acquired, patch, anchor=anchor, main_root=main_root)
    elif document['baseline_renderer_verified'] is not False:
        raise ValueError('candidate cannot assert baseline verification')
    return document


def verify(path, **kwargs):
    return verify_document(json.loads(Path(path).read_text()), **kwargs)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    sub = parser.add_subparsers(dest='command', required=True)
    create = sub.add_parser('seal')
    create.add_argument('--root', type=Path, required=True)
    create.add_argument('--role', choices=('baseline', 'candidate'), required=True)
    create.add_argument('--output', type=Path, required=True)
    create.add_argument('--baseline-patch', type=Path, default=BASELINE_PATCH)
    check = sub.add_parser('verify')
    check.add_argument('file', type=Path)
    args = parser.parse_args()
    try:
        if args.command == 'seal':
            seal(args.root, args.role, args.output, args.baseline_patch)
        else:
            verify(args.file)
    except (OSError, ValueError, KeyError, TypeError, subprocess.CalledProcessError) as error:
        parser.exit(1, 'provenance: ' + str(error) + '\n')
    print('provenance: verified' if args.command == 'verify' else 'provenance: sealed')


if __name__ == '__main__':
    main()
