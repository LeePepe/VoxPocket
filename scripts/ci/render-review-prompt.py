#!/usr/bin/env python3
"""渲染两道 review 门共用的 prompt 模板(scripts/ci/review-prompt.md)。

为什么用 python 而不是 shell:模板里含大量反引号(`swift test`、`project.yml`、
`cloudKitDatabase: .none` …)。历史上 prompt 内联在 shell 双引号字符串里,未转义的
反引号被 bash 当成命令替换执行掉,规则文本在运行时**从 prompt 里消失**。
这里做的是纯文本单次替换,模板内容永不被 shell 求值,该类
quoting 事故在结构上不可能再发生 —— 因此模板里的反引号写正常反引号,不需转义。

用法(占位符取值一律走环境变量,避免出现在命令行/被 shell 二次求值):
    CHANGED=... TRUNCATED=... DIFF=... \
        python3 scripts/ci/render-review-prompt.py scripts/ci/review-prompt.md

渲染结果写 stdout。三个占位符缺任意一个环境变量时按空串处理(TRUNCATED 常为空);
替换是单次扫描,注入值里的 {{...}} 字面量不会被二次替换。
模板缺失、或模板里少了任一占位符,视为错误 → 非 0 退出,调用方 fail-closed。

注意校验只针对**模板**:渲染后不再扫 `{{`,否则 PR diff 里任何合法的 mustache /
Jinja 文本都会把门弄红(fail-closed 的误报也是门失效)。
"""

import os
import pathlib
import re
import sys

PLACEHOLDERS = ("CHANGED", "TRUNCATED", "DIFF")


def main() -> int:
    if len(sys.argv) != 2:
        print(f"usage: {sys.argv[0]} <template.md>", file=sys.stderr)
        return 2

    template_path = pathlib.Path(sys.argv[1])
    if not template_path.is_file():
        print(f"render-review-prompt: template not found: {template_path}", file=sys.stderr)
        return 2

    rendered = template_path.read_text(encoding="utf-8")

    missing = [n for n in PLACEHOLDERS if "{{" + n + "}}" not in rendered]
    if missing:
        print(
            "render-review-prompt: template is missing placeholder(s): "
            + ", ".join("{{" + n + "}}" for n in missing),
            file=sys.stderr,
        )
        return 3

    values = {name: os.environ.get(name, "") for name in PLACEHOLDERS}
    # 单次扫描替换,不做链式 str.replace:后者的结果依赖替换顺序 —— 先替入的内容
    # 里若恰好含有后续占位符字面量(例如 PR 新增一个名叫 {{DIFF}} 的文件,进入
    # CHANGED 列表),会被二次替换。一次性 re.sub 回调消除这个隐性顺序依赖。
    rendered = re.sub(
        r"\{\{(" + "|".join(PLACEHOLDERS) + r")\}\}",
        lambda m: values[m.group(1)],
        rendered,
    )

    # Defense-in-depth: if upstream somehow passes surrogate characters
    # (e.g. from surrogateescape os.environ decoding of truncated UTF-8 bytes),
    # encode→decode with 'replace' to eliminate lone surrogates before writing.
    # This prevents UnicodeEncodeError on sys.stdout.write without masking real
    # render failures (template missing, placeholder missing still fail above).
    rendered = rendered.encode("utf-8", "replace").decode("utf-8")

    sys.stdout.write(rendered)
    return 0


if __name__ == "__main__":
    sys.exit(main())
