import unittest
from face_material_rules import light_frame_guard, dark_selfie_frame_guard


def rgb(values):
    return tuple(channel / 255 for channel in values)


class FaceMaterialRulesTests(unittest.TestCase):
    def test_observed_green_halo_and_approved_skin_are_editable(self):
        # Actual pixels incorrectly protected by the old absolute-chroma check.
        for value in [(112,157,78),(116,170,87),(102,154,76),(128,179,90),(151,211,106)]:
            with self.subTest(value=value):
                self.assertFalse(light_frame_guard(*rgb(value)))

    def test_light_neutral_and_warm_eyewear_remains_protected(self):
        for value in [(245,245,245),(235,230,170),(215,240,190)]:
            with self.subTest(value=value):
                self.assertTrue(light_frame_guard(*rgb(value)))

    def test_selfie_frame_guard_excludes_black_pupils_and_green_mouth(self):
        self.assertTrue(dark_selfie_frame_guard(*rgb((45,35,30))))
        for value in [(12,12,12),(32,69,42),(112,157,78)]:
            with self.subTest(value=value):
                self.assertFalse(dark_selfie_frame_guard(*rgb(value)))


if __name__ == '__main__':
    unittest.main()
