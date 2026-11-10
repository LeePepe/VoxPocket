# VoxPocket 原生图标（Pocket Wave · 口袋声波）

## 设计

采用批准的「方案 1 · Pocket Wave（口袋声波）」三层 Liquid Glass 架构：画布 `256×256`（`width="1024" height="1024"`），共三个前景图层（从顶到底依次为 `Sonic Bars`、`Pocket Pouch`、`Capture Card`），每层包含 `light`、`dark`、`mono` 三个外观变体（共 9 个 SVG 文件，`a-l{1,2,3}-{light,dark,mono}.svg`）。`design/app-icon/source.json` 是几何与色板的唯一事实源。

- **Pocket Pouch（`a-l1-*`）**：高饱和蓝宝石渐变口袋前襟，带顶部 V 字开口；`mono` 模式使用 `fill-opacity="0.62"` 形成中景玻璃层次。
- **Capture Card（`a-l2-*`）**：暖珊瑚橙语音速记卡片，所有外观下均沿口袋 V 字上沿精确裁切（`y ≤ 129`），避免延伸到蓝色口袋背面造成 Liquid Glass 折射串色；`mono` 模式使用 `fill-opacity="0.34"` 与前景声波柱拉开对比。
- **Sonic Bars（`a-l3-*`）**：5 根圆角声波柱与口袋底部微笑缝线胶囊，圆角统一展开为精确圆弧路径；`mono` 模式保持 `1.0` 不透明度作为最亮视觉锚点。

原生材质配置保存在 `VoxPocket/VoxPocket/AppIcon.icon/icon.json`：

- `fill-specializations`：默认（Light）模式使用纯净冰白微蓝线性渐变（`srgb:0.975,0.988,1.000,1.000` → `srgb:0.895,0.940,0.995,1.000`），Dark 模式保持 `automatic`；圆角由系统负责。
- 每层开启 Glass；组高光开启，使用 individual lighting。
- 中性阴影 opacity 0.26；关闭额外 translucency，不预烘焙光晕或反光。
- 不声明 Composer 2 features，不依赖 macOS 27 折射或高光位置参数。

## 生成与验证

在仓库根目录：

```bash
python3 scripts/icons/generate_icon.py
python3 scripts/icons/generate_icon.py --check
python3 -m unittest discover -s scripts/icons -p 'test_*.py' -v
python3 scripts/icons/render_icon.py
```

原生预览位于 `build/icon-preview/index.html`，包含 Default、Dark、ClearLight、ClearDark、TintedLight、TintedDark 及 16/32/64/128/1024px。
`render-info.json` 记录实际宿主 macOS 和 Icon Composer 渲染器版本。该预览不是 CSS 模拟材质，也不等同于真实桌面壁纸下的实时合成。

## App 接入

`VoxPocket/project.yml` 明确将 `.icon` 作为 iOS/macOS 资源加入，排除 visionOS；已同步 `.pbxproj` 的 wrapper.icon 引用、资源 membership 与 platform filters。
保持图标名称为 `AppIcon`，原 `Assets.xcassets/AppIcon.appiconset` 暂不删除。

本机使用下列资源级命令验证，**不是完整 App 构建/归档**：

```bash
mkdir -p build/icon-validation/macos
xcrun actool VoxPocket/VoxPocket/Assets.xcassets VoxPocket/VoxPocket/AppIcon.icon \
  --compile build/icon-validation/macos --platform macosx \
  --minimum-deployment-target 26.2 --app-icon AppIcon \
  --output-partial-info-plist build/icon-validation/macos/partial-info.plist

mkdir -p build/icon-validation/ios
xcrun actool VoxPocket/VoxPocket/Assets.xcassets VoxPocket/VoxPocket/AppIcon.icon \
  --compile build/icon-validation/ios --platform iphonesimulator \
  --minimum-deployment-target 26.2 --target-device iphone --target-device ipad \
  --app-icon AppIcon --output-partial-info-plist build/icon-validation/ios/partial-info.plist
```

macOS 输出新的 `Assets.car`、`AppIcon.icns`，partial Info.plist 中 `CFBundleIconFile` / `CFBundleIconName` 均为 `AppIcon`。
已检查该 `.icns` 的图片，确认是新 Pocket Wave 三层图标而非旧图标。完整 App build 仍归 CI；本次没有安装替换、启动 App 或 TestFlight 发布。

## 原生验证环境与限制

- macOS 26.6.2（25G83），Xcode 26.6（17F113），Icon Composer 1.6（99.1）。
- macOS/iOS 最低目标 26.2；更早 26.x 的运行时外观尚未实机检查。
- GUI 自动化缺少辅助功能授权，因此使用随 Xcode 提供的 Icon Composer `ictool` 导出；没有改变系统权限。
- SVG 渐变、dark/tinted 图层特化、原生高光与阴影均经真实渲染验证。
- iOS 编译出现宿主模拟器 `CIPortraitEffectSpillCorrection` 提示，但返回成功并生成图标资源；仍需 CI 完整 App 验证。
- 本次不做商标唯一性声明；未把 PNG 备份等同于原生分层配方。

TintedDark 的 16px 内部细节较弱。原生导出预览不等同于已安装 App 的 Dock 或壁纸合成验收，最终效果仍需在目标系统中检查。

## 一手设计依据

- [Apple HIG — App icons](https://developer.apple.com/design/human-interface-guidelines/app-icons)
- [WWDC25 — Say hello to the new look of app icons](https://developer.apple.com/videos/play/wwdc2025/220/)
- [WWDC25 — Create icons with Icon Composer](https://developer.apple.com/videos/play/wwdc2025/361/)
- [Creating your app icon using Icon Composer](https://developer.apple.com/documentation/xcode/creating-your-app-icon-using-icon-composer)

`.icon` 文档结构通过本机已有 Composer 文件及公开序列化实例核对，并最终以本机原生导出/actool 编译结果为准；未运行第三方 MCP 或安装图像 API。
