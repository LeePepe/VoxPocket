"""Static pilot contract; no Swift, Git, network, hooks, or dependency acquisition.

Fixtures are in memory. RepositoryManifestTests reads the three real manifests and
must run only after their writer freezes the cohort. Neither class validates CI
acquisition, transitive resolution, compilation, or runtime telemetry delivery.
This narrow current-pilot literal contract also checks Infrastructure's reviewed
async-algorithms minimum; the other layers retain transitive use. It is not a
general Swift evaluator, dependency solver, or CI gate. Changing manifest syntax
requires reviewing this contract too.
Lexical support is limited to ordinary single-line quoted strings with escapes,
line comments and non-nested block comments. Nested comments, Swift raw/multiline
strings and unterminated strings/block comments fail closed at token boundaries;
delimiter-like text inside supported strings/comments is not reinterpreted.
"""

import json
from pathlib import Path
import re
import unittest


URL = "https://github.com/LeePepe/shared-telemetry.git"
REVISION = "eff9c1712cd648ed0717e41183ad8bd7bf39cbea"
IDENTITY = "shared-telemetry"
PRODUCT = "LokiKit"
ASYNC_URL = "https://github.com/apple/swift-async-algorithms"
ASYNC_MINIMUM = "1.1.2"
ASYNC_DECLARATION = f'.package(url: "{ASYNC_URL}", from: "{ASYNC_MINIMUM}")'
TARGETS = {
    "VoxInfrastructure": (
        "TranscriptionKit", "LLMKit", "PlatformAdapters",
        "PrivateTranscriptionBenchmarkTests", "TranscriptionKitTests", "LLMKitTests",
    ),
    "VoxApplication": ("UseCases", "UseCasesTests"),
    "VoxPresentation": ("UIShared", "PlatformUI", "PlatformUITests"),
}
TOKEN = re.compile(
    r'(?P<unsupported>#+"|""")|"(?:\\[^\r\n]|[^"\\\r\n])*"'
    r'|//[^\r\n]*|/\*.*?\*/|(?P<unterminated>/\*|")|[A-Za-z_][\w]*|[^\s]', re.S)


def tokens(source):
    """按词法边界拒绝不支持的形式，不能让注释或字符串内部泄漏调用。"""
    result = []
    for match in TOKEN.finditer(source):
        token = match.group()
        if match.lastgroup in ("unsupported", "unterminated"):
            raise ValueError("unsupported or unterminated Swift string/comment")
        if token.startswith("/*") and "/*" in token[2:]:
            raise ValueError("nested Swift block comments are unsupported")
        if not token.startswith(("//", "/*")):
            result.append(token)
    return tuple(result)


def calls(stream, name):
    """返回指定点调用的参数；字符串里的括号不参与配对。"""
    result = []
    for start in range(len(stream) - 2):
        if stream[start:start + 3] != (".", name, "("):
            continue
        depth = 1
        end = start + 3
        while end < len(stream) and depth:
            depth += (stream[end] == "(") - (stream[end] == ")")
            end += 1
        if depth:
            raise ValueError(f"unclosed .{name} declaration")
        result.append(stream[start + 3:end - 1])
    return result


def literal_arguments(body):
    """仅接受无重复键的字符串实参，拒绝别名、表达式或浮动范围。"""
    values = {}
    position = 0
    while position < len(body):
        field = body[position:position + 3]
        if len(field) != 3 or field[1] != ":" or not field[2].startswith('"'):
            raise ValueError("expected literal named argument")
        key, _, raw = field
        if key in values:
            raise ValueError(f"duplicate argument: {key}")
        values[key] = json.loads(raw)
        position += 3
        if position < len(body):
            if body[position] != ",":
                raise ValueError("expected argument separator")
            position += 1
    return values


def concerns_telemetry(body):
    return any("lokikit" in token.lower() or IDENTITY in token.lower() for token in body)


