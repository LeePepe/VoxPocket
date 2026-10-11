#!/usr/bin/env ruby
# frozen_string_literal: true

# 独立、只读的 acquisition 合约；不接入 CI/hooks，不执行 workflow 中的命令。
# 授权后可用 /usr/bin/ruby --disable-gems scripts/tests/test_ci_telemetry_acquisition.rb。
# 以下完整 YAML 是编辑前冻结的结构源；哈希先验来自 authoring 输入，不从候选反推。
require 'psych'
require 'digest/sha2'

BASE_SHA = '5d2ab2fafc453017f909dc289b81aead73c83918'
PIN = 'eff9c1712cd648ed0717e41183ad8bd7bf39cbea'
REPOSITORY = 'LeePepe/shared-telemetry'
CI_PATH = '.github/workflows/ci.yml'
RELEASE_PATH = '.github/workflows/testflight.yml'
LOGGING_PATH = 'scripts/tests/test_app_logging.py'
BASELINE_HASHES = {
  CI_PATH => '1e8c5981c39bc2536f8cc5031c301bf890a7a5d26406d7b843a79210e5adeaf1',
  RELEASE_PATH => 'b17174108ce56226b0936377a5561a1ba048312a76168fb91ad849b2592ff504'
}.freeze
LOGGING_HASH = '8a9564c2e4159f8b4641ba91bcd817ffe7e13e580c7ab6ba542d33c66db6f24b'
MANIFEST_HASHES = {
  'Packages/VoxInfrastructure/Package.swift' =>
    '38d81441f007cd39e641a7dfd0942622644b1141d3ad89c7def828fe1b0ce8bf',
  'Packages/VoxApplication/Package.swift' =>
    '19c9557207ac75ebe2042ba495c307d5ba5b98731a96b22cf4773881426f4ac0',
  'Packages/VoxPresentation/Package.swift' =>
    '3d50c5232d0a7b1ed4961f32e16af210b6914b327f70a362a87d1c8df814e41e'
}.freeze

PRE_CI = <<'CI_BASELINE'.freeze
name: CI

# 服务端强制门禁。两个触发：
#   - pull_request → main：合并前拦 PR。spm/app/policy 在 ruleset 里设为 required
#     status check，红了挡合。
#   - push → main：合并后安全网（main 只经 PR 落地，这里再验一次合并结果）。
# check 名（spm 的 "SPM <pkg>"、"App target"、"Lint & policy"）被 ruleset 引用，
# 改名需同步 ruleset。
on:
  push:
    branches: [main]
  pull_request:
    branches: [main]
  workflow_dispatch:

concurrency:
  group: ci-${{ github.ref }}
  cancel-in-progress: true

