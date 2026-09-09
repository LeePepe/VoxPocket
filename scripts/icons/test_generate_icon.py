"""图标生成与资源接入的无网络回归测试。"""

import copy
import json
import math
from pathlib import Path
import tempfile
import unittest
import xml.etree.ElementTree as ET

import generate_icon as icon


class AppIconTests(unittest.TestCase):
    def setUp(self):
        self.source = icon.load_source()
        self.shape = self.source["geometry"]

    def test_approved_geometry_is_preserved_and_stroke_is_bolder(self):
        self.assertEqual(self.shape["rx"], 56)
        self.assertEqual(self.shape["ry"], 99.12)
        self.assertEqual(self.shape["angles"], [-60, 0, 60])
        self.assertEqual(self.shape["stroke"], 7)

    def test_offset_uses_normal_distance_not_scaled_ellipse(self):
        distance = self.shape["stroke"] / 2
        for t in (0, 0.3, 0.9, math.pi / 2, math.pi, 5.4):
            point, _ = icon.offset_sample(self.shape, t, distance)
            centerline = (128 + 56 * math.cos(t), 128 + 99.12 * math.sin(t))
            self.assertAlmostEqual(math.dist(point, centerline), distance, places=9)
            tangent = (-56 * math.sin(t), 99.12 * math.cos(t))
            self.assertAlmostEqual(sum((point[i] - centerline[i]) * tangent[i]
                                       for i in (0, 1)), 0, places=8)

    def test_curve_derivative_matches_numeric_derivative(self):
        epsilon = 1e-6
        for t in (0, 0.4, 1.8, 3.1, 5.7):
            for distance in (-3.5, 3.5):
                _, tangent = icon.offset_sample(self.shape, t, distance)
                before, _ = icon.offset_sample(self.shape, t - epsilon, distance)
                after, _ = icon.offset_sample(self.shape, t + epsilon, distance)
                for i in (0, 1):
                    self.assertAlmostEqual(tangent[i], (after[i] - before[i]) /
                                           (2 * epsilon), places=6)

    def test_contour_closes_with_matching_tangent(self):
        for distance in (-3.5, 3.5):
            first, df = icon.offset_sample(self.shape, 0, distance)
            last, dl = icon.offset_sample(self.shape, 2 * math.pi, distance)
            for i in (0, 1):
                self.assertAlmostEqual(first[i], last[i], places=9)
                self.assertAlmostEqual(df[i], dl[i], places=9)

    def test_layers_are_expanded_hollow_svg_with_original_palettes(self):
        ns = {"s": "http://www.w3.org/2000/svg"}
        for appearance, colors in self.source["palettes"].items():
            svg = icon.ring_svg(self.shape, colors, -60)
            root = ET.fromstring(svg)
            self.assertEqual(root.attrib["viewBox"], "0 0 256 256")
            self.assertEqual(root.attrib["width"], "1024")
            self.assertEqual([s.attrib["stop-color"] for s in root.findall(".//s:stop", ns)], colors)
            path = root.find("s:path", ns)
            self.assertEqual(path.attrib["fill-rule"], "evenodd")
            self.assertEqual(path.attrib["d"].count("M"), 2)
            self.assertEqual(path.attrib["d"].count("Z"), 2)
            self.assertEqual(path.attrib["d"].count("C"), 128)
            self.assertNotIn("L", path.attrib["d"])
            for tag in ("image", "filter", "script", "foreignObject", "rect"):
                self.assertEqual(root.findall(f".//s:{tag}", ns), [], appearance)

    def test_generated_layers_are_current_and_deterministic(self):
        expected = icon.expected_assets(self.source)
        self.assertEqual(len(expected), 9)
        self.assertEqual(expected, icon.expected_assets(self.source))
        for name, text in expected.items():
            self.assertEqual((icon.ASSETS / name).read_text(), text, name)

    def test_invalid_source_is_rejected(self):
        cases = [("stroke", 200), ("rx", -1), ("ry", float("nan")),
                 ("rx", 200), ("center", 120), ("angles", [0]), ("samples", 8)]
        for key, value in cases:
            with self.subTest(key=key, value=value), tempfile.TemporaryDirectory() as directory:
                source = copy.deepcopy(self.source)
                source["geometry"][key] = value
                path = Path(directory) / "source.json"
                path.write_text(json.dumps(source))
                with self.assertRaises(ValueError):
                    icon.load_source(path)

    def test_palette_cannot_inject_svg(self):
        with tempfile.TemporaryDirectory() as directory:
            source = copy.deepcopy(self.source)
            source["palettes"]["light"][0] = '<script>bad</script>'
            path = Path(directory) / "source.json"
            path.write_text(json.dumps(source))
            with self.assertRaises(ValueError):
                icon.load_source(path)

    def test_composer_manifest_references_all_appearance_layers(self):
        manifest = json.loads((icon.ASSETS.parent / "icon.json").read_text())
        self.assertNotIn("features", manifest)  # 不依赖 Composer 2 / macOS 27 效果。
        self.assertEqual(manifest["fill"], "automatic")
        self.assertEqual(len(manifest["groups"]), 1)
        group = manifest["groups"][0]
        self.assertTrue(group["specular"])
        self.assertFalse(group["translucency"]["enabled"])
        self.assertEqual(group["shadow"]["kind"], "neutral")
        self.assertLessEqual(group["shadow"]["opacity"], 0.3)
        self.assertEqual(len(group["layers"]), 3)
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
