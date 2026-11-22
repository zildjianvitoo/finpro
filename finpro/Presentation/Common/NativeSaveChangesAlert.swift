//
//  NativeSaveChangesAlert.swift
//  finpro
//
//  Reusable 2-button "Save Changes?" system alert with a native iOS blue primary "Save" button
//  (instead of the app's plum AccentColor) for leaving unsaved edits on fresh takes and drafts.
//

import SwiftUI
import UIKit

struct NativeSaveChangesAlert: ViewModifier {
    @Binding var isPresented: Bool
    let title: String
    let message: String
    let cancelTitle: String
    let saveTitle: String
    let onCancel: () -> Void
    let onSave: () -> Void

    @State private var activeAlert: UIAlertController?

    func body(content: Content) -> some View {
        content
            .onChange(of: isPresented) { _, presented in
                if presented {
                    presentIfNeeded()
                } else if let alert = activeAlert {
                    activeAlert = nil
                    alert.dismiss(animated: true)
                }
            }
            .onDisappear {
                if let alert = activeAlert {
                    activeAlert = nil
                    alert.dismiss(animated: false)
                }
            }
    }

    private func presentIfNeeded() {
        guard activeAlert == nil else { return }
        let window = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)
            .first { $0.isKeyWindow }
        var top = window?.rootViewController
        while let presented = top?.presentedViewController { top = presented }
        guard let presenter = top else {
            isPresented = false
            return
        }
        let alert = UIAlertController(title: title, message: message, preferredStyle: .alert)
        alert.view.tintColor = .systemBlue
        let cancel = UIAlertAction(title: cancelTitle, style: .cancel) { _ in
            activeAlert = nil
            isPresented = false
            onCancel()
        }
        let save = UIAlertAction(title: saveTitle, style: .default) { _ in
            activeAlert = nil
            isPresented = false
            onSave()
        }
        alert.addAction(cancel)
        alert.addAction(save)
        alert.preferredAction = save
        activeAlert = alert
        presenter.present(alert, animated: true)
    }
}

extension View {
    /// Presents the reusable native iOS blue 2-button "Save Changes?" alert.
    func saveChangesAlert(
        isPresented: Binding<Bool>,
        title: String = "Save Changes?",
        message: String = "Your edits haven't been saved. Would you like to save them before leaving?",
        cancelTitle: String = "Cancel",
        saveTitle: String = "Save",
        onCancel: @escaping () -> Void,
        onSave: @escaping () -> Void
    ) -> some View {
        modifier(NativeSaveChangesAlert(
            isPresented: isPresented,
            title: title,
            message: message,
            cancelTitle: cancelTitle,
            saveTitle: saveTitle,
            onCancel: onCancel,
            onSave: onSave
        ))
    }
}
