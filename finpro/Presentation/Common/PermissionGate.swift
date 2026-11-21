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
    private let content: () -> Content

    init(_ permissions: [MediaPermission], provider: any MediaPermissionProviding,
         @ViewBuilder content: @escaping () -> Content) {
        _model = State(initialValue: PermissionGateModel(permissions: permissions, provider: provider))
        self.content = content
    }

    var body: some View {
        Group {
            switch model.state {
            case .checking:
                LoadingMascotView()
            case .granted:
                content()
            case .needsRequest:
                // The system prompts appear over this; nothing of our own to read or tap.
                Color.clear
                    .task { await model.requestMissing() }
            case .denied(let missing):
                ErrorStateView(error: .permissionDenied(missing), actionTitle: "Open Settings") {
                    if let url = URL(string: UIApplication.openSettingsURLString) {
                        UIApplication.shared.open(url)
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
