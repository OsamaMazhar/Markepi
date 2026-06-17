import CoreImage
import Foundation
import Observation
import PhotosUI
import SwiftUI
import UIKit
import WatermarkCore

@Observable @MainActor
final class WatermarkViewModel: WatermarkConfigurable {
    var selectedItems: [PhotosPickerItem] = []
    var photos: [PhotoItem] = []
    var currentIndex: Int = 0
    var config = WatermarkConfiguration(watermarks: [
        .text(
            TextWatermarkInput(text: "", fontSize: 48, color: CGColor(gray: 1, alpha: 1), opacity: 1.0),
            position: .bottomRight,
            scale: 0.15
        )
    ]) {
        didSet { AppGroupConfigSync.save(config) }
    }

    var previewImage: UIImage?
    var isGeneratingPreview: Bool = false

    var renderingState: RenderingState = .idle
    var fullResResult: ProcessingResult?
    var showPicker: Bool = false
    var showShareSheet: Bool = false
    var showCancelAlert: Bool = false
    var errorMessage: String?
    var showError: Bool = false

    var activeLayerIndex: Int = 0

    private let engine = WatermarkEngine.shared

    // MARK: - Init

    override init() {
        // Load saved config from App Group if available (D-08 bidirectional sync)
        if let saved = AppGroupConfigSync.load() {
            config = saved
        }
    }

    var currentPhoto: PhotoItem? {
        guard !photos.isEmpty, currentIndex >= 0, currentIndex < photos.count else { return nil }
        return photos[currentIndex]
    }

    var hasMultiplePhotos: Bool { photos.count > 1 }

    var previewIdentifier: String {
        var parts: [String] = ["\(currentIndex)"]
        for layer in config.watermarks {
            switch layer {
            case .text(let input, let pos, let scl):
                parts.append("t:\(input.text)-pos:\(pos.rawValue)-s:\(String(format: "%.3f", scl))")
            case .image(let input, let pos, let scl):
                parts.append("im:\(input.pngData.hashValue)-pos:\(pos.rawValue)-s:\(String(format: "%.3f", scl))")
            }
        }
        parts.append("wf:\(config.whiteFrame?.isEnabled == true ? "1" : "0")")
        return parts.joined(separator: "-")
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

    func addLogoLayer(pngData: Data) {
        guard let _ = CIImage(data: pngData) else {
            errorMessage = "The selected image is not a valid PNG file."
            showError = true
            return
        }
        guard let input = try? ImageWatermarkInput(pngData: pngData) else {
            errorMessage = "The selected image is not a valid PNG file."
            showError = true
            return
        }
        config.watermarks.append(.image(input, position: .bottomRight, scale: 0.15))
        activeLayerIndex = config.watermarks.count - 1
    }

    func removeLayer(at index: Int) {
        guard index >= 0, index < config.watermarks.count else { return }
        config.watermarks.remove(at: index)
        if activeLayerIndex >= config.watermarks.count {
            activeLayerIndex = max(0, config.watermarks.count - 1)
        }
    }

    func updateLayerPosition(at index: Int, position: WatermarkPosition) {
        guard index >= 0, index < config.watermarks.count else { return }
        let scale = config.watermarks[index].scale
        switch config.watermarks[index] {
        case .text(let input, _, _):
            config.watermarks[index] = .text(input, position: position, scale: scale)
        case .image(let input, _, _):
            config.watermarks[index] = .image(input, position: position, scale: scale)
        }
    }

    func updateLayerScale(at index: Int, scale scaleInput: CGFloat) {
        guard index >= 0, index < config.watermarks.count else { return }
        let clamped = min(max(scaleInput, 0.01), 0.90)
        let position = config.watermarks[index].position
        switch config.watermarks[index] {
        case .text(let input, _, _):
            config.watermarks[index] = .text(input, position: position, scale: clamped)
        case .image(let input, _, _):
            config.watermarks[index] = .image(input, position: position, scale: clamped)
        }
    }

    func toggleWhiteFrame() {
        if config.whiteFrame?.isEnabled == true {
            config.whiteFrame = nil
        } else {
            config.whiteFrame = WhiteFrameConfig(isEnabled: true)
        }
    }

    var whiteFrameEnabled: Bool {
        config.whiteFrame?.isEnabled ?? false
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
