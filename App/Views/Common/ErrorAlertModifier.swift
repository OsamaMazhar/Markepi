import SwiftUI

struct ErrorAlertModifier: ViewModifier {
    @Binding var errorMessage: String?
    @Binding var isPresented: Bool

    func body(content: Content) -> some View {
        content
            .alert("Rendering Error", isPresented: $isPresented) {
                Button("OK") {
                    errorMessage = nil
                }
            } message: {
                Text(errorMessage ?? "Unknown error")
            }
    }
}
