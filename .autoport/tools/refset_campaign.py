#!/usr/bin/env python3
"""Serial x86 REFSET attempts; receipts are bookkeeping, never qualification.
DIRECTIVES v6fca51fe40. See refset_campaign.md for the input/locking contract.
"""
import argparse
from contextlib import contextmanager
from datetime import datetime
import fcntl
import hashlib
import importlib.util
import json
import os
from pathlib import Path
import re
import shutil
import signal
import subprocess
import sys
import time
import uuid

PHASE = 'lighting-census'

# L'AUTORITE DE NOMMAGE des fichiers d'une course de preuve. La campagne COPIE ce que
# `proof_run.sh` vient d'ecrire : un nom reecrit ici ne trouverait plus rien a copier, et la
# campagne conclurait sur une course qu'elle n'a pas lue.
sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'lib'))
import impossible as NOMS  # noqa: E402
NOM_PREUVE = NOMS.arm_name('proof', '')
NOM_JOURNAL = NOMS.arm_name('engine', '')
OUTPUT_KEYS = {'OG_REFSET_DIR', 'OG_REFSET_ASSET_MANIFEST', 'OG_PAD_REPLAY_TRACE', 'OG_REFSET_RUN_ID'}


def digest(path):
    h = hashlib.sha256()
    with Path(path).open('rb') as stream:
        for block in iter(lambda: stream.read(1024 * 1024), b''):
            h.update(block)
    return h.hexdigest()


def json_write(path, value):
    temp = path.with_name(path.name + '.tmp')
    with temp.open('w') as stream:
        json.dump(value, stream, indent=2, sort_keys=True)
        stream.write('\n')
        stream.flush()
        os.fsync(stream.fileno())
    temp.replace(path)


def tree(paths):
    result = {}
    for path in sorted(set(map(Path, paths))):
        if not path.exists():
            result[str(path)] = None
        elif path.is_file():
            result[str(path)] = digest(path)
        else:
            result[str(path) + '/'] = 'directory'
            for child in sorted(path.rglob('*')):
                if child.is_file():
                    result[str(child)] = digest(child)
    return result


def reference_tree(root):
    """Only producer reference inputs; ledgers/adoption/other run receipts are outputs."""
    names = {'captured-by.txt', 'refset-format.txt', 'qualification-capture.json'}
    paths = [p for p in root.rglob('*') if p.is_file() and
             (p.name in names or p.name.endswith(('.png', '.provenance.txt', '.state.bin')))]
    capture = root / 'qualification-capture.json'
    if capture.is_file():
        report = json.loads(capture.read_text())
        if report.get('assets_path'):
            assets = Path(report['assets_path'])
            if not assets.is_absolute():
                raise ValueError('qualification assets_path must be absolute')
            paths.append(assets)
    return tree(paths)


def producer_hash(path):
    value = 1469598103934665603  # Producer hash_file FNV-1a, not SHA256.
    for byte in path.read_bytes():
        value = ((value ^ byte) * 1099511628211) & ((1 << 64) - 1)
    return value or 1


def qualification_complete(proof, reference, mode, run_id):
    fields = dict(re.findall(r'^([\w]+)=([^\r\n]+)$', proof, re.M))
    path = reference / ('qualification-capture.json' if mode == 'capture' else
                        'qualification-replays/' + run_id + '.json')
    try:
        report = json.loads(path.read_text())
        return (fields.get('refset_qualification_state_bad') == '0'
                and fields.get('refset_qualification_receipt_written') == '1'
                and report['version'] == 1 and report['kind'] == mode
                and report['clean'] is True and report['reconstructed'] is True
                and len(report['cases']) == int(fields['refset_steps'])
                and Path(report['assets_path']).is_absolute()
                and report['assets_fp'] == producer_hash(Path(report['assets_path']))
                and (mode == 'capture' or report['capture_fp'] == producer_hash(reference / 'qualification-capture.json')))
    except (OSError, KeyError, ValueError, TypeError):
        return False


