import SwiftUI

public struct ExportReceiptView: View {
    public let receipt: ExportReceipt

    public init(receipt: ExportReceipt) { self.receipt = receipt }

    public var body: some View {
        List {
            Section("Source") {
                LabeledContent("State", value: receipt.report.state.displayLabel)
                ForEach(receipt.report.evidence) { e in
                    LabeledContent(e.source, value: e.summary)
                }
                if receipt.report.userDeclaration != .none {
                    LabeledContent("Declared by user",
                                   value: receipt.report.userDeclaration.rawValue)
                }
            }
            Section("Records added") {
                LabeledContent("Content Credentials", value: signingText)
                if receipt.signingResult?.status == .signed, let s = receipt.signingResult {
                    Text("Signed with \(s.displayName). This is a device signing identity, "
                         + "not a verified legal identity.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
            }
            if !(receipt.signingResult?.warnings.isEmpty ?? true) {
                Section("Notes") {
                    ForEach(receipt.signingResult?.warnings ?? [], id: \.self) { Text($0) }
                }
            }
        }
    }

    private var signingText: String {
        switch receipt.signingResult?.status {
        case .signed:       return "Signed"
        case .notSigned:    return "Not signed"
        case .notSupported: return "Not supported for this format"
        case .none:         return "Not signed"
        }
    }
}
