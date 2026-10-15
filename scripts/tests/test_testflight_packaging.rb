# frozen_string_literal: true

# 使用已安装的 fastlane/gym；只替换 Xcode 构建、签名和网络，不构建 App。
require "minitest/autorun"
require "tmpdir"
require "fastlane"
require "gym"
require "yaml"
require "rexml/document"
require "open3"
require "sigh"
require "sigh/manager"

Fastlane.load_actions

ROOT = File.expand_path("../..", __dir__)
UI = FastlaneCore::UI

class FixtureProject < FastlaneCore::Project
  def initialize(platform)
    @platform = platform
    project = Xcodeproj::Project.open(File.join(ROOT, "VoxPocket/VoxPocket.xcodeproj"))
    target = project.targets.find { |item| item.name == "VoxPocket" }
    @settings = target.build_configurations.find { |item| item.name == "Release" }.build_settings
  end

  def build_settings(key:)
    {
      "SUPPORTED_PLATFORMS" => @settings.fetch("SUPPORTED_PLATFORMS"),
      "SUPPORTS_MACCATALYST" => @settings["SUPPORTS_MACCATALYST"],
      "PLATFORM_NAME" => @platform,
      "PRODUCT_TYPE" => "com.apple.product-type.application"
    }[key]
  end
end

# 保留真实 Runner.run、平台分类、move_ipa/move_pkg 与包查找逻辑。
class FixtureRunner < Gym::Runner
  def build_app; end
  def verify_archive; end
  def fix_generic_archive; end
  def package_app; end
  def compress_and_move_dsym; end
  def copy_mac_app; end
  def move_manifest; end
  def move_app_thinning; end
  def move_app_thinning_size_report; end
  def move_apps_folder; end
  def move_asset_packs; end
  def move_appstore_info; true; end
end

class FixtureLane < Fastlane::FastFile
  attr_reader :build_options, :upload_options, :distributed, :build_number_options, :requested_build_platform

  def initialize(artifact, stub_build_number: true)
    super(File.join(ROOT, "fastlane/Fastfile"))
    @artifact = artifact
    define_singleton_method(:asc_api_key) { { key_id: "test", issuer_id: "test", key: "test" } }
    define_singleton_method(:regenerate_project) {}
    if stub_build_number
      define_singleton_method(:next_build_number) do |_, platform: "ios"|
        @requested_build_platform = platform
        40
      end
    end
    define_singleton_method(:distribute_to_internal) { |*args| @distributed = args }
  end

  def build_app(**options)
    @build_options = options
    @artifact
  end

  def upload_to_testflight(**options)
    @upload_options = options
  end

  def latest_testflight_build_number(**options)
    @build_number_options = options
    40
  end

  def run(platform)
    runner.execute(:beta, platform)
  end
end

