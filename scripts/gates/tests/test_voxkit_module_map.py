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
        (self.source / "VoxCore").mkdir(parents=True)
        (self.source / "VoxSpeech").mkdir()
        (self.source / "VoxCore/Core.swift").write_text("public struct CoreValue {}\n")
        self.data = {"modules": {
            "VoxCore": {"files": ["VoxCore/Core.swift"], "depends_on": []},
            "VoxSpeech": {"files": [], "depends_on": ["VoxCore"]}}}

    def testCompleteValidMapPasses(self):
        self.assertEqual(MODULE.validate(self.data, self.source, self.root), 0)

    def testUnmappedFileFails(self):
        (self.source / "VoxSpeech/Missing.swift").write_text("struct Missing {}")
        with self.assertRaisesRegex(ValueError, "incomplete coverage"):
            MODULE.validate(self.data, self.source, self.root)

    def testDuplicateAndMissingMappingsFail(self):
        duplicate = copy.deepcopy(self.data)
        duplicate["modules"]["VoxSpeech"]["files"] = ["VoxCore/Core.swift"]
        with self.assertRaisesRegex(ValueError, "duplicate mapping"):
            MODULE.validate(duplicate, self.source, self.root)
        self.data["modules"]["VoxCore"]["files"].append("VoxCore/Absent.swift")
        with self.assertRaisesRegex(ValueError, "missing mapped file"):
            MODULE.validate(self.data, self.source, self.root)

    def testCycleFails(self):
        self.data["modules"]["VoxCore"]["depends_on"] = ["VoxSpeech"]
        with self.assertRaisesRegex(ValueError, "cyclic dependency"):
            MODULE.validate(self.data, self.source, self.root)

    def testHostBridgeReferencesNeedExplicitImport(self):
        bridge = self.root / "Packages/VoxInfrastructure/Sources/VoxKitBridge"
        bridge.mkdir(parents=True)
        (bridge / "Coordinator.swift").write_text("public protocol TranscriptionCoordinator {}")
        application = self.root / "Packages/VoxApplication/Sources"
        application.mkdir(parents=True)
        consumer = application / "Consumer.swift"
        consumer.write_text("let source: (any TranscriptionCoordinator)? = nil")
        with self.assertRaisesRegex(ValueError, "missing explicit import VoxKitBridge"):
            MODULE.validate(self.data, self.source, self.root)
        consumer.write_text("import VoxKitBridge\nlet source: (any TranscriptionCoordinator)? = nil")
        self.assertEqual(MODULE.validate(self.data, self.source, self.root), 0)

    def testCoreCannotReferenceSpeechType(self):
        self.data["modules"]["VoxSpeech"]["files"] = ["VoxSpeech/Speech.swift"]
        (self.source / "VoxSpeech/Speech.swift").write_text("import VoxCore\npublic struct SpeechValue {}")
        (self.source / "VoxCore/Core.swift").write_text("public struct CoreValue { let speech: SpeechValue }")
        with self.assertRaisesRegex(ValueError, "forbidden module references"):
            MODULE.validate(self.data, self.source, self.root)

    def testSourceAndTestsRequirePreStagedCoreImport(self):
        self.data["modules"]["VoxSpeech"]["files"] = ["VoxSpeech/Speech.swift"]
        (self.source / "VoxSpeech/Speech.swift").write_text("public struct SpeechValue { let core: CoreValue }")
        with self.assertRaisesRegex(ValueError, "missing pre-staged import"):
            MODULE.validate(self.data, self.source, self.root)
        (self.source / "VoxSpeech/Speech.swift").write_text("import VoxCore\npublic struct SpeechValue { let core: CoreValue }")
        tests = self.root / "Tests"
        tests.mkdir()
        (tests / "Consumer.swift").write_text("import VoxSpeech\nlet value: CoreValue? = nil")
        with self.assertRaisesRegex(ValueError, "missing pre-staged import"):
            MODULE.validate(self.data, self.source, self.root)


if __name__ == "__main__":
    unittest.main()