def check_async_dependency(stream, package):
    """仅约束当前 pilot 的字面声明；不求解传递依赖或 Swift 别名。"""
    dependencies = [body for body in calls(stream, "package")
                    if any("swift-async-algorithms" in token.lower()
                           or "asyncalgorithms" in token.lower() for token in body)]
    expected_count = 1 if package == "VoxInfrastructure" else 0
    if len(dependencies) != expected_count:
        raise ValueError("expected async-algorithms direct dependency only in Infrastructure")
    if dependencies and literal_arguments(dependencies[0]) != {
        "url": ASYNC_URL, "from": ASYNC_MINIMUM,
    }:
        raise ValueError("expected canonical async-algorithms URL and reviewed from: 1.1.2 only")


def check_manifest(source, package):
    expected_targets = TARGETS[package]
    stream = tokens(source)
    check_async_dependency(stream, package)
    dependencies = [body for body in calls(stream, "package") if concerns_telemetry(body)]
    if len(dependencies) != 1:
        raise ValueError("expected exactly one telemetry dependency")
    if literal_arguments(dependencies[0]) != {"url": URL, "revision": REVISION}:
        raise ValueError("expected canonical URL and approved exact revision only")
    expected_product = {"name": PRODUCT, "package": IDENTITY}
    products = [body for body in calls(stream, "product") if concerns_telemetry(body)]
    if len(products) != len(expected_targets):
        raise ValueError("missing or duplicate telemetry product selector")
    if any(literal_arguments(body) != expected_product for body in products):
        raise ValueError("expected LokiKit product with shared-telemetry selector")
    targets = calls(stream, "target") + calls(stream, "testTarget")
    for name in expected_targets:
        matches = [body for body in targets if body[:3] == ("name", ":", f'"{name}"')]
        if len(matches) != 1:
            raise ValueError(f"missing or duplicate target: {name}")
        selected = [body for body in calls(matches[0], "product") if concerns_telemetry(body)]
        if len(selected) != 1 or literal_arguments(selected[0]) != expected_product:
            raise ValueError(f"missing or duplicate telemetry selector in {name}")


def manifest_contract_errors(manifests):
    """只检查完整 manifest cohort；返回空元组不代表 CI acquisition 通过。"""
    errors = []
    if set(manifests) != set(TARGETS):
        errors.append("expected exactly Infrastructure/Application/Presentation cohort")
    for package in TARGETS:
        if package not in manifests:
            continue
        try:
            check_manifest(manifests[package], package)
        except ValueError as error:
            errors.append(f"{package}: {error}")
    return tuple(errors)


def fixture_manifest(package):
    async_dependency = ASYNC_DECLARATION + "," if package == "VoxInfrastructure" else ""
    targets = []
    for name in TARGETS[package]:
        kind = "testTarget" if name.endswith("Tests") else "target"
        targets.append(f'.{kind}(name: "{name}", dependencies: ['
                       f'.product(name: "{PRODUCT}", package: "{IDENTITY}")])')
    return (f'let package = Package(name: "{package}", dependencies: ['
            '.package(path: "../VoxDomain"),'
            f'{async_dependency}'
            f'.package(url: "{URL}", revision: "{REVISION}")],'
            f'targets: [{",".join(targets)}])')


def nonliteral_declaration_sources(declaration):
    """内存反例：嵌套注释、不同井号数的原始字符串、多行及未终止形式。"""
    return (
        f'/* outer /* inner */\n{declaration}\n*/\n',
        f'let note = """\n{declaration}\n"""\n',
        f'/* unterminated\n{declaration}',
        'let note = "unterminated',
        'let note = "dangling\\',
        f'let note = """\n{declaration}',
    ) + tuple(source for hashes in ("#", "##", "###") for source in (
        f'let note = {hashes}"" {declaration} ""{hashes}\n',
        f'let note = {hashes}"""\n{declaration}\n"""{hashes}\n',
        f'let note = {hashes}"unterminated {declaration}',
        f'let note = {hashes}"""\n{declaration}',
    ))