jobs:
  # ---- Job A (REQUIRED)：5 个 SPM 包 —— swift build + test，秒级，无模拟器 ----
  # 每个包一个独立 check（SPM <pkg>），便于 ruleset 精确 required + 并行。
  spm:
    name: SPM ${{ matrix.package }}
    runs-on: macos-26
    strategy:
      fail-fast: false
      matrix:
        package: [VoxDomain, VoxInfrastructure, VoxApplication, VoxPresentation, VoxUITesting]
    steps:
      - name: Checkout VoxPocket
        uses: actions/checkout@v4
        with:
          path: repo
      # LokiKit 是外部本地依赖（../../../LokiKit）。从 Packages/<pkg>/ 解析 →
      # 落在 $GITHUB_WORKSPACE/LokiKit。VoxInfrastructure/Application/Presentation 需要。
      - name: Checkout LokiKit (external local dependency)
        uses: actions/checkout@v4
        with:
          repository: LeePepe/LokiKit
          path: LokiKit
      - name: Select latest Xcode
        run: |
          latest="$(ls -d /Applications/Xcode_*.app 2>/dev/null | sort -V | tail -1)"
          if [ -n "$latest" ]; then sudo xcode-select -s "$latest"; fi
          swift --version
      - name: swift build
        working-directory: repo/Packages/${{ matrix.package }}
        run: swift build
      - name: swift test
        working-directory: repo/Packages/${{ matrix.package }}
        run: swift test

  # ---- Job B (REQUIRED)：app target —— xcodegen + xcodebuild build（禁签名）----
  # 重验证（app 全量 xcodebuild）唯一强制点，不在本地 pre-push（见 AGENTS.md）。
  app:
    name: App target
    runs-on: macos-26
    steps:
      - name: Checkout VoxPocket
        uses: actions/checkout@v4
        with:
          path: repo
      - name: Checkout LokiKit (external local dependency)
        uses: actions/checkout@v4
        with:
          repository: LeePepe/LokiKit
          path: LokiKit
      # xcodeproj 通过 XCLocalSwiftPackageReference 引用 ../../AppleUITesting。
      - name: Checkout AppleUITesting (external local dependency)
        uses: actions/checkout@v4
        with:
          repository: LeePepe/AppleUITesting
          path: AppleUITesting
      - name: Select latest Xcode
        run: |
          latest="$(ls -d /Applications/Xcode_*.app 2>/dev/null | sort -V | tail -1)"
          if [ -n "$latest" ]; then sudo xcode-select -s "$latest"; fi
          xcodebuild -version
      - name: Install XcodeGen
        run: brew install xcodegen
      - name: Regenerate xcodeproj from project.yml
        working-directory: repo/VoxPocket
        run: xcodegen generate --spec project.yml
      - name: Build app — macOS (no signing)
        working-directory: repo
        run: |
          set -o pipefail
          xcodebuild -project VoxPocket/VoxPocket.xcodeproj -scheme VoxPocket \
            -destination 'platform=macOS' \
            CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO \
            build 2>&1 | tee /tmp/xcodebuild-macos.log
      - name: Startup main-queue interaction regression
        working-directory: repo
        run: |
          python3 scripts/tests/test_app_startup.py
          python3 scripts/tests/test_startup_interaction.py
          python3 scripts/tests/test_menu_bar_launch.py
          python3 scripts/tests/test_realtime_config.py
      # iOS 也验证：VoxPocket 是多平台 target，TestFlight 发 iOS。CI 只验 macOS 曾让
      # iOS 编译债长期潜伏（homeDirectoryForCurrentUser 等）直到发版才暴露。这里守住 iOS。
      - name: Log configuration regression (Debug and Release)
        working-directory: repo
        timeout-minutes: 10
        run: python3 scripts/tests/test_app_logging.py

      - name: Build app — iOS (no signing)
        working-directory: repo
        run: |
          set -o pipefail
          xcodebuild -project VoxPocket/VoxPocket.xcodeproj -scheme VoxPocket \
            -destination 'generic/platform=iOS' \
            CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO \
            build 2>&1 | tee /tmp/xcodebuild-ios.log

  # ---- Job C (REQUIRED)：lint + policy 门禁（服务端）----
  policy:
    name: Lint & policy
    runs-on: macos-26
    steps:
      - uses: actions/checkout@v4
        with:
          fetch-depth: 0
      # 分层 frontmatter 防腐（tech-context 与代码一致）
      - name: Layer frontmatter anti-rot check
        run: python3 scripts/gates/check_frontmatter.py
      - name: Private model configuration stays outside Git
        run: |
          python3 scripts/gates/check_private_config.py
          python3 -m unittest discover -s scripts/gates/tests -p 'test_private_config.py'
      - name: Advisory review policy contract
        run: bash scripts/ci/kimi-review.contract.test.sh
      - name: Review prompt transport contract
        run: |
          python3 scripts/ci/tests/test_review_prompt.py
          python3 scripts/ci/tests/test_review_raven.py
      - name: TestFlight manual-only release policy
        run: python3 scripts/tests/test_testflight_schedule.py
      # 密钥扫描：拦硬编码 API key / token / password。测试假 key 在 .gitleaks.toml allowlist。
      - name: Install gitleaks
        run: brew install gitleaks
      - name: gitleaks detect (required, full history)
        run: gitleaks detect --no-banner --config .gitleaks.toml --redact
      # 隐私：转写/精炼文本是用户敏感数据，禁止进日志/遥测（宪法 IV）。
      - name: No transcription text in logs
        run: |
          set -uo pipefail
          # 只扫本仓库源码；排除 .build（第三方 vendored 代码如 WhisperKit 不算）。
          MATCHES=$(grep -rnE '(os_log|Logger|print|NSLog|log\.(debug|info|error|warning))[^"]*"[^"]*\\\((refinedText|rawTranscription|liveTranscription|transcript|refined|displayText)' \
            --include='*.swift' Packages VoxPocket 2>/dev/null | grep -v '/\.build/' || true)
          if [ -n "$MATCHES" ]; then
            echo "Blocked: 转写/精炼文本不得进日志（隐私，宪法 IV）："
            echo "$MATCHES"
            exit 1
          fi
          echo "OK: 无转写文本落日志。"
