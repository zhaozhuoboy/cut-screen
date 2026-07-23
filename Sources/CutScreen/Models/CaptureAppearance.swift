import AppKit

struct CaptureAppearance: Equatable {
    static let maximumCornerRadius: CGFloat = 32
    static let defaultShadowStrength: CGFloat = 0.4

    var cornerRadius: CGFloat = 16
    var shadowStrength: CGFloat = defaultShadowStrength

    init(cornerRadius: CGFloat = 16, shadowStrength: CGFloat = defaultShadowStrength) {
        self.cornerRadius = cornerRadius
        self.shadowStrength = shadowStrength
    }

    init(cornerRadius: CGFloat, hasShadow: Bool) {
        self.cornerRadius = cornerRadius
        shadowStrength = hasShadow ? Self.defaultShadowStrength : 0
    }

    var hasShadow: Bool { normalizedShadowStrength > 0.001 }
    var normalizedShadowStrength: CGFloat { min(max(shadowStrength, 0), 1) }
    var shadowBlurRadius: CGFloat { hasShadow ? 6 + 16 * normalizedShadowStrength : 0 }
    var shadowOffsetY: CGFloat { hasShadow ? -(1 + 4 * normalizedShadowStrength) : 0 }
    var shadowPadding: CGFloat { hasShadow ? 6 + 24 * normalizedShadowStrength : 0 }
    var shadowOpacity: CGFloat { hasShadow ? 0.10 + 0.32 * normalizedShadowStrength : 0 }
    var previewShadowOpacity: CGFloat { hasShadow ? 0.16 + 0.52 * normalizedShadowStrength : 0 }
    var previewShadowFillOpacity: CGFloat { hasShadow ? 0.08 + 0.213 * normalizedShadowStrength : 0 }
}
