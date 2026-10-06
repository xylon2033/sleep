import SwiftUI

/// Rounded card used across screens.
struct Card<Content: View>: View {
    var title: String?
    var systemImage: String?
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let title {
                Label(title, systemImage: systemImage ?? "circle")
                    .labelStyle(.titleAndIcon)
                    .font(.headline)
                    .foregroundStyle(.secondary)
            }
            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(.fill.tertiary, in: .rect(cornerRadius: 18))
    }
}

struct StatTile: View {
    var label: String
    var value: String
    var detail: String?
    var lowConfidence = false

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.title3.weight(.semibold))
                .monospacedDigit()
                .foregroundStyle(lowConfidence ? .secondary : .primary)
            if let detail {
                Text(detail)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct Chip: View {
    var title: String
    var systemImage: String?
    var isOn: Bool
    var detail: String?
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                if let systemImage { Image(systemName: systemImage) }
                Text(title)
                if let detail {
                    Text(detail).foregroundStyle(.secondary)
                }
            }
            .font(.subheadline)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(isOn ? AnyShapeStyle(Color.indigo.opacity(0.85)) : AnyShapeStyle(.fill.secondary), in: .capsule)
            .foregroundStyle(isOn ? .white : .primary)
        }
        .buttonStyle(.plain)
    }
}

/// Simple wrapping layout for chips.
struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? .infinity
        var x: CGFloat = 0, y: CGFloat = 0, rowHeight: CGFloat = 0, maxX: CGFloat = 0
        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            if x > 0, x + size.width > width {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            x += size.width + spacing
            maxX = max(maxX, x - spacing)
            rowHeight = max(rowHeight, size.height)
        }
        return CGSize(width: proposal.width ?? maxX, height: y + rowHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, rowHeight: CGFloat = 0
        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            if x > bounds.minX, x + size.width > bounds.maxX {
                x = bounds.minX
                y += rowHeight + spacing
                rowHeight = 0
            }
            view.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}

/// "Estimated" badge so audio estimates are never mistaken for clinical staging.
struct EstimateNote: View {
    var text = "Estimated from sound. Phones can't measure sleep stages; use this for trends, not diagnosis."

    var body: some View {
        Label(text, systemImage: "info.circle")
            .font(.caption)
            .foregroundStyle(.secondary)
    }
}

extension Date {
    var shortDay: String { formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated)) }
}
