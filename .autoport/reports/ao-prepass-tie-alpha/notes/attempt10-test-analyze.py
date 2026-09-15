#!/usr/bin/env python3
"""DIRECTIVES v775512c234 -- synthetic tests, no device claim."""
import importlib.util
import contextlib
import io
import json
import pathlib
import struct
import sys
import tempfile
import unittest
from unittest.mock import patch

import numpy as np

spec = importlib.util.spec_from_file_location('attribution', pathlib.Path(__file__).with_name('attempt10-analyze.py'))
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)


class AttributionTest(unittest.TestCase):
    def test_projection_overwrites_translation_w(self):
        ubo = np.zeros(56, dtype='<f4')
        columns = ubo[:16].reshape(4, 4)
        columns[0, 0] = -1
        columns[1, 1] = -1
        columns[2, 2] = -1
        columns[2, 3] = -1
        columns[3, 3] = 999  # tfrag3.vert explicitly overwrites this component
        ubo[36:39] = [10, 20, 30]
        clip = module.project([[11, 22, 34]], ubo.tobytes())
        np.testing.assert_array_equal(clip[0], [1, np.float32(2*512/448), 4, 4])
        compact = np.concatenate((ubo[:16], ubo[36:40]))
        np.testing.assert_array_equal(module.project([[11, 22, 34]], compact.tobytes()), clip)

    def test_depth_quantum_and_boundary_refused(self):
        q = 12000000
        d = np.float32(q/module.D24)
        screen = np.array([[0, 0, q/module.D24], [4, 0, q/module.D24], [0, 4, q/module.D24]])
        self.assertEqual(module.compatible(screen, .5, .5, d), (True, False))
        self.assertEqual(module.compatible(screen, 2, 2, d), (False, True))
        screen[:, 2] += 2/module.D24
        self.assertEqual(module.compatible(screen, .5, .5, d), (False, False))

    def test_ambiguity_never_unique(self):
        self.assertEqual(module.classify_candidates([]), ('missing', []))
        self.assertEqual(module.classify_candidates(['a', 'a']), ('unique-geometric', ['a']))
        self.assertEqual(module.classify_candidates(['a', 'b'])[0], 'ambiguous')

    def test_contact_indices_required_and_effective(self):
        self.assertFalse(module.contact_inert('1', None, [0, 1, 2]))
        self.assertFalse(module.contact_inert('1', np.array([0, 9, 0]), [0, 1, 2]))
        self.assertTrue(module.contact_inert('1', np.array([0, 9, 0, 0]), [0, 2, 3]))
        self.assertTrue(module.contact_inert('0', None, [0, 1, 2]))
        self.assertFalse(module.contact_inert('unknown', np.zeros(3), [0, 1, 2]))

    def test_contact_sidecar_hash_and_absence(self):
        with tempfile.TemporaryDirectory(prefix='contact-test-', dir=pathlib.Path(__file__).parent) as tmp:
            root = pathlib.Path(tmp)
            g = dict(geo=0, tree=2, vertices=np.zeros(3))
            self.assertIsNone(module.load_contact_indices(root, g))
            data = np.array([0, 4, 0], dtype='<u4').tobytes()
            (root/'contact-indices-0-2.u32').write_bytes(data)
            self.assertIsNone(module.load_contact_indices(root, g))
            proof = {'ao_hut_contact_indices_0_2_'+key: value for key, value in dict(
                io_error='0', count='3', buffer='99', hash=str(module.fnv(data)),
                path='/device/archive/contact-indices-0-2.u32').items()}
            np.testing.assert_array_equal(module.load_contact_indices(root, g, proof), [0, 4, 0])
            (root/'contact-indices-0-2.u32').write_bytes(bytes(12))
            with self.assertRaises(ValueError):
                module.load_contact_indices(root, g, proof)

    def test_strip_parity_restart_and_degenerate(self):
        indices = [0, 1, 2, 2, 3, 4, module.RESTART, 4, 5, 6, 7]
        pairs = np.column_stack((indices, np.arange(len(indices)))).astype('<u4')
        self.assertEqual(list(module.triangles(pairs, 5)), [(0, 1, 2), (4, 3, 5), (7, 8, 9), (9, 8, 10)])

    def test_gpu_primitive_counter_restart_degenerate_and_new_draw(self):
        data = [0, 1, 2, 3, module.RESTART, 4, 5, 6, 7]
        pairs = np.column_stack((data, np.arange(len(data)))).astype('<u4')
        self.assertEqual(module.primitive_ordinals(pairs, 5), [(0, 1, 2), (2, 1, 3), (5, 6, 7), (7, 6, 8)])
        self.assertEqual(module.primitive_ordinals(pairs[5:], 5), [(0, 1, 2), (2, 1, 3)])
        data = [0, 0, 0, 0, 0, 1, 2, 3]
        pairs = np.column_stack((data, np.arange(len(data)))).astype('<u4')
        table = module.primitive_ordinals(pairs, 5)
        self.assertEqual(len(table), 6)
        self.assertTrue(all(len(set(pairs[list(t), 0])) < 3 for t in table[:4]))
        self.assertEqual(tuple(pairs[list(table[4]), 0]), (0, 1, 2))
        self.assertEqual(tuple(pairs[list(table[5]), 0]), (2, 1, 3))

    def test_clipping_near_plane(self):
        clipped = module.clip_triangle(np.array([[-.5, -.5, -2, 1], [.5, -.5, 0, 1], [0, .5, 0, 1]]))
        self.assertEqual(len(clipped), 2)
        for tri in clipped:
            self.assertTrue(np.all(tri[:, 2] >= -tri[:, 3]))
            self.assertTrue(np.all(tri[:, 2] <= tri[:, 3]))

    def test_archive_to_pixel_refuses_overlapping_primitives_and_wrong_draw(self):
        for copies, visible_id, expected in ((1, 7, 'unique-geometric'), (2, 7, 'ambiguous'), (1, 8, 'missing')):
            with self.subTest(copies=copies, visible_id=visible_id), tempfile.TemporaryDirectory(
                    prefix='attribution-test-', dir=pathlib.Path(__file__).parent) as tmp:
                root = pathlib.Path(tmp)
                geo = bytearray(b'AOHUTF01')
                geo += struct.pack('<IIIIIQQQ', 0x01020304, 0, 0, 0, 0, 3*copies, 1, 8) + b'village1'
                for _ in range(copies):
                    for xyz in ((-1, -1, 1), (1, -1, 1), (0, 1, 1)):
                        geo += struct.pack('<5fI', *xyz, 0, 0, 0)
                geo += struct.pack('<IiQQ', 0, 0, 0, 3*copies)
                geo += np.arange(3*copies, dtype='<u4').tobytes()
                (root/'geometry-tfrag-0-0.bin').write_bytes(geo)
                ubo = np.zeros(56, dtype='<f4')
                ubo[0] = -1
                ubo[5] = -1
                ubo[11] = -1
                uh = module.fnv(ubo.tobytes())
                (root/f'frame-ubo-9-{uh}.bin').write_bytes(ubo.tobytes())
                pairs = np.repeat(np.arange(3*copies, dtype='<u4')[:, None], 2, axis=1).tobytes()
                (root/'draws-indices.bin').write_bytes(pairs)
                (root/'draws.txt').write_text(f'seq=0 family=tfrag pass=color render_frame=9 geo=0 tree=0 '
                    f'draw_begin=0 draw_end=1 count={3*copies} payload_offset=0 payload_hash={module.fnv(pairs)} '
                    f'payload_ok=1 mode=4 ubo_hash={uh} viewport=0,0,1,1 projection_kind=pc_camera '
                    'projection_hash=0 probe_id=7 depth_write=1\n')
                depth = np.array([.5], dtype='<f4').tobytes()
                (root/'scene-depth.f32').write_bytes(depth)
                (root/'scene-depth.meta').write_text(f'status=complete\nrender_frame=9\nbytes=4\nfnv1a64={module.fnv(depth)}\n')
                meta = 'format=ao-hut-color-f32-v1\nstatus=complete\nrender_frame=9\nwidth=1\nheight=1\norigin=lower-left\nalpha=post-discard\n'
                for name, values in (('identity', [1, 1, .5, visible_id]), ('contribution', [-.2, -.1, 0, .7]), ('normal', [0, 1, 0, 1])):
                    data = np.array(values, dtype='<f4').tobytes()
                    filename = f'color-{name}.rgba32f'
                    (root/filename).write_bytes(data)
                    meta += f'stage={filename} bytes=16 fnv1a64={module.fnv(data)}\n'
                meta += 'draw_id=7 state=depthwrite:1\n'
                (root/'color.meta').write_text(meta)
                argv = ['analyze', str(root), '--depth', str(root/'scene-depth.f32'), '--width', '1', '--height', '1',
                        '--frame', '9', '--roi', '0,0,1,1', '--output', str(root/'diagnostic.json')]
                with patch.object(sys, 'argv', argv), contextlib.redirect_stdout(io.StringIO()):
                    module.main()
                result = json.loads((root/'diagnostic.json').read_text())
                self.assertEqual(result['counters'].get('pixels_'+expected), 1)
                self.assertTrue(result['post_alpha_draw_mask_applied'])
                summary_argv = argv[:-2] + ['--summary-only', '--output', str(root/'summary.json')]
                with patch.object(sys, 'argv', summary_argv), contextlib.redirect_stdout(io.StringIO()):
                    module.main()
                summary = json.loads((root/'summary.json').read_text())
                self.assertEqual(summary['observed_draws'][0]['pixels'], 1)
                self.assertEqual(summary['observed_draws'][0]['normal_abs_y_bins'], [0, 0, 1])
                if visible_id == 7:
                    self.assertEqual(summary['observed_draws'][0]['submissions'][0]['world_bounds_units'], [[-1., -1., 1.], [1., 1., 1.]])
                    # v2 ordinal zero selects the first triangle even if another
                    # coplanar primitive appears later in this same submission.
                    v2meta = meta.replace('ao-hut-color-f32-v1', 'ao-hut-color-f32-v2') + 'identity_r=primitive-id-plus-one\n'
                    (root/'color.meta').write_text(v2meta)
                    v2argv = argv[:-1] + [str(root/'gpu.json')]
                    with patch.object(sys, 'argv', v2argv), contextlib.redirect_stdout(io.StringIO()):
                        module.main()
                    gpu = json.loads((root/'gpu.json').read_text())
                    self.assertEqual(gpu['counters']['pixels_gpu-unique'], 1)
                    self.assertFalse(gpu['cpu_depth_used_for_identity'])
                    self.assertEqual(gpu['primitives'][0]['full_source_offsets'], [0, 1, 2])
                    if copies == 2:
                        # Two real submissions reset primitive ordinal to zero.
                        # Same probe ID cannot distinguish their DIFFERENT sources.
                        lines = []
                        for seq in (0, 1):
                            chunk = pairs[seq*24:seq*24+24]
                            lines.append(f'seq={seq} family=tfrag pass=color render_frame=9 geo=0 tree=0 draw_begin=0 draw_end=1 '
                                f'count=3 payload_offset={seq*24} payload_hash={module.fnv(chunk)} payload_ok=1 mode=4 '
                                f'ubo_hash={uh} viewport=0,0,1,1 projection_kind=pc_camera projection_hash=0 probe_id=7 depth_write=1')
                        (root/'draws.txt').write_text('\n'.join(lines))
                        with patch.object(sys, 'argv', argv[:-1]+[str(root/'gpu-ambiguous.json')]), contextlib.redirect_stdout(io.StringIO()):
                            module.main()
                        ambiguous = json.loads((root/'gpu-ambiguous.json').read_text())
                        self.assertEqual(ambiguous['counters']['pixels_gpu-ambiguous'], 1)


if __name__ == '__main__':
    unittest.main(verbosity=2)