CI_BASELINE

PRE_RELEASE = <<'RELEASE_BASELINE'.freeze
name: testflight

# 仅通过 workflow_dispatch 手动构建 main 并上传 macOS TestFlight；iOS 继续暂停。
# 自动发布已暂停。force=true 可忽略“无新提交”检查；发布标记仍记录成功版本。
#
# 跑在 self-hosted runner（macmini-local，与 VitalStride 同一台物理机）：Apple
# Distribution 证书已在登录钥匙串。签名走 project.yml 的 manual + App Store profile。
# 需要的 Secrets: ASC_KEY_ID / ASC_ISSUER_ID / ASC_KEY_P8_BASE64 / KEYCHAIN_PASSWORD。
#
# push tag 不触发 ci.yml（其 push 过滤是 branches:[main]），无副作用。

on:
  workflow_dispatch:
    inputs:
      force:
        description: '忽略"无新提交"检查，强制发一次'
        type: boolean
        default: false
      platform:
        description: '当前仅发布 macOS；恢复 iOS 须用户明确要求'
        type: choice
        options:
          - macos
        default: macos

concurrency:
  group: testflight
  cancel-in-progress: false # 不打断进行中的上传

permissions:
  contents: write # 移动 macOS 发布标记，保留旧双平台标记

jobs:
  release:
    name: Build & upload to TestFlight
    if: github.event_name == 'workflow_dispatch'
    runs-on: [self-hosted, macOS, ARM64]
    timeout-minutes: 60
    steps:
      - name: Checkout VoxPocket
        uses: actions/checkout@v4
        with:
          ref: main
          fetch-depth: 0
          fetch-tags: true
          path: repo
      # 外部本地依赖（fastlane build 需要）：LokiKit 落在 repo 上两级、
      # AppleUITesting 落在 repo/VoxPocket 上两级 = $GITHUB_WORKSPACE 同级。
      - name: Checkout LokiKit (external local dependency)
        uses: actions/checkout@v4
        with:
          repository: LeePepe/LokiKit
          path: LokiKit
      - name: Checkout AppleUITesting (external local dependency)
        uses: actions/checkout@v4
        with:
          repository: LeePepe/AppleUITesting
          path: AppleUITesting

      - name: Decide whether to release
        id: gate
        working-directory: repo
        env:
          RELEASE_PLATFORM: ${{ inputs.platform || 'macos' }}
        run: |
          set -euo pipefail
          if [ "$RELEASE_PLATFORM" != "macos" ]; then
            echo "::error::iOS releases are paused; only macos is allowed."
            exit 1
          fi
          LATEST="$(git rev-parse HEAD)"
          RELEASED="$(git rev-parse -q --verify refs/tags/testflight/macos-last-released || echo none)"
          FORCE="${{ github.event.inputs.force }}"
          echo "latest=$LATEST"   >> "$GITHUB_OUTPUT"
          echo "HEAD=$LATEST  last-released=$RELEASED  force=$FORCE"
          if [ "$FORCE" = "true" ] || [ "$LATEST" != "$RELEASED" ]; then
            echo "release=true" >> "$GITHUB_OUTPUT"
            echo "→ 有新提交（或 force）：将 build + 上传"
          else
            echo "release=false" >> "$GITHUB_OUTPUT"
            echo "→ skipped: no new commits since last TestFlight release"
          fi

      - name: Verify Xcode
        if: steps.gate.outputs.release == 'true'
        run: |
          echo "Using: $(xcode-select -p)"
          xcodebuild -version

      - name: Ensure fastlane + xcodegen
        if: steps.gate.outputs.release == 'true'
        run: |
          brew list fastlane >/dev/null 2>&1 || brew install fastlane
          brew list xcodegen >/dev/null 2>&1 || brew install xcodegen

      - name: Test release packaging without building an App
        if: steps.gate.outputs.release == 'true'
        working-directory: repo
        run: |
          GEM_PATH="$(brew --prefix fastlane)/libexec" \
            "$(brew --prefix ruby)/bin/ruby" scripts/tests/test_testflight_packaging.rb

      - name: Verify API key secret present
        if: steps.gate.outputs.release == 'true'
        env:
          ASC_KEY_P8_BASE64: ${{ secrets.ASC_KEY_P8_BASE64 }}
        run: |
          set -euo pipefail
          # fastlane 直接吃 base64 key_content，这里仅校验 Secret 存在，不落地明文 .p8。
          if [ -z "${ASC_KEY_P8_BASE64:-}" ]; then
            echo "::error::ASC_KEY_P8_BASE64 secret 未设置" ; exit 1
          fi

      - name: Unlock login keychain for codesign
        if: steps.gate.outputs.release == 'true'
        env:
          KEYCHAIN_PASSWORD: ${{ secrets.KEYCHAIN_PASSWORD }}
        run: |
          set -euo pipefail
          # runner 跑在独立 launchd 会话，login keychain 默认锁定 → codesign 拿不到
          # Apple Distribution 私钥 → errSecInternalComponent。每次 build 前显式解锁。
          if [ -z "${KEYCHAIN_PASSWORD:-}" ]; then
            echo "::error::KEYCHAIN_PASSWORD secret 未设置（gh secret set KEYCHAIN_PASSWORD -R LeePepe/VoxPocket）"; exit 1
          fi
          KC="$HOME/Library/Keychains/login.keychain-db"
          # 单独判解锁结果：密码错(错误码 51)时给出明确指引，区别于"secret 没设"。
          if ! security unlock-keychain -p "$KEYCHAIN_PASSWORD" "$KC" 2>/tmp/kc-unlock.err; then
            echo "::error::解锁 login keychain 失败——KEYCHAIN_PASSWORD 的值不对（应为这台 runner Mac 的登录密码，注意别含尾随空格/换行）。重设：gh secret set KEYCHAIN_PASSWORD -R LeePepe/VoxPocket"
            cat /tmp/kc-unlock.err >&2 || true
            exit 1
          fi
          security set-keychain-settings "$KC"
          EXISTING=$(security list-keychains -d user | sed -e 's/^[[:space:]]*"//' -e 's/"$//')
          security list-keychains -d user -s $(printf '%s\n' "$KC" $EXISTING | awk '!seen[$0]++')
          security set-key-partition-list -S apple-tool:,apple:,codesign: \
            -s -k "$KEYCHAIN_PASSWORD" "$KC" >/dev/null 2>&1 || true

      - name: fastlane iOS beta
        # 保留恢复入口与实现；暂停期间手动/定时触发均不执行 iOS lane。
        if: ${{ false }}
        working-directory: repo
        env:
          ASC_KEY_ID: ${{ secrets.ASC_KEY_ID }}
          ASC_ISSUER_ID: ${{ secrets.ASC_ISSUER_ID }}
          ASC_KEY_P8_BASE64: ${{ secrets.ASC_KEY_P8_BASE64 }}
          FASTLANE_SKIP_UPDATE_CHECK: "1"
          FASTLANE_XCODEBUILD_SETTINGS_TIMEOUT: "120"
          FASTLANE_XCODEBUILD_SETTINGS_RETRIES: "6"
        run: fastlane ios beta

      - name: fastlane macOS beta
        if: steps.gate.outputs.release == 'true'
        working-directory: repo
        env:
          ASC_KEY_ID: ${{ secrets.ASC_KEY_ID }}
          ASC_ISSUER_ID: ${{ secrets.ASC_ISSUER_ID }}
          ASC_KEY_P8_BASE64: ${{ secrets.ASC_KEY_P8_BASE64 }}
          FASTLANE_SKIP_UPDATE_CHECK: "1"
          FASTLANE_XCODEBUILD_SETTINGS_TIMEOUT: "120"
          FASTLANE_XCODEBUILD_SETTINGS_RETRIES: "6"
        run: fastlane mac beta

      - name: Move last-released tag
        if: steps.gate.outputs.release == 'true'
        working-directory: repo
        env:
          GH_TOKEN: ${{ secrets.GITHUB_TOKEN }}
        run: |
          set -euo pipefail
          SHA="${{ steps.gate.outputs.latest }}"
          git tag -f testflight/macos-last-released "$SHA"
          git push -f "https://x-access-token:${GH_TOKEN}@github.com/${GITHUB_REPOSITORY}.git" \
            "refs/tags/testflight/macos-last-released"
          echo "✅ testflight/macos-last-released → $SHA"
