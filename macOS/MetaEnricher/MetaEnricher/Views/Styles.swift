import SwiftUI

// MARK: - App Colors

extension Color {
    /// Warm amber — the app's brand color. Use instead of Color.appAmber.
    static let appAmber = Color("AccentColor")
}

// MARK: - Inspector Field Modifier

/// Styled text field for the inspector panel:
/// visible background, subtle border, accent-colored focus ring.
struct InspectorFieldModifier: ViewModifier {
    @FocusState private var isFocused: Bool

    func body(content: Content) -> some View {
        content
            .focused($isFocused)
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(.fill.quaternary, in: RoundedRectangle(cornerRadius: 6))
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .strokeBorder(
                        isFocused ? Color.appAmber : Color.primary.opacity(0.08),
                        lineWidth: isFocused ? 1 : 0.5
                    )
                    .animation(.easeInOut(duration: 0.15), value: isFocused)
            )
    }
}

extension View {
    func inspectorField() -> some View {
        modifier(InspectorFieldModifier())
    }
}

// MARK: - Enrichment Scan Overlay

/// Animated scan-line + pulsing border overlay shown during AI enrichment.
/// Replaces the boring spinner with a "scanning your photo" effect.
struct EnrichmentScanOverlay: View {
    @State private var scanOffset: CGFloat = -0.1
    @State private var borderOpacity: Double = 0.2

    var body: some View {
        GeometryReader { geo in
            Rectangle()
                .fill(Color.appAmber.opacity(0.5))
                .frame(height: 2)
                .blur(radius: 8)
                .offset(y: geo.size.height * scanOffset)
        }
        .clipped()
        .overlay {
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(Color.appAmber.opacity(borderOpacity), lineWidth: 1.5)
        }
        .allowsHitTesting(false)
        .onAppear {
            withAnimation(.linear(duration: 2.0).repeatForever(autoreverses: false)) {
                scanOffset = 1.1
            }
            withAnimation(.easeInOut(duration: 1.0).repeatForever(autoreverses: true)) {
                borderOpacity = 0.6
            }
        }
    }
}
