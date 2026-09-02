// iOS-only UI. Guarded so WatermarkCore also builds for macOS, where the
// `markepi` CLI target links the engine without the SwiftUI layer.
#if canImport(UIKit)
import CoreImage
import SwiftUI
#if canImport(UIKit)
import PencilKit
import UIKit
#endif

/// Full-screen signature capture view with a PencilKit canvas wrapped
/// in UIViewRepresentable for finger/Apple Pencil drawing.
///
/// Generic over any `WatermarkConfigurable & Observable` ViewModel,
/// following the same pattern as LogoPickerView.
///
/// - Note: On non-UIKit platforms (macOS), a stub view is provided that
///   shows a "not available" message. Signature capture requires UIKit
///   and PencilKit.
#if canImport(UIKit)
public struct SignatureCaptureView<ViewModel: WatermarkConfigurable & Observable>: View {
    @Bindable var viewModel: ViewModel
    @State private var drawing = PKDrawing()
    @State private var showCaptureSheet = false
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    /// Whether to render the built-in section header. Hidden when the host
    /// already provides a single title (editor tool panel); shown when the view
    /// stands alone as a labeled section (extensions' ControlsView).
    private let showsSectionHeader: Bool

    public init(viewModel: ViewModel, showsSectionHeader: Bool = true) {
        self.viewModel = viewModel
        self.showsSectionHeader = showsSectionHeader
    }

    public var body: some View {
        VStack(spacing: 0) {
            // Section header
            if showsSectionHeader {
                Text("Signature")
                    .markepiTypography(.sectionHeader)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 16)
                    .padding(.bottom, 8)
            }

            if hasSignatureLayer {
                // The populated state is a multi-row card → glass backing fits.
                signatureSelectedView
                    .markepiGlass(
                        shape: RoundedRectangle(cornerRadius: 12, style: .continuous),
                        isEnabled: !reduceTransparency
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .padding(.horizontal, 16)
            } else {
                // Empty state is a single capsule button — no surrounding card,
                // so the button's own shape isn't fighting a rounded-rect.
                addSignatureButton
                    .padding(.horizontal, 16)
            }
        }
        .sheet(isPresented: $showCaptureSheet) {
            signatureCaptureSheet
        }
    }

    // MARK: - Layer Detection

    private var hasSignatureLayer: Bool { signatureLayerIndex != nil }

    private var signatureLayerIndex: Int? {
        viewModel.config.watermarks.firstIndex { layer in
            if case .signature = layer { return true }
            return false
        }
    }

    private var signatureInput: SignatureInput? {
        guard let index = signatureLayerIndex,
              case .signature(let input, _, _, _, _) = viewModel.config.watermarks[index] else { return nil }
        return input
    }

    // MARK: - Buttons

    private var addSignatureButton: some View {
        Button {
            startNewSignature()
        } label: {
            Label("Add Signature", systemImage: "signature")
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
        }
        .buttonStyle(.markepiPrimary())
        .accessibilityLabel("Add signature watermark")
        .accessibilityHint("Open the signature capture canvas to draw your signature")
    }