RELEASE_BASELINE

LEGACY_CHECKOUT = <<~'YAML'.lines.map { |line| "      #{line}" }.join.freeze
  - name: Checkout LokiKit (external local dependency)
    uses: actions/checkout@v4
    with:
      repository: LeePepe/LokiKit
      path: LokiKit
YAML
SPM_COMMENT = <<~'YAML'.lines.map { |line| "      #{line}" }.join.freeze
  # LokiKit 是外部本地依赖（../../../LokiKit）。从 Packages/<pkg>/ 解析 →
  # 落在 $GITHUB_WORKSPACE/LokiKit。VoxInfrastructure/Application/Presentation 需要。
YAML
RELEASE_COMMENT = <<~'YAML'.lines.map { |line| "      #{line}" }.join.freeze
  # 外部本地依赖（fastlane build 需要）：LokiKit 落在 repo 上两级、
  # AppleUITesting 落在 repo/VoxPocket 上两级 = $GITHUB_WORKSPACE 同级。
YAML
APPLE_COMMENT = <<~'YAML'.lines.map { |line| "      #{line}" }.join.freeze
  # 外部本地依赖（fastlane build 需要）：AppleUITesting
  # 落在 repo/VoxPocket 上两级 = $GITHUB_WORKSPACE 同级。
