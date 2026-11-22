//
//  PermissionGate.swift
//  finpro
//
//  Shows `content` only when the given permissions are granted. Permissions not asked yet are
//  asked straight away with the system prompts (their reasons are in Info.plist), without a
//  page of our own first; a refused permission shows how to turn it on in Settings.
//  Owner: Zildjian Vito (ZV-14).
//
//  Usage (in RootView, so feature screens never deal with permissions):
//      PermissionGate([.camera, .microphone], provider: container.permissions) { RecordingView() }
//

import SwiftUI
import UIKit

struct PermissionGate<Content: View>: View {
    @State private var model: PermissionGateModel
    @Environment(\.scenePhase) private var scenePhase
    private let content: (Bool) -> Content

    init(_ permissions: [MediaPermission], provider: any MediaPermissionProviding,
         @ViewBuilder content: @escaping (_ isGranted: Bool) -> Content) {
        _model = State(initialValue: PermissionGateModel(permissions: permissions, provider: provider))
        self.content = content
    }

    init(_ permissions: [MediaPermission], provider: any MediaPermissionProviding,
         @ViewBuilder content: @escaping () -> Content) {
        self.init(permissions, provider: provider) { _ in content() }
    }

    var body: some View {
        Group {
            if case .denied(let missing) = model.state {
                ErrorStateView(error: .permissionDenied(missing), actionTitle: "Open Settings") {
                    if let url = URL(string: UIApplication.openSettingsURLString) {
                        UIApplication.shared.open(url)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color.screenBackground.ignoresSafeArea())
            } else {
                // Keep the feature screen visible behind system permission prompts instead of a
                // blank white screen, preserving view identity once granted.
                let isGranted = model.state == .granted
                content(isGranted)
                    .allowsHitTesting(isGranted)
                    .task(id: model.state) {
                        if case .needsRequest = model.state {
                            await model.requestMissing()
                        }
                    }
            }
        }
        .onAppear { model.refresh() }
        // Coming back from Settings.
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { model.refresh() }
        }
    }
}

#if DEBUG
#Preview("Needs request") {
    PermissionGate([.camera, .microphone],
                   provider: FakeMediaPermissions(statuses: [.camera: .notDetermined, .microphone: .notDetermined])) {
        Text("Recording")
    }
}

#Preview("Denied") {
    PermissionGate([.camera, .microphone], provider: FakeMediaPermissions(statuses: [.microphone: .denied])) {
        Text("Recording")
    }
}
#endif
