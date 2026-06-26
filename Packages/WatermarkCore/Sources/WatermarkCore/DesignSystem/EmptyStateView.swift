import SwiftUI

/// A shared empty state component used across the main app and Share Extension
/// when no media is loaded.
///
/// Per D-07: Hero illustration + CTA button design replaces the old
/// ultraThinMaterial "Add Photos" pill and extension "Preparing photo..."
/// idle state.
///
/// Per D-08: One component across both targets for a consistent look. The CTA
/// button is conditionally rendered — the main app passes a closure; the Share
/// Extension passes `nil` because media is already selected.
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

    /// Optional closure triggered by the primary "Choose Photo" CTA button.
    /// When `nil`, the CTA button is not rendered (extension contexts).
    let onChoosePhoto: (() -> Void)?

    /// Optional closure for the secondary "Import from Files" CTA. When `nil`
    /// the button is omitted (extensions, or hosts without a Files importer).
    let onImportFiles: (() -> Void)?

    /// Creates an empty state view.
    ///
    /// - Parameters:
    ///   - onChoosePhoto: Closure invoked by the primary CTA. Pass `nil` in
    ///     extension contexts where no photo-picker action is needed.
    ///   - onImportFiles: Closure invoked by the secondary "Import from Files"
    ///     CTA. Pass `nil` to omit it.
    public init(
        onChoosePhoto: (() -> Void)?,
        onImportFiles: (() -> Void)? = nil
    ) {
        self.onChoosePhoto = onChoosePhoto
        self.onImportFiles = onImportFiles
    }

    public var body: some View {
        VStack(spacing: 28) {
            Spacer()

            hero

            VStack(spacing: 10) {
                Text("Add a Photo or Video")
                    .font(.title2.weight(.bold))
                    .foregroundStyle(.primary)
                Text("Add your signature watermark, frame, and caption — then export in full quality.")
                    .markepiTypography(.controlLabel)
                    .foregroundStyle(.secondary)
            }

            if onChoosePhoto != nil || onImportFiles != nil {
                VStack(spacing: 12) {
                    if let onChoosePhoto {
                        Button {
                            onChoosePhoto()
                        } label: {
                            Label("Choose Photo or Video", systemImage: "photo.on.rectangle.angled")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.markepiPrimary())
                    }
                    if let onImportFiles {
                        Button {
                            onImportFiles()
                        } label: {
                            Label("Import from Files", systemImage: "folder")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.markepiSecondary())
                    }
                }
                .padding(.horizontal, 32)
            }

            Spacer()
        }
        .multilineTextAlignment(.center)
        .padding(.horizontal, 32)
        .accessibilityElement(children: .contain)       // Group as one logical region
    }

    /// Accent-tinted hero so the empty state reads as a finished, branded
    /// surface rather than a plain gray placeholder disk on the dark canvas.
    private var hero: some View {
        ZStack {
            Circle()
                .fill(Color.accentColor.opacity(0.16))
                .frame(width: 116, height: 116)
            Image(systemName: "photo.on.rectangle.angled")
                .font(.system(size: 46, weight: .regular))
                .foregroundStyle(Color.accentColor)
                .symbolRenderingMode(.hierarchical)
        }
        .accessibilityHidden(true)
    }
}