@contextmanager
def lock(path):
    with path.open('a+') as stream:
        fcntl.flock(stream, fcntl.LOCK_EX | fcntl.LOCK_NB)
        stream.seek(0)
        stream.truncate()
        stream.write(f'pid={os.getpid()}\n')
        stream.flush()
        try:
            yield
        finally:
            fcntl.flock(stream, fcntl.LOCK_UN)


def backlog_module(root):
    spec = importlib.util.spec_from_file_location('campaign_backlog', root / '.autoport/lib/backlog.py')
    module = importlib.util.module_from_spec(spec)
    sys.modules[spec.name] = module
    spec.loader.exec_module(module)
    return module


def configuration(root, replace=None, expected=None, save=None, restore=None):
    module = backlog_module(root)
    path = root / '.autoport/backlog.yaml'
    with module._Lock(path):
        doc = module._read(path)
        item = next(it for it in doc['items'] if it['id'] == PHASE)
        before = item.get('proof_env', [])
        if not isinstance(before, list) or any(not isinstance(x, str) or '=' not in x for x in before):
            raise ValueError('proof_env must be a list of KEY=value strings')
        if expected is not None and before != expected:
            raise RuntimeError('proof_env changed concurrently; refusing to overwrite another writer')
        if replace is None and restore is None:
            return before
        after = restore if restore is not None else [x for x in before if x.split('=', 1)[0] not in replace] + [f'{k}={v}' for k, v in sorted(replace.items())]
        if save:
            json_write(save, {'before': before, 'during': after})
        item['proof_env'] = after
        module._atomic_write(path, module._dump(doc))
        return after


def env_dict(entries):
    return dict(entry.split('=', 1) for entry in entries)


def resolved(root, value):
    path = Path(value)
    return path if path.is_absolute() else root / path


def proof_run_path(root, args):
    return args.proof_run.resolve() if args.proof_run else root / '.autoport/lib/proof_run.sh'


def identity(root, env, args):
    # Capture destinations are allocated per attempt, never shared between processes.
    stable_env = {k: v for k, v in env.items() if k not in OUTPUT_KEYS or (k == 'OG_REFSET_DIR' and env['OG_REFSET'] == 'replay')}
    inputs = [resolved(root, p) for p in args.input]
    for key in ('OG_BOOT_REPLAY_REPLAY', 'OG_PAD_REPLAY_REPLAY', 'OG_REFSET_QUALIFICATION', 'OG_REFSET_BUILD_PROVENANCE'):
        if env.get(key):
            inputs.append(resolved(root, env[key]))
    data = [root / 'out/jak1/iso', root / 'out/jak1/fr3', root / 'build/game/assets', root / 'build/game/custom_assets']
    data += [resolved(root, p) for p in args.data]
    return {
        'schema': 2, 'root': str(root), 'timeout': args.timeout, 'env': stable_env,
        'host_env': {k: os.environ.get(k) for k in ('DISPLAY', 'XAUTHORITY', 'PATH', 'LD_LIBRARY_PATH', 'LD_PRELOAD', 'MESA_LOADER_DRIVER_OVERRIDE', 'LIBGL_ALWAYS_SOFTWARE')},
        'binary': tree([root / 'build/game/gk']),
        'sources': tree([root / 'game/graphics', root / 'game/kernel', root / 'game/system', root / 'common', root / 'game/main.cpp']),
        'runner': tree([Path(__file__).resolve(), proof_run_path(root, args), root / '.autoport/lib/backlog.py']),
        'data': tree(data),
        'settings': tree([root / 'build/game/OpenGOAL/jak1/settings', root / 'build/game/OpenGOAL/jak1/misc/debug-settings.json']),
        'inputs': tree(inputs),
        'references': reference_tree(resolved(root, env['OG_REFSET_DIR'])) if env['OG_REFSET'] == 'replay' else {},
    }