    /// Persistent controls for an existing signature: edit/remove plus LIVE
    /// thickness and ink-color adjustment that update the preview immediately.
    @ViewBuilder
    private var signatureSelectedView: some View {
        if let index = signatureLayerIndex {
            VStack(spacing: 0) {
                HStack {
                    Image(systemName: "signature")
                        .foregroundStyle(.secondary)
                        .frame(width: 24)
                    Text("Signature")
                        .markepiTypography(.controlLabel)
                        // Never let the label break mid-word into "Sig-na-ture"
                        // when the row is tight (narrow landscape panel); keep it
                        // one line and let the Spacer absorb the slack instead.
                        .lineLimit(1)
                        .fixedSize(horizontal: true, vertical: false)
                    Spacer(minLength: 8)
                    Button {
                        startEditingSignature()
                    } label: {
                        Label("Edit", systemImage: "pencil")
                            .lineLimit(1)
                            .fixedSize(horizontal: true, vertical: false)
                    }
                    .buttonStyle(.markepiPrimary())
                    .fixedSize(horizontal: true, vertical: false)

                    Button {
                        withAnimation(.easeOut(duration: 0.25)) {
                            viewModel.removeLayer(at: index)
                        }
                    } label: {
                        Text("Remove")
                            .lineLimit(1)
                            .fixedSize(horizontal: true, vertical: false)
                    }
                    .buttonStyle(.markepiDestructive())
                    .fixedSize(horizontal: true, vertical: false)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)

                Divider().padding(.leading, 16)

                // LIVE thickness — the user asked to "press thick/thin and see it
                // immediately"; this rescales the rendered strokes on every change.
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("Thickness")
                            .markepiTypography(.controlLabel)
                        Spacer()
                        Text("\(Int(thicknessBinding(index).wrappedValue.rounded()))")
                            .markepiTypography(.value)
                            .monospacedDigit()
                    }
                    HStack(spacing: 12) {
                        Button {
                            thicknessBinding(index).wrappedValue = max(1, thicknessBinding(index).wrappedValue - 1)
                        } label: { Image(systemName: "minus.circle.fill").font(.title3) }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Thinner")

                        Slider(value: thicknessBinding(index), in: 1...12, step: 1)
                            .accessibilityLabel("Signature thickness")

                        Button {
                            thicknessBinding(index).wrappedValue = min(12, thicknessBinding(index).wrappedValue + 1)
                        } label: { Image(systemName: "plus.circle.fill").font(.title3) }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Thicker")
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)

                Divider().padding(.leading, 16)

                HStack {
                    Text("Ink Color")
                        .markepiTypography(.controlLabel)
                    Spacer()
                    ColorPicker("", selection: inkColorBinding(index), supportsOpacity: false)
                        .labelsHidden()
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .accessibilityElement(children: .combine)
                .accessibilityLabel("Signature ink color")
            }
        }
    }

    // MARK: - Live Bindings (existing signature)

    private func thicknessBinding(_ index: Int) -> Binding<Double> {
        Binding(
            get: { Double(signatureInput?.strokeWidth ?? SignatureRenderer.referenceStrokeWidth) },
            set: { viewModel.updateSignature(at: index, inkColor: nil, strokeWidth: CGFloat($0)) }
        )
    }

    private func inkColorBinding(_ index: Int) -> Binding<Color> {
        Binding(
            get: { signatureInput.map { Color(cgColor: $0.inkColor) } ?? .black },
            set: { viewModel.updateSignature(at: index, inkColor: Self.cgColor(from: $0), strokeWidth: nil) }
        )
    }

    // MARK: - Capture / Edit Entry Points

    private func startNewSignature() {
        drawing = PKDrawing()
        showCaptureSheet = true
    }

    /// Opens the canvas pre-loaded with the existing signature so it can be
    /// touched up instead of starting blank (the previous behaviour discarded
    /// the saved drawing on every Edit).
    private func startEditingSignature() {
        if let data = signatureInput?.strokeData, let existing = try? PKDrawing(data: data) {
            drawing = existing
        } else {
            drawing = PKDrawing()
        }
        showCaptureSheet = true
    }

    // MARK: - Capture Sheet