YAML
FIXTURE_CHECKOUT = <<~'YAML'.lines.map { |line| "      #{line}" }.join.freeze
  # 仅供 test_app_logging.py 的 sibling-path fixture；运行时包仍由远程 URL 解析。
  - name: Checkout shared telemetry (logging regression fixture)
    uses: actions/checkout@v4
    with:
      repository: LeePepe/shared-telemetry
      ref: eff9c1712cd648ed0717e41183ad8bd7bf39cbea
      path: LokiKit
YAML

class ContractError < StandardError; end

def assert(condition, message)
  raise ContractError, message unless condition
end

def replace_once(source, before, after)
  assert(source.split(before, -1).length == 2, "fixture anchor not unique: #{before}")
  source.sub(before) { after }
end

# 只读取 Psych AST，不调用 load/safe_load/to_ruby，不实例化 YAML 声明的对象。
# scalar 保留词法值；尤其 on/yes/true 不经 YAML 1.1 布尔强制转换。
# 结构比对之外再比对允许变换后的字节，保护 scalar 引号/类型及所有注释。
def ast_value(node)
  allowed = [Psych::Nodes::Scalar, Psych::Nodes::Sequence, Psych::Nodes::Mapping]
  assert(allowed.include?(node.class), "unsupported YAML node: #{node.class}")
  assert(node.tag.nil? && node.anchor.nil?, 'YAML tags/anchors are unsupported')
  case node
  when Psych::Nodes::Scalar
    node.value
  when Psych::Nodes::Sequence
    node.children.map { |child| ast_value(child) }
  when Psych::Nodes::Mapping
    ast_mapping(node)
  end
end

