import copy
import importlib.util
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
SPEC = importlib.util.spec_from_file_location("voxkit_module_map", ROOT / "Packages/VoxKit/scripts/redlines/module-map.py")
MODULE = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(MODULE)


class ModuleMapTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name)
        self.source = self.root / "Sources"
        (self.source / "TranscriptionKit").mkdir(parents=True)
        (self.source / "LLMKit").mkdir()
        (self.source / "TranscriptionKit/Core.swift").write_text("import VoxCore\npublic struct CoreValue {}\n")
        self.data = {"modules": {
            "VoxCore": {"files": ["TranscriptionKit/Core.swift"], "native": [], "depends_on": []},
            "VoxSpeech": {"files": [], "depends_on": ["VoxCore"]}}}

    def testCompleteValidMapPasses(self):
        self.assertEqual(MODULE.validate(self.data, self.source, self.root), 0)

    def testUnmappedFileFails(self):
        (self.source / "LLMKit/Missing.swift").write_text("struct Missing {}")
        with self.assertRaisesRegex(ValueError, "incomplete coverage"):
            MODULE.validate(self.data, self.source, self.root)

    def testDuplicateAndMissingMappingsFail(self):
        duplicate = copy.deepcopy(self.data)
        duplicate["modules"]["VoxSpeech"]["files"] = ["TranscriptionKit/Core.swift"]
        with self.assertRaisesRegex(ValueError, "duplicate mapping"):
            MODULE.validate(duplicate, self.source, self.root)
        self.data["modules"]["VoxCore"]["files"].append("TranscriptionKit/Absent.swift")
        with self.assertRaisesRegex(ValueError, "missing mapped file"):
            MODULE.validate(self.data, self.source, self.root)

    def testCycleFails(self):
        self.data["modules"]["VoxCore"]["depends_on"] = ["VoxSpeech"]
        with self.assertRaisesRegex(ValueError, "cyclic dependency"):
            MODULE.validate(self.data, self.source, self.root)

    def testCoreCannotReferenceSpeechType(self):
        self.data["modules"]["VoxSpeech"]["files"] = ["TranscriptionKit/Speech.swift"]
        (self.source / "TranscriptionKit/Speech.swift").write_text("import VoxCore\npublic struct SpeechValue {}")
        (self.source / "TranscriptionKit/Core.swift").write_text("import VoxCore\npublic struct CoreValue { let speech: SpeechValue }")
        with self.assertRaisesRegex(ValueError, "forbidden module references"):
            MODULE.validate(self.data, self.source, self.root)

    def testSourceAndTestsRequirePreStagedCoreImport(self):
        (self.source / "TranscriptionKit/Core.swift").write_text("public struct CoreValue {}")
        with self.assertRaisesRegex(ValueError, "missing pre-staged import"):
            MODULE.validate(self.data, self.source, self.root)
        (self.source / "TranscriptionKit/Core.swift").write_text("import VoxCore\npublic struct CoreValue {}")
        tests = self.root / "Tests"
        tests.mkdir()
        (tests / "Consumer.swift").write_text("import TranscriptionKit\nlet value: CoreValue? = nil")
        with self.assertRaisesRegex(ValueError, "missing pre-staged import"):
            MODULE.validate(self.data, self.source, self.root)


if __name__ == "__main__":
    unittest.main()
