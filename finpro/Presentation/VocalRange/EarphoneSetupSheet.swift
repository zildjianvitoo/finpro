//
//  EarphoneSetupSheet.swift
//  finpro
//
//  "Get your setup ready" (Sketch 3rd Iteration 1.5), shown as a sheet over the warm-up when
//  sound still goes to the phone's speaker: the app needs earphones to hear the voice apart from
//  the song. It closes on its own once earphones are connected.
//

import SwiftUI

struct EarphoneSetupSheet: View {
    let onDismiss: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Get your setup ready.")
                .font(.appTitle1).fontWeight(.bold)
                .foregroundStyle(Color.primaryBrand)
                .accessibilityAddTraits(.isHeader)
            Text("Use wired earphones or headphones for more synchronized audio. Bluetooth may cause recording delays.")
                .font(.appBody).foregroundStyle(Color.primary300)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, AppSpacing.small)
            RoundedRectangle(cornerRadius: AppRadius.medium)
                .fill(Color.primaryButton)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(.top, AppSpacing.section)
                .accessibilityLabel("Illustration placeholder")
            Button("Got It", action: onDismiss)
                .buttonStyle(.appPrimary)
                .padding(.top, AppSpacing.section)
        }
        .padding(.horizontal, AppSpacing.large)
        .padding(.top, AppSpacing.spacious)
        .padding(.bottom, AppSpacing.regular)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Color.screenBackground)
        .presentationDragIndicator(.visible)
    }
}

#Preview {
    Color.clear.sheet(isPresented: .constant(true)) { EarphoneSetupSheet {} }
}
