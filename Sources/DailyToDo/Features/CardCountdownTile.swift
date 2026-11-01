import SwiftUI
import TodoDomain

/// Large day counts get their own line so they cannot compress the event title.
struct CardCountdownTile: View {
    @Environment(\.colorSchemeContrast) private var contrast
    let event: CountdownEvent
    let today: LocalDate
    private var days: Int { event.days(from: today) }
    private var stacked: Bool { abs(days) >= 10000 }
    var body: some View {
        let layout = stacked ? AnyLayout(VStackLayout(alignment: .leading, spacing: 12)) : AnyLayout(HStackLayout(alignment: .center, spacing: 12))
        layout {
            VStack(alignment: .leading, spacing: 7) {
                Text(event.title).font(.callout.weight(.semibold)).lineLimit(2)
                Text(event.targetDay.description).font(.caption2).foregroundStyle(.secondary).monospacedDigit()
            }.frame(maxWidth: .infinity, alignment: .leading)
            if stacked {
                HStack(alignment: .firstTextBaseline, spacing: 6) { number; unit }.foregroundStyle(days < 0 ? .secondary : Color.accentColor)
            } else {
                VStack(alignment: .trailing, spacing: 2) { number; unit }.foregroundStyle(days < 0 ? .secondary : Color.accentColor)
            }
        }.padding(14).frame(maxWidth: .infinity, minHeight: 82, alignment: .leading)
            .background(.primary.opacity(0.045), in: RoundedRectangle(cornerRadius: 16))
            .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(.primary.opacity(contrast == .increased ? 0.5 : 0.055), lineWidth: contrast == .increased ? 1.5 : 1))
    }
    private var number: some View {
        Text(days == 0 ? "今天" : abs(days).formatted()).font(.system(size: days == 0 ? 22 : 30, weight: .light, design: .rounded)).monospacedDigit().lineLimit(1).minimumScaleFactor(0.75).fixedSize(horizontal: !stacked, vertical: false)
    }
    @ViewBuilder private var unit: some View { if days != 0 { Text(days < 0 ? "天前" : "天后").font(.caption2).foregroundStyle(.secondary) } }
}
