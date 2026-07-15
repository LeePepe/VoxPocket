#!/usr/bin/env python3
"""
check_frontmatter.py — 分层 tech-context frontmatter 防腐校验(与语言无关的解析器)。

校验每个 Packages/*/tech-context.md 的 frontmatter 与代码一致:
  1. layer 名 == 目录名
  2. depends_on 与 Package.swift 的本地 path 依赖【双向一致】(LokiKit 等仓库外依赖除外)
  3. depended_by 与 depends_on 全局【互为镜像】(可选字段,填了就校验)
  4. roles 的角色名都在顶层 canonical_roles 词表内;映射的目录/类型在本层真实存在
  5. test 命令引用的 --package-path 路径存在

腐烂即以退出码 1 失败。无副作用、秒级,符合 pre-push 快门禁约束。
"""
import os
import re
import sys

REPO = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
PACKAGES = os.path.join(REPO, "Packages")
TOP_TECH_CONTEXT = os.path.join(REPO, "docs", "architecture", "tech-context.md")


def read_frontmatter(path):
    """返回 (fields_dict, roles_dict) 或 None(无 frontmatter)。"""
    with open(path, encoding="utf-8") as f:
        text = f.read()
    m = re.match(r"^---\n(.*?)\n---\n", text, re.S)
    if not m:
        return None
    fm = m.group(1)
    fields = {}
    roles = {}
    lines = fm.split("\n")
    i = 0
    while i < len(lines):
        line = lines[i]
        # roles: 嵌套块
        if re.match(r"^roles:\s*$", line):
            i += 1
            while i < len(lines) and re.match(r"^\s+\S", lines[i]):
                rm = re.match(r"^\s+([A-Za-z]+):\s*\[(.*?)\]\s*$", lines[i])
                if rm:
                    role = rm.group(1)
                    items = [x.strip() for x in rm.group(2).split(",") if x.strip()]
                    roles[role] = items
                i += 1
            continue
        # key: [list]
        lm = re.match(r"^([A-Za-z_]+):\s*\[(.*?)\]\s*$", line)
        if lm:
            fields[lm.group(1)] = [x.strip() for x in lm.group(2).split(",") if x.strip()]
            i += 1
            continue
        # key: scalar
        sm = re.match(r"^([A-Za-z_]+):\s*(.+)$", line)
        if sm:
            fields[sm.group(1)] = sm.group(2).strip()
        i += 1
    return fields, roles


def read_canonical_roles():
    if not os.path.isfile(TOP_TECH_CONTEXT):
        return None
    parsed = read_frontmatter(TOP_TECH_CONTEXT)
    if not parsed:
        return None
    fields, _ = parsed
    val = fields.get("canonical_roles", [])
    return val if isinstance(val, list) else []


def local_deps_from_package(pkg_dir):
    """从 Package.swift 提取【仓库内】的 path 依赖名(排除 LokiKit 等外部包)。"""
    pkg_swift = os.path.join(pkg_dir, "Package.swift")
    if not os.path.isfile(pkg_swift):
        return set()
    with open(pkg_swift, encoding="utf-8") as f:
        content = f.read()
    deps = set()
    for rel in re.findall(r'\.package\(path:\s*"([^"]+)"', content):
        resolved = os.path.realpath(os.path.join(pkg_dir, rel))
        # 只算解析后仍落在本仓库 Packages/ 内的依赖
        if resolved.startswith(PACKAGES + os.sep):
            deps.add(os.path.basename(resolved))
    return deps


def source_names(pkg_dir):
    """收集本包 Sources/ 下所有目录 basename 与文件 stem,用于 roles 存在性校验。"""
    dirs, stems = set(), set()
    src = os.path.join(pkg_dir, "Sources")
    for root, dnames, fnames in os.walk(src):
        for d in dnames:
            dirs.add(d)
        for fn in fnames:
            if fn.endswith(".swift"):
                stems.add(fn[:-6])
    return dirs, stems


