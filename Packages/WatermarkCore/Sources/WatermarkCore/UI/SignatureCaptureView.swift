import CoreImage
import SwiftUI
#if canImport(UIKit)
import PencilKit
import UIKit
#endif
import WatermarkCore

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
    @State private var inkColor: Color = .black
    @State private var strokeWidth: CGFloat = 3.0
    @State private var showCaptureSheet = false
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    public init(viewModel: ViewModel) {
        self.viewModel = viewModel
    }

    public var body: some View {
        VStack(spacing: 0) {
            // Section header
            Text("Signature")
                .markepiTypography(.sectionHeader)
                .padding(.horizontal, 16)
                .padding(.bottom, 8)

            // Row container with glass backing
            VStack(spacing: 0) {
                if hasSignatureLayer {
                    signatureSelectedView
                } else {
                    addSignatureButton
                }
            }
            .markepiGlass(
                shape: RoundedRectangle(cornerRadius: 12, style: .continuous),
                isEnabled: !reduceTransparency
            )
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .padding(.horizontal, 16)
        }
        .sheet(isPresented: $showCaptureSheet) {
            signatureCaptureSheet
        }
    }

    // MARK: - Layer Detection

    private var hasSignatureLayer: Bool {
        viewModel.config.watermarks.contains { layer in
            if case .signature = layer { return true }
            return false
        }
    }

    private var signatureLayerIndex: Int? {
        viewModel.config.watermarks.firstIndex { layer in
            if case .signature = layer { return true }
            return false
        }
    }

    // MARK: - Buttons

    private var addSignatureButton: some View {
        Button {
            showCaptureSheet = true
        } label: {
            Label("Add Signature", systemImage: "signature")
        }
        .buttonStyle(.markepiPrimary())
        .accessibilityLabel("Add signature watermark")
        .accessibilityHint("Open the signature capture canvas to draw your signature")
    }

    private var signatureSelectedView: some View {
        HStack {
            Image(systemName: "signature")
                .foregroundStyle(.secondary)
                .frame(width: 24)

            Text("Signature")
                .markepiTypography(.controlLabel)

            Spacer()

            Button {
                showCaptureSheet = true
            } label: {
                Label("Edit", systemImage: "pencil")
            }
            .buttonStyle(.markepiPrimary())

            Button {
                if let index = signatureLayerIndex {
                    withAnimation(.easeOut(duration: 0.25)) {
                        viewModel.removeLayer(at: index)
                    }
                }
            } label: {
                Text("Remove")
            }
            .buttonStyle(.markepiDestructive())
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    // MARK: - Capture Sheet

    private var signatureCaptureSheet: some View {
        NavigationStack {
            SignatureCanvasView(
                drawing: $drawing,
                inkColor: UIColor(inkColor),
                strokeWidth: strokeWidth
            )
            .background(Color(uiColor: .systemBackground))
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
                        viewModel.addSignatureLayer(
                            strokeData: strokeData,
                            inkColor: UIColor(inkColor).cgColor,
                            strokeWidth: strokeWidth
                        )
                        drawing = PKDrawing()
                        showCaptureSheet = false
                    }
                    .fontWeight(.semibold)
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

                    Spacer()

                    ColorPicker("", selection: $inkColor)
                        .labelsHidden()

                    HStack(spacing: 0) {
                        Button {
                            strokeWidth = max(1.0, strokeWidth - 1.0)
                        } label: {
                            Image(systemName: "minus.circle")
                        }
                        Text("\(Int(strokeWidth))pt")
                            .font(.caption.monospacedDigit())
                            .frame(width: 32)
                        Button {
                            strokeWidth = min(12.0, strokeWidth + 1.0)
                        } label: {
                            Image(systemName: "plus.circle")
                        }
                    }
                }
            }
        }
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
