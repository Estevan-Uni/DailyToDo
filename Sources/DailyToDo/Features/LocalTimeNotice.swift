import SwiftUI
import TodoDomain

enum LocalTimePresentation {
    static func detail(_ value: LocalTimeResolution) -> String {
        switch value.kind {
        case .exact: return ""
        case .advanced: return "\(value.requestedTimeLabel) 在当天不存在，解析为 \(value.resolvedTimeLabel)（\(LocalTimeResolution.offsetLabel(value.utcOffset))）。"
        case .repeated:
            return "当天有两次 \(value.requestedTimeLabel)，采用第一次（\(LocalTimeResolution.offsetLabel(value.utcOffset))）；第二次为 \(LocalTimeResolution.offsetLabel(value.alternativeUTCOffset!))，不会重复执行。"
        }
    }
    static func detail(day: LocalDate, minute: Int, timeZone: TimeZone) -> String {
        guard minute != ScheduledTime.unspecified else { return "" }
        return (try? day.resolveTime(minute: minute, timeZone: timeZone)).map(detail) ?? "该日期与时间在当前时区无法解析，请选择其他时刻。"
    }
}

struct LocalTimeNotice: View {
    @Environment(\.timeZone) private var timeZone
    let day: LocalDate
    let minute: Int
    var body: some View {
        let detail = LocalTimePresentation.detail(day: day, minute: minute, timeZone: timeZone)
        if !detail.isEmpty { Text(detail).font(.caption2).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true) }
    }
}