def complete(proof, log, mode):
    """Conservative resume predicate, not a gate or a product verdict."""
    fields = dict(re.findall(r'^([\w]+)=([^\r\n]+)$', proof, re.M))
    done = re.findall(r'REFSET done steps=(\d+) captured=(\d+) compared=(\d+) maxdiff=(\d+) diffpx=(\d+) missing=(\d+)', log)
    if len(done) != 1:
        return False
    steps, captured, compared, maxdiff, diffpx, missing = map(int, done[0])
    try:
        if fields['source'] != 'x86' or int(fields['crash']) != 0 or int(fields['frames']) <= 0 or int(fields['refset_provenance_bad']) != 0:
            return False
        if steps <= 0 or int(fields['refset_steps']) != steps or int(fields['refset_captured']) != captured or missing:
            return False
        if mode == 'capture':
            return captured == steps and compared == 0
        return (compared == steps and captured == 0 and maxdiff == diffpx == 0
                and int(fields['refset_compared']) == steps
                and all(int(fields[k]) == 0 for k in ('refset_replay_run_maxdiff', 'refset_replay_diffpx', 'refset_missing', 'refset_size_bad', 'refset_decode_bad')))
    except (KeyError, ValueError):
        return False


def reusable(receipt, current):
    try:
        proof = Path(receipt['attempt']) / 'proof-original.txt'  # NOM-LITTERAL-ATTENDU: genre-propre-a-la-campagne-refset
        log = Path(receipt['attempt']) / NOM_JOURNAL
        return (receipt['state'] == 'complete' and receipt['exit_code'] == 0
                and receipt['before'] == receipt['after'] == current
                and receipt['artifacts'] == tree(receipt['artifact_roots'])
                and receipt['references'] == reference_tree(Path(receipt['reference_root']))
                and (current['env'].get('OG_REFSET_QUALIFY_STATE') != '1' or
                     qualification_complete(proof.read_text(), Path(receipt['reference_root']), current['env']['OG_REFSET'], receipt['runtime']['OG_REFSET_RUN_ID']))
                and complete(proof.read_text(), log.read_text(errors='replace'), current['env']['OG_REFSET']))
    except (OSError, KeyError, ValueError):
        return False


def status(campaign):
    # Deliberately no mkdir, locks, recovery, or rewriting of receipts.
    return [json.loads(p.read_text()) for p in sorted(campaign.glob('attempt-*/receipt.json'))]


def stop_process(process):
    if process is not None:
        try:
            os.killpg(process.pid, signal.SIGTERM)
        except ProcessLookupError:
            return
        try:
            process.wait(timeout=5)
        except subprocess.TimeoutExpired:
            os.killpg(process.pid, signal.SIGKILL)
            process.wait()


