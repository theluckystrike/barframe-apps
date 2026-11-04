import SwiftUI
import AppKit
import Charts
import MASKit
import PortSenseCore

struct PopoverView: View {
    @ObservedObject var model: AppState
    var workspaceHeight: Double? = nil
    var measureLayout: (([String: CGRect]) -> Void)? = nil
    private var screenHeight: Double { workspaceHeight ?? NSScreen.main?.visibleFrame.height ?? 720 }
    private var tab: InspectorTab { model.selectedTab }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                Image(systemName: "cable.connector")
                    .font(.system(size: 22, weight: .medium)).foregroundStyle(.tint)
                    .frame(width: 40, height: 40)
                    .background(Color.accentColor.opacity(0.1), in: RoundedRectangle(cornerRadius: 10))
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 3) {
                    Text(model.isSample ? "PortSense · Sample" : "PortSense").font(.headline)
                    Text(model.powerError == nil ? (model.power?.supply.label ?? "Checking power source…") : "Reading unavailable")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Button { model.refresh() } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .buttonStyle(.plain)
                .disabled(model.refreshing)
                .help("Refresh power and connections")
                .accessibilityLabel("Refresh power and connections")
            }
            .measureControl("header")
            HStack(spacing: 2) {
                ForEach(InspectorTab.allCases, id: \.self) { item in
                    Button { model.selectedTab = item } label: {
                        Text(item.rawValue)
                            .font(.caption.weight(tab == item ? .semibold : .regular))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 6)
                            .background(tab == item ? Color.primary.opacity(0.12) : .clear, in: RoundedRectangle(cornerRadius: 6))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Show " + item.rawValue)
                    .accessibilityValue(tab == item ? "Selected" : "")
                }
            }
            .padding(3)
            .background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 8))
            .accessibilityElement(children: .contain)
            .accessibilityLabel("Inspector section")
            .measureControl("tabs")

            ScrollView { detailContent.frame(maxWidth: .infinity, alignment: .leading) }
                .frame(height: PopoverLayout.bodyHeight(visibleHeight: screenHeight))
                .measureControl("detail")
            Divider()
            HStack {
                Button(model.isSample ? "Return to Live" : "Try Sample") { model.setSample(!model.isSample) }
                    .accessibilityLabel(model.isSample ? "Return to live hardware readings" : "Try Sample hardware readings")
                Spacer()
                Button("Read privacy") { model.openPrivacy() }.accessibilityLabel("Read local privacy policy")
                PortLinksView(model: model)
            }
            .font(.caption).buttonStyle(.plain)
            .measureControl("links")
            HStack {
                Text(model.power.map { "Updated " + $0.date.formatted(date: .omitted, time: .shortened) } ?? "No reading")
                    .font(.caption2).foregroundStyle(.secondary)
                Spacer()
                Button("Settings…") { model.openSettings() }
                    .keyboardShortcut(",", modifiers: .command)
                    .accessibilityLabel("Open PortSense Settings")
                Button("Quit") { NSApp.terminate(nil) }
                    .keyboardShortcut("q", modifiers: .command)
                    .accessibilityLabel("Quit PortSense")
            }
            .buttonStyle(.plain)
            .measureControl("footer")
        }
        .padding(18)
        .frame(width: 360)
        .coordinateSpace(name: "popover")
        .onPreferenceChange(ControlFrames.self) { measureLayout?($0) }
        .onExitCommand { NSApp.keyWindow?.close() }
    }

    @ViewBuilder private var detailContent: some View {
        switch tab {
        case .power: powerContent
        case .connections: connectionContent
        case .history: historyContent
        }
        ForEach(model.notificationErrors, id: \.self) { message in
            Text(message).font(.caption2).foregroundStyle(.secondary)
        }
    }

    private var powerContent: some View {
        VStack(alignment: .leading, spacing: 14) {
            if let error = model.powerError {
                errorState(error)
            } else if let power = model.power {
                VStack(alignment: .leading, spacing: 6) {
                    Text("CHARGER CAPACITY").font(.caption2.weight(.semibold)).foregroundStyle(.secondary)
                    Text(power.supply == .battery ? "On battery" : ReadingFormat.watts(power.adapter?.watts))
                        .font(.system(size: 36, weight: .semibold, design: .rounded)).monospacedDigit()
                    Text(power.adapter?.name ?? (power.supply == .battery ? "Connect a charger to inspect its capacity." : "Adapter name not reported by macOS."))
                        .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    Text("Reported capacity, not power drawn.")
                        .font(.caption2).foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(14).background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 12))
                dataRow("Charger input telemetry", value: DetailFormat.watts(power.inputWatts))
                dataRow("Negotiated voltage", value: power.adapter?.volts.map { "\($0.formatted(.number.precision(.fractionLength(1)))) V" } ?? "Unavailable")
                dataRow("Negotiated current", value: power.adapter?.milliamps.map { "\((Double($0) / 1000).formatted(.number.precision(.fractionLength(2)))) A" } ?? "Unavailable")
                Text("Input telemetry is separate from adapter capacity; it is not a wall-power measurement.")
                    .font(.caption2).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                chargerStatus
                if let battery = power.battery {
                    VStack(alignment: .leading, spacing: 9) {
                        sectionTitle("Battery", symbol: "battery.75percent")
                        dataRow("Charge", value: battery.chargePercent.map { "\($0)% · \(battery.chargingState)" } ?? "Unavailable")
                        if let percent = battery.chargePercent {
                            GeometryReader { geometry in
                                ZStack(alignment: .leading) {
                                    Capsule().fill(Color.primary.opacity(0.1))
                                    Capsule().fill(Color.accentColor).frame(width: geometry.size.width * Double(percent) / 100)
                                }
                            }
                            .frame(height: 6)
                            .accessibilityLabel("Battery charge").accessibilityValue("\(percent) percent")
                        }
                        dataRow("Health", value: battery.health ?? "Unavailable")
                        dataRow(ReadingFormat.rawCapacityLabel, value: battery.maximumCapacityPercent.map { "\($0)%" } ?? "Unavailable")
                        Text("Raw registry ratio; System Settings can show a different health percentage.")
                            .font(.caption2).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                        dataRow("Cycle count", value: battery.cycleCount.map(String.init) ?? "Unavailable")
                        dataRow("Full charge / design", value: battery.fullChargeCapacity.flatMap { full in battery.designCapacity.map { "\(full.formatted(.number.precision(.fractionLength(0)))) / \($0.formatted(.number.precision(.fractionLength(0)))) mAh" } } ?? "Unavailable")
                        dataRow("Battery power (signed)", value: DetailFormat.watts(battery.signedWatts))
                        Text("Positive charges the battery; negative discharges it.").font(.caption2).foregroundStyle(.secondary)
                        dataRow("Temperature", value: DetailFormat.temperature(battery.temperatureCelsius))
                        dataRow(battery.isCharging ? "Time to full (estimate)" : "Time to empty (estimate)", value: DetailFormat.minutes(battery.remainingMinutes))
                        if let error = power.batteryDetailError {
                            Text(error).font(.caption2).foregroundStyle(.secondary)
                            Button("Retry battery details") { model.refresh() }.accessibilityLabel("Retry battery details")
                        }
                    }
                } else {
                    Text("No internal battery reported by macOS.").font(.caption).foregroundStyle(.secondary)
                    Button("Refresh power information") { model.refresh() }.accessibilityLabel("Refresh power information")
                }
            } else {
                Text("Checking power source…").font(.caption).foregroundStyle(.secondary)
                Button("Try Sample") { model.setSample(true) }.accessibilityLabel("Try Sample power readings")
            }
        }
    }

    @ViewBuilder private var chargerStatus: some View {
        switch model.verdict {
        case .belowRating(let actual, let rating):
            VStack(alignment: .leading, spacing: 6) {
                Label("Below your charger rating", systemImage: "exclamationmark.triangle.fill")
                    .font(.caption.weight(.semibold)).foregroundStyle(.orange)
                Text("macOS reports \(ReadingFormat.watts(actual)); your rating is \(ReadingFormat.watts(rating)). Try another cable or a direct connection.")
                    .font(.caption).fixedSize(horizontal: false, vertical: true)
                Button("Edit charger rating") { model.openSettings() }.accessibilityLabel("Edit charger rating")
            }
            .padding(10).background(Color.orange.opacity(0.1), in: RoundedRectangle(cornerRadius: 10))
        case .notConfigured:
            HStack(alignment: .top) {
                Text("Set the wattage printed on your charger to flag a lower reported capacity.")
                    .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                Button("Set rating") { model.openSettings() }.accessibilityLabel("Set charger rating")
            }
        case .sufficient:
            Label("Matches your \(ReadingFormat.watts(model.effectiveRating)) rating", systemImage: "checkmark.circle")
                .font(.caption).foregroundStyle(.secondary)
        case .unavailable:
            Text("macOS has not reported charger capacity.").font(.caption).foregroundStyle(.secondary)
            Button("Refresh charger") { model.refresh() }.accessibilityLabel("Refresh charger capacity")
        case .disconnected:
            EmptyView()
        }
    }

    private var connectionContent: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                sectionTitle("USB devices", symbol: "externaldrive.connected.to.line.below")
                Spacer()
                Text("\(model.visibleUSB.count)").font(.caption).foregroundStyle(.secondary)
            }
            Toggle("Include built-in devices", isOn: $model.showBuiltIn)
                .font(.caption).toggleStyle(InspectorToggleStyle()).accessibilityLabel("Include built-in USB devices")
            if let error = model.connectionError { errorState(error) }
            else if model.visibleUSB.isEmpty && model.connections.thunderbolt.isEmpty {
                Text("No connections are reported in this view.").font(.caption).foregroundStyle(.secondary)
                Button("Refresh connections") { model.refresh() }.accessibilityLabel("Refresh connections")
            } else {
                connectionRows
            }
            ForEach(model.connections.warnings, id: \.self) { errorState($0) }
            Text("Speed is the USB link ceiling, not transfer throughput. Bus current is an allocation or limit, not a measured draw. macOS may omit port details.")
                .font(.caption2).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }
    }

    private var connectionRows: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(model.visibleUSB) { device in
                VStack(alignment: .leading, spacing: 5) {
                    HStack(alignment: .firstTextBaseline) {
                        Text(device.product).font(.subheadline.weight(.medium)).fixedSize(horizontal: false, vertical: true)
                        Spacer(minLength: 4)
                        Text(device.speedLabel).font(.caption.weight(.semibold)).foregroundStyle(.tint)
                    }
                    Text(device.vendor + " · " + (device.isBuiltIn ? "Built-in" : device.portType))
                        .font(.caption).foregroundStyle(.secondary)
                    dataRow("Bus allocation", value: device.allocatedMilliamps.map { "\($0) mA" } ?? "Unavailable")
                    dataRow("Port current limit", value: device.availableMilliamps.map { "\($0) mA" } ?? "Unavailable")
                    if device.checkCable {
                        Label("USB 3 device at a USB 2 link ceiling. Check the cable or connection.", systemImage: "info.circle")
                            .font(.caption2).foregroundStyle(.orange).fixedSize(horizontal: false, vertical: true)
                    }
                    if let location = device.location {
                        Text("Location " + location).font(.caption2.monospaced()).foregroundStyle(.secondary)
                    }
                }
                .padding(10).background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 9))
            }
            if !model.connections.thunderbolt.isEmpty {
                sectionTitle("Thunderbolt", symbol: "bolt.horizontal")
                ForEach(model.connections.thunderbolt) { device in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(device.name).font(.subheadline.weight(.medium))
                        Text(device.vendor ?? "Vendor unavailable").font(.caption).foregroundStyle(.secondary)
                        Text("Link speed not reported.").font(.caption2).foregroundStyle(.secondary)
                    }.padding(10)
                }
            }
        }
    }

    private var historyContent: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionTitle("Charger capacity over time", symbol: "chart.xyaxis.line")
            Text("Up to 60 readings · 15-second polling cadence")
                .font(.caption).foregroundStyle(.secondary)
            Text("Manual reads and failed attempts can add entries. Polling can wait for an active read.")
                .font(.caption2).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            if let range = model.history.range {
                Chart(model.history.plotPoints) { point in
                    capacityMarks(point)
                }
                .chartYScale(domain: 0...max(20, range.upperBound * 1.2))
                .chartXScale(range: .plotDimension(startPadding: 24, endPadding: 30))
                .chartXAxis {
                    AxisMarks(values: HistoryAxis.ticks(model.history)) { value in
                        AxisValueLabel(format: HistoryAxis.format,
                            anchor: value.as(Date.self) == model.history.samples.last?.date ? .topTrailing : .topLeading)
                        AxisGridLine()
                    }
                }
                .frame(height: 155)
                .accessibilityLabel("Charger capacity history")
                .accessibilityValue("\(model.history.samples.count) samples; minimum \(ReadingFormat.watts(range.lowerBound)); maximum \(ReadingFormat.watts(range.upperBound))")
                dataRow("Observed range", value: ReadingFormat.watts(range.lowerBound) + " – " + ReadingFormat.watts(range.upperBound))
            } else {
                Text("No charger wattage has been reported this session.")
                    .font(.caption).foregroundStyle(.secondary)
                Button("Refresh charger") { model.refresh() }.accessibilityLabel("Refresh charger for history")
            }
            if let failed = model.history.latestFailure {
                Text("\(model.history.failedReadCount) failed read(s) · latest at \(failed.date.formatted(date: .omitted, time: .shortened))")
                    .font(.caption).foregroundStyle(.secondary)
                Text(failed.failure ?? "Reading unavailable.").font(.caption2).foregroundStyle(.secondary)
                Button("Retry power reading") { model.refresh() }.accessibilityLabel("Retry failed power reading")
            }
            Text("\(model.history.samples.count) of 60 samples recorded. Gaps mean a failed read or no reported charger capacity; they do not mean zero watts.")
                .font(.caption2).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            Text("History stays in memory and resets when you quit.").font(.caption2).foregroundStyle(.secondary)
            Button("Clear history") { model.clearHistory() }.accessibilityLabel("Clear charger capacity history")
        }
    }

    @ChartContentBuilder private func capacityMarks(_ point: WattagePlotPoint) -> some ChartContent {
        let time = PlottableValue<Date>.value(Text("Time"), point.date)
        let capacity = PlottableValue<Double>.value(Text("Capacity (W)"), point.watts)
        let segment = PlottableValue<Int>.value(Text("Continuous reading"), point.segment)
        LineMark(x: time, y: capacity, series: segment).interpolationMethod(.stepEnd)
        PointMark(x: time, y: capacity).symbolSize(12)
    }

    private func sectionTitle(_ title: String, symbol: String) -> some View {
        Label(title, systemImage: symbol).font(.subheadline.weight(.semibold))
    }
    private func dataRow(_ label: String, value: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(label).foregroundStyle(.secondary)
            Spacer(minLength: 8)
            Text(value).multilineTextAlignment(.trailing)
        }.font(.caption)
    }
    private func errorState(_ message: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Label(message, systemImage: "exclamationmark.circle").font(.caption).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Button("Retry") { model.refresh() }.accessibilityLabel("Retry reading system information")
        }
    }
}
