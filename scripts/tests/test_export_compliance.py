#!/usr/bin/env python3
"""检查源文件或打包后的 Info.plist，防止遗漏 TestFlight 出口合规声明。"""
import plistlib
from pathlib import Path
import sys
import unittest


ROOT = Path(__file__).resolve().parents[2]
PLISTS = [ROOT / "VoxPocket/VoxPocket/Info.plist"]


class ExportComplianceTests(unittest.TestCase):
    def test_declares_only_exempt_encryption_as_boolean(self):
        for path in PLISTS:
            with self.subTest(plist=str(path)), path.open("rb") as file:
                info = plistlib.load(file)
                # 必须是布尔 false；缺失、整数 0 和字符串 "NO" 都不能代替。
                self.assertIs(info.get("ITSAppUsesNonExemptEncryption"), False)

    def test_does_not_supply_an_unissued_compliance_code(self):
        for path in PLISTS:
            with self.subTest(plist=str(path)), path.open("rb") as file:
                self.assertNotIn("ITSEncryptionExportComplianceCode", plistlib.load(file))


if __name__ == "__main__":
    if len(sys.argv) > 1:
        PLISTS = [Path(path) for path in sys.argv[1:]]
    unittest.main(argv=[sys.argv[0]])
