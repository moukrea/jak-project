"""Fake producer only in isolated temporary repositories; never launches the game."""
import importlib.util
import json
import os
from pathlib import Path
import signal
import subprocess
import sys
import tempfile
import time
import unittest

TOOL = Path(__file__).resolve().parents[2] / 'tools/refset_campaign.py'
spec = importlib.util.spec_from_file_location('refset_campaign', TOOL)
runner = importlib.util.module_from_spec(spec)
spec.loader.exec_module(runner)

FAKE_BACKLOG = '''
import json
from contextlib import contextmanager
@contextmanager
def _Lock(path):
    import fcntl
    with open(str(path)+'.lock', 'a') as stream:
        fcntl.flock(stream, fcntl.LOCK_EX)
        yield

def _read(path): return json.loads(path.read_text())
def _dump(doc): return json.dumps(doc)
def _atomic_write(path, text): path.write_text(text)
'''
FAKE_PRODUCER = '''#!/usr/bin/env bash
exec python3 - <<'ENGINE'
from pathlib import Path
import datetime, hashlib, json, os, time
root=Path.cwd()
if (root/'force-failure').exists(): raise SystemExit(7)
mode=os.environ['OG_REFSET']
output=Path(os.environ['OG_REFSET_DIR'])
(root/'invocations').open('a').write(os.environ['OG_REFSET_RUN_ID']+'\\n')
if os.environ.get('OG_TEST_SLEEP') == '1': time.sleep(30)
if mode == 'capture':
    output.mkdir()
    (output/'sample.png').write_bytes(b'fixture image')
    (output/'sample.png.provenance.txt').write_text('fixture sidecar')
    snapshot=output/'qualification-assets-capture.tsv'
    snapshot.write_text('capture assets')
    (output/'qualification-capture.json').write_text(json.dumps({'assets_path':str(snapshot)}))
if os.environ.get('OG_REFSET_QUALIFY_STATE') == '1' and mode == 'replay':
    q=output/'qualification-replays'
    q.mkdir(exist_ok=True)
    fp=1469598103934665603
    for byte in (output/'qualification-capture.json').read_bytes(): fp=((fp ^ byte)*1099511628211)&((1<<64)-1)
    snapshot=output/('qualification-assets-'+os.environ['OG_REFSET_RUN_ID']+'.tsv')
    snapshot.write_text('replay assets')
    assets_fp=1469598103934665603
    for byte in snapshot.read_bytes(): assets_fp=((assets_fp ^ byte)*1099511628211)&((1<<64)-1)
    report={'assets_path':str(snapshot), 'assets_fp':assets_fp, 'version':1, 'kind':'replay', 'clean':True, 'reconstructed':True, 'cases':[{}], 'capture_fp':fp}
    if os.environ.get('OG_TEST_BAD_QUALIFICATION') == '1': report['capture_fp'] += 1
    (q/(os.environ['OG_REFSET_RUN_ID']+'.json')).write_text(json.dumps(report))
    (output/'replay-ledger.txt').write_text(os.environ['OG_REFSET_RUN_ID'])
    (output/('qualification-adoption-'+os.environ['OG_REFSET_RUN_ID']+'.json')).write_text('{}')
d=root/'.autoport/reports/lighting-census'
d.mkdir(parents=True, exist_ok=True)
captured=1 if mode == 'capture' else 0
compared=1-captured
diff=int(os.environ.get('OG_TEST_DIFF', '0'))
proof=f'source=x86\\nstarted_at={datetime.datetime.now(datetime.timezone.utc).isoformat()}\\nsha={hashlib.sha256((root/"build/game/gk").read_bytes()).hexdigest()[:16]}\\ncrash=0\\nframes=50\\nrefset_provenance_bad=0\\nrefset_steps=1\\nrefset_captured={captured}\\n'
if mode == 'replay': proof+=f'refset_compared=1\\nrefset_replay_maxdiff=254\\nrefset_replay_run_maxdiff={diff}\\nrefset_replay_diffpx={diff}\\nrefset_missing=0\\nrefset_size_bad=0\\nrefset_decode_bad=0\\n'
if os.environ.get('OG_REFSET_QUALIFY_STATE') == '1': proof+='refset_qualification_state_bad=0\\nrefset_qualification_receipt_written=1\\n'
(d/'proof.txt').write_text(proof)
(d/'proof-engine.log').write_text(f'REFSET done steps=1 captured={captured} compared={compared} maxdiff={diff} diffpx={diff} missing=0\\n')
ENGINE
'''


class CampaignTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.base = Path(self.temp.name)
        self.root = self.base / 'root'
        for directory in ('.autoport/lib', 'build/game', 'game/graphics', 'out/jak1/iso'):
            (self.root / directory).mkdir(parents=True)
        (self.root / 'build/game/gk').write_bytes(b'fake test binary')
        (self.root / 'game/graphics/source.cpp').write_text('source')
        (self.root / '.autoport/lib/backlog.py').write_text(FAKE_BACKLOG)
        (self.root / '.autoport/lib/proof_run.sh').write_text(FAKE_PRODUCER)
        self.backlog = self.root / '.autoport/backlog.yaml'
        self.original = {'items': [{'id': 'lighting-census', 'proof_env': ['OG_PRESERVED=1', 'OG_REFSET=disabled'], 'gate': {'unchanged': True}}, {'id': 'other', 'status': 'open'}]}
        self.backlog.write_text(json.dumps(self.original))
        self.campaign = self.base / 'campaign'
        self.env = self.base / 'env.json'
        self.env.write_text(json.dumps({'OG_REFSET': 'capture'}))

    def command(self, name='one'):
        return [sys.executable, str(TOOL), 'run', '--campaign', str(self.campaign), '--root', str(self.root), '--name', name, '--env-json', str(self.env), '--timeout', '1']

    def invoke(self, name='one', code=0):
        result = subprocess.run(self.command(name), capture_output=True, text=True)
        self.assertEqual(result.returncode, code, result.stdout + result.stderr)
        self.assertEqual(json.loads(self.backlog.read_text()), self.original)
        return result

    def receipts(self):
        return runner.status(self.campaign)

    def test_five_names_five_processes_and_resume(self):
        for i in range(5): self.invoke(str(i))
        self.invoke('4')
        self.assertEqual(len((self.root / 'invocations').read_text().splitlines()), 5)
        self.assertEqual(len(self.receipts()), 5)
        self.assertEqual(len(set(r['runtime']['OG_REFSET_RUN_ID'] for r in self.receipts())), 5)
        self.assertTrue(all('OG_PRESERVED' in r['before']['env'] for r in self.receipts()))

    def test_changed_source_and_sidecar_force_new_attempt(self):
        self.invoke()
        (self.root / 'game/graphics/source.cpp').write_text('changed')
        self.invoke()
        capture = Path(self.receipts()[-1]['runtime']['OG_REFSET_DIR'])
        (capture / 'sample.png.provenance.txt').write_text('changed')
        self.invoke()
        self.assertEqual(len(self.receipts()), 3)

    def test_replay_requires_exact_diff_and_archives_qualification(self):
        self.invoke('capture')
        reference = self.receipts()[0]['runtime']['OG_REFSET_DIR']
        self.env.write_text(json.dumps({'OG_REFSET': 'replay', 'OG_REFSET_DIR': reference, 'OG_REFSET_QUALIFY_STATE': '1'}))
        self.invoke('replay')
        self.invoke('replay')
        self.assertEqual(len(self.receipts()), 2)
        self.env.write_text(json.dumps({'OG_REFSET': 'replay', 'OG_REFSET_DIR': reference, 'OG_TEST_DIFF': '1'}))
        self.invoke('replay', code=1)
        self.invoke('replay', code=1)
        self.assertEqual(len(self.receipts()), 4)
        self.assertEqual(self.receipts()[-1]['state'], 'failed')

    def test_failure_does_not_archive_stale_proof_or_reuse_older_success(self):
        self.invoke()
        first = self.receipts()[0]
        sidecar = Path(first['runtime']['OG_REFSET_DIR']) / 'sample.png.provenance.txt'
        original_sidecar = sidecar.read_bytes()
        sidecar.write_text('force a fresh attempt')
        (self.root / 'force-failure').touch()
        self.invoke(code=1)
        failure = self.receipts()[-1]
        self.assertEqual(failure['exit_code'], 7)
        self.assertFalse((Path(failure['attempt']) / 'proof-original.txt').exists())
        sidecar.write_bytes(original_sidecar)
        (self.root / 'force-failure').unlink()
        self.invoke()
        self.assertEqual(len(self.receipts()), 3)

    def test_bad_qualification_capture_fingerprint_is_failed(self):
        self.invoke('capture')
        reference = self.receipts()[0]['runtime']['OG_REFSET_DIR']
        self.env.write_text(json.dumps({'OG_REFSET': 'replay', 'OG_REFSET_DIR': reference,
                                       'OG_REFSET_QUALIFY_STATE': '1', 'OG_TEST_BAD_QUALIFICATION': '1'}))
        self.invoke('replay', code=1)
        self.invoke('replay', code=1)
        self.assertEqual(len(self.receipts()), 3)

    def test_settings_system_common_and_build_provenance_force_new_runs(self):
        provenance = self.base / 'build-provenance.json'
        provenance.write_text('{}')
        self.env.write_text(json.dumps({'OG_REFSET': 'capture', 'OG_REFSET_BUILD_PROVENANCE': str(provenance)}))
        self.invoke()
        for relative in ('game/system/boot_replay.cpp', 'game/kernel/replay.cpp', 'common/source.cpp',
                         'build/game/OpenGOAL/jak1/settings/display-settings.json'):
            path = self.root / relative
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_text('new input')
            self.invoke()
        provenance.write_text('{"changed": true}')
        self.invoke()
        self.assertEqual(len(self.receipts()), 6)

    def test_asset_snapshot_mutation_invalidates_reuse(self):
        self.invoke('capture')
        reference = Path(self.receipts()[0]['runtime']['OG_REFSET_DIR'])
        snapshot = reference / 'qualification-assets-capture.tsv'
        snapshot.write_text('mutated capture assets')
        self.invoke('capture')
        self.assertEqual(len(self.receipts()), 2)
        self.env.write_text(json.dumps({'OG_REFSET': 'replay', 'OG_REFSET_DIR': str(reference),
                                       'OG_REFSET_QUALIFY_STATE': '1'}))
        self.invoke('replay')
        record = json.loads((Path(self.receipts()[-1]['attempt']) / 'qualification-original.json').read_text())
        Path(record['assets_path']).write_text('mutated replay assets')
        self.invoke('replay')
        self.assertEqual(len(self.receipts()), 4)

    def test_status_read_only(self):
        missing = self.base / 'does-not-exist'
        result = subprocess.run([sys.executable, str(TOOL), 'status', '--campaign', str(missing)], capture_output=True)
        self.assertEqual(result.returncode, 0)
        self.assertFalse(missing.exists())

    def test_cas_preserves_other_writer(self):
        original = runner.configuration(self.root)
        selected = runner.configuration(self.root, replace={'OG_REFSET': 'capture'}, expected=original)
        doc = json.loads(self.backlog.read_text())
        doc['items'][0]['proof_env'] = ['OG_OTHER_WRITER=1']
        self.backlog.write_text(json.dumps(doc))
        with self.assertRaises(RuntimeError): runner.configuration(self.root, restore=original, expected=selected)
        self.assertEqual(runner.configuration(self.root), ['OG_OTHER_WRITER=1'])

    def test_sigterm_restores_and_records_failure(self):
        self.env.write_text(json.dumps({'OG_REFSET': 'capture', 'OG_TEST_SLEEP': '1'}))
        process = subprocess.Popen(self.command(), stdout=subprocess.PIPE, stderr=subprocess.PIPE)
        try:
            deadline = time.monotonic() + 5
            while not (self.root / 'invocations').exists() and time.monotonic() < deadline:
                time.sleep(.02)
            self.assertTrue((self.root / 'invocations').exists())
            process.send_signal(signal.SIGTERM)
            stdout, stderr = process.communicate(timeout=8)
            self.assertEqual(process.returncode, 1, stdout + stderr)
            self.assertEqual(json.loads(self.backlog.read_text()), self.original)
            self.assertEqual(self.receipts()[0]['state'], 'failed')
        finally:
            if process.poll() is None:
                process.kill()
                process.wait()

    def test_selected_shared_producer_is_used_and_fingerprinted(self):
        shared = self.base / 'shared' / '.autoport/lib/proof_run.sh'
        shared.parent.mkdir(parents=True)
        shared.write_text(FAKE_PRODUCER)
        (self.root / '.autoport/lib/proof_run.sh').write_text('exit 9\n')
        command = self.command() + ['--proof-run', str(shared)]
        for _ in range(2):
            result = subprocess.run(command, capture_output=True, text=True)
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertEqual(len(self.receipts()), 1)
        self.assertIn(str(shared), self.receipts()[0]['before']['runner'])
        self.assertNotIn(str(self.root / '.autoport/lib/proof_run.sh'), self.receipts()[0]['before']['runner'])
        shared.write_text(FAKE_PRODUCER + '\n')
        result = subprocess.run(command, capture_output=True, text=True)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertEqual(len(self.receipts()), 2)
        self.assertEqual(json.loads(self.backlog.read_text()), self.original)

    def test_lock_exclusion(self):
        self.campaign.mkdir()
        with runner.lock(self.campaign / '.campaign.lock'):
            self.invoke(code=2)
        self.assertFalse((self.root / 'invocations').exists())

    def test_partial_proof_not_reusable(self):
        self.assertFalse(runner.complete('crash=0\nframes=20\n', '', 'capture'))


if __name__ == '__main__':
    unittest.main()