def ast_mapping(node)
  assert(node.children.length.even?, 'invalid mapping')
  node.children.each_slice(2).each_with_object({}) do |(key, value), mapping|
    assert(key.is_a?(Psych::Nodes::Scalar), 'complex mapping key is unsupported')
    name = ast_value(key)
    assert(name != '<<', 'YAML merge keys are unsupported')
    assert(!mapping.key?(name), "duplicate YAML mapping key: #{name}")
    mapping[name] = ast_value(value)
  end
end

def parse_yaml(source)
  stream = Psych.parse_stream(source)
  assert(stream.children.length == 1, 'expected exactly one YAML document')
  document = stream.children.first
  assert(document.root.is_a?(Psych::Nodes::Mapping), 'workflow must be a mapping')
  ast_value(document.root)
rescue Psych::SyntaxError => error
  raise ContractError, "invalid YAML: #{error.message}"
end

def expected_sources
  frozen_sources = { CI_PATH => PRE_CI, RELEASE_PATH => PRE_RELEASE }
  frozen_sources.each do |path, source|
    assert(Digest::SHA256.hexdigest(source) == BASELINE_HASHES.fetch(path),
           "pre-edit baseline hash drift: #{path}")
    parse_yaml(source)
  end
  ci = replace_once(PRE_CI, SPM_COMMENT + LEGACY_CHECKOUT, '')
  ci = replace_once(ci, LEGACY_CHECKOUT, FIXTURE_CHECKOUT)
  release = replace_once(PRE_RELEASE, RELEASE_COMMENT + LEGACY_CHECKOUT, APPLE_COMMENT)
  { CI_PATH => ci.freeze, RELEASE_PATH => release.freeze }.freeze
end

def telemetry_checkouts(workflow)
  workflow.fetch('jobs').flat_map do |job, body|
    body.fetch('steps').select do |step|
      options = step.fetch('with', {})
      options['path'] == 'LokiKit' ||
        ['LeePepe/LokiKit', REPOSITORY].include?(options['repository'])
    end.map { |step| [job, step] }
  end
end

def check_workflows(sources, expected)
  parsed = sources.transform_values { |source| parse_yaml(source) }
  expected.each do |path, source|
    assert(parsed.fetch(path) == parse_yaml(source), "frozen control structure changed: #{path}")
    assert(sources.fetch(path) == source, "unapproved text/comment/type change: #{path}")
  end
  ci = parsed.fetch(CI_PATH)
  release = parsed.fetch(RELEASE_PATH)
  assert(ci.fetch('on').keys == %w[push pull_request workflow_dispatch], 'CI event names')
  assert(release.fetch('on').keys == ['workflow_dispatch'], 'manual-only release')
  assert(PIN.match?(/\A[0-9a-f]{40}\z/), 'canonical 40-character pin')
  expected_step = {
    'name' => 'Checkout shared telemetry (logging regression fixture)',
    'uses' => 'actions/checkout@v4',
    'with' => { 'repository' => REPOSITORY, 'ref' => PIN, 'path' => 'LokiKit' }
  }
  assert(telemetry_checkouts(ci) == [['app', expected_step]],
         'exactly one telemetry fixture in app and zero in spm/other jobs')
  assert(telemetry_checkouts(release).empty?, 'zero telemetry checkouts in release')
  logging = ci.fetch('jobs').fetch('app').fetch('steps').select do |step|
    step['name'] == 'Log configuration regression (Debug and Release)'
  end
  assert(logging == [{
    'name' => 'Log configuration regression (Debug and Release)',
    'working-directory' => 'repo', 'timeout-minutes' => '10',
    'run' => 'python3 scripts/tests/test_app_logging.py'
  }], 'logging harness invocation must remain unchanged')
end

def check_consumers(sources)
  MANIFEST_HASHES.each do |path, hash|
    source = sources.fetch(path)
    assert(Digest::SHA256.hexdigest(source) == hash, "frozen manifest changed: #{path}")
    declaration = "url: \"https://github.com/#{REPOSITORY}.git\",\n" \
                  "            revision: \"#{PIN}\""
    assert(source.scan(declaration).length == 1, "manifest/fixture pin coherence: #{path}")
  end
  assert(Digest::SHA256.hexdigest(sources.fetch(LOGGING_PATH)) == LOGGING_HASH,
         'logging harness source changed')
end

