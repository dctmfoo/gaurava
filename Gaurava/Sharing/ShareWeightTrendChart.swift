import Charts
import SwiftUI

struct ShareWeightTrendChart: View {
    let snapshot: ShareCardSnapshot
    let configuration: ShareCardConfiguration
    var style: ShareWeightTrendChartStyle = .standard

    var body: some View {
        Chart {
            if style != .sparkline {
                ForEach(xGridDates, id: \.timeIntervalSince1970) { date in
                    RuleMark(x: .value(appLocalizedValue("Date"), date))
                        .foregroundStyle(AppTheme.chartGrid)
                        .lineStyle(StrokeStyle(lineWidth: 0.8, dash: [3, 5]))
                }
            }

            ForEach(segments) { segment in
                ForEach(segment.points) { point in
                    LineMark(
                        x: .value(appLocalizedValue("Date"), point.date),
                        y: .value(yAxisTitle, point.value),
                        series: .value(appLocalizedValue("Dose"), segment.id)
                    )
                    .interpolationMethod(.linear)
                    .foregroundStyle(doseColor(segment.doseMg))
                    .lineStyle(StrokeStyle(lineWidth: style.lineWidth, lineCap: .round, lineJoin: .round))
                }
            }

            ForEach(chartPoints) { point in
                PointMark(
                    x: .value(appLocalizedValue("Date"), point.date),
                    y: .value(yAxisTitle, point.value)
                )
                .foregroundStyle(doseColor(point.doseMg))
                .symbolSize(style.pointSize)
            }
        }
        .chartXAxis {
            if style.showsAxes, configuration.dateVisibility == .show {
                AxisMarks(values: xAxisDates) { value in
                    AxisGridLine()
                        .foregroundStyle(.clear)
                    AxisTick()
                        .foregroundStyle(.clear)
                    AxisValueLabel(anchor: .top) {
                        if let date = value.as(Date.self) {
                            Text(axisDateText(date))
                                .font(.system(size: 9, weight: .semibold))
                                .foregroundStyle(AppTheme.textTertiary)
                        }
                    }
                }
            }
        }
        .chartYAxis {
            if style.showsAxes {
                AxisMarks(position: .trailing, values: .automatic(desiredCount: style.yAxisCount)) { value in
                    AxisGridLine()
                        .foregroundStyle(AppTheme.chartGrid)
                    AxisTick()
                        .foregroundStyle(.clear)
                    AxisValueLabel {
                        if let number = value.as(Double.self) {
                            Text(yAxisLabel(number))
                                .font(.system(size: 9, weight: .semibold))
                                .foregroundStyle(AppTheme.textTertiary)
                        }
                    }
                }
            }
        }
        .chartXScale(domain: xDomain)
        .chartYScale(domain: yDomain)
        .chartLegend(.hidden)
        .chartPlotStyle { plotArea in
            plotArea
                .background(AppTheme.chartPlotSurface.opacity(style == .sparkline ? 0 : 0.30))
        }
    }

    private var chartPoints: [ShareChartPoint] {
        snapshot.weightPoints.map { point in
            ShareChartPoint(
                id: point.id,
                date: point.date,
                value: yValue(for: point.weightKg),
                doseMg: point.doseMg
            )
        }
    }

    private var segments: [ShareChartSegment] {
        zip(chartPoints, chartPoints.dropFirst()).enumerated().map { index, pair in
            ShareChartSegment(
                id: index,
                points: [pair.0, pair.1],
                doseMg: pair.0.doseMg ?? pair.1.doseMg
            )
        }
    }

    private var xDomain: ClosedRange<Date> {
        guard let first = chartPoints.first?.date, let last = chartPoints.last?.date else {
            return Date().addingTimeInterval(-86_400)...Date()
        }
        let span = max(last.timeIntervalSince(first), 86_400)
        let pad = min(max(span * 0.08, 86_400), 21 * 86_400)
        return first.addingTimeInterval(-pad)...last.addingTimeInterval(pad)
    }

    private var yDomain: ClosedRange<Double> {
        let values = chartPoints.map(\.value)
        guard let minValue = values.min(), let maxValue = values.max() else { return 0...1 }
        let padding = max(configuration.privacyMode == .percentOnly ? 2.0 : 1.5, (maxValue - minValue) * 0.22)
        let lower = floor(minValue - padding)
        let upper = ceil(maxValue + padding)
        if lower < upper {
            return lower...upper
        }
        return (minValue - 1)...(maxValue + 1)
    }

    private var xAxisDates: [Date] {
        guard let first = chartPoints.first?.date, let last = chartPoints.last?.date else { return [] }
        if Calendar.current.isDate(first, inSameDayAs: last) {
            return [first]
        }
        let middle = first.addingTimeInterval(last.timeIntervalSince(first) / 2)
        return [first, middle, last]
    }

    private var xGridDates: [Date] {
        guard style != .sparkline else { return [] }
        return xAxisDates
    }

    private var yAxisTitle: String {
        configuration.privacyMode == .percentOnly ? appLocalizedValue("Percent of start") : appLocalizedValue("Weight")
    }

    private func yValue(for weightKg: Double) -> Double {
        switch configuration.privacyMode {
        case .exact:
            return configuration.unit.value(fromKilograms: weightKg)
        case .percentOnly:
            guard let start = snapshot.startWeightKg, start > 0 else { return 0 }
            return (weightKg / start) * 100
        }
    }

    private func yAxisLabel(_ number: Double) -> String {
        switch configuration.privacyMode {
        case .exact:
            appLocalizedValue("\(number.formatted(.number.precision(.fractionLength(0))))\(configuration.unit.title)")
        case .percentOnly:
            appLocalizedValue("\(number.formatted(.number.precision(.fractionLength(0))))%")
        }
    }

    private func axisDateText(_ date: Date) -> String {
        guard configuration.dateVisibility == .show else { return "" }
        return date.appFormatted(.dateTime.month(.abbreviated).day())
    }
}

enum ShareWeightTrendChartStyle {
    case standard
    case compact
    case sparkline

    var showsAxes: Bool {
        self != .sparkline
    }

    var lineWidth: CGFloat {
        switch self {
        case .standard: 4.5
        case .compact: 3.6
        case .sparkline: 3.4
        }
    }

    var pointSize: CGFloat {
        switch self {
        case .standard: 58
        case .compact: 42
        case .sparkline: 22
        }
    }

    var yAxisCount: Int {
        switch self {
        case .standard: 4
        case .compact: 3
        case .sparkline: 0
        }
    }
}

private struct ShareChartPoint: Identifiable {
    let id: UUID
    let date: Date
    let value: Double
    let doseMg: Double?
}

private struct ShareChartSegment: Identifiable {
    let id: Int
    let points: [ShareChartPoint]
    let doseMg: Double?
}
