import BagIdSDK
import SwiftUI

struct MapFlowNetworkTimelineView: View {
    let presentation: NetworkTimelinePresentation

    private var marks: [NetworkTimelineMark] {
        presentation.marks as? [NetworkTimelineMark] ?? []
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Your baggage will be tracked until")
                .font(.footnote)
                .foregroundStyle(MapFlowTheme.onLight.opacity(0.7))
            Text(presentation.trackedUntilLabel)
                .font(.body.bold())
                .foregroundStyle(MapFlowTheme.onLight)
            timelineAxis
            timelineLabels
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private var timelineAxis: some View {
        let items = marks
        GeometryReader { geo in
            let width = geo.size.width
            let count = max(items.count, 1)
            let step = count > 1 ? width / CGFloat(count - 1) : width
            let endIndex = items.lastIndex(where: { $0.kind == .end }) ?? items.count - 1
            ZStack(alignment: .leading) {
                ForEach(Array(items.enumerated()), id: \.offset) { index, _ in
                    let x = count > 1 ? step * CGFloat(index) : width / 2
                    Circle()
                        .fill(index == endIndex ? MapFlowTheme.accent : Color.black)
                        .frame(width: 10, height: 10)
                        .position(x: x, y: geo.size.height / 2)
                    if index < items.count - 1 {
                        let nextX = step * CGFloat(index + 1)
                        Path { path in
                            path.move(to: CGPoint(x: x + 6, y: geo.size.height / 2))
                            path.addLine(to: CGPoint(x: nextX - 6, y: geo.size.height / 2))
                        }
                        .stroke(
                            index >= endIndex ? Color.gray.opacity(0.5) : Color.black,
                            style: StrokeStyle(lineWidth: 2, dash: index >= endIndex ? [4, 4] : [])
                        )
                    }
                }
            }
        }
        .frame(height: 14)
        .padding(.top, 4)
    }

    @ViewBuilder
    private var timelineLabels: some View {
        let items = marks
        HStack(alignment: .top) {
            ForEach(Array(items.enumerated()), id: \.offset) { index, mark in
                VStack(spacing: 4) {
                    if mark.kind == .flight {
                        Image(systemName: "airplane")
                            .font(.caption)
                            .foregroundStyle(MapFlowTheme.accent)
                    }
                    Text(mark.timeLabel)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(MapFlowTheme.onLight)
                    if let axis = mark.axisLabel {
                        Text(axis)
                            .font(.caption2)
                            .foregroundStyle(MapFlowTheme.onLight.opacity(0.55))
                            .multilineTextAlignment(
                                index == 0 ? .leading : (index == items.count - 1 ? .trailing : .center)
                            )
                    }
                }
                .frame(
                    maxWidth: .infinity,
                    alignment: index == 0 ? .leading : (index == items.count - 1 ? .trailing : .center)
                )
            }
        }
    }
}
