import SwiftUI
import WatermarkCore

/// A single row in the template list showing a 48x48pt preview thumbnail,
/// template name, creation date, and a default star badge.
///
/// Uses the same HStack row pattern as `LayerListView.layerRow`.
struct TemplateRowView: View {
    let template: Template
    let sourceURL: URL?

    var body: some View {
        HStack(spacing: 12) {
            TemplatePreviewThumbnail(template: template, sourceURL: sourceURL)

            VStack(alignment: .leading, spacing: 4) {
                Text(template.name)
                    .font(.body)
                    .lineLimit(1)

                Text(template.createdAt, style: .date)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            if template.isDefault {
                Image(systemName: "star.fill")
                    .foregroundStyle(.yellow)
                    .font(.caption)
                    .accessibilityLabel("Default template")
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }
}
