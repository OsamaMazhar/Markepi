import SwiftUI

struct AsyncButton<Label: View>: View {
    let action: () async -> Void
    @ViewBuilder let label: () -> Label

    @State private var isPerformingTask = false

    var body: some View {
        Button {
            guard !isPerformingTask else { return }
            Task {
                isPerformingTask = true
                await action()
                isPerformingTask = false
            }
        } label: {
            HStack(spacing: 8) {
                if isPerformingTask {
                    ProgressView().controlSize(.small)
                }
                label()
            }
        }
        .disabled(isPerformingTask)
    }
}
