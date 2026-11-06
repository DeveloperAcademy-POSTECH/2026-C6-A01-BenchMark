"""Regression checks for folds, protected UVs and front/back placement.
Run with Python + numpy or Blender --background --python this-file.
"""
import sys, unittest
from pathlib import Path
sys.path.insert(0, str(Path(__file__).resolve().parent))
import numpy as np
from photo_bake_geometry import bake_map, depth_sides, projection

class PhotoBakeTests(unittest.TestCase):
    def test_steep_fold_is_not_discarded(self):
        # A front-facing volume with an almost sideways fold normal: old dot-normal filter dropped it.
        p=np.array([[0,0,.4],[.001,0,.6],[0,1,.4],[0,0,-.4],[.001,0,-.6],[0,1,-.4]])
        tris=np.array([[0,1,2],[3,4,5]])
        side=depth_sides(p,tris)
        self.assertEqual(side.tolist(),[0,1])
        uv=np.array([[[.05,.05],[.45,.05],[.05,.95]],[[.55,.05],[.95,.05],[.55,.95]]])
        result, stats=bake_map(p,tris,uv,side,[(-.1,.1,-.1,1.1)]*2,size=64)
        self.assertGreater(stats['mappedPixels'],1000)
        self.assertLess(result[40,10,0],32767)
        self.assertGreater(result[40,40,0],32767)
        self.assertLess(result[40,40,0],65535)

    def test_region_crossing_triangle_keeps_inside_pixels(self):
        p=np.array([[0,0,.2],[1,0,.2],[0,1,.2]])
        result,stats=bake_map(p,np.array([[0,1,2]]),np.array([[[0,0],[1,0],[0,1]]]),[0],[(0,.5,0,.5)]*2,size=32)
        self.assertGreater(stats['mappedPixels'],150)
        self.assertEqual(int(result[25,25,0]),65535)

    def test_accessory_with_shared_uv_cannot_receive_photo(self):
        p=np.array([[0,0,.2],[1,0,.2],[0,1,.2]])
        uv=np.array([[[0,0],[1,0],[0,1]]]*2)
        result,stats=bake_map(p,np.array([[0,1,2]]*2),uv,[0,0],[(0,1,0,1)]*2,size=32,excluded=[False,True])
        self.assertEqual(stats['mappedPixels'],0)
        self.assertGreater(stats['protectedOverlapPixels'],100)
        self.assertTrue(np.all(result==65535))

    def test_back_is_mirrored_and_editor_origin_is_top_left(self):
        p=np.array([[-.5,1,0],[.5,0,0]])
        front=projection(p,0,(-.5,.5,0,1));back=projection(p,1,(-.5,.5,0,1))
        self.assertLess(front[0,0],front[1,0])
        self.assertGreater(back[0,0],back[1,0])
        self.assertLess(front[0,1],front[1,1])

    def test_subpixel_accessory_protects_bilinear_footprint(self):
        p=np.array([[0,0,.2],[1,0,.2],[0,1,.2],[1,1,.2]])
        tris=np.array([[0,1,2],[1,3,2],[0,1,2]])
        uv=np.array([[[0,0],[1,0],[0,1]],[[1,0],[1,1],[0,1]],
                     [[.495,.1],[.498,.1],[.495,.9]]])
        result,_=bake_map(p,tris,uv,[0,0,0],[(0,1,0,1)]*2,size=32,excluded=[False,False,True])
        self.assertEqual(int(result[16,16,0]),65535)
        self.assertNotEqual(int(result[16,8,0]),65535)

if __name__=='__main__':
    result=unittest.TextTestRunner(verbosity=2).run(unittest.defaultTestLoader.loadTestsFromTestCase(PhotoBakeTests))
    if not result.wasSuccessful(): raise SystemExit(1)