class TestFlightPackagingTests < Minitest::Test
  def setup
    @directory = Dir.mktmpdir("voxpocket-package-test-")
    @orig_sigh_name = ENV["SIGH_NAME"]
    @orig_sigh_uuid = ENV["SIGH_UUID"]
    @orig_lane_context = Fastlane::Actions.lane_context.dup
    Fastlane::Actions.lane_context.clear
    ENV.delete("SIGH_NAME")
    ENV.delete("SIGH_UUID")

    # Default Sigh::Manager.start stub publishes standard fixture values
    Sigh::Manager.define_singleton_method(:start) do
      ENV["SIGH_NAME"] = "fixture-profile"
      ENV["SIGH_UUID"] = "fixture-uuid-12345"
      "path/to/profile"
    end
  end

  def teardown
    FileUtils.remove_entry(@directory)
    Fastlane::Actions.lane_context.clear
    Fastlane::Actions.lane_context.merge!(@orig_lane_context)
    if @orig_sigh_name.nil?
      ENV.delete("SIGH_NAME")
    else
      ENV["SIGH_NAME"] = @orig_sigh_name
    end
    if @orig_sigh_uuid.nil?
      ENV.delete("SIGH_UUID")
    else
      ENV["SIGH_UUID"] = @orig_sigh_uuid
    end
  end

  def artifact(name)
    path = File.join(@directory, name)
    File.write(path, "fixture, not a signed application")
    path
  end

  def run_gym(options, extension)
    exported = File.join(@directory, "export")
    FileUtils.mkdir_p(exported)
    File.write(File.join(exported, "VoxPocket.#{extension}"), "fixture")
    # 跳过会运行 xcodebuild -showBuildSettings 的 config setter，仅注入边界输入。
    Gym.instance_variable_set(:@config, options.merge(
      output_directory: File.join(@directory, "output"), output_name: "VoxPocket"
    ))
    Gym.cache = { temporary_output_path: exported }
    Gym.project = FixtureProject.new(extension == "pkg" ? "macosx" : "iphoneos")
    FixtureRunner.new.run
  end

  def test_destination_alone_reproduces_real_ipa_invalid_failure
    error = assert_raises(FastlaneCore::Interface::FastlaneBuildFailure) do
      run_gym({ destination: "generic/platform=macOS" }, "pkg")
    end
    assert_equal "IPA invalid", error.message
  end

  def test_mac_lane_routes_exported_package_through_real_gym
    lane = FixtureLane.new(artifact("VoxPocket.pkg"))
    lane.run(:mac)
    result = run_gym(lane.build_options, "pkg")
    assert_equal ".pkg", File.extname(result)
    assert File.file?(result)
  end

  def test_ios_lane_still_routes_ipa
    lane = FixtureLane.new(artifact("VoxPocket.ipa"))
    lane.run(:ios)
    result = run_gym(lane.build_options, "ipa")
    assert_equal ".ipa", File.extname(result)
    assert File.file?(result)
  end

  def test_mac_upload_uses_exact_built_package_and_platform
    pkg = artifact("VoxPocket.pkg")
    lane = FixtureLane.new(pkg)
    lane.run(:mac)
    assert_equal pkg, lane.upload_options[:pkg]
    assert_equal "osx", lane.upload_options[:app_platform]
    refute lane.upload_options.key?(:ipa)
    assert_nil lane.distributed
    assert_equal "osx", lane.requested_build_platform
  end

  def test_upload_lanes_leave_group_distribution_to_app_store_connect
    { mac: "pkg", ios: "ipa" }.each do |platform, extension|
      lane = FixtureLane.new(artifact("VoxPocket.#{extension}"))
      lane.run(platform)
      assert_nil lane.distributed, "#{platform} must not manually assign beta groups"
      assert_equal false, lane.upload_options[:skip_waiting_for_build_processing]
      assert_equal true, lane.upload_options[:skip_submission]
      assert_equal false, lane.upload_options[:distribute_external]
      refute lane.upload_options.key?(:groups)
    end
  end

  def test_mac_build_number_looks_up_macos_across_versions
    lane = FixtureLane.new(nil, stub_build_number: false)
    assert_equal 41, lane.next_build_number(:fixture_key, platform: "osx")
    assert_equal "osx", lane.build_number_options[:platform]
    refute lane.build_number_options.key?(:version)
  end

  def test_mac_rejects_missing_or_wrong_artifact_before_upload
    [nil, File.join(@directory, "missing.pkg"), artifact("wrong.ipa")].each do |path|
      lane = FixtureLane.new(path)
      assert_raises(FastlaneCore::Interface::FastlaneError) { lane.run(:mac) }
      assert_nil lane.upload_options
      assert_nil lane.distributed
    end
  end

  def test_workflow_pauses_ios_and_defaults_to_macos
    workflow = YAML.load_file(File.join(ROOT, ".github/workflows/testflight.yml"))
    events = workflow.fetch("on") { workflow.fetch(true) }
    selection = events.fetch("workflow_dispatch").fetch("inputs").fetch("platform")
    assert_equal "macos", selection.fetch("default")
    assert_equal ["macos"], selection.fetch("options")
    steps = workflow.fetch("jobs").fetch("release").fetch("steps")
    conditions = steps.to_h { |step| [step["name"], step["if"]] }
    assert_equal "${{ false }}",
                 conditions.fetch("fastlane iOS beta")
    assert_equal "steps.gate.outputs.release == 'true'",
                 conditions.fetch("fastlane macOS beta")
    assert_equal "steps.gate.outputs.release == 'true'",
                 conditions.fetch("Move last-released tag")
    gate = steps.find { |step| step["id"] == "gate" }
    assert_equal "${{ inputs.platform || 'macos' }}", gate.fetch("env").fetch("RELEASE_PLATFORM")
    assert_includes gate.fetch("run"), '"$RELEASE_PLATFORM" != "macos"'
    assert_includes gate.fetch("run"), "refs/tags/testflight/macos-last-released"
    tag_step = steps.find { |step| step["name"] == "Move last-released tag" }
    assert_includes tag_step.fetch("run"), "refs/tags/testflight/macos-last-released"
    refute_includes tag_step.fetch("run"), "refs/tags/testflight/last-released"
  end

  def test_shared_scheme_does_not_force_ios_widget_into_macos_archive
    scheme = REXML::Document.new(File.read(File.join(
      ROOT, "VoxPocket/VoxPocket.xcodeproj/xcshareddata/xcschemes/VoxPocket.xcscheme"
    )))
    entries = REXML::XPath.match(scheme, "//BuildActionEntry[@buildForArchiving='YES']/BuildableReference")
    assert_equal ["VoxPocket"], entries.map { |entry| entry.attributes["BlueprintName"] }
    assert_equal "YES", REXML::XPath.first(scheme, "//BuildAction").attributes["buildImplicitDependencies"]
  end

  def test_release_gate_rejects_paused_platforms_and_accepts_macos
    workflow = YAML.load_file(File.join(ROOT, ".github/workflows/testflight.yml"))
    gate = workflow.fetch("jobs").fetch("release").fetch("steps").find { |step| step["id"] == "gate" }
    script = gate.fetch("run").gsub("${{ github.event.inputs.force }}", "false")
    %w[ios all invalid macos].each do |platform|
      output_path = File.join(@directory, "output-#{platform}")
      File.write(output_path, "")
      output, status = Open3.capture2e(
        { "RELEASE_PLATFORM" => platform, "GITHUB_OUTPUT" => output_path },
        "bash", "-c", script, chdir: ROOT
      )
      if platform == "macos"
        assert status.success?, output
        assert_includes File.read(output_path), "latest="
      else
        refute status.success?
        assert_includes output, "iOS TestFlight releases need separate Owner authorization; only macos is allowed."
        assert_empty File.read(output_path)
      end
    end
  end

  def test_widget_is_still_an_ios_only_app_dependency
    spec = YAML.load_file(File.join(ROOT, "VoxPocket/project.yml"))
    dependency = spec.fetch("targets").fetch("VoxPocket").fetch("dependencies")
                     .find { |item| item["target"] == "VoxPocketWidgetExtension" }
    refute_nil dependency
    assert_equal "iOS", dependency.fetch("platformFilter")
    assert_equal "iOS", spec.fetch("targets").fetch("VoxPocketWidgetExtension").fetch("platform")
    assert_equal ["VoxPocket"], spec.fetch("schemes").fetch("VoxPocket").fetch("build").fetch("targets").keys
  end

  def test_mac_lane_fetches_forced_installed_profile_without_fixed_name
    captured_options = nil
    Sigh::Manager.define_singleton_method(:start) do
      captured_options = Sigh.config
      ENV["SIGH_NAME"] = "VoxPocket Mac App Store Fetched"
      ENV["SIGH_UUID"] = "uuid-fetched"
      "path/to/profile"
    end

    lane = FixtureLane.new(artifact("VoxPocket.pkg"))
    lane.run(:mac)

    assert_equal true, captured_options[:force]
    assert_equal false, captured_options[:skip_install]
    assert_equal "macos", captured_options[:platform]
    assert_nil captured_options[:provisioning_name]
    assert_equal "com.leepepe.voxpocket", captured_options[:app_identifier]
  end

  def test_mac_lane_fails_closed_when_profile_name_is_missing_or_blank
    Sigh::Manager.define_singleton_method(:start) do
      ENV.delete("SIGH_NAME")
      ENV["SIGH_UUID"] = "uuid-missing-name"
      "path/to/profile"
    end

    lane = FixtureLane.new(artifact("VoxPocket.pkg"))
    assert_raises(FastlaneCore::Interface::FastlaneError) { lane.run(:mac) }
    assert_nil lane.build_options, "build_app must not be called when profile name is missing"
    assert_nil lane.upload_options, "upload_to_testflight must not be called when profile name is missing"

    Sigh::Manager.define_singleton_method(:start) do
      ENV["SIGH_NAME"] = "   "
      ENV["SIGH_UUID"] = "uuid-blank-name"
      "path/to/profile"
    end

    lane = FixtureLane.new(artifact("VoxPocket.pkg"))
    assert_raises(FastlaneCore::Interface::FastlaneError) { lane.run(:mac) }
    assert_nil lane.build_options, "build_app must not be called when profile name is blank"
    assert_nil lane.upload_options, "upload_to_testflight must not be called when profile name is blank"
  end

  def test_mac_lane_passes_shell_escaped_profile_specifier_and_generic_installer
    Sigh::Manager.define_singleton_method(:start) do
      ENV["SIGH_NAME"] = "VoxPocket App Store 2026 (Special)"
      ENV["SIGH_UUID"] = "uuid-distinct-1234"
      "path/to/profile"
    end

    lane = FixtureLane.new(artifact("VoxPocket.pkg"))
    lane.run(:mac)

    assert_includes lane.build_options[:xcargs], "VOXPOCKET_MAC_PROFILE_SPECIFIER=VoxPocket\\ App\\ Store\\ 2026\\ \\(Special\\)"
    assert_equal "Mac Installer Distribution", lane.build_options.dig(:export_options, :installerSigningCertificate)
    assert_equal "VoxPocket App Store 2026 (Special)", lane.build_options.dig(:export_options, :provisioningProfiles, "com.leepepe.voxpocket")
    # Verify that the action return value (UUID) is distinct and was not mistakenly used as the profile display name
    refute_includes lane.build_options[:xcargs], "uuid-distinct-1234"
  end
end
