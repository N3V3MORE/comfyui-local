import sys
import unittest
from pathlib import Path


PROJECT_ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(PROJECT_ROOT / "custom_nodes"))


class StudioPresetTests(unittest.TestCase):
    def setUp(self) -> None:
        from comfyui_local_studio import presets

        self.presets = presets

    def test_resolution_presets_are_exact(self) -> None:
        expected = {
            "Square 1:1": (1024, 1024),
            "Portrait 4:5": (896, 1152),
            "Photo Portrait 2:3": (832, 1216),
            "Tall 9:16": (768, 1344),
            "Landscape 5:4": (1152, 896),
            "Photo Landscape 3:2": (1216, 832),
            "Wide 16:9": (1344, 768),
        }

        self.assertEqual(expected, self.presets.RESOLUTION_PRESETS)

    def test_photo_style_composes_positive_and_negative_prompts(self) -> None:
        positive, negative = self.presets.compose_style(
            family="photo",
            style="Cinematic",
            positive="portrait in London",
            negative="watermark",
        )

        self.assertIn("portrait in London", positive)
        self.assertIn("cinematic", positive.lower())
        self.assertIn("watermark", negative)

    def test_none_style_leaves_prompts_unchanged(self) -> None:
        self.assertEqual(
            ("subject", "artifact"),
            self.presets.compose_style("anime", "None", "subject", "artifact"),
        )

    def test_invalid_style_family_pair_is_rejected(self) -> None:
        with self.assertRaisesRegex(ValueError, "not valid for family"):
            self.presets.compose_style("anime", "Cinematic", "subject", "")

    def test_lora_path_must_match_family_directory(self) -> None:
        self.assertEqual(
            "sdxl/portrait.safetensors",
            self.presets.validate_lora_path("sdxl", "sdxl/portrait.safetensors"),
        )
        self.assertIsNone(self.presets.validate_lora_path("flux2", "None"))
        with self.assertRaisesRegex(ValueError, "SDXL LoRA"):
            self.presets.validate_lora_path("sdxl", "flux2/detail.safetensors")

    def test_control_mode_maps_to_switch_and_union_type(self) -> None:
        self.assertEqual((1, "canny/lineart/anime_lineart/mlsd"), self.presets.get_control_preset("Canny"))
        self.assertEqual((2, "depth"), self.presets.get_control_preset("Depth"))
        self.assertEqual((3, "openpose"), self.presets.get_control_preset("Pose"))


if __name__ == "__main__":
    suite = unittest.defaultTestLoader.loadTestsFromTestCase(StudioPresetTests)
    result = unittest.TextTestRunner(stream=sys.stdout).run(suite)
    raise SystemExit(0 if result.wasSuccessful() else 1)
