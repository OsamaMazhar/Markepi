import SwiftUI

/// A shared empty state component used across the main app, Share Extension,
/// and Photos Edit Extension when no media is loaded.
///
/// Per D-07: Hero illustration + CTA button design replaces the old
/// ultraThinMaterial "Add Photos" pill and extension "Preparing photo..."
/// idle state.
///
/// Per D-08: One component, 3 targets, consistent look. The CTA button
/// is conditionally rendered — main app passes a closure; extensions pass
/// `nil` since media is already selected from the share sheet or Photos app.
///
/// Per D-10 content recipe:
/// - Large SF Symbol (`photo.on.rectangle.angled`, 40pt) in a glass circle
/// - Headline: "Add a Photo" — `.sectionHeader` typography
/// - Body: "Choose a photo or video to watermark and share instantly" — `.controlLabel`, secondary
/// - CTA: Markepi primary button "Choose Photo" (only when `onChoosePhoto != nil`)
///
/// Per Pitfall 4: Reduce Transparency gate on the glass circle via
/// `@Environment(\.accessibilityReduceTransparency)`.
public struct EmptyStateView: View {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    /// Optional closure triggered by the "Choose Photo" CTA button.
    /// When `nil`, the CTA button is not rendered (extension contexts).
    let onChoosePhoto: (() -> Void)?

    /// Creates an empty state view.
    ///
    /// - Parameter onChoosePhoto: Closure invoked when the CTA button is tapped.
    ///   Pass `nil` for extension contexts where no photo-picker action is needed.
    public init(onChoosePhoto: (() -> Void)?) {
        self.onChoosePhoto = onChoosePhoto
    }

    public var body: some View {
        VStack(spacing: 24) {
            Spacer()

            // Glass circle with SF Symbol (D-10)
            Image(systemName: "photo.on.rectangle.angled")
                .font(.system(size: 40))
                .foregroundStyle(.secondary)
                .frame(width: 80, height: 80)
                .markepiGlass(
                    shape: Circle(),
                    isEnabled: !reduceTransparency  // Reduce Transparency gate (Pitfall 4)
                )

            VStack(spacing: 8) {
                Text("Add a Photo")                    // D-10 headline
                    .markepiTypography(.sectionHeader)
                Text("Choose a photo or video to watermark and share instantly")  // D-10 body
                    .markepiTypography(.controlLabel)
                    .foregroundStyle(.secondary)
            }

            if let onChoosePhoto {                     // CTA: only in main app
                Button {
                    onChoosePhoto()
                } label: {
                    Label("Choose Photo", systemImage: "photo.on.rectangle.angled")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.markepiPrimary())        // D-10: Markepi primary button
                .padding(.horizontal, 40)
            }

            Spacer()
        }
        .multilineTextAlignment(.center)
        .padding(.horizontal, 32)
        .accessibilityElement(children: .contain)       // Group as one logical region
    }
}
