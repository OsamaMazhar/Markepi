import CoreGraphics

/// Every proportion the gallery frame is built from, in one place.
///
/// The defaults are measured from the reference card rather than chosen by
/// eye. That card was 1290x1669 with a 40px mat, a 125px caption band, a
/// 1210x1506 photo, caption text about 26px, a 58x68 brand mark, and a mat
/// that graded from white at the top to mid grey at the bottom. The ratios
/// below encode those measurements, so the look is retuned here rather than by
/// hunting constants through the renderer.
///
/// Ratios rather than pixels, because the gallery style is measured in
/// millimetres: a proportion survives any resolution or border size, a pixel
/// count does not.
public struct FrameMetrics: Sendable, Equatable {

    // MARK: Band

    /// Caption band height ÷ mat thickness. Measured: 125 ÷ 40.
    public var bandToBorder: CGFloat

    // MARK: Type

    /// Default caption text size ÷ mat thickness. Measured: ~26 ÷ 40.
    ///
    /// This sets the *default* for the user's millimetre text setting; once
    /// they change it, it is their number that counts.
    public var captionToBorder: CGFloat

    /// Baseline-to-baseline ÷ font size. Measured: ~36 ÷ 26.
    public var linePitchToFont: CGFloat

    /// Share of the pitch that is the gap between the lines, the rest being
    /// the line box itself.
    public var interlineShareOfPitch: CGFloat

    // MARK: Mark

    /// Default mark height ÷ mat thickness.
    public var markToBorder: CGFloat

    /// Hard ceiling on mark width, as a share of the band. Wordmarks run to
    /// about 10:1, and without this a wide one crowds out the caption.
    public var markMaxWidthOfBand: CGFloat

    // MARK: Spacing

    /// Gap either side of the divider, and between the mark and the divider,
    /// ÷ font size.
    public var columnGapToFont: CGFloat

    /// Divider rule width ÷ font size.
    public var dividerWidthToFont: CGFloat

    /// Divider height ÷ the height of the text block beside it.
    public var dividerHeightToBlock: CGFloat

    // MARK: Ink

    /// Keyline thickness ÷ mat thickness. Measured: 14 ÷ 40.
    ///
    /// Of the mat, not the photo: tied to the photo it came out a hairline on
    /// small images and vanished. The reference line is heavier than it looks
    /// — better than a third of the border — which is what lets it read as a
    /// deliberate edge rather than a rendering artefact.
    public var keylineToBorder: CGFloat

    /// How far the secondary caption tone moves from the primary toward the
    /// mat. 0 is identical to the primary, 1 is invisible.
    public var secondaryToneMix: CGFloat

    /// Whether the right column's first line is emphasised the way the left's
    /// is.
    ///
    /// False in the reference: the device name is the only bold thing on the
    /// card. The handle is set in the same weight as the detail line beneath
    /// it and distinguished by tone alone, which keeps one focal point rather
    /// than two competing ones.
    public var emphasiseRightPrimary: Bool

    /// The mat's tone at the top of the card. Measured: 255/255.
    public var matTopWhite: CGFloat

    /// The mat's tone at the bottom. Measured: 166/255.
    ///
    /// The mat is a vertical gradient, not a flat fill — that shading is what
    /// stops a large pale border reading as dead space, and it is why the
    /// caption sits on a noticeably darker ground than the photo's top edge.
    public var matBottomWhite: CGFloat

    public init(
        bandToBorder: CGFloat = 3.12,
        captionToBorder: CGFloat = 0.65,
        linePitchToFont: CGFloat = 1.38,
        interlineShareOfPitch: CGFloat = 0.18,
        markToBorder: CGFloat = 1.70,
        markMaxWidthOfBand: CGFloat = 0.28,
        columnGapToFont: CGFloat = 0.80,
        dividerWidthToFont: CGFloat = 0.05,
        dividerHeightToBlock: CGFloat = 1.0,
        keylineToBorder: CGFloat = 0.35,
        secondaryToneMix: CGFloat = 0.45,
        emphasiseRightPrimary: Bool = false,
        matTopWhite: CGFloat = 1.0,
        matBottomWhite: CGFloat = 0.651
    ) {
        self.bandToBorder = bandToBorder
        self.captionToBorder = captionToBorder
        self.linePitchToFont = linePitchToFont
        self.interlineShareOfPitch = interlineShareOfPitch
        self.markToBorder = markToBorder
        self.markMaxWidthOfBand = markMaxWidthOfBand
        self.columnGapToFont = columnGapToFont
        self.dividerWidthToFont = dividerWidthToFont
        self.dividerHeightToBlock = dividerHeightToBlock
        self.keylineToBorder = keylineToBorder
        self.secondaryToneMix = secondaryToneMix
        self.emphasiseRightPrimary = emphasiseRightPrimary
        self.matTopWhite = matTopWhite
        self.matBottomWhite = matBottomWhite
    }

    /// The measured reference layout.
    public static let reference = FrameMetrics()

    // MARK: Derived defaults

    /// Default border, in millimetres. Everything else keys off it.
    ///
    /// Calibrated so a typical 12MP phone photo (3024x4032) frames with the
    /// reference card's proportions: 8mm at print resolution is ~3.3% of the
    /// photo's width, which is what the reference measures. The earlier 5mm
    /// was physically consistent but read half the reference's visual weight —
    /// the complaint that "everything is small".
    public static let defaultBorderMillimetres: CGFloat = 8.0

    /// Caption text default, in millimetres — the reference's ratio applied to
    /// the default border, so the two arrive in proportion.
    public static var defaultCaptionMillimetres: CGFloat {
        (defaultBorderMillimetres * reference.captionToBorder * 100).rounded() / 100
    }

    /// Mark height default, in millimetres.
    public static var defaultMarkMillimetres: CGFloat {
        (defaultBorderMillimetres * reference.markToBorder * 100).rounded() / 100
    }
}
