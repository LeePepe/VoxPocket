"""Pocket Wave 原生图标生成与资源接入的无网络回归测试。"""

import copy
import json
from pathlib import Path
import re
import tempfile
import unittest
import xml.etree.ElementTree as ET

import generate_icon as icon


class AppIconTests(unittest.TestCase):
    def setUp(self):
        self.source = icon.load_source()
        self.shape = self.source["geometry"]

    def test_approved_pocket_wave_geometry_and_palettes_are_preserved(self):
        self.assertEqual(self.shape["canvas"], 256)
        self.assertEqual(self.shape["pouch"]["d"], icon.APPROVED_POUCH_PATH)
        self.assertEqual(self.shape["card"]["d"], icon.APPROVED_CARD_PATH)
        self.assertEqual(self.shape["sonic"]["bars"], icon.APPROVED_SONIC_BARS)
        self.assertEqual(self.shape["sonic"]["arc"], icon.APPROVED_SONIC_ARC)
        self.assertEqual(self.shape["sonic"]["radius"], 6)
        self.assertEqual(self.shape["pouch"]["mono_opacity"], 0.62)
        self.assertEqual(self.shape["card"]["mono_opacity"], 0.34)
        self.assertEqual(self.shape["sonic"]["mono_opacity"], 1.0)

    def test_capture_card_is_clipped_along_pocket_v_lip_without_bleeding_below(self):
        card_d = self.shape["card"]["d"]
        pouch_d = self.shape["pouch"]["d"]
        # Capture card bottom lip matches the exact V-lip curve of the pouch
        self.assertIn("L 190 112 L 142 126 C 133 129, 123 129, 114 126 L 66 112", card_d)
        self.assertIn("L 114 126 C 123 129, 133 129, 142 126 L 190 112", pouch_d)
        # All y-coordinates in the capture card path stay above or on the V-lip (y <= 129)
        tokens = re.findall(r"-?\d+(?:\.\d+)?", card_d)
        # Extract (x, y) pairs from M, L, C commands and endpoint of A commands
        self.assertNotIn("220", tokens)
        self.assertNotIn("168", tokens)

    def test_rrect_d_expands_rounded_capsules_into_closed_arc_paths(self):
        d = icon.rrect_d(82, 70, 12, 26, 6)
        self.assertTrue(d.startswith("M 88 70 L 88 70 A 6 6 0 0 1 94 76"))
        self.assertTrue(d.endswith("Z"))
        self.assertEqual(d.count("A 6 6 0 0 1"), 4)

    def test_layers_are_clean_svg_with_expected_gradients_and_mono_opacity_tiers(self):
        ns = {"s": "http://www.w3.org/2000/svg"}
        expected_opacity = {"pouch": "0.62", "card": "0.34", "sonic": None}
        for layer_key, _, _ in icon.LAYER_SPECS:
            for appearance in icon.APPEARANCES:
                colors = self.source["palettes"][layer_key][appearance]
                svg = icon.layer_svg(self.source, layer_key, appearance)
                root = ET.fromstring(svg)
                self.assertEqual(root.attrib["viewBox"], "0 0 256 256")
                self.assertEqual(root.attrib["width"], "1024")
                self.assertEqual(root.attrib["height"], "1024")
                self.assertEqual([s.attrib["stop-color"] for s in root.findall(".//s:stop", ns)], colors)
                path = root.find("s:path", ns)
                self.assertIsNotNone(path)
                if appearance == "mono" and expected_opacity[layer_key] is not None:
                    self.assertEqual(path.attrib.get("fill-opacity"), expected_opacity[layer_key])
                else:
                    self.assertNotIn("fill-opacity", path.attrib)
                for tag in ("image", "filter", "script", "foreignObject", "rect"):
                    self.assertEqual(root.findall(f".//s:{tag}", ns), [], f"{layer_key}/{appearance}")

    def test_generated_layers_are_current_and_deterministic(self):
        expected = icon.expected_assets(self.source)
        self.assertEqual(len(expected), 9)
        self.assertEqual(expected, icon.expected_assets(self.source))
        actual_files = {p.name for p in icon.ASSETS.glob("*.svg")}
        self.assertEqual(actual_files, set(expected))
        for name, text in expected.items():
            self.assertEqual((icon.ASSETS / name).read_text(), text, name)

    def test_invalid_source_is_rejected(self):
        mutations = [
            lambda s: s["geometry"].__setitem__("canvas", 128),
            lambda s: s["geometry"]["pouch"].__setitem__("d", "M 0 0 Z"),
            lambda s: s["geometry"]["card"].__setitem__("d", "M 0 0 Z"),
            lambda s: s["geometry"]["pouch"].__setitem__("mono_opacity", 0.5),
            lambda s: s["geometry"]["sonic"].__setitem__("radius", 10),
            lambda s: s["geometry"]["sonic"].__setitem__("bars", [[82, 70, 12, 300]]),
            lambda s: s["geometry"]["sonic"]["gradient"].__setitem__("x1", "bad"),
        ]
        for index, mutate in enumerate(mutations):
            with self.subTest(case=index), tempfile.TemporaryDirectory() as directory:
                source = copy.deepcopy(self.source)
                mutate(source)
                path = Path(directory) / "source.json"
                path.write_text(json.dumps(source))
                with self.assertRaises(ValueError):
                    icon.load_source(path)

    def test_palette_cannot_inject_svg(self):
        with tempfile.TemporaryDirectory() as directory:
            source = copy.deepcopy(self.source)
            source["palettes"]["pouch"]["light"][0] = "<script>bad</script>"
            path = Path(directory) / "source.json"
            path.write_text(json.dumps(source))
            with self.assertRaises(ValueError):
                icon.load_source(path)

    def test_composer_manifest_references_all_appearance_layers_and_fill_specializations(self):
        manifest = json.loads((icon.ASSETS.parent / "icon.json").read_text())
        self.assertNotIn("features", manifest)  # 不依赖 Composer 2 / macOS 27 效果。
        fill_specs = manifest["fill-specializations"]
        self.assertEqual(
            fill_specs,
            [
                {
                    "value": {
                        "linear-gradient": [
                            "srgb:0.975,0.988,1.000,1.000",
                            "srgb:0.895,0.940,0.995,1.000",
                        ]
                    }
                },
                {"appearance": "dark", "value": "automatic"},
            ],
        )
        self.assertEqual(len(manifest["groups"]), 1)
        group = manifest["groups"][0]
        self.assertEqual(group["name"], "Pocket Wave")
        self.assertTrue(group["specular"])
        self.assertFalse(group["translucency"]["enabled"])
        self.assertEqual(group["shadow"]["kind"], "neutral")
        self.assertLessEqual(group["shadow"]["opacity"], 0.3)
        self.assertEqual([layer["name"] for layer in group["layers"]], ["Sonic Bars", "Pocket Pouch", "Capture Card"])
        names = set()
        for layer in group["layers"]:
            self.assertTrue(layer["glass"])
            specs = layer["image-name-specializations"]
            self.assertEqual([s.get("appearance") for s in specs], [None, "dark", "tinted"])
            for spec in specs:
                self.assertTrue((icon.ASSETS / spec["value"]).is_file())
                names.add(spec["value"])
        self.assertEqual(names, set(icon.expected_assets(self.source)))

    def test_xcode_project_includes_native_icon(self):
        project = (icon.ROOT / "VoxPocket/VoxPocket.xcodeproj/project.pbxproj").read_text()
        self.assertIn("lastKnownFileType = wrapper.icon; path = AppIcon.icon;", project)
        self.assertIn("AppIcon.icon in Resources", project)
        self.assertIn("ASSETCATALOG_COMPILER_APPICON_NAME = AppIcon;", project)
        self.assertIn("Assets.xcassets in Resources", project)  # 暂不删除旧资源。
        self.assertIn("platformFilters = (ios, macos, );", project)
        config = (icon.ROOT / "VoxPocket/project.yml").read_text()
        self.assertIn("path: VoxPocket/AppIcon.icon", config)
        self.assertIn("destinationFilters: [iOS, macOS]", config)


if __name__ == "__main__":
    unittest.main()

