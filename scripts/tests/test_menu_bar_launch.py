#!/usr/bin/env python3
"""Exercise production macOS scenes with fake content/configuration, without an App build."""
from pathlib import Path
import subprocess
import tempfile


def main():
    root = Path(__file__).resolve().parents[2]
    with tempfile.TemporaryDirectory(prefix="vox-menu-scene-") as temporary:
        directory = Path(temporary)
        scenes = directory / "MacOSAppScenes.swift"
        # 同次编译使用真实 SPM 菜单源码，无需链接完整模型/存储依赖。
        scenes.write_text((root / "VoxPocket/VoxPocket/MacOSAppScenes.swift")
                          .read_text().replace("import PlatformUI\n", ""))
        binary = directory / "menu-scene-probe"
        subprocess.run([
            "swiftc", "-parse-as-library", "-swift-version", "6",
            str(scenes),
            str(root / "Packages/VoxPresentation/Sources/PlatformUI/VoxMenuBarContent.swift"),
            str(root / "VoxPocket/VoxPocket/AppStartup.swift"),
            str(root / "VoxPocket/VoxPocket/AppStartupView.swift"),
            str(root / "scripts/tests/menu_bar_launch_probe.swift"),
            "-o", str(binary),
        ], check=True, timeout=60)
        for arguments in [[], ["--configuration-fails"]]:
            subprocess.run([str(binary), *arguments], check=True, timeout=15)


if __name__ == "__main__":
    main()
