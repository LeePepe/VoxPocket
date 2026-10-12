# frozen_string_literal: true

# 使用已安装的 fastlane/gym；只替换 Xcode 构建、签名和网络，不构建 App。
require "minitest/autorun"
require "tmpdir"
require "gym"
require "yaml"
require "rexml/document"
require "open3"

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

class FixtureLane
  attr_reader :build_options, :upload_options, :distributed, :build_number_options, :requested_build_platform

  def initialize(artifact, stub_build_number: true)
    @artifact = artifact
    @lanes = {}
    instance_eval(File.read(File.join(ROOT, "fastlane/Fastfile")), "Fastfile")
    define_singleton_method(:asc_api_key) { :fixture_key }
    define_singleton_method(:regenerate_project) {}
    if stub_build_number
      define_singleton_method(:next_build_number) do |_, platform: "ios"|
        @requested_build_platform = platform
        40
      end
    end
    define_singleton_method(:distribute_to_internal) { |*args| @distributed = args }
  end

  def default_platform(*); end
  def desc(*); end
  def platform(name)
    @platform = name
    yield
  end
  def lane(name, &block)
    @lanes[[@platform, name]] = block
  end
  def get_provisioning_profile(**); "fixture-profile"; end
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
    instance_exec(&@lanes.fetch([platform, :beta]))
  end
end

class TestFlightPackagingTests < Minitest::Test
  def setup
    @directory = Dir.mktmpdir("voxpocket-package-test-")
  end

  def teardown
    FileUtils.remove_entry(@directory)
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
        assert_includes output, "iOS releases are paused"
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
end
