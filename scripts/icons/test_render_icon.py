"""验证原生导出工具的失败信号与外观覆盖，不调用实际 GUI。"""

from pathlib import Path
import struct
import tempfile
import unittest
from unittest.mock import patch

import render_icon as renderer


class NativeRenderTests(unittest.TestCase):
    def test_six_native_appearances_and_small_sizes_are_covered(self):
        self.assertEqual(renderer.RENDITIONS, (
            "Default", "Dark", "ClearLight", "ClearDark", "TintedLight", "TintedDark"))
        self.assertEqual(renderer.SIZES, (16, 32, 64, 128, 1024))

    def test_png_header_and_dimensions_are_checked(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "preview.png"
            with self.assertRaises(SystemExit):
                renderer.check_png(path, 32)
            path.write_bytes(b"")
            with self.assertRaises(SystemExit):
                renderer.check_png(path, 32)
            header = b"\x89PNG\r\n\x1a\n" + struct.pack(">I", 13) + b"IHDR"
            path.write_bytes(header + struct.pack(">II", 32, 32))
            renderer.check_png(path, 32)
            with self.assertRaises(SystemExit):
                renderer.check_png(path, 64)

    def test_missing_native_tool_is_not_silently_replaced(self):
        with patch.object(renderer.subprocess, "check_output", return_value="/missing/Xcode/Developer"):
            with self.assertRaises(SystemExit):
                renderer.native_tool()

    def test_export_failure_stops_before_reporting_success(self):
        with tempfile.TemporaryDirectory() as directory, patch.object(renderer.subprocess, "run") as run:
            run.return_value.returncode = 1
            run.return_value.stderr = "fixture native error"
            with self.assertRaisesRegex(SystemExit, "Native rendering failed"):
                renderer.export_images(Path("/fixture/ictool"), Path(directory))
            self.assertEqual(run.call_count, 1)

    def test_zero_exit_without_image_is_not_success(self):
        with tempfile.TemporaryDirectory() as directory, patch.object(renderer.subprocess, "run") as run:
            run.return_value.returncode = 0
            with self.assertRaisesRegex(SystemExit, "did not create"):
                renderer.export_images(Path("/fixture/ictool"), Path(directory))

    def test_gallery_references_native_exports(self):
        with tempfile.TemporaryDirectory() as directory:
            output = Path(directory)
            renderer.write_gallery(output)
            html = (output / "index.html").read_text()
            for appearance in renderer.RENDITIONS:
                for size in (16, 32, 64, 1024):
                    self.assertIn(f'{appearance}-{size}.png', html)
            self.assertNotIn("filter: blur", html)
            self.assertNotIn("<script", html)


if __name__ == "__main__":
    unittest.main()