def rejects(label)
  begin
    yield
  rescue ContractError
    return
  end
  raise ContractError, "negative fixture was accepted: #{label}"
end

def checkout_mutations
  [
    ['missing fixture', CI_PATH, FIXTURE_CHECKOUT, ''],
    ['duplicate fixture', CI_PATH, FIXTURE_CHECKOUT, FIXTURE_CHECKOUT * 2],
    ['legacy repository', CI_PATH, REPOSITORY, 'LeePepe/LokiKit'],
    ['wrong repository', CI_PATH, REPOSITORY, 'other/shared-telemetry'],
    ['wrong fixture path', CI_PATH, 'path: LokiKit', 'path: shared-telemetry'],
    ['missing fixture path', CI_PATH, "          path: LokiKit\n", ''],
    ['missing pin', CI_PATH, "          ref: #{PIN}\n", ''],
    ['floating pin', CI_PATH, "ref: #{PIN}", 'ref: main'],
    ['wrong full pin', CI_PATH, "ref: #{PIN}", "ref: #{'a' * 40}"],
    ['short pin', CI_PATH, "ref: #{PIN}", "ref: #{PIN[0, 12]}"],
    ['unpinned spm checkout', CI_PATH, "      - name: swift build\n",
     LEGACY_CHECKOUT + "      - name: swift build\n"],
    ['unpinned release checkout', RELEASE_PATH, APPLE_COMMENT, APPLE_COMMENT + LEGACY_CHECKOUT],
  ]
end

def ci_control_mutations
  [
    ['SPM required name', CI_PATH, 'name: SPM ${{ matrix.package }}', 'name: Other SPM'],
    ['app required name', CI_PATH, 'name: App target', 'name: Other app'],
    ['policy required name', CI_PATH, 'name: Lint & policy', 'name: Other policy'],
    ['job name', CI_PATH, "  app:\n", "  other_app:\n"],
    ['trigger on to true', CI_PATH, "\non:\n", "\ntrue:\n"],
    ['trigger on to yes', CI_PATH, "\non:\n", "\nyes:\n"],
    ['pull request event', CI_PATH, "  pull_request:\n", "  pull_request_target:\n"],
    ['push event', CI_PATH, "  push:\n", "  schedule:\n"],
    ['dispatch removal', CI_PATH, "  workflow_dispatch:\n", ''],
    ['branch filter', CI_PATH, "  push:\n    branches: [main]", "  push:\n    branches: [other]"],
    ['added CI permissions', CI_PATH, "concurrency:\n", "permissions: write-all\nconcurrency:\n"],
    ['matrix', CI_PATH, '[VoxDomain, VoxInfrastructure, VoxApplication, VoxPresentation, VoxUITesting]',
     '[VoxInfrastructure, VoxApplication, VoxPresentation, VoxUITesting]'],
    ['SPM command', CI_PATH, 'run: swift test', 'run: echo skipped'],
    ['logging command', CI_PATH, 'run: python3 scripts/tests/test_app_logging.py', 'run: echo skipped'],
    ['startup command', CI_PATH, 'python3 scripts/tests/test_app_startup.py', 'echo skipped'],
    ['iOS compatibility', CI_PATH, "-destination 'generic/platform=iOS'", "-destination 'platform=macOS'"],
    ['app signing', CI_PATH, "CODE_SIGNING_ALLOWED=NO \\\n            build 2>&1 | tee /tmp/xcodebuild-macos.log",
     "CODE_SIGNING_ALLOWED=YES \\\n            build 2>&1 | tee /tmp/xcodebuild-macos.log"],
    ['CI AppleUITesting', CI_PATH, 'repository: LeePepe/AppleUITesting', 'repository: other/AppleUITesting'],
  ]
end

