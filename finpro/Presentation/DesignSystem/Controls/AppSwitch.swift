//
//  AppSwitch.swift
//  finpro
//
//  On/off switch of the Settings sheet in the design: a grey track with a white knob that
//  carries the words "On" or "Off" (the system's "On/Off Labels" look).
//

import SwiftUI

struct AppSwitch: View {
    @Binding var isOn: Bool

    private let trackSize = CGSize(width: 94, height: 34)
    private let knobWidth: CGFloat = 54

    var body: some View {
        Button {
            withAnimation(.snappy) { isOn.toggle() }
        } label: {
            ZStack(alignment: isOn ? .trailing : .leading) {
                Capsule().fill(Color(red: 0x3C / 255, green: 0x3C / 255, blue: 0x43 / 255).opacity(0.3))
                Text(isOn ? "On" : "Off")
                    .font(.appSubheadline.weight(.semibold))
                    .foregroundStyle(Color(white: 0.1))
                    .frame(width: knobWidth, height: trackSize.height)
                    .background(Capsule().fill(.white))
            }
            .frame(width: trackSize.width, height: trackSize.height)
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(.isToggle)
        .accessibilityValue(isOn ? "On" : "Off")
    }
}
