import SwiftUI
import ScrollbackCore

enum ViewMode: String, CaseIterable, Identifiable {
    case list, timeline

    var id: String { rawValue }
    var label: String { self == .list ? "List" : "Timeline" }
    var symbol: String { self == .list ? "list.bullet" : "chart.bar.xaxis" }
}

extension DeviceKind {
    var symbol: String { self == .iphone ? "iphone" : "laptopcomputer" }
}

/// The first choice on screen: whose day you're looking at. Everything below follows it.
struct DeviceSwitcher: View {
    @Bindable var model: AppModel
    @Environment(\.liveToday) private var liveToday

    var body: some View {
        HStack(spacing: Space.xs) {
            ForEach(DeviceKind.allCases, id: \.self) { device in
                tab(device)
            }
        }
        .padding(Space.xs)
        .background(Palette.ink.opacity(0.06), in: RoundedRectangle(cornerRadius: Radius.card + Space.xs))
    }

    /// The phone's real total lives inside Screen Time's card, which the app can't read,
    /// so don't show a partial number beside it.
    private func subtitle(for device: DeviceKind) -> String {
        if device == .iphone, model.isToday, liveToday != nil { return "Live today" }
        return Format.duration(model.report.total(on: device)) + (model.isToday ? " today" : "")
    }

    private func tab(_ device: DeviceKind) -> some View {
        let isSelected = model.device == device
        return Button {
            withAnimation(Motion.quick) { model.device = device }
        } label: {
            HStack(spacing: Space.s) {
                Image(systemName: device.symbol)
                    .font(TypeScale.title)
                    .frame(width: 22)
                VStack(alignment: .leading, spacing: 0) {
                    Text(device.label).font(TypeScale.bodyStrong)
                    Text(subtitle(for: device))
                        .font(TypeScale.mono)
                        .foregroundStyle(isSelected ? Palette.inkMuted : Palette.inkFaint)
                }
                Spacer(minLength: 0)
            }
            .foregroundStyle(isSelected ? Palette.ink : Palette.inkMuted)
            .padding(.horizontal, Space.m)
            .padding(.vertical, Space.s + Space.xxs)
            .frame(maxWidth: .infinity)
            .background {
                if isSelected {
                    RoundedRectangle(cornerRadius: Radius.card)
                        .fill(Palette.raised)
                        .shadow(color: .black.opacity(0.08), radius: 3, y: 1)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(PressScale())
        .accessibilityLabel("\(device.label), \(subtitle(for: device))")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

/// "Activity" with the list/timeline choice; the color key only matters on the timeline.
struct ActivityHeader: View {
    @Bindable var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: Space.s) {
            HStack {
                Text("Activity").font(TypeScale.title).foregroundStyle(Palette.ink)
                Spacer()
                Picker("View", selection: $model.viewMode) {
                    ForEach(ViewMode.allCases) { mode in
                        Label(mode.label, systemImage: mode.symbol).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .fixedSize()
            }
            if model.viewMode == .timeline { Legend() }
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