def release_control_mutations
  [
    ['release AppleUITesting', RELEASE_PATH, 'path: AppleUITesting', 'path: other'],
    ['release event', RELEASE_PATH, "  workflow_dispatch:\n", "  push:\n"],
    ['release permissions', RELEASE_PATH, 'contents: write', 'contents: read'],
    ['release condition', RELEASE_PATH, "if: github.event_name == 'workflow_dispatch'", 'if: true'],
    ['iOS activation', RELEASE_PATH, 'if: ${{ false }}', 'if: ${{ true }}'],
    ['release platform option', RELEASE_PATH, "          - macos\n", "          - macos\n          - ios\n"],
    ['release default platform', RELEASE_PATH, 'default: macos', 'default: ios'],
    ['release force default', RELEASE_PATH, 'default: false', 'default: true'],
    ['release guard command', RELEASE_PATH, 'if [ "$RELEASE_PLATFORM" != "macos" ]; then', 'if false; then'],
    ['release runner', RELEASE_PATH, '[self-hosted, macOS, ARM64]', 'macos-26'],
    ['release concurrency', RELEASE_PATH, 'cancel-in-progress: false', 'cancel-in-progress: true'],
    ['release command', RELEASE_PATH, 'run: fastlane mac beta', 'run: fastlane ios beta'],
    ['keychain command', RELEASE_PATH, 'security set-keychain-settings', 'echo set-keychain-settings'],
    ['signing secret', RELEASE_PATH, 'KEYCHAIN_PASSWORD: ${{ secrets.KEYCHAIN_PASSWORD }}',
     'KEYCHAIN_PASSWORD: changed'],
    ['release checkout ref', RELEASE_PATH, 'ref: main', 'ref: other'],
    ['release tag command', RELEASE_PATH, 'git tag -f testflight/macos-last-released',
     'git tag -f testflight/last-released']
  ]
end

def workflow_mutations
  checkout_mutations + ci_control_mutations + release_control_mutations
end

def parser_fixtures
  {
    'duplicate root key' => "on: {}\non: {}\n",
    'duplicate quoted key' => "on: {}\n'on': {}\n",
    'duplicate nested key' => "jobs:\n  app: {}\n  app: {}\n",
    'alias' => "on: *missing\n",
    'anchor' => "on: &events {}\n",
    'merge key' => "on:\n  <<: {}\n",
    'object tag' => "on: !ruby/object:Object {}\n",
    'typed scalar' => "on: !!bool true\n",
    'typed collection' => "on: !!set {push: null}\n",
    'complex key' => "? [on]\n: {}\n",
    'multiple documents' => "on: {}\n---\non: {}\n",
    'sequence root' => "- on\n",
    'empty document' => '',
    'malformed YAML' => "on: [\n"
  }
end

def run_contract
  expected = expected_sources
  # 正向 oracle 只从冻结源与精确变换生成，不从磁盘候选生成。
  check_workflows(expected, expected)
  assert(parse_yaml("on: {}\nyes: {}\ntrue: {}\n").keys == %w[on yes true],
         'YAML 1.1 event names must remain distinct')
  workflow_mutations.each do |label, path, before, after|
    mutated = expected.merge(path => replace_once(expected.fetch(path), before, after))
    rejects(label) { check_workflows(mutated, expected) }
  end
  parser_fixtures.each { |label, source| rejects(label) { parse_yaml(source) } }
  root = File.expand_path('../..', __dir__)
  workflows = expected.keys.each_with_object({}) do |path, result|
    result[path] = File.read(File.join(root, path), encoding: 'UTF-8')
  end
  consumers = (MANIFEST_HASHES.keys + [LOGGING_PATH]).each_with_object({}) do |path, result|
    result[path] = File.read(File.join(root, path), encoding: 'UTF-8')
  end
  check_workflows(workflows, expected)
  check_consumers(consumers)
  MANIFEST_HASHES.each_key do |path|
    changed = consumers.merge(path => replace_once(consumers.fetch(path), PIN, 'a' * 40))
    rejects("changed manifest pin: #{path}") { check_consumers(changed) }
  end
  changed_logging = consumers.merge(LOGGING_PATH => consumers.fetch(LOGGING_PATH) + "\n")
  rejects('changed logging harness') { check_consumers(changed_logging) }
  puts "OK: frozen workflows, checkout/pin/consumer contracts; " \
       "#{workflow_mutations.length + parser_fixtures.length + 4} negative fixtures"
end

run_contract if $PROGRAM_NAME == __FILE__
