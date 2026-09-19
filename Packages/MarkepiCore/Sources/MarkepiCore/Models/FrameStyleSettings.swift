import CoreGraphics

// Per-style frame settings: every read and write of a frame style's settings
// goes through here, so the style dropdown, the style strip and the settings
// rows cannot disagree about what "switch style" and "edit" mean.
public extension WatermarkConfiguration {

    /// The frame settings for `style`.
    ///
    /// The style on screen answers with `whiteFrame` itself; a style the user
    /// has visited and left answers with what they left; a style nobody has
    /// visited inherits the current settings, so a strip of style previews
    /// shows the user's own border, caption and mark in every frame rather than
    /// four sets of factory defaults.
    func frameConfig(for style: FrameStyle) -> WhiteFrameConfig {
        let active = whiteFrame ?? WhiteFrameConfig(isEnabled: true)
        if active.style == style { return active }

        var resolved = frameStylePresets[style.rawValue] ?? Self.restyled(active, to: style)
        // Whether there is a frame at all is one switch for the whole feature,
        // never a per-style memory: without this, turning the frame off and
        // then changing style would turn it back on.
        resolved.isEnabled = active.isEnabled
        resolved.style = style
        return resolved
    }

    /// Switches the style on screen, remembering the one being left.
    mutating func selectFrameStyle(_ style: FrameStyle) {
        let active = whiteFrame ?? WhiteFrameConfig(isEnabled: true)
        guard active.style != style else { return }
        frameStylePresets[active.style.rawValue] = active
        whiteFrame = frameConfig(for: style)
    }

    /// Applies a frame edit, to the style on screen or to every style.
    ///
    /// The style itself is not editable this way — it is chosen with
    /// `selectFrameStyle`, which has to remember what it is leaving.
    mutating func editFrame(_ transform: (inout WhiteFrameConfig) -> Void) {
        var frame = whiteFrame ?? WhiteFrameConfig(isEnabled: true)
        let active = frame.style

        // The other styles are transformed from their own state *before* the
        // active one changes. Derived afterwards, a style nobody has visited
        // would inherit the already-edited config and take the edit twice —
        // which for anything that toggles means it lands back where it started.
        var others: [String: WhiteFrameConfig] = [:]
        if applyFrameEditsToAllStyles {
            for style in FrameStyle.allCases where style != active {
                var other = frameConfig(for: style)
                transform(&other)
                other.style = style
                others[style.rawValue] = other
            }
        }

        transform(&frame)
        frame.style = active
        whiteFrame = frame

        // `isEnabled` is the feature's own switch, so it follows the active
        // frame into every remembered style whether or not the edit was meant
        // for all of them.
        for key in frameStylePresets.keys {
            frameStylePresets[key]?.isEnabled = frame.isEnabled
        }
        for (key, value) in others { frameStylePresets[key] = value }
    }

    /// `config` wearing another style, with the caption size following along
    /// when the user has not set one of their own.
    ///
    /// Classic's caption sits inside the border and gallery's in a band three
    /// times as thick, so the same millimetre value reads very differently in
    /// each; a size the user actually chose is never touched.
    private static func restyled(_ config: WhiteFrameConfig, to style: FrameStyle) -> WhiteFrameConfig {
        // Only the style changes. A size the user never set follows the style
        // and the mat on its own, and one they did set is theirs to keep —
        // this used to infer the difference by comparing against the default,
        // which the config now simply knows.
        var out = config
        out.style = style
        return out
    }
}
