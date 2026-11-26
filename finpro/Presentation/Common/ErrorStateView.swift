//
//  ErrorStateView.swift
//  finpro
//
//  Full-screen error with an optional action, using the wording from UserFacingError.
//  Owner: Zildjian Vito (ZV-14).
//

import SwiftUI

struct ErrorStateView: View {
    let error: UserFacingError
    var actionTitle: String?
    var action: (() -> Void)?
    var secondaryActionTitle: String?
    var secondaryAction: (() -> Void)?

    init(error: UserFacingError, actionTitle: String? = nil, action: (() -> Void)? = nil) {
        self.error = error
        self.actionTitle = actionTitle
        self.action = action
        self.secondaryActionTitle = nil
        self.secondaryAction = nil
    }

    init(error: UserFacingError,
         actionTitle: String,
         action: @escaping () -> Void,
         secondaryActionTitle: String,
         secondaryAction: @escaping () -> Void) {
        self.error = error
        self.actionTitle = actionTitle
        self.action = action
        self.secondaryActionTitle = secondaryActionTitle
        self.secondaryAction = secondaryAction
    }

    var body: some View {
        ContentUnavailableView {
            Label(error.title, systemImage: error.systemImage)
        } description: {
            Text(error.message)
        } actions: {
            if let actionTitle, let action {
                VStack(spacing: AppSpacing.small) {
                    Button(actionTitle, action: action)
                        .buttonStyle(.borderedProminent)
                    if let secondaryActionTitle, let secondaryAction {
                        Button(secondaryActionTitle, action: secondaryAction)
                            .buttonStyle(.borderless)
                    }
                }
            }
        }
    }
}

#Preview {
    ErrorStateView(error: .permissionDenied([.camera, .microphone]), actionTitle: "Open Settings") {}
}
