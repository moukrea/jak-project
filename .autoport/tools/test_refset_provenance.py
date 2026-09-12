"""Temporary-repository tests; never build or launch gk."""
import importlib.util
from pathlib import Path
import subprocess
import tempfile
import unittest

import sys

# L'AUTORITE DE NOMMAGE : le fichier de course qu'on commite ici doit porter le nom que la
# course ecrit vraiment, sinon le test verifie qu'un chemin quelconque ne casse pas le sceau.
sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'lib'))
import impossible as NOMS  # noqa: E402

spec = importlib.util.spec_from_file_location('provenance', Path(__file__).with_name('refset_provenance.py'))
p = importlib.util.module_from_spec(spec)
spec.loader.exec_module(p)


class ProvenanceTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.base = Path(self.temporary.name)
        self.root = self.base / 'tree'
        self.root.mkdir()
        self.git('init', '-q')
        self.git('config', 'user.email', 'test@example.invalid')
        self.git('config', 'user.name', 'Test')
        self.shader = self.write(p.SHADERS + '/test.frag', 'historical shader\n')
        self.source = self.write(p.RENDERER + '/renderer.cpp', 'historical renderer\n')
        self.write('game/kernel/test.cpp', 'kernel\n')
        self.write('common/test.h', 'common\n')
        self.git('add', '.')  # git-sandbox-ok
        self.git('commit', '-qm', 'anchor')  # git-sandbox-ok
        self.anchor = self.git('rev-parse', 'HEAD').decode().strip()
        self.binary = self.write('build/game/gk', 'binary fixture\n')
        for name in p.PORTABLE_SETTINGS:
            self.write('build/game/OpenGOAL/jak1/' + name, '{}\n')
        self.source.write_text('adapted historical renderer\n')
        self.acquired = self.base / 'acquired.patch'
        self.acquired.write_bytes(p.diff(self.root))
        self.output = self.base / 'sealed.json'

    def git(self, *args):
        return subprocess.check_output(['git', '-C', str(self.root), *args], stderr=subprocess.PIPE)

    def write(self, name, text):
        path = self.root / name
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(text)
        return path

    def seal(self, role='baseline', **kwargs):
        return p.seal(self.root, role, self.output, self.acquired, anchor=kwargs.get('anchor', self.anchor))

    def verify(self):
        return p.verify(self.output, anchor=self.anchor)

    def test_baseline_and_candidate(self):
        certificate = self.seal()
        self.assertTrue(self.verify()['baseline_renderer_verified'])
        self.assertEqual(certificate['bin'], p.fnv64(self.binary.read_bytes()))
        self.output = self.base / 'candidate.json'
        self.assertFalse(self.seal('candidate')['baseline_renderer_verified'])
        self.verify()

    def test_bad_anchor_and_main_tree(self):
        with self.assertRaisesRegex(ValueError, 'anchor'):
            self.seal(anchor='0' * 40)
        with self.assertRaisesRegex(ValueError, 'distinct'):
            p.seal(self.root, 'baseline', self.output, self.acquired,
                   anchor=self.anchor, main_root=self.root)
        self.assertFalse(self.output.exists())

    def test_shader_rejected_at_seal(self):
        self.shader.write_text('candidate shader\n')
        with self.assertRaisesRegex(ValueError, 'shader'):
            self.seal()

    def test_additional_shader_rejected(self):
        self.write(p.SHADERS + '/extra.frag', 'extra\n')
        with self.assertRaisesRegex(ValueError, 'shader inventory'):
            self.seal()

    def test_renderer_rejected(self):
        self.source.write_text('unacquired renderer\n')
        with self.assertRaisesRegex(ValueError, 'renderer differs'):
            self.seal()

    def test_mutations(self):
        self.seal()
        for path in (self.shader, self.source, self.binary, self.acquired,
                     self.root / 'common/test.h', self.output.with_suffix('.patch'),
                     self.root / 'build/game/OpenGOAL/jak1/settings/settings.ini'):
            with self.subTest(path=path):
                original = path.read_bytes()
                path.write_bytes(original + b'mutation')
                with self.assertRaises(ValueError):
                    self.verify()
                path.write_bytes(original)
        self.verify()

    def test_new_source_invalidates_inventory(self):
        self.seal()
        self.write('game/system/new.cpp', 'new source\n')
        with self.assertRaisesRegex(ValueError, 'inventory'):
            self.verify()

    def test_head_change_invalidates(self):
        self.seal()
        self.git('commit', '--allow-empty', '-qm', 'new head')  # git-sandbox-ok
        with self.assertRaisesRegex(ValueError, 'HEAD changed'):
            self.verify()

    def test_candidate_commit_preserves_certificate(self):
        self.write('game/system/new.cpp', 'new system source\n')
        self.write('game/overlord/new.cpp', 'new source outside regular roots\n')
        self.write('common/new.h', 'new common source\n')
        self.git('add', 'game/kernel/test.cpp')  # git-sandbox-ok
        certificate = self.seal('candidate')
        self.git('add', 'game', 'common')  # git-sandbox-ok
        self.git('commit', '-qm', 'commit sealed edits')  # git-sandbox-ok
        self.assertNotEqual(self.git('rev-parse', 'HEAD').decode().strip(), certificate['base_commit'])
        self.assertEqual(self.verify()['base_commit'], certificate['base_commit'])
        self.source.write_text('later source mutation\n')
        with self.assertRaises(ValueError):
            self.verify()

    def test_candidate_unrelated_commit_preserves_certificate(self):
        self.seal('candidate')
        self.write(NOMS.arm_name('proof', ''), 'unrelated runtime state\n')
        self.git('add', NOMS.arm_name('proof', ''))
        self.git('commit', '-qm', 'runtime state')  # git-sandbox-ok
        self.verify()

    def test_staged_unstaged_and_new_game_sources(self):
        self.git('add', p.RENDERER + '/renderer.cpp')
        self.write('game/kernel/test.cpp', 'unstaged kernel\n')
        new = self.write('game/system/refset_extra.cpp', 'new instrumentation\n')
        certificate = self.seal()
        self.assertIn(str(new), certificate['files'])
        archive = self.output.with_suffix('.patch').read_bytes()
        for text in (b'adapted historical renderer', b'unstaged kernel', b'new instrumentation'):
            self.assertIn(text, archive)
        self.verify()

    def test_no_overwrite(self):
        self.seal()
        original = self.output.read_bytes()
        with self.assertRaises(FileExistsError):
            self.seal()
        self.assertEqual(original, self.output.read_bytes())
        self.output.unlink()
        with self.assertRaises(FileExistsError):
            self.seal()
        self.assertFalse(self.output.exists())

    def test_historical_fnv_offset(self):
        self.assertEqual(p.fnv64(b''), 1469598103934665603)
        self.assertEqual(p.fnv64(b'a'), 4953267810257967366)


if __name__ == '__main__':
    unittest.main()
