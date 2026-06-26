import Foundation

/// User-facing copy for batch C2PA signing limits.
///
/// C2PA signing is image-only in this build. Videos should continue exporting
/// without C2PA signatures and without being counted as signing failures.
public struct BatchC2PASigningDisclosure: Equatable, Sendable {
    public let signableImageCount: Int
    public let videoCount: Int

    public init(signableImageCount: Int, videoCount: Int) {
        self.signableImageCount = max(0, signableImageCount)
        self.videoCount = max(0, videoCount)
    }

    public var hasVideos: Bool {
        videoCount > 0
    }

    public var hasSignableImages: Bool {
        signableImageCount > 0
    }

    public var confirmationButtonTitle: String {
        if hasVideos && hasSignableImages {
            return "OK, Sign Images"
        }
        if hasVideos {
            return "OK, Continue"
        }
        return "Sign now"
    }

    public var alertContinueButtonTitle: String {
        hasSignableImages ? "OK, Sign Images" : "OK, Continue"
    }

    public var moreSectionText: String {
        if hasSignableImages {
            return "Batch signing is image-only in this version. Markepi will sign \(signableImageDescription) and keep exporting \(videoDescription) without C2PA signatures."
        }
        return "Batch signing is image-only in this version. This batch has \(videoDescription) and no images to sign."
    }

    public var sheetText: String {
        if hasSignableImages {
            return "This batch includes \(signableImageDescription) and \(videoDescription). Markepi will sign images only."
        }
        return "This batch includes \(videoDescription) and no images. C2PA signing is not available for videos in this version."
    }

    public var alertMessage: String {
        if hasSignableImages {
            return "Content Credentials signing is image-only in this version. This batch has \(signableImageDescription) and \(videoDescription). Markepi will sign the image exports and continue watermarking/exporting videos without C2PA signatures. Videos will not be treated as signing errors."
        }
        return "Content Credentials signing is image-only in this version. This batch has \(videoDescription) and no images. Markepi can continue watermarking/exporting videos without C2PA signatures."
    }

    private var signableImageDescription: String {
        "\(signableImageCount) \(signableImageCount == 1 ? "image" : "images")"
    }

    private var videoDescription: String {
        "\(videoCount) \(videoCount == 1 ? "video" : "videos")"
    }
}