def run(args):
    root = args.root.resolve()
    campaign = args.campaign.resolve()
    requested = json.loads(args.env_json.read_text())
    if not isinstance(requested, dict) or any(not re.fullmatch(r'OG_[A-Z0-9_]+', k) or not isinstance(v, str) or '\n' in v or '\0' in v for k, v in requested.items()):
        raise ValueError('env-json must be an object of explicit OG_* string values (no newline/NUL)')
    if requested.get('OG_REFSET') not in ('capture', 'replay'):
        raise ValueError('env-json must explicitly select OG_REFSET=capture or replay')
    if requested['OG_REFSET'] == 'replay' and not requested.get('OG_REFSET_DIR'):
        raise ValueError('replay requires OG_REFSET_DIR')
    campaign.mkdir(parents=True, exist_ok=True)
    with lock(campaign / '.campaign.lock'), lock(root / '.autoport/.refset-campaign.lock'):
        before_env = configuration(root)
        env = env_dict(before_env) | requested
        before = identity(root, env, args)
        history = [r for r in status(campaign) if r['name'] == args.name]
        # A subsequent failed/interrupted attempt must never disappear behind an older success.
        if history and reusable(history[-1], before):
            print(json.dumps({'reused': history[-1]['attempt'], 'name': args.name}))
            return 0
        attempt = campaign / f'attempt-{time.time_ns()}-{uuid.uuid4().hex[:8]}'
        attempt.mkdir()
        runtime = dict(requested)
        runtime['OG_REFSET_RUN_ID'] = uuid.uuid4().hex
        if env['OG_REFSET'] == 'capture':
            runtime['OG_REFSET_DIR'] = str(attempt / 'captures')
        runtime['OG_REFSET_ASSET_MANIFEST'] = str(attempt / 'consumed.tsv')
        runtime['OG_PAD_REPLAY_TRACE'] = str(attempt / 'pad-state.trace')
        receipt = {'schema': 1, 'name': args.name, 'attempt': str(attempt), 'state': 'prepared', 'before': before, 'runtime': runtime, 'exit_code': None, 'started_ns': time.time_ns()}
        receipt_path = attempt / 'receipt.json'
        json_write(receipt_path, receipt)
        process = None
        selected = None
        interrupted = False
        def interrupt(signum, _frame):
            nonlocal interrupted
            if not interrupted:
                interrupted = True
                raise InterruptedError(f'interrupted by signal {signum}')
        previous = {s: signal.signal(s, interrupt) for s in (signal.SIGINT, signal.SIGTERM)}
        originals = root / '.autoport/reports' / PHASE
        old = {p: (p.stat().st_mtime_ns, p.stat().st_ino) if p.exists() else None for p in (originals / NOM_PREUVE, originals / NOM_JOURNAL)}
        try:
            selected = configuration(root, replace=runtime, expected=before_env, save=attempt / 'proof-env-selection.json')
            child_env = {k: v for k, v in os.environ.items() if not k.startswith('OG_')}
            child_env.update(env_dict(selected))
            child_env['AUTOPORT_BACKEND'] = 'codex'
            child_env['AUTOPORT_PROOF_WAIT_MAX'] = '60'
            receipt['state'] = 'running'
            json_write(receipt_path, receipt)
            with (attempt / 'proof-run.log').open('xb') as log:  # NOM-LITTERAL-ATTENDU: genre-propre-a-la-campagne-refset
                process = subprocess.Popen(['bash', str(proof_run_path(root, args)), PHASE, 'x86', '--timeout', str(args.timeout)], cwd=root, env=child_env, stdout=log, stderr=subprocess.STDOUT, start_new_session=True)
                receipt['pid'] = process.pid
                json_write(receipt_path, receipt)
                receipt['exit_code'] = process.wait(timeout=args.timeout + 90)
        except (Exception, KeyboardInterrupt) as error:
            receipt['error'] = str(error)
            receipt['state'] = 'failed'
        finally:
            # Keep cleanup itself safe from a second SIGTERM/interrupt.
            for sig in previous:
                signal.signal(sig, signal.SIG_IGN)
            stop_process(process)
            if process is not None and receipt['exit_code'] is None:
                receipt['exit_code'] = process.returncode
            # Recover even if a signal arrived just after the atomic selection write.
            selection = attempt / 'proof-env-selection.json'
            if selection.exists():
                saved = json.loads(selection.read_text())
                try:
                    actual = configuration(root)
                    if actual != saved['before']:
                        configuration(root, expected=saved['during'], restore=saved['before'])
                    receipt['restored'] = True
                except Exception as error:
                    receipt['restore_error'] = str(error)
                    receipt['restored'] = False
            for source, signature in old.items():
                if source.exists() and (source.stat().st_mtime_ns, source.stat().st_ino) != signature:
                    shutil.copy2(source, attempt / ('proof-original.txt' if source.name == NOM_PREUVE else source.name))  # NOM-LITTERAL-ATTENDU: genre-propre-a-la-campagne-refset
            try:
                receipt['after'] = identity(root, env, args)
                paths = [attempt / 'proof-original.txt', attempt / NOM_JOURNAL, attempt / 'proof-run.log', attempt / 'consumed.tsv', attempt / 'pad-state.trace']  # NOM-LITTERAL-ATTENDU: genre-propre-a-la-campagne-refset
                reference = resolved(root, runtime.get('OG_REFSET_DIR', env.get('OG_REFSET_DIR', '')))
                receipt['reference_root'] = str(reference)
                receipt['references'] = reference_tree(reference)
                if env['OG_REFSET'] == 'replay' and env.get('OG_REFSET_QUALIFY_STATE') == '1':
                    qualification = reference / 'qualification-replays' / (runtime['OG_REFSET_RUN_ID'] + '.json')
                    paths.append(qualification)
                    if qualification.is_file():
                        shutil.copy2(qualification, attempt / 'qualification-original.json')
                        paths.append(attempt / 'qualification-original.json')
                        assets = Path(json.loads(qualification.read_text())['assets_path'])
                        if not assets.is_absolute():
                            raise ValueError('qualification assets_path must be absolute')
                        paths.append(assets)
                        shutil.copy2(assets, attempt / 'qualification-assets-original.tsv')
                        paths.append(attempt / 'qualification-assets-original.tsv')
                receipt['artifact_roots'] = list(map(str, paths))
                receipt['artifacts'] = tree(paths)
                proof = (attempt / 'proof-original.txt').read_text()  # NOM-LITTERAL-ATTENDU: genre-propre-a-la-campagne-refset
                log = (attempt / NOM_JOURNAL).read_text(errors='replace')
                fields = dict(re.findall(r'^([\w]+)=([^\r\n]+)$', proof, re.M))
                proof_start = datetime.fromisoformat(fields['started_at'].replace('Z', '+00:00')).timestamp()
                binary_sha = before['binary'][str(root / 'build/game/gk')]
                images = list(reference.rglob('*.png'))
                sidecars = all(p.with_name(p.name + '.provenance.txt').is_file() for p in images)
                good = (complete(proof, log, env['OG_REFSET']) and proof_start >= receipt['started_ns'] // 1_000_000_000
                        and fields.get('sha') == binary_sha[:16] and len(images) >= int(fields['refset_steps']) and sidecars
                        and (env.get('OG_REFSET_QUALIFY_STATE') != '1' or
                             qualification_complete(proof, reference, env['OG_REFSET'], runtime['OG_REFSET_RUN_ID'])))
                receipt['state'] = 'complete' if (good and receipt['exit_code'] == 0 and receipt.get('restored') and 'error' not in receipt and before == receipt['after']) else 'failed'
            except Exception as error:
                receipt['state'] = 'failed'
                receipt['archive_error'] = str(error)
            receipt['finished_ns'] = time.time_ns()
            json_write(receipt_path, receipt)
            for sig, handler in previous.items():
                signal.signal(sig, handler)
        print(json.dumps({'receipt': str(receipt_path), 'state': receipt['state']}))
        return 0 if receipt['state'] == 'complete' else 1


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    commands = parser.add_subparsers(dest='command', required=True)
    execute = commands.add_parser('run')
    execute.add_argument('--campaign', type=Path, required=True)
    execute.add_argument('--name', required=True)
    execute.add_argument('--root', type=Path, required=True)
    execute.add_argument('--env-json', type=Path, required=True)
    execute.add_argument('--proof-run', type=Path, help='Existing shared proof_run.sh producer; default: ROOT/.autoport/lib/proof_run.sh')
    execute.add_argument('--timeout', type=int, choices=range(1, 301), metavar='1..300', required=True)
    execute.add_argument('--data', action='append', default=[], help='Additional data/overlay file or tree to fingerprint, repeatable')
    execute.add_argument('--input', action='append', default=[], help='Additional input file or tree to fingerprint, repeatable')
    inspect = commands.add_parser('status')
    inspect.add_argument('--campaign', type=Path, required=True)
    args = parser.parse_args()
    try:
        if args.command == 'status':
            print(json.dumps(status(args.campaign), indent=2))
            return 0
        return run(args)
    except (OSError, ValueError, RuntimeError) as error:
        print(str(error), file=sys.stderr)
        return 2


if __name__ == '__main__':
    sys.exit(main())
