import SwiftUI

/// The regular x regular shell (iPad, Mac, the iPhone Duo's inner display): a
/// sidebar listing every tab plus Settings, with the chosen tab in the detail
/// column. A `NavigationSplitView` over a plain `List`, deliberately not a
/// `TabView` (see `MainTabView.usesSidebar`).
///
/// Selection lives in `MainTabView` so a shell swap keeps the tab. The detail is
/// `.id`'d by selection so no tab's state leaks into another's (the same
/// "never share a view between destinations" rule as the split-detail `.id`s).
struct HorizonSidebarShell: View {
    @Binding var selectedTab: String
    @Binding var showsSettings: Bool

    private static let settingsID = "settings"

    private var selection: Binding<String?> {
        Binding(get: { showsSettings ? Self.settingsID : selectedTab },
                set: {
                    guard let id = $0 else { return }
                    if id == Self.settingsID {
                        showsSettings = true
                    } else if HorizonTab(rawValue: id) != nil {
                        selectedTab = id
                        showsSettings = false
                    }
                })
    }

    var body: some View {
        NavigationSplitView {
            List(selection: selection) {
                Section {
                    ForEach(HorizonTab.allCases) { tab in
                        Label(tab.title, systemImage: tab.systemImage).tag(tab.id)
                    }
                }
                Section {
                    Label("Settings", systemImage: "gearshape").tag(Self.settingsID)
                }
            }
            .navigationTitle("Horizon")
        } detail: {
            detail
                .id(selection.wrappedValue)
        }
    }

    @ViewBuilder
    private var detail: some View {
        if showsSettings {
            SettingsView(embedded: true)
        } else if let tab = HorizonTab(rawValue: selectedTab) {
            if tab.ownsNavigation {
                // Plans owns a NavigationSplitView of its own (list beside plan).
                HorizonTabRoot(tab: tab)
            } else {
                NavigationStack { HorizonTabRoot(tab: tab) }
            }
        }
    }
}
