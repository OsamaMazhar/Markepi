import Foundation

/// How a countdown the user is watching is put into words.
///
/// One place for it because three screens show one — the batch overlay, the
/// batch button, and the single video banner — and they had drifted into
/// saying different things about the same number. The worst of it was
/// `Int(eta / 60) min`, which spends the whole of a short batch saying
/// "0 min".
public enum TimeRemaining {

    /// A short phrase for `seconds` remaining, or what to say when there is no
    /// estimate yet.
    ///
    /// Deliberately vague at the edges. A countdown that claims "37 sec left"
    /// is read as a promise and is wrong a second later; rounding to a step
    /// the eye cannot check makes it honest and steadier to look at.
    public static func phrase(_ seconds: TimeInterval?) -> String {
        guard let seconds, seconds.isFinite, seconds > 0 else { return "Estimating…" }
        switch seconds {
        case ..<4:
            return "Almost done"
        case ..<60:
            // To the next 5 seconds, so the label does not flicker every tick.
            let step = max(5, (seconds / 5).rounded(.up) * 5)
            return "About \(Int(step)) sec left"
        case ..<90:
            return "About a minute left"
        default:
            return "About \(Int((seconds / 60).rounded())) min left"
        }
    }
}
