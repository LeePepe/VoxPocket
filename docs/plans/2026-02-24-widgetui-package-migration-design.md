# WidgetUI Package Migration Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Move widget implementation code into `Packages/VoxPresentation` and let `VoxPocketWidgetExtension` consume it via a package product.

**Architecture:** Add a new `WidgetUI` target/product in `VoxPresentation` that contains the widget/provider/control intent implementation. Keep a tiny `@main` bundle entry file in the extension target that references a public widget builder from `WidgetUI`. Update Xcode target package dependency to link `WidgetUI`.

**Tech Stack:** Swift 6.2, Swift Package Manager, WidgetKit, SwiftUI, AppIntents, Xcode project target package dependencies.

### Task 1: Define failing spec for package API

**Files:**
- Create: `Packages/VoxPresentation/Tests/WidgetUITests/WidgetUITests.swift`
- Modify: `Packages/VoxPresentation/Package.swift`

1. Write a test that imports `@testable import WidgetUI` and references public entry API for widget composition.
2. Run `swift test --package-path Packages/VoxPresentation --filter WidgetUITests` and confirm it fails because target/product doesn't exist yet.

### Task 2: Implement `WidgetUI` package target

**Files:**
- Modify: `Packages/VoxPresentation/Package.swift`
- Create: `Packages/VoxPresentation/Sources/WidgetUI/QuickRecordWidget.swift`
- Create: `Packages/VoxPresentation/Sources/WidgetUI/VoxPocketControlWidget.swift`
- Create: `Packages/VoxPresentation/Sources/WidgetUI/VoxPocketWidgetEntries.swift`

1. Add `WidgetUI` library product, target, and test target.
2. Move widget implementation into `WidgetUI`, keeping types public where extension target needs them.
3. Expose a public widget builder API consumed by extension `@main` type.

### Task 3: Rewire widget extension target

**Files:**
- Modify: `VoxPocket/VoxPocket.xcodeproj/project.pbxproj`
- Modify: `VoxPocketWidget/VoxPocketWidgetBundle.swift`
- Delete: `VoxPocketWidget/QuickRecordWidget.swift`
- Delete: `VoxPocketWidget/VoxPocketControlWidget.swift`

1. Add `WidgetUI` package product dependency to `VoxPocketWidgetExtension` target and frameworks phase.
2. Update extension bundle file to import `WidgetUI` and compose widgets via package entry API.
3. Remove duplicated implementation files from extension folder.

### Task 4: Verify

**Files:**
- Test: `Packages/VoxPresentation/Tests/WidgetUITests/WidgetUITests.swift`

1. Run `swift test --package-path Packages/VoxPresentation --filter WidgetUITests`.
2. Run `swift test --package-path Packages/VoxPresentation` to ensure no regressions in package tests.
