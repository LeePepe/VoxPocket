import Foundation

/// 侧边栏导航目标
public enum SidebarDestination: Hashable {
    case session(UUID)
    case me
}
