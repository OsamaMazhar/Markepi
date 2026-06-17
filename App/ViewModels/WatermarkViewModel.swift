import CoreImage
import Foundation
import Observation
import PhotosUI
import SwiftUI
import UIKit
import WatermarkCore

@Observable @MainActor
final class WatermarkViewModel {
    var selectedItems: [PhotosPickerItem] = []
    var photos: [PhotoItem] = []
    var currentIndex: Int = 0
    var config = WatermarkConfiguration(watermarks: [
        .text(
            TextWatermarkInput(text: "", fontSize: 48, color: CGColor(gray: 1, alpha: 1), opacity: 1.0),
            position: .bottomRight,
            scale: 0.15
        )
    ])

    var previewImage: UIImage?
    var isGeneratingPreview: Bool = false

    var renderingState: RenderingState = .idle
    var fullResResult: ProcessingResult?
    var showPicker: Bool = false
    var showShareSheet: Bool = false
    var showCancelAlert: Bool = false
    var errorMessage: String?
    var showError: Bool = false

    private let engine = WatermarkEngine.shared

    var currentPhoto: PhotoItem? {
        guard !photos.isEmpty, currentIndex >= 0, currentIndex < photos.count else { return nil }
        return photos[currentIndex]
    }

    var hasMultiplePhotos: Bool { photos.count > 1 }

    var previewIdentifier: String {
        let textLayer = config.watermarks.first
        let text: String
        let position: String
        let scale: String
        if case .text(let input, let pos, let scl) = textLayer {
            text = input.text
            position = pos.rawValue
            scale = String(format: "%.2f", scl)
        } else {
            text = ""
            position = WatermarkPosition.bottomRight.rawValue
            scale = "0.15"
        }
        let wf = config.whiteFrame?.isEnabled == true ? "1" : "0"
        return "\(currentIndex)-t:\(text)-pos:\(position)-s:\(scale)-wf:\(wf)"
    }

    func handleSelection(_ items: [PhotosPickerItem]) {
        Task {
            var loaded: [PhotoItem] = []
            for item in items {
                if let data = try? await item.loadTransferable(type: Data.self) {
                    let thumb = createThumbnail(from: data, maxPixelSize: 200)
                    let sourceURL = await copyToTemp(data: data)
                    loaded.append(PhotoItem(
                        id: UUID(),
                        thumbnail: thumb,
                        sourceURL: sourceURL
                    ))
                }
            }
            photos = loaded
            currentIndex = 0
            showPicker = false
        }
    }

    func goToNext() {
        guard currentIndex < photos.count - 1 else { return }
        currentIndex += 1
    }

    func goToPrev() {
        guard currentIndex > 0 else { return }
        currentIndex -= 1
    }

    func generatePreview() async {
        guard let sourceURL = currentPhoto?.sourceURL else { return }
        isGeneratingPreview = true
        defer { isGeneratingPreview = false }

        try? await Task.sleep(for: .milliseconds(350))
        guard !Task.isCancelled else { return }

        let result = try? await engine.process(sourceURL: sourceURL, config: config)
        if let url = result?.url,
           let data = try? Data(contentsOf: url),
           let uiImage = UIImage(data: data) {
            previewImage = uiImage
        }
    }

    func renderAndPrepareShare() async {
        guard let sourceURL = currentPhoto?.sourceURL else { return }
        renderingState = .rendering

        do {
            let result = try await engine.process(sourceURL: sourceURL, config: config)
            fullResResult = result
            renderingState = .done
            if let url = result.url,
               let data = try? Data(contentsOf: url),
               let uiImage = UIImage(data: data) {
                previewImage = uiImage
            }
        } catch {
            renderingState = .error(error)
            errorMessage = error.localizedDescription
            showError = true
        }
    }

    func presentShareSheet() {
        guard renderingState == .done else { return }
        showShareSheet = true
    }

    func cleanupTempFile() {
        if let url = fullResResult?.url {
            try? TempFileManager.cleanup(url: url)
        }
        fullResResult = nil
        renderingState = .idle
    }

    func requestCancel() {
        showCancelAlert = true
    }

    func confirmCancel() {
        photos = []
        currentIndex = 0
        fullResResult = nil
        renderingState = .idle
        showPicker = true
    }

    private func copyToTemp(data: Data) async -> URL {
        let tempDir = FileManager.default.temporaryDirectory
        let filename = "photo_\(UUID().uuidString).jpg"
        let url = tempDir.appendingPathComponent(filename)
        try? data.write(to: url)
        return url
    }
}

private func createThumbnail(from data: Data, maxPixelSize: CGFloat) -> UIImage? {
    let options = [
        kCGImageSourceCreateThumbnailFromImageAlways: true,
        kCGImageSourceCreateThumbnailWithTransform: true,
        kCGImageSourceThumbnailMaxPixelSize: maxPixelSize
    ] as CFDictionary
    guard let source = CGImageSourceCreateWithData(data as CFData, nil),
          let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, options) else {
        return nil
    }
    return UIImage(cgImage: cgImage)
}
