import Accessibility
import SwiftUI

/// A chart as an Audio Graph: VoiceOver's Chart Details reads its summary
/// and plays each series as rising and falling pitch, so someone who can't
/// see the line can still hear the month go up toward the budget. Each
/// chart builds one from the same numbers it draws.
struct AudioGraph: AXChartDescriptorRepresentable {
    struct Series {
        let name: String
        /// One value per category, in the same order as `categories`.
        let values: [Double]
    }

    let title: String
    let summary: String
    let categoryTitle: String
    let categories: [String]
    let valueTitle: String
    let currencyCode: String
    let series: [Series]

    func makeChartDescriptor() -> AXChartDescriptor {
        let all = series.flatMap(\.values)
        let low = min(all.min() ?? 0, 0)
        let high = max(all.max() ?? 1, 1)
        let code = currencyCode
        let xAxis = AXCategoricalDataAxisDescriptor(title: categoryTitle, categoryOrder: categories)
        let yAxis = AXNumericDataAxisDescriptor(title: valueTitle, range: low...high, gridlinePositions: []) { value in
            Money.whole(Decimal(value), code)
        }
        let dataSeries = series.map { item in
            AXDataSeriesDescriptor(
                name: item.name,
                isContinuous: true,
                dataPoints: zip(categories, item.values).map { AXDataPoint(x: $0, y: $1) }
            )
        }
        return AXChartDescriptor(title: title, summary: summary, xAxis: xAxis, yAxis: yAxis,
                                 additionalAxes: [], series: dataSeries)
    }
}