    private var signatureCaptureSheet: some View {
        NavigationStack {
            SignatureCanvasView(
                drawing: $drawing,
                // Always draw in black on a white "paper" canvas so the
                // signature is visible while drawing. The rendered watermark
                // color is independent of this: SignatureRenderer re-tints the
                // stroke *alpha* with the layer's `inkColor`, so the drawing
                // color here never reaches the output. (Previously this used
                // the same color as the saved inkColor — coupling the two made
                // a white default render as invisible white-on-light strokes.)
                inkColor: .black,
                // Capture at a fixed reference width so geometry is consistent;
                // display thickness is a live, post-capture render multiplier.
                strokeWidth: SignatureRenderer.referenceStrokeWidth
            )
            .background(Color.white)
            .navigationTitle("Draw Signature")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") {
                        drawing = PKDrawing()
                        showCaptureSheet = false
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Save") {
                        let strokeData = drawing.dataRepresentation()
                        // Preserve the current thickness and ink color when
                        // editing; default a brand-new signature to fixed
                        // black ink, independent of the current appearance.
                        let width = signatureInput?.strokeWidth ?? 5
                        let inkColor = signatureInput?.inkColor ?? CGColor(gray: 0, alpha: 1)
                        viewModel.addSignatureLayer(
                            strokeData: strokeData,
                            inkColor: inkColor,
                            strokeWidth: width
                        )
                        drawing = PKDrawing()
                        showCaptureSheet = false
                    }
                    .fontWeight(.semibold)
                    .disabled(drawing.strokes.isEmpty)
                }
                ToolbarItemGroup(placement: .bottomBar) {
                    Button {
                        let strokes = drawing.strokes
                        drawing = strokes.dropLast().isEmpty
                            ? PKDrawing()
                            : PKDrawing(strokes: Array(strokes.dropLast()))
                    } label: {
                        Image(systemName: "arrow.uturn.backward")
                    }
                    .disabled(drawing.strokes.isEmpty)

                    Spacer()

                    Button(role: .destructive) {
                        drawing = PKDrawing()
                    } label: {
                        Text("Clear")
                    }
                    .disabled(drawing.strokes.isEmpty)
                }
            }
        }
    }

    /// Converts a SwiftUI `Color` to a `CGColor`.
    private static func cgColor(from color: Color) -> CGColor {
        UIColor(color).cgColor
    }
}

// MARK: - PencilKit Canvas UIViewRepresentable

/// Wraps PKCanvasView as a UIViewRepresentable for SwiftUI integration.
///
/// Provides a transparent drawing canvas with configurable ink color
/// and stroke width, supporting both finger and Apple Pencil input.
struct SignatureCanvasView: UIViewRepresentable {
    @Binding var drawing: PKDrawing
    var inkColor: UIColor
    var strokeWidth: CGFloat

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeUIView(context: Context) -> PKCanvasView {
        let canvas = PKCanvasView()
        canvas.drawingPolicy = .anyInput
        canvas.tool = PKInkingTool(.pen, color: inkColor, width: strokeWidth)
        canvas.backgroundColor = .clear
        canvas.isOpaque = false
        canvas.overrideUserInterfaceStyle = .light
        canvas.delegate = context.coordinator
        return canvas
    }

    func updateUIView(_ uiView: PKCanvasView, context: Context) {
        uiView.tool = PKInkingTool(.pen, color: inkColor, width: strokeWidth)
        if uiView.drawing != drawing {
            uiView.drawing = drawing
        }
    }

    class Coordinator: NSObject, PKCanvasViewDelegate {
        var parent: SignatureCanvasView

        init(_ parent: SignatureCanvasView) {
            self.parent = parent
        }

        func canvasViewDrawingDidChange(_ canvasView: PKCanvasView) {
            parent.drawing = canvasView.drawing
        }
    }
}

#else
// MARK: - Non-UIKit Stub

public struct SignatureCaptureView<ViewModel: WatermarkConfigurable & Observable>: View {
    @Bindable var viewModel: ViewModel
    @State private var showCaptureSheet = false
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    public init(viewModel: ViewModel) {
        self.viewModel = viewModel
    }

    public var body: some View {
        VStack(spacing: 0) {
            Text("Signature")
                .markepiTypography(.sectionHeader)
                .padding(.horizontal, 16)
                .padding(.bottom, 8)

            VStack(spacing: 0) {
                Button {
                    showCaptureSheet = true
                } label: {
                    Label("Add Signature", systemImage: "signature")
                }
                .buttonStyle(.markepiPrimary())
                .disabled(true)
            }
            .markepiGlass(
                shape: RoundedRectangle(cornerRadius: 12, style: .continuous),
                isEnabled: !reduceTransparency
            )
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .padding(.horizontal, 16)
        }
        .sheet(isPresented: $showCaptureSheet) {
            VStack(spacing: 16) {
                Image(systemName: "pencil.tip.crop.circle.badge.xmark")
                    .font(.system(size: 48))
                    .foregroundStyle(.secondary)
                Text("Signature capture is not available on this platform.")
                    .font(.body)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
                Button("Close") {
                    showCaptureSheet = false
                }
                .buttonStyle(.markepiSecondary())
            }
            .padding()
        }
    }
}
#endif
#endif
