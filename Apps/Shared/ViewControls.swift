import SwiftUI
import ScrollbackCore

enum DeviceFilter: String, CaseIterable, Identifiable {
    case iphone, mac, both

    var id: String { rawValue }

    var devices: [DeviceKind] {
        switch self {
        case .iphone: [.iphone]
        case .mac: [.mac]
        case .both: DeviceKind.allCases
        }
    }

    var label: String {
        switch self {
        case .iphone: "iPhone"
        case .mac: "Mac"
        case .both: "Both"
        }
    }
}

enum ViewMode: String, CaseIterable, Identifiable {
    case list, timeline

    var id: String { rawValue }
    var label: String { self == .list ? "List" : "Timeline" }
    var symbol: String { self == .list ? "list.bullet" : "chart.bar.xaxis" }
}

struct ViewControls: View {
    @Bindable var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: Space.s) {
            HStack(spacing: Space.m) {
                Picker("View", selection: $model.viewMode) {
                    ForEach(ViewMode.allCases) { mode in
                        Label(mode.label, systemImage: mode.symbol).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .fixedSize()
                Picker("Device", selection: $model.deviceFilter) {
                    ForEach(DeviceFilter.allCases) { Text($0.label).tag($0) }
                }
                .pickerStyle(.segmented)
                .fixedSize()
                Spacer(minLength: 0)
            }
            .labelsHidden()
            Legend()
        }
    }
}

struct Legend: View {
    var body: some View {
        HStack(spacing: Space.m) {
            ForEach(AppCategory.allCases, id: \.self) { category in
                HStack(spacing: Space.xs) {
                    RoundedRectangle(cornerRadius: 2).fill(Palette.category(category)).frame(width: 10, height: 10)
                    Text(category.label).font(TypeScale.label).foregroundStyle(Palette.inkMuted)
                }
            }
        }
        .accessibilityElement(children: .combine)
    }
}
