import SwiftUI
import WatermarkCore

// MARK: - SheetDetent

/// The two detents for the inspector bottom sheet (D-01).
///
/// - `peek`: Pill bar + drag indicator only (~60pt).
/// - `expanded`: Full ControlsView content (~half screen height).
public enum SheetDetent: Equatable {
    case peek
    case expanded
}

// MARK: - InspectorSheetView

/// A custom ZStack-compatible bottom sheet container that hosts `ControlsView`
/// unchanged inside a Liquid Glass surface with a drag-to-resize indicator
/// and spring-animated detent snapping (D-01, D-02, D-04, D-09, D-10, D-11,
/// D-14, D-15).
///
/// Generic over any `WatermarkConfigurable & Observable` ViewModel so the
/// main app can instantiate it with `WatermarkViewModel`.
///
/// The detent is owned by the parent (e.g., `ContentView`) via `@Binding`,
/// and the drag gesture on the indicator capsule drives detent transitions.
///
/// Usage:
/// ```swift
/// @State private var detent: SheetDetent = .peek
/// InspectorSheetView(
///     detent: $detent,
///     peekHeight: 60,
///     viewModel: viewModel
/// )
/// ```
public struct InspectorSheetView<ViewModel: WatermarkConfigurable & Observable>: View {

    // MARK: - Properties

    /// The current detent — owned by the parent view (ContentView).
    @Binding var detent: SheetDetent

    /// The height of the sheet at the peek detent (~60pt).
    public let peekHeight: CGFloat

    /// The ViewModel driving ControlsView.
    @State var viewModel: ViewModel

    /// Live drag offset during gesture (not animated).
    @State private var dragOffset: CGFloat = 0

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    // MARK: - Init

    public init(
        detent: Binding<SheetDetent>,
        peekHeight: CGFloat,
        viewModel: ViewModel
    ) {
        self._detent = detent
        self.peekHeight = peekHeight
        self.viewModel = viewModel
    }

    // MARK: - Body

    public var body: some View {
        VStack(spacing: 0) {
            // D-10: Standard iOS drag indicator — 36pt × 5pt capsule
            RoundedRectangle(cornerRadius: 2.5)
                .fill(Color.secondary.opacity(0.4))
                .frame(width: 36, height: 5)
                .padding(.top, 8)
                .padding(.bottom, 4)
                .accessibilityLabel("Resize controls")
                .accessibilityHint("Drag up to show all controls, down to minimize")

            // D-14: ControlsView completely unchanged
            ControlsView(viewModel: viewModel)
        }
        .frame(maxWidth: .infinity)
        .frame(height: sheetHeight)
        .background {
            // D-09: Liquid Glass surface with iOS 26 native glass or iOS 18 material fallback.
            // D-11: Standard iOS sheet corners — 20pt rounded top, 0pt square bottom.
            let sheetShape = UnevenRoundedRectangle(
                topLeadingRadius: 20,
                bottomLeadingRadius: 0,
                bottomTrailingRadius: 0,
                topTrailingRadius: 20,
                style: .continuous
            )
            sheetShape
                .fill(.clear)
                .markepiGlass(
                    shape: sheetShape,
                    isEnabled: !reduceTransparency
                )
        }
        .clipShape(
            UnevenRoundedRectangle(
                topLeadingRadius: 20,
                bottomLeadingRadius: 0,
                bottomTrailingRadius: 0,
                topTrailingRadius: 20,
                style: .continuous
            )
        )
        .animation(
            reduceMotion ? nil : .spring(response: 0.4, dampingFraction: 0.85),
            value: detent
        )
    }

    // MARK: - Computed Properties

    /// The current height of the sheet based on detent and live drag offset.
    ///
    /// Clamped to never drop below `peekHeight` (D-04: not dismissible).
    /// The expanded height is a placeholder (~300pt) — Task 2 makes this
    /// dynamic via the `expandedHeight` parameter passed from the parent.
    private var sheetHeight: CGFloat {
        let base = detent == .peek ? peekHeight : 300
        return max(peekHeight, base + dragOffset)
    }
}