class ManifestFixtureTests(unittest.TestCase):
    def setUp(self):
        self.manifests = {name: fixture_manifest(name) for name in TARGETS}

    def reject_replacement(self, before, after, package="VoxApplication"):
        changed = self.manifests[package].replace(before, after)
        self.assertNotEqual(changed, self.manifests[package], "fixture mutation must apply")
        candidate = dict(self.manifests, **{package: changed})
        self.assertTrue(manifest_contract_errors(candidate))

    def test_canonical_identity_exact_revision_and_all_product_selectors(self):
        self.assertEqual(manifest_contract_errors(self.manifests), ())

    def test_whitespace_comments_and_argument_order_do_not_change_contract(self):
        candidate = {
            name: source.replace(
                f'url: "{URL}", revision: "{REVISION}"',
                f'revision: "{REVISION}",\n /* pin */ url: "{URL}",'
            ) + '\n// .package(path: "../../../LokiKit")\n'
            + '/* harmless #" ##" """ // */\n// harmless /* #" """\n'
            + 'let note = ' + json.dumps('/* /* */ // #" ##" """ https://example.test/ \\')
            for name, source in self.manifests.items()
        }
        self.assertEqual(manifest_contract_errors(candidate), ())

    def test_missing_or_extra_cohort_member_is_rejected(self):
        for package in TARGETS:
            with self.subTest(package=package):
                self.assertTrue(manifest_contract_errors(
                    {key: value for key, value in self.manifests.items() if key != package}))
        self.assertTrue(manifest_contract_errors(dict(self.manifests, Extra="")))

    def test_local_legacy_redirect_and_noncanonical_sources_are_rejected(self):
        requirement = f'url: "{URL}", revision: "{REVISION}"'
        for replacement in (
            'path: "../../../LokiKit"',
            'path: "../../../shared-telemetry"',
            f'url: "https://github.com/LeePepe/LokiKit.git", revision: "{REVISION}"',
            f'url: "https://github.com/other/shared-telemetry.git", revision: "{REVISION}"',
            f'url: "{URL.removesuffix(".git")}", revision: "{REVISION}"',
            f'name: "LokiKit", {requirement}',
        ):
            with self.subTest(replacement=replacement):
                self.reject_replacement(requirement, replacement)

    def test_floating_branch_tag_range_and_missing_revision_are_rejected(self):
        for requirement in ('branch: "main"', 'from: "1.0.0"', 'exact: "1.0.0"',
                            'revision: "main"', 'revision: "v1.0.0"',
                            'revision: "eff9c17"', '"1.0.0"..<"2.0.0"'):
            with self.subTest(requirement=requirement):
                self.reject_replacement(f'revision: "{REVISION}"', requirement)
        self.reject_replacement(f', revision: "{REVISION}"', "")

    def test_one_mismatched_pin_in_each_layer_is_rejected(self):
        for package in TARGETS:
            with self.subTest(package=package):
                self.reject_replacement(REVISION, "0" * 40, package)

    def test_same_but_unapproved_revision_is_rejected(self):
        candidate = {key: source.replace(REVISION, "1" * 40)
                     for key, source in self.manifests.items()}
        self.assertTrue(manifest_contract_errors(candidate))

    def test_duplicate_remote_or_mixed_local_dependency_is_rejected(self):
        declaration = f'.package(url: "{URL}", revision: "{REVISION}")'
        for extra in (declaration, '.package(path: "../../../LokiKit")',
                      '.package(path: "../../../shared-telemetry")'):
            with self.subTest(extra=extra):
                self.reject_replacement(declaration, declaration + "," + extra)

    def test_duplicate_revision_field_is_rejected(self):
        self.reject_replacement(f'revision: "{REVISION}"',
                                f'revision: "{REVISION}", revision: "{REVISION}"')

    def test_exact_pin_cannot_mask_an_additional_floating_requirement(self):
        self.reject_replacement(f'revision: "{REVISION}"',
                                f'revision: "{REVISION}", branch: "main"')

    def test_legacy_missing_mismatched_and_duplicate_products_are_rejected(self):
        declaration = f'.product(name: "{PRODUCT}", package: "{IDENTITY}")'
        for replacement in ('', declaration + "," + declaration,
                            '.product(name: "LokiKit", package: "LokiKit")',
                            '.product(name: "LokiKit", package: "lokikit")',
                            '.product(name: "LokiKit", package: "unrelated")',
                            '.product(name: "Other", package: "shared-telemetry")',
                            '.product(name: "LokiKit")'):
            with self.subTest(replacement=replacement):
                self.reject_replacement(declaration, replacement)

    def test_test_target_requires_its_own_explicit_product(self):
        self.reject_replacement(
            '.testTarget(name: "UseCasesTests", dependencies: ['
            '.product(name: "LokiKit", package: "shared-telemetry")])',
            '.testTarget(name: "UseCasesTests", dependencies: ["UseCases"])')

    def test_global_product_count_cannot_hide_wrong_target_placement(self):
        product = '.product(name: "LokiKit", package: "shared-telemetry")'
        source = self.manifests["VoxApplication"]
        source = source.replace(f'dependencies: [{product}]', 'dependencies: []', 1)
        source = source.replace(f'dependencies: [{product}]',
                                f'dependencies: [{product}, {product}]', 1)
        self.assertTrue(manifest_contract_errors(dict(self.manifests, VoxApplication=source)))

    def test_comments_cannot_supply_a_missing_dependency(self):
        declaration = f'.package(url: "{URL}", revision: "{REVISION}")'
        for replacement in ("", f'/* {declaration} */', f'// {declaration}\n',
                            json.dumps(declaration)):
            with self.subTest(replacement=replacement):
                self.reject_replacement(declaration, replacement)
        original = self.manifests["VoxApplication"]
        for fake in nonliteral_declaration_sources(declaration):
            for source in (fake + original.replace(declaration, ""), original + "\n" + fake):
                with self.subTest(source=source):
                    self.assertTrue(manifest_contract_errors(
                        dict(self.manifests, VoxApplication=source)))

    def test_async_reviewed_minimum_and_transitive_consumers_are_valid(self):
        self.assertIn(ASYNC_DECLARATION, self.manifests["VoxInfrastructure"])
        for package in ("VoxApplication", "VoxPresentation"):
            self.assertNotIn(ASYNC_DECLARATION, self.manifests[package])
        self.assertEqual(manifest_contract_errors(self.manifests), ())

    def test_async_whitespace_comments_and_argument_order_preserve_meaning(self):
        source = self.manifests["VoxInfrastructure"].replace(
            ASYNC_DECLARATION,
            f'.package ( from : "{ASYNC_MINIMUM}", // reviewed minimum\n'
            f'/* source */ url : "{ASYNC_URL}", )')
        self.assertEqual(manifest_contract_errors(
            dict(self.manifests, VoxInfrastructure=source)), ())

    def test_async_old_minimums_are_rejected(self):
        for minimum in ("1.0.0", "1.1.1"):
            with self.subTest(minimum=minimum):
                self.reject_replacement(f'from: "{ASYNC_MINIMUM}"',
                                        f'from: "{minimum}"', "VoxInfrastructure")

    def test_async_missing_declaration_is_rejected(self):
        self.reject_replacement(ASYNC_DECLARATION + ",", "", "VoxInfrastructure")

    def test_async_duplicate_remote_or_mixed_local_declaration_is_rejected(self):
        for extra in (ASYNC_DECLARATION, '.package(path: "../swift-async-algorithms")',
                      '.package(path: "../AsyncAlgorithms")'):
            with self.subTest(extra=extra):
                self.reject_replacement(ASYNC_DECLARATION,
                                        ASYNC_DECLARATION + "," + extra, "VoxInfrastructure")

    def test_async_local_noncanonical_and_named_alias_sources_are_rejected(self):
        for replacement in (
            '.package(path: "../swift-async-algorithms")',
            '.package(path: "../AsyncAlgorithms")',
            f'.package(url: "{ASYNC_URL}.git", from: "{ASYNC_MINIMUM}")',
            f'.package(url: "https://github.com/other/swift-async-algorithms", '
            f'from: "{ASYNC_MINIMUM}")',
            f'.package(name: "AsyncAlgorithms", url: "{ASYNC_URL}", '
            f'from: "{ASYNC_MINIMUM}")',
        ):
            with self.subTest(replacement=replacement):
                self.reject_replacement(ASYNC_DECLARATION, replacement, "VoxInfrastructure")

    def test_async_source_and_requirement_expressions_are_rejected(self):
        for before, after in (
            (f'url: "{ASYNC_URL}"', 'url: asyncURL'),
            (f'from: "{ASYNC_MINIMUM}"', 'from: asyncMinimum'),
            (ASYNC_DECLARATION, 'asyncDependency'),
        ):
            with self.subTest(after=after):
                source = (f'let asyncURL = "{ASYNC_URL}"\n'
                          f'let asyncMinimum = "{ASYNC_MINIMUM}"\n'
                          + self.manifests["VoxInfrastructure"].replace(before, after))
                self.assertTrue(manifest_contract_errors(
                    dict(self.manifests, VoxInfrastructure=source)))

    def test_async_floating_exact_missing_and_conflicting_requirements_are_rejected(self):
        for requirement in (
            'branch: "main"', 'revision: "main"',
            'revision: "2971dd5d9f6e0515664b01044826bcea16e59fac"',
            f'exact: "{ASYNC_MINIMUM}"', '"1.1.2"..<"2.0.0"',
            f'from: "{ASYNC_MINIMUM}", from: "{ASYNC_MINIMUM}"',
            f'from: "{ASYNC_MINIMUM}", from: "1.1.1"',
            f'from: "{ASYNC_MINIMUM}", exact: "{ASYNC_MINIMUM}"',
            f'from: "{ASYNC_MINIMUM}", branch: "main"',
        ):
            with self.subTest(requirement=requirement):
                self.reject_replacement(f'from: "{ASYNC_MINIMUM}"', requirement,
                                        "VoxInfrastructure")
        self.reject_replacement(f', from: "{ASYNC_MINIMUM}"', "", "VoxInfrastructure")

    def test_async_comments_and_strings_cannot_fake_a_valid_declaration(self):
        old = ASYNC_DECLARATION.replace('"1.1.2"', '"1.1.1"')
        for replacement in (
            f'/* {ASYNC_DECLARATION} */', f'// {ASYNC_DECLARATION}\n',
            json.dumps(ASYNC_DECLARATION),
            old + f' /* {ASYNC_DECLARATION} */',
            old + f' // {ASYNC_DECLARATION}\n',
        ):
            with self.subTest(replacement=replacement):
                self.reject_replacement(ASYNC_DECLARATION, replacement, "VoxInfrastructure")
        original = self.manifests["VoxInfrastructure"]
        for fake in nonliteral_declaration_sources(ASYNC_DECLARATION):
            for source in (fake + original.replace(ASYNC_DECLARATION, ""),
                           original + "\n" + fake):
                with self.subTest(source=source):
                    self.assertTrue(manifest_contract_errors(
                        dict(self.manifests, VoxInfrastructure=source)))

    def test_async_artificial_direct_dependencies_in_other_layers_are_rejected(self):
        for package in ("VoxApplication", "VoxPresentation"):
            for declaration in (ASYNC_DECLARATION,
                                '.package(path: "../swift-async-algorithms")'):
                with self.subTest(package=package, declaration=declaration):
                    self.reject_replacement('.package(path: "../VoxDomain")',
                                            declaration, package)


class RepositoryManifestTests(unittest.TestCase):
    """独立执行入口：仅在三份 manifest 冻结后读取；不读取或认可工作流。"""

    def test_frozen_repository_manifest_cohort(self):
        root = Path(__file__).resolve().parents[3]
        manifests = {name: (root / "Packages" / name / "Package.swift").read_text()
                     for name in TARGETS}
        self.assertEqual(manifest_contract_errors(manifests), ())


if __name__ == "__main__":
    unittest.main()
