import SwiftUI

struct SettingsRoot: View {
    var body: some View {
        TabView {
            GeneralTab()
                .tabItem { Label("通用", systemImage: "gearshape") }

            DisplayTab()
                .tabItem { Label("显示", systemImage: "display") }

            PermissionsTab()
                .tabItem { Label("权限", systemImage: "lock.shield") }

            AboutTab()
                .tabItem { Label("关于", systemImage: "info.circle") }
        }
        .frame(minWidth: 520, maxWidth: 520, minHeight: 380, maxHeight: 600)
    }
}
