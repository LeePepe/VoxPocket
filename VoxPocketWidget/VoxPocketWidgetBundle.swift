import WidgetKit
import SwiftUI

/// VoxPocket Widget Bundle
///
/// 包含 Home Screen Widget 和 Control Center 控件。
@main
struct VoxPocketWidgetBundle: WidgetBundle {
    var body: some Widget {
        QuickRecordWidget()
        #if os(iOS)
        if #available(iOSApplicationExtension 18.0, *) {
            VoxPocketControlWidget()
        }
        #endif
    }
}
