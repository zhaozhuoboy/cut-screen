import CoreGraphics

enum ScrollOverlayGeometry {
    static func maskRects(in displayBounds: CGRect, outside selection: CGRect) -> [CGRect] {
        let bounds = displayBounds.standardized
        let selected = selection.standardized.intersection(bounds)
        guard !bounds.isEmpty else { return [] }
        guard !selected.isNull, !selected.isEmpty else { return [bounds] }

        return [
            CGRect(
                x: bounds.minX,
                y: bounds.minY,
                width: bounds.width,
                height: selected.minY - bounds.minY
            ),
            CGRect(
                x: bounds.minX,
                y: selected.maxY,
                width: bounds.width,
                height: bounds.maxY - selected.maxY
            ),
            CGRect(
                x: bounds.minX,
                y: selected.minY,
                width: selected.minX - bounds.minX,
                height: selected.height
            ),
            CGRect(
                x: selected.maxX,
                y: selected.minY,
                width: bounds.maxX - selected.maxX,
                height: selected.height
            )
        ]
        .map { $0.intersection(bounds) }
        .filter { !$0.isNull && !$0.isEmpty }
    }

    static func borderRects(
        around selection: CGRect,
        in screenBounds: CGRect,
        thickness: CGFloat = 2
    ) -> [CGRect] {
        let bounds = screenBounds.standardized
        let selected = selection.standardized.intersection(bounds)
        let lineWidth = max(1, thickness)
        guard !selected.isNull, !selected.isEmpty else { return [] }

        return [
            CGRect(
                x: selected.minX,
                y: selected.minY - lineWidth,
                width: selected.width,
                height: lineWidth
            ),
            CGRect(
                x: selected.minX,
                y: selected.maxY,
                width: selected.width,
                height: lineWidth
            ),
            CGRect(
                x: selected.minX - lineWidth,
                y: selected.minY,
                width: lineWidth,
                height: selected.height
            ),
            CGRect(
                x: selected.maxX,
                y: selected.minY,
                width: lineWidth,
                height: selected.height
            )
        ]
        .map { $0.intersection(bounds) }
        .filter { !$0.isNull && !$0.isEmpty }
    }
}