def main():
    canonical = read_canonical_roles()
    if canonical is None:
        print(f"❌ 顶层 canonical_roles 未找到({TOP_TECH_CONTEXT})")
        return 1

    fail = 0
    layers = {}  # name -> fields
    tc_files = sorted(
        os.path.join(PACKAGES, d, "tech-context.md")
        for d in os.listdir(PACKAGES)
        if os.path.isfile(os.path.join(PACKAGES, d, "tech-context.md"))
    )
    if not tc_files:
        print("❌ 未发现任何 Packages/*/tech-context.md")
        return 1

    for tc in tc_files:
        pkg_dir = os.path.dirname(tc)
        pkg = os.path.basename(pkg_dir)
        parsed = read_frontmatter(tc)
        if parsed is None:
            print(f"❌ {tc}: 缺 frontmatter")
            fail = 1
            continue
        fields, roles = parsed
        layers[pkg] = fields

        # ① layer 名 == 目录名
        if fields.get("layer") != pkg:
            print(f"❌ {tc}: layer='{fields.get('layer')}' ≠ 目录 '{pkg}'")
            fail = 1

        # ② depends_on ⇄ Package.swift 本地依赖 双向一致
        declared = local_deps_from_package(pkg_dir)
        depends_on = set(fields.get("depends_on", []) or [])
        for d in depends_on:
            if not os.path.isdir(os.path.join(PACKAGES, d)):
                print(f"❌ {tc}: depends_on '{d}' 是幽灵层(Packages/ 下无此目录)")
                fail = 1
            elif d not in declared:
                print(f"❌ {tc}: depends_on 有 '{d}' 但 Package.swift 未声明该本地依赖")
                fail = 1
        for d in declared - depends_on:
            print(f"❌ {tc}: Package.swift 依赖本地 '{d}' 但 depends_on 漏写")
            fail = 1

        # ④ roles: 角色名在 canonical_roles 内 + 目录/类型在本层存在
        dirs, stems = source_names(pkg_dir)
        for role, items in roles.items():
            if role not in canonical:
                print(f"❌ {tc}: roles 角色 '{role}' 不在 canonical_roles {canonical} 内")
                fail = 1
            for it in items:
                if it not in dirs and it not in stems:
                    print(f"❌ {tc}: roles['{role}'] 的 '{it}' 在本层 Sources/ 下不存在(非目录也非类型)")
                    fail = 1

        # ⑤ test --package-path 存在
        test_cmd = fields.get("test", "")
        pm = re.search(r"--package-path\s+(\S+)", test_cmd if isinstance(test_cmd, str) else "")
        if pm:
            tp = os.path.join(REPO, pm.group(1))
            if not os.path.isdir(tp):
                print(f"❌ {tc}: test 路径 '{pm.group(1)}' 不存在")
                fail = 1

    # ③ depended_by ⇄ depends_on 全局镜像(可选字段)
    for name, fields in layers.items():
        for db in set(fields.get("depended_by", []) or []):
            other = layers.get(db)
            if other is None:
                print(f"❌ {name}: depended_by '{db}' 不是已知 layer")
                fail = 1
            elif name not in set(other.get("depends_on", []) or []):
                print(f"❌ 镜像不一致: {name}.depended_by 含 '{db}',但 {db}.depends_on 不含 '{name}'")
                fail = 1
        for dep in set(fields.get("depends_on", []) or []):
            other = layers.get(dep)
            if other is not None and "depended_by" in other:
                if name not in set(other.get("depended_by", []) or []):
                    print(f"❌ 镜像不一致: {name}.depends_on 含 '{dep}',但 {dep}.depended_by 不含 '{name}'")
                    fail = 1

    if fail == 0:
        print(f"✅ frontmatter 一致({len(tc_files)} 层校验通过)")
    else:
        print("架构变了?更新对应 tech-context frontmatter 后重试。")
    return fail


if __name__ == "__main__":
    sys.exit(main())
