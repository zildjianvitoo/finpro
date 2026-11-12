//
//  DesignSystemGalleryView.swift
//  finpro
//
//  Debug-only page that shows every design system token and component, to compare the app with
//  the Sketch page "Design System". Open it with the launch argument `-startScreen designSystem`.
//

#if DEBUG
import SwiftUI

struct DesignSystemGalleryView: View {
    private let primaryRamp: [(String, Color)] = [
        ("100", .primary100), ("200", .primary200), ("300", .primary300), ("400", .primary400),
        ("500", .primary500), ("600", .primary600), ("700", .primary700), ("800", .primary800),
    ]
    private let secondaryRamp: [(String, Color)] = [
        ("100", .secondary100), ("200", .secondary200), ("300", .secondary300), ("400", .secondary400),
        ("500", .secondary500), ("600", .secondary600), ("700", .secondary700), ("800", .secondary800),
    ]
    private let semantic: [(String, Color)] = [
        ("PrimaryBrand", .primaryBrand), ("SecBrand", .secBrand), ("PrimaryDark", .primaryDark),
        ("SmallButton", .smallButton), ("PrimaryButton", .primaryButton), ("SelectedButton", .selectedButton),
        ("SecondaryButton", .secondaryButton), ("ScreenBackground", .screenBackground), ("BodyText", .bodyText),
        ("SecText", .secText), ("SecondaryText", .secondaryText), ("TertiaryText", .tertiaryText),
    ]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                ramp("Primary Color", primaryRamp)
                ramp("Secondary Color", secondaryRamp)
                semanticList
                typography
                radii
                buttons
            }
            .padding(16)
        }
        .background(Color.screenBackground)
    }

    private func ramp(_ title: String, _ colors: [(String, Color)]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.appHeadline).foregroundStyle(Color.bodyText)
            HStack(spacing: 0) {
                ForEach(colors, id: \.0) { _, color in
                    Rectangle().fill(color).frame(height: 44)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: AppRadius.small))
            HStack(spacing: 0) {
                ForEach(colors, id: \.0) { _, color in
                    Text(hex(of: color)).font(.system(size: 8).monospaced()).frame(maxWidth: .infinity)
                }
            }
            .foregroundStyle(Color.secondaryText)
        }
    }

    private var semanticList: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Semantic Colors").font(.appHeadline).foregroundStyle(Color.bodyText)
            ForEach(semantic, id: \.0) { name, color in
                HStack(spacing: 12) {
                    RoundedRectangle(cornerRadius: 6).fill(color).frame(width: 28, height: 28)
                        .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.primary200, lineWidth: 0.5))
                    Text(name).font(.appSubheadline).foregroundStyle(Color.bodyText)
                    Spacer()
                    Text(hex(of: color)).font(.appCaption.monospaced()).foregroundStyle(Color.secondaryText)
                }
            }
        }
    }

    private var typography: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Typography Scale").font(.appHeadline).foregroundStyle(Color.bodyText)
            Group {
                Text("Large Title / Bold / 34").font(.appLargeTitle)
                Text("Title 1 / SemiBold / 28").font(.appTitle1)
                Text("Title 2 / SemiBold / 22").font(.appTitle2)
                Text("Title 3 / Regular / 20").font(.appTitle3)
                Text("Headline / SemiBold / 17").font(.appHeadline)
                Text("Body / Regular / 17").font(.appBody)
                Text("Subheadline / Regular / 15").font(.appSubheadline)
                Text("Footnote / Regular / 13").font(.appFootnote)
                Text("Caption / Regular / 12").font(.appCaption)
                Text("Caption 2 / Regular / 11").font(.appCaption2)
                Text("Button / CTA / SemiBold / 17").font(.appCTA)
            }
            .foregroundStyle(Color.bodyText)
        }
    }

    private var radii: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Corner Radius").font(.appHeadline).foregroundStyle(Color.bodyText)
            HStack(spacing: 16) {
                radius("Large / 20", AppRadius.large, .primaryBrand)
                radius("Medium / 16", AppRadius.medium, .secondaryButton)
                radius("Small / 12", AppRadius.small, .secondaryButton)
            }
        }
    }

    private func radius(_ title: String, _ value: CGFloat, _ color: Color) -> some View {
        VStack(spacing: 4) {
            RoundedRectangle(cornerRadius: value).fill(color).frame(width: 80, height: 80)
            Text(title).font(.appCaption).foregroundStyle(Color.secondaryText)
        }
    }

    private var buttons: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Button").font(.appHeadline).foregroundStyle(Color.bodyText)
            Button("Get started") {}.buttonStyle(.appPrimary)
            Button("Continue") {}.buttonStyle(.appPrimary).disabled(true)
            Button("Skip") {}.buttonStyle(.appAccent)
            HStack(spacing: 16) {
                Button { } label: { Image(systemName: "xmark") }.buttonStyle(.appIcon(.primary))
                Button { } label: { Image(systemName: "xmark") }.buttonStyle(.appIcon(.secondary))
                Button { } label: { Image(systemName: "xmark") }.buttonStyle(.appIcon(.tinted))
            }
        }
    }

    /// The color as it resolves in the current appearance, e.g. `#6A1E55`.
    private func hex(of color: Color) -> String {
        let resolved = UIColor(color).resolvedColor(with: UITraitCollection.current)
        var red: CGFloat = 0, green: CGFloat = 0, blue: CGFloat = 0, alpha: CGFloat = 0
        resolved.getRed(&red, green: &green, blue: &blue, alpha: &alpha)
        return String(format: "#%02X%02X%02X", Int((red * 255).rounded()), Int((green * 255).rounded()), Int((blue * 255).rounded()))
    }
}

#Preview {
    DesignSystemGalleryView()
}
#endif
