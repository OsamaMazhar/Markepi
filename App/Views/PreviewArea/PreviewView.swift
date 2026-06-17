import SwiftUI

struct PreviewView: View {
    @Bindable var viewModel: WatermarkViewModel

    var body: some View {
        Group {
            if let preview = viewModel.previewImage {
                Image(uiImage: preview)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .drawingGroup()
                    .overlay {
                        if viewModel.isGeneratingPreview {
                            Color.black.opacity(0.4)
                            ProgressView()
                                .tint(.white)
                        }
                    }
            } else if viewModel.currentPhoto != nil {
                if let thumbnail = viewModel.currentPhoto?.thumbnail {
                    Image(uiImage: thumbnail)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .overlay {
                            ProgressView()
                        }
                } else {
                    ProgressView()
                }
            } else {
                pickerButton
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .edgesIgnoringSafeArea(.top)
    }

    private var pickerButton: some View {
        Button {
            viewModel.showPicker = true
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "photo.on.rectangle.angled")
                    .font(.system(size: 24, weight: .regular))
                Text("Add Photos")
                    .font(.body.weight(.semibold))
            }
            .foregroundStyle(.white)
            .frame(width: 200, height: 56)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 28))
        }
    }
}
