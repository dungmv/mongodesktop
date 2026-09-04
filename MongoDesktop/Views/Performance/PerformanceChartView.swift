import SwiftUI

// MARK: - Performance Chart Series

struct ChartSeries: Identifiable {
    var id: String { name }
    let name: String
    let color: Color
    let values: [Double]

    init(name: String, color: Color, values: [Double]) {
        self.name = name
        self.color = color
        self.values = values
    }
}

// MARK: - PerformanceChartView

struct PerformanceChartView: View {
    let series: [ChartSeries]
    let secondarySeries: ChartSeries?
    let yAxisLabel: String
    let secondaryYAxisLabel: String?
    let maxValueOverride: Double?

    init(
        series: [ChartSeries],
        secondarySeries: ChartSeries? = nil,
        yAxisLabel: String,
        secondaryYAxisLabel: String? = nil,
        maxValueOverride: Double? = nil
    ) {
        self.series = series
        self.secondarySeries = secondarySeries
        self.yAxisLabel = yAxisLabel
        self.secondaryYAxisLabel = secondaryYAxisLabel
        self.maxValueOverride = maxValueOverride
    }

    var body: some View {
        GeometryReader { proxy in
            let w = proxy.size.width
            let h = proxy.size.height

            // Calculate primary max value
            let allPrimaryValues = series.flatMap(\.values)
            let maxPrimary = maxValueOverride ?? max(1.0, (allPrimaryValues.max() ?? 1.0) * 1.15)

            // Secondary series max value
            let maxSecondary = secondarySeries.map { s in
                max(1.0, (s.values.max() ?? 1.0) * 1.15)
            } ?? 1.0

            ZStack(alignment: .topLeading) {
                // Background subtle card
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(Color(nsColor: .textBackgroundColor).opacity(0.4))

                // Grid Lines
                chartGrid(width: w, height: h)

                // Y-axis Labels
                HStack {
                    Text(yAxisLabel)
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(.secondary)
                        .padding(.leading, 6)
                        .padding(.top, 4)

                    Spacer()

                    if let secLabel = secondaryYAxisLabel {
                        Text(secLabel)
                            .font(.caption2.monospacedDigit())
                            .foregroundStyle(.secondary)
                            .padding(.trailing, 6)
                            .padding(.top, 4)
                    }
                }

                // Primary Series Lines
                ForEach(series) { s in
                    linePath(values: s.values, maxValue: maxPrimary, width: w, height: h)
                        .stroke(s.color, style: StrokeStyle(lineWidth: 1.8, lineCap: .round, lineJoin: .round))
                }

                // Secondary Series Line (if any)
                if let sec = secondarySeries {
                    linePath(values: sec.values, maxValue: maxSecondary, width: w, height: h)
                        .stroke(sec.color, style: StrokeStyle(lineWidth: 1.8, lineCap: .round, lineJoin: .round))
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .stroke(Color(nsColor: .separatorColor).opacity(0.4), lineWidth: 1)
            )
        }
    }

    private func chartGrid(width: CGFloat, height: CGFloat) -> some View {
        Canvas { context, size in
            // 3 horizontal guideline lines
            let stepY = size.height / 4
            for i in 1...3 {
                let y = CGFloat(i) * stepY
                var path = Path()
                path.move(to: CGPoint(x: 0, y: y))
                path.addLine(to: CGPoint(x: size.width, y: y))
                context.stroke(
                    path,
                    with: .color(Color(nsColor: .separatorColor).opacity(0.2)),
                    style: StrokeStyle(lineWidth: 0.8, dash: [4, 4])
                )
            }

            // Vertical guidelines
            let stepX = size.width / 6
            for i in 1...5 {
                let x = CGFloat(i) * stepX
                var path = Path()
                path.move(to: CGPoint(x: x, y: 0))
                path.addLine(to: CGPoint(x: x, y: size.height))
                context.stroke(
                    path,
                    with: .color(Color(nsColor: .separatorColor).opacity(0.15)),
                    style: StrokeStyle(lineWidth: 0.8)
                )
            }
        }
    }

    private func linePath(values: [Double], maxValue: Double, width: CGFloat, height: CGFloat) -> Path {
        var path = Path()
        guard !values.isEmpty else { return path }

        let count = max(values.count, 2)
        let stepX = width / CGFloat(max(count - 1, 1))

        let points: [CGPoint] = values.enumerated().map { idx, val in
            let clampedVal = max(0, val)
            let ratio = CGFloat(clampedVal / maxValue)
            let clampedRatio = min(1.0, max(0.0, ratio))
            // Leave 8pt padding top and bottom
            let y = height - 8 - (clampedRatio * (height - 16))
            let x = CGFloat(idx) * stepX
            return CGPoint(x: x, y: y)
        }

        path.move(to: points[0])
        for i in 1..<points.count {
            path.addLine(to: points[i])
        }

        return path
    }
}
