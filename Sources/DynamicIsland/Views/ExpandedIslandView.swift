import SwiftUI
import IOKit.ps

struct ExpandedIslandView: View {
    @ObservedObject var model: IslandModel
    @ObservedObject var media: MediaController
    var ns: Namespace.ID

    @Namespace private var tabNS
    @ViewState private var tabDirection: Edge = .trailing

    var body: some View {
        VStack(spacing: 0) {
            header
                .frame(height: model.notchSize.height)
                .staggered(0)
            ZStack {
                page(for: model.tab)
                    .id(model.tab)
                    .transition(.asymmetric(
                        insertion: .move(edge: tabDirection).combined(with: .opacity),
                        removal: .move(edge: tabDirection == .trailing ? .leading : .trailing).combined(with: .opacity)))
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .clipped()
            .staggered(1)
            .padding(.horizontal, 22)
            .padding(.top, 8)
            .padding(.bottom, 18)
        }
        .background(alignment: .bottom) {
            // Мягкое свечение цвета обложки на вкладке музыки.
            if model.tab == .music && media.hasTrack {
                RadialGradient(colors: [media.accent.opacity(0.22), .clear],
                               center: .bottomLeading, startRadius: 10, endRadius: 360)
                    .allowsHitTesting(false)
                    .transition(.opacity)
            }
        }
    }

    private var header: some View {
        HStack(spacing: 0) {
            HStack(spacing: 4) {
                ForEach(IslandTab.allCases) { tab in
                    TabButton(tab: tab, selected: model.tab == tab, badge: badge(for: tab), ns: tabNS) {
                        select(tab)
                    }
                }
            }
            .padding(.leading, 16)
            Spacer(minLength: model.notchSize.width + 20)
            WeatherChip(service: model.weather)
                .padding(.trailing, 20)
        }
    }

    private func badge(for tab: IslandTab) -> Int {
        tab == .shelf ? model.shelf.items.count : 0
    }

    private func select(_ tab: IslandTab) {
        let all = IslandTab.allCases
        let from = all.firstIndex(of: model.tab) ?? 0
        let to = all.firstIndex(of: tab) ?? 0
        tabDirection = to >= from ? .trailing : .leading
        withAnimation(.spring(response: 0.38, dampingFraction: 0.82)) { model.tab = tab }
    }

    @ViewBuilder
    private func page(for tab: IslandTab) -> some View {
        switch tab {
        case .home: HomeView(model: model, media: media, batteries: model.batteries) { select(.music) }
        case .music: MusicPlayerView(media: media, ns: ns)
        case .shelf: ShelfView(store: model.shelf, isTargeted: model.isDropTargeted)
        case .notes: NotesView(store: model.notes, clipboard: model.clipboard)
        case .controls: ControlsView(volume: model.volume, brightness: model.brightness)
        }
    }
}

private struct TabButton: View {
    var tab: IslandTab
    var selected: Bool
    var badge: Int
    var ns: Namespace.ID
    var action: () -> Void

    @ViewState private var hovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: tab.icon)
                .font(.system(size: 12.5, weight: .semibold))
                .foregroundStyle(selected ? .black : .white.opacity(hovering ? 1 : 0.65))
                .symbolEffect(.bounce, value: selected)
                .frame(width: 30, height: 22)
                .background {
                    if selected {
                        Capsule().fill(.white).matchedGeometryEffect(id: "tab", in: ns)
                    } else if hovering {
                        Capsule().fill(.white.opacity(0.1))
                    }
                }
                .overlay(alignment: .topTrailing) {
                    if badge > 0 && !selected {
                        Text("\(badge)")
                            .font(.system(size: 8.5, weight: .bold, design: .rounded))
                            .foregroundStyle(.black)
                            .padding(.horizontal, 3.5)
                            .frame(minWidth: 13, minHeight: 13)
                            .background(Capsule().fill(Color.orange))
                            .offset(x: 4, y: -3)
                            .transition(.scale.combined(with: .opacity))
                    }
                }
                .contentShape(Capsule())
        }
        .buttonStyle(PressableStyle())
        .help(tab.title)
        .onHover { h in withAnimation(.easeOut(duration: 0.15)) { hovering = h } }
    }
}

/// Погода в правом углу шапки.
private struct WeatherChip: View {
    @ObservedObject var service: WeatherService

    var body: some View {
        if let w = service.weather {
            HStack(spacing: 5) {
                Image(systemName: w.symbol)
                    .symbolRenderingMode(.multicolor)
                    .font(.system(size: 13))
                Text("\(w.temperature)°")
                    .font(.system(size: 12.5, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .contentTransition(.numericText(value: Double(w.temperature)))
                if let city = w.city {
                    Text(city)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.white.opacity(0.5))
                        .lineLimit(1)
                }
            }
            .foregroundStyle(.white.opacity(0.9))
            .transition(.blurFade)
        }
    }
}

struct BatteryInfo: Equatable {
    var percent: Int
    var charging: Bool
    var onAC = false

    var symbol: String {
        if charging { return "battery.100percent.bolt" }
        switch percent {
        case ..<13: return "battery.0percent"
        case ..<38: return "battery.25percent"
        case ..<63: return "battery.50percent"
        case ..<88: return "battery.75percent"
        default: return "battery.100percent"
        }
    }

    static func read() -> BatteryInfo? {
        guard let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let list = IOPSCopyPowerSourcesList(info)?.takeRetainedValue() as? [CFTypeRef] else { return nil }
        for source in list {
            guard let desc = IOPSGetPowerSourceDescription(info, source)?.takeUnretainedValue() as? [String: Any],
                  desc[kIOPSTypeKey] as? String == kIOPSInternalBatteryType,
                  let current = desc[kIOPSCurrentCapacityKey] as? Int,
                  let max = desc[kIOPSMaxCapacityKey] as? Int, max > 0 else { continue }
            let onAC = desc[kIOPSPowerSourceStateKey] as? String == kIOPSACPowerValue
            let charging = (desc[kIOPSIsChargingKey] as? Bool ?? false) || onAC
            return BatteryInfo(percent: current * 100 / max, charging: charging, onAC: onAC)
        }
        return nil
    }
}
