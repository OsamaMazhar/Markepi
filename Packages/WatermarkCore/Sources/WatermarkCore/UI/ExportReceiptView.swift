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

            if let verification = receipt.signingResult?.verification, verification.hasWarnings {
                Section("Verification") {
                    HStack(spacing: 8) {
                        Image(systemName: verification.signatureIsIntact
                              ? "checkmark.seal.fill" : "exclamationmark.seal.fill")
                            .foregroundStyle(verification.signatureIsIntact ? .green : .orange)
                        Text(verification.signatureIsIntact
                             ? "Signature is intact. Tamper detection is active."
                             : "Signature could not be verified.")
                    }
                    ForEach(verification.items) { item in
                        HStack(alignment: .firstTextBaseline, spacing: 6) {
                            Image(systemName: item.code.contains("untrusted")
                                  ? "info.circle" : "exclamationmark.triangle")
                                .foregroundStyle(.secondary)
                                .font(.footnote)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(item.code).font(.caption).monospaced().foregroundStyle(.secondary)
                                Text(item.explanation).font(.footnote)
                            }
                        }
                    }
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
