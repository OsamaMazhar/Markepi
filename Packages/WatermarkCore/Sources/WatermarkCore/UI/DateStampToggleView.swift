// iOS-only UI. Guarded so WatermarkCore also builds for macOS, where the
// `markepi` CLI target links the engine without the SwiftUI layer.
#if canImport(UIKit)
import SwiftUI

/// Retro date-stamp controls: an enable toggle plus, when enabled, a date
/// format picker and a size slider. Mirrors the classic film-camera databack —
/// an amber, softly glowing date burned into the corner of the photo or video.
///
/// Generic over any `WatermarkConfigurable & Observable` ViewModel so the main
/// app and the extensions can all reuse it.
public struct DateStampToggleView<ViewModel: WatermarkConfigurable & Observable>: View {
    @Bindable var viewModel: ViewModel

    public init(viewModel: ViewModel) {
        self.viewModel = viewModel
    }

    public var body: some View {
        // Read the observable value in `body` so SwiftUI tracks enable/disable.
        let isEnabled = viewModel.config.dateStamp?.isEnabled ?? false

        VStack(spacing: 0) {
            Toggle(isOn: Binding(
                get: { isEnabled },
                set: { setEnabled($0) }
            )) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Retro Date Stamp")
                        .markepiTypography(.controlLabel)
                    Text("Adds an old-style orange film-camera date")
                        .markepiTypography(.metadata)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .accessibilityLabel("Retro date stamp")
            .accessibilityHint("Stamps the capture date on your photo in a vintage orange style")

            if isEnabled {
                Divider().padding(.leading, 16)
                formatRow
                Divider().padding(.leading, 16)
                positionRow
                Divider().padding(.leading, 16)
                sizeRow
            }
        }
    }

    // MARK: - Rows

    private var formatRow: some View {
        HStack {
            Text("Format")
                .markepiTypography(.controlLabel)
            Spacer()
            Menu {
                ForEach(DateStampFormat.allCases) { format in
                    Button {
                        mutate { $0.format = format }
                    } label: {
                        if currentFormat == format {
                            Label(format.displayName, systemImage: "checkmark")
                        } else {
                            Text(format.displayName)
                        }
                    }
                }
            } label: {
                HStack(spacing: 4) {
                    Text(currentFormat.displayName)
                        .markepiTypography(.value)
                        .monospaced()
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.secondary)
                }
            }
            .accessibilityLabel("Date format, currently \(currentFormat.displayName)")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    private var positionRow: some View {
        HStack {
            Text("Position")
                .markepiTypography(.controlLabel)
            Spacer()
            Picker("Position", selection: Binding(
                get: { currentPosition },
                set: { newValue in mutate { $0.position = newValue } }
            )) {
                Text("Lower Left").tag(WatermarkPosition.bottomLeft)
                Text("Lower Right").tag(WatermarkPosition.bottomRight)
            }
            .pickerStyle(.segmented)
            .fixedSize()
            .accessibilityLabel("Date stamp position, currently \(currentPosition.displayName)")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    private var sizeRow: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Font Size")
                    .markepiTypography(.controlLabel)
                Spacer()
                Text("\(String(format: "%.1f", sizeBinding.wrappedValue * 100))%")
                    .markepiTypography(.value)
                    .monospacedDigit()
            }
            // Digit height as a fraction of the image's shorter dimension.
            Slider(value: sizeBinding, in: 0.015...0.12)
                .accessibilityLabel("Date stamp font size")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    // MARK: - State helpers

    private var currentFormat: DateStampFormat {
        viewModel.config.dateStamp?.format ?? .dayMonthYear
    }

    private var currentPosition: WatermarkPosition {
        viewModel.config.dateStamp?.position ?? .bottomLeft
    }

    /// Enables/disables the stamp, creating a default config the first time it's
    /// switched on and clearing it when switched off (parity with white frame).
    private func setEnabled(_ enabled: Bool) {
        if enabled {
            if viewModel.config.dateStamp == nil {
                viewModel.config.dateStamp = DateStampConfig(isEnabled: true)
            } else {
                viewModel.config.dateStamp?.isEnabled = true
            }
        } else {
            viewModel.config.dateStamp?.isEnabled = false
        }
    }

    /// Mutates the stamp config, creating an enabled one if absent so a control
    /// never silently no-ops.
    private func mutate(_ transform: (inout DateStampConfig) -> Void) {
        var stamp = viewModel.config.dateStamp ?? DateStampConfig(isEnabled: true)
        transform(&stamp)
        viewModel.config.dateStamp = stamp
    }

    private var sizeBinding: Binding<CGFloat> {
        Binding(
            get: { viewModel.config.dateStamp?.sizeRatio ?? DateStampConfig.defaultSizeRatio },
            set: { newValue in mutate { $0.sizeRatio = newValue } }
        )
    }
}
#endif
