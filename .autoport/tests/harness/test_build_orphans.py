"""Runtime cleanup must move only graph-proven, contained orphan objects."""
import importlib.util
from pathlib import Path
import tempfile
import unittest


MODULE_PATH = Path(__file__).resolve().parents[2] / 'lib/build_orphans.py'
SPEC = importlib.util.spec_from_file_location('build_orphans', MODULE_PATH)
ORPHANS = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(ORPHANS)
RUNTIME = Path('game/CMakeFiles/runtime.dir')


class BuildOrphansTest(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix='build-orphans-test-')
        self.addCleanup(self.temp.cleanup)
        self.base = Path(self.temp.name)
        self.build = self.base / 'build'
        self.runtime = self.build / RUNTIME
        self.runtime.mkdir(parents=True)
        self.live = self.runtime / 'live.o'
        self.live.write_bytes(b'live\x00object')
        self.orphan = self.runtime / 'orphan.o'
        self.orphan.write_bytes(b'orphan\x00object')
        (self.build / 'build.ninja').write_text(f'build {RUNTIME}/live.o: phony\n')

    def test_quarantine_preserves_live_and_orphan_bytes_and_is_idempotent(self):
        result = ORPHANS.quarantine(self.build)
        self.assertEqual(result['moved'], [str(RUNTIME / 'orphan.o')])
        self.assertEqual(self.live.read_bytes(), b'live\x00object')
        self.assertFalse(self.orphan.exists())
        saved = Path(result['quarantine']) / RUNTIME / 'orphan.o'
        self.assertEqual(saved.read_bytes(), b'orphan\x00object')
        second = ORPHANS.quarantine(self.build)
        self.assertEqual(second['moved'], [])
        self.assertEqual(second['quarantine'], '-')
        self.assertEqual(second['after']['orphan_count'], 0)
        self.assertEqual(saved.read_bytes(), b'orphan\x00object')
        self.assertEqual(self.live.read_bytes(), b'live\x00object')

    def test_empty_runtime_graph_refuses_without_moving_objects(self):
        (self.build / 'build.ninja').write_text('build unrelated: phony\n')
        with self.assertRaisesRegex(ValueError, 'no runtime object edges'):
            ORPHANS.quarantine(self.build)
        self.assertEqual(self.live.read_bytes(), b'live\x00object')
        self.assertEqual(self.orphan.read_bytes(), b'orphan\x00object')
        self.assertFalse((self.build / '.orphan-objects').exists())

    def test_quarantine_symlink_refuses_without_writing_outside(self):
        outside = self.base / 'outside'
        outside.mkdir()
        marker = outside / 'marker'
        marker.write_bytes(b'untouched')
        quarantine = self.build / '.orphan-objects'
        quarantine.symlink_to(outside, target_is_directory=True)
        with self.assertRaisesRegex(ValueError, 'quarantine escapes'):
            ORPHANS.quarantine(self.build)
        self.assertEqual(list(outside.iterdir()), [marker])
        self.assertEqual(marker.read_bytes(), b'untouched')
        self.assertTrue(quarantine.is_symlink())
        self.assertEqual(self.orphan.read_bytes(), b'orphan\x00object')
        self.assertEqual(self.live.read_bytes(), b'live\x00object')

    def test_orphan_symlink_refuses_without_removing_link(self):
        outside = self.base / 'outside.o'
        outside.write_bytes(b'external object')
        self.orphan.unlink()
        self.orphan.symlink_to(outside)
        with self.assertRaisesRegex(ValueError, 'object escapes'):
            ORPHANS.quarantine(self.build)
        self.assertTrue(self.orphan.is_symlink())
        self.assertEqual(self.orphan.readlink(), outside)
        self.assertEqual(outside.read_bytes(), b'external object')
        self.assertEqual(self.live.read_bytes(), b'live\x00object')
        self.assertFalse((self.build / '.orphan-objects').exists())


if __name__ == '__main__':
    unittest.main(verbosity=2)
