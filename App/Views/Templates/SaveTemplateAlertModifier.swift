import SwiftUI

/// A reusable alert modifier for saving the current watermark configuration
/// as a named template.
///
/// Usage:
/// ```swift
/// someView
///     .saveTemplateAlert(isPresented: $showAlert) { name in
///         viewModel.saveTemplate(named: name)
///     }
/// ```
struct SaveTemplateAlertModifier: ViewModifier {
    @Binding var isPresented: Bool
    let onSave: (String) -> Void

    @State private var templateName = ""

    func body(content: Content) -> some View {
        content
            .alert("Save Template", isPresented: $isPresented) {
                TextField("Template name", text: $templateName)
                Button("Save") {
                    let trimmed = templateName.trimmingCharacters(in: .whitespaces)
                    if !trimmed.isEmpty {
                        onSave(trimmed)
                        templateName = ""
                    }
                }
                Button("Cancel", role: .cancel) {
                    templateName = ""
                }
            } message: {
                Text("Enter a name for this template.")
            }
    }
}

extension View {
    /// Attaches a save-template alert to the view.
    ///
    /// - Parameters:
    ///   - isPresented: Binding controlling alert visibility
    ///   - onSave: Closure called with the trimmed template name when Save is tapped
    func saveTemplateAlert(
        isPresented: Binding<Bool>,
        onSave: @escaping (String) -> Void
    ) -> some View {
        modifier(SaveTemplateAlertModifier(isPresented: isPresented, onSave: onSave))
    }
}
