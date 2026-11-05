"""Regression tests for the layer contract frontmatter gate."""

from pathlib import Path
import importlib.util
import shutil
import tempfile
import unittest


REPO = Path(__file__).resolve().parents[3]
CHECK_PATH = REPO / "scripts" / "gates" / "check_frontmatter.py"
SPEC = importlib.util.spec_from_file_location("check_frontmatter", CHECK_PATH)
check_frontmatter = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(check_frontmatter)


class CheckFrontmatterTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory(prefix="voxpocket frontmatter tests ")
        self.addCleanup(self.temporary.cleanup)
        self.repo = Path(self.temporary.name) / "fixture"
        shutil.copytree(REPO / "Packages", self.repo / "Packages")
        (self.repo / "docs" / "architecture").mkdir(parents=True)
        shutil.copy2(REPO / "docs" / "architecture" / "tech-context.md",
                     self.repo / "docs" / "architecture" / "tech-context.md")

    def run_check(self):
        return check_frontmatter.main(repo_root=str(self.repo))

    def read(self, relative):
        return (self.repo / relative).read_text(encoding="utf-8")

    def write(self, relative, content):
        (self.repo / relative).write_text(content, encoding="utf-8")

    def test_current_repository_passes(self):
        self.assertEqual(check_frontmatter.main(), 0)

    def test_package_local_dependency_missing_from_depends_on_fails(self):
        path = self.repo / "Packages" / "VoxApplication" / "tech-context.md"
        content = path.read_text(encoding="utf-8").replace(
            "depends_on: [VoxDomain, VoxInfrastructure, VoxKit]",
            "depends_on: [VoxDomain, VoxInfrastructure]",
        )
        self.write("Packages/VoxApplication/tech-context.md", content)
        manifest = self.repo / "Packages" / "VoxApplication" / "Package.swift"
        self.write("Packages/VoxApplication/Package.swift",
                   manifest.read_text(encoding="utf-8").replace(
                       '        .package(path: "../VoxInfrastructure"),',
                       '        .package(path: "../VoxInfrastructure"),\n'
                       '        .package(path: "../VoxKit"),',
                   ))
        self.assertNotEqual(self.run_check(), 0)

    def test_phantom_layer_in_depends_on_fails(self):
        path = self.repo / "Packages" / "VoxInfrastructure" / "tech-context.md"
        content = path.read_text(encoding="utf-8").replace(
            "depends_on: [VoxDomain, VoxKit]",
            "depends_on: [VoxDomain, VoxKit, VoxGhost]",
        )
        self.write("Packages/VoxInfrastructure/tech-context.md", content)
        self.assertNotEqual(self.run_check(), 0)

    def test_non_voxkit_staged_dependency_fails_but_voxkit_passes(self):
        self.assertEqual(self.run_check(), 0)
        path = self.repo / "Packages" / "VoxInfrastructure" / "tech-context.md"
        content = path.read_text(encoding="utf-8").replace(
            "depends_on: [VoxDomain, VoxKit]",
            "depends_on: [VoxDomain, VoxKit, VoxApplication]",
        )
        root = self.repo / "docs" / "architecture" / "tech-context.md"
        root_content = root.read_text(encoding="utf-8").replace(
            "VoxDomain, VoxKit, LokiKit(ext)",
            "VoxDomain, VoxKit, VoxApplication, LokiKit(ext)",
        )
        self.write("Packages/VoxInfrastructure/tech-context.md", content)
        self.write("docs/architecture/tech-context.md", root_content)
        self.assertNotEqual(self.run_check(), 0)

    def test_leaf_depends_on_mismatch_with_root_table_fails(self):
        root = self.repo / "docs" / "architecture" / "tech-context.md"
        content = root.read_text(encoding="utf-8").replace(
            "VoxDomain, VoxInfrastructure, VoxKit, LokiKit(ext)",
            "VoxDomain, VoxInfrastructure, LokiKit(ext)",
        )
        self.write("docs/architecture/tech-context.md", content)
        self.assertNotEqual(self.run_check(), 0)


if __name__ == "__main__":
    unittest.main()
