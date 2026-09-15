#!/usr/bin/env python3
"""DIRECTIVES v775512c234 -- bridge integration only, native criteria unchanged."""
import importlib.util
import pathlib
import unittest

import numpy as np

notes = pathlib.Path(__file__).resolve().parent
spec = importlib.util.spec_from_file_location('profile_bridge', notes/'attempt10-profile.py')
profile = importlib.util.module_from_spec(spec)
spec.loader.exec_module(profile)


class NativeProfileTest(unittest.TestCase):
    def test_native_bridge_band_censored_and_unqualified(self):
        ao = np.full((3,20),180,dtype='u1')
        depth = np.full(ao.shape,.5,dtype='<f4')
        surface = np.ones_like(ao); surface[:,10:] = 2
        identity = surface.astype('<u8')
        right = np.zeros_like(ao); right[:,9] = 1
        down = np.zeros_like(ao)
        ao[:,9:11] = 220
        r = profile.native_measure(notes/'attempt10-profile-native', notes, ao, depth, surface, right, down, identity)
        self.assertEqual((r['native_exit'],r['contacts'],r['band_pixels'],r['max_width']), (0,3,6,1))
        ao[:]=180
        r = profile.native_measure(notes/'attempt10-profile-native', notes, ao, depth, surface, right, down, identity)
        self.assertEqual((r['native_exit'],r['contacts'],r['censored_sides'],r['measured']), (3,3,6,False))
        right[:]=0
        r = profile.native_measure(notes/'attempt10-profile-native', notes, ao, depth, surface, right, down, identity)
        self.assertEqual((r['contacts'],r['adjacent_wall_roof_edges'],r['measured']), (0,3,False))

    def test_physical_intersection_and_pixel_segment(self):
        a = np.array([[-2,-2,0],[2,-2,0],[0,2,0]],dtype=float)
        b = np.array([[0,-1,-1],[0,-1,1],[0,1,0]],dtype=float)
        segment = profile.physical_intersection(a,b)
        self.assertEqual(np.linalg.norm(segment[1]-segment[0]),2)
        self.assertTrue(profile.crosses_segment(np.array([-.5,0]),np.array([.5,0]),segment[0,:2],segment[1,:2]))
        self.assertFalse(profile.crosses_segment(np.array([-.5,2]),np.array([.5,2]),segment[0,:2],segment[1,:2]))
        with self.assertRaises(ValueError):
            profile.physical_intersection(a,b+np.array([10,0,0]))


if __name__ == '__main__':
    unittest.main(verbosity=2)
