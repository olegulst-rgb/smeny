import SwiftUI
import EventKit
import UIKit

// MARK: - Модель смен (график 2-2-4, цикл 8 дней)

enum ShiftType { case day, night, off }

struct SlotInfo {
    let t: ShiftType
    let name: String
    let short: String
    let startHour: Int
    let startMinute: Int
    let endHour: Int
    let endMinute: Int
}

let slots: [SlotInfo] = [
    SlotInfo(t: .day,   name: "Дневная смена", short: "Д", startHour: 7,  startMinute: 0, endHour: 19, endMinute: 0),
    SlotInfo(t: .day,   name: "Дневная смена", short: "Д", startHour: 7,  startMinute: 0, endHour: 19, endMinute: 0),
    SlotInfo(t: .night, name: "Ночная смена",  short: "Н", startHour: 19, startMinute: 0, endHour: 7,  endMinute: 0),
    SlotInfo(t: .night, name: "Ночная смена",  short: "Н", startHour: 19, startMinute: 0, endHour: 7,  endMinute: 0),
    SlotInfo(t: .off,   name: "Выходной",      short: "В", startHour: 0,  startMinute: 0, endHour: 0,  endMinute: 0),
    SlotInfo(t: .off,   name: "Выходной",      short: "В", startHour: 0,  startMinute: 0, endHour: 0,  endMinute: 0),
    SlotInfo(t: .off,   name: "Выходной",      short: "В", startHour: 0,  startMinute: 0, endHour: 0,  endMinute: 0),
    SlotInfo(t: .off,   name: "Выходной",      short: "В", startHour: 0,  startMinute: 0, endHour: 0,  endMinute: 0)
]

let offNames = ["1-й выходной", "2-й выходной", "3-й выходной", "4-й выходной"]

private var cal: Calendar {
    var c = Calendar.current
    c.locale = Locale(identifier: "ru_RU")
    return c
}

struct Occurrence {
    let slot: Int
    let day: Date
    let start: Date
    let end: Date
}

enum ShiftModel {

    static func dayStart(_ date: Date) -> Date {
        cal.startOfDay(for: date)
    }

    static func addDays(_ date: Date, _ n: Int) -> Date {
        cal.date(byAdding: .day, value: n, to: dayStart(date)) ?? date
    }

    static func addMonths(_ date: Date, _ n: Int) -> Date {
        cal.date(byAdding: .month, value: n, to: date) ?? date
    }

    static func atTime(_ date: Date, _ h: Int, _ m: Int) -> Date {
        cal.date(bySettingHour: h, minute: m, second: 0, of: date) ?? date
    }

    /// Якорь: base = любой день с дневной сменой (yyyy-MM-dd), pos = 0 → это 1-й день цикла, 1 → 2-й.
    static func anchor(base: String, pos: Int) -> Date? {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        guard let b = f.date(from: base) else { return nil }
        return addDays(b, -pos)
    }

    static func slot(of date: Date, anchor: Date) -> Int {
        let d = cal.dateComponents([.day], from: dayStart(anchor), to: dayStart(date)).day ?? 0
        return ((d % 8) + 8) % 8
    }

    static func currentShift(now: Date, anchor: Date) -> Occurrence? {
        let t0 = dayStart(now)
        for back in [1, 0] {
            let day = addDays(t0, -back)
            let slot = slot(of: day, anchor: anchor)
            let s = slots[slot]
            if s.t == .off { continue }
            let start = atTime(day, s.startHour, s.startMinute)
            let end = s.t == .night ? atTime(addDays(day, 1), s.endHour, s.endMinute)
                                    : atTime(day, s.endHour, s.endMinute)
            if now >= start && now < end {
                return Occurrence(slot: slot, day: day, start: start, end: end)
            }
        }
        return nil
    }

    static func nextShift(from t: Date, anchor: Date) -> Occurrence? {
        let d0 = dayStart(t)
        for i in 0..<9 {
            let day = addDays(d0, i)
            let slot = slot(of: day, anchor: anchor)
            let s = slots[slot]
            if s.t == .off { continue }
            let start = atTime(day, s.startHour, s.startMinute)
            if start > t {
                let end = s.t == .night ? atTime(addDays(day, 1), s.endHour, s.endMinute)
                                        : atTime(day, s.endHour, s.endMinute)
                return Occurrence(slot: slot, day: day, start: start, end: end)
            }
        }
        return nil
    }
}

// MARK: - Форматирование

enum Fmt {

    static func plural(_ n: Int, _ one: String, _ few: String, _ many: String) -> String {
        let n10 = n % 10, n100 = n % 100
        if n10 == 1 && n100 != 11 { return one }
        if n10 >= 2 && n10 <= 4 && (n100 < 12 || n100 > 14) { return few }
        return many
    }

    static func dur(_ ti: TimeInterval) -> String {
        let t = max(0, ti)
        let totalMin = Int(t / 60.0.rounded())
        if totalMin < 60 { return "\(totalMin) мин" }
        let h = totalMin / 60, m = totalMin % 60
        if h < 24 {
            return m == 0 ? "\(h) ч" : "\(h) ч \(m) мин"
        }
        let d = h / 24, hh = h % 24
        let word = plural(d, "день", "дня", "дней")
        return hh == 0 ? "\(d) \(word)" : "\(d) \(word) \(hh) ч"
    }

    static func rel(_ target: Date, _ now: Date) -> String {
        let dt = target.timeIntervalSince(now)
        if dt <= 60 { return "скоро" }
        if dt < 3600 { return "через \(Int(ceil(dt / 60))) мин" }
        return "через " + dur(dt)
    }

    static func relDay(_ d: Date, _ now: Date) -> String {
        let n = cal.dateComponents([.day], from: ShiftModel.dayStart(now), to: ShiftModel.dayStart(d)).day ?? 0
        if n == 0 { return "сегодня" }
        if n == 1 { return "завтра" }
        if n == -1 { return "вчера" }
        return n > 0 ? "через \(n) \(plural(n, "день", "дня", "дней"))"
                     : "\(abs(n)) \(plural(abs(n), "день назад", "дня назад", "дней назад"))"
    }

    static func pad(_ v: Int) -> String { v < 10 ? "0\(v)" : "\(v)" }

    static func hhmm(_ date: Date) -> String {
        pad(cal.component(.hour, from: date)) + ":" + pad(cal.component(.minute, from: date))
    }

    static let wdLong: DateFormatter = {
        let f = DateFormatter(); f.locale = Locale(identifier: "ru_RU"); f.dateFormat = "EEEE"; return f
    }()
    static let wdShort: DateFormatter = {
        let f = DateFormatter(); f.locale = Locale(identifier: "ru_RU"); f.dateFormat = "EEE"; return f
    }()
    static let dMonth: DateFormatter = {
        let f = DateFormatter(); f.locale = Locale(identifier: "ru_RU"); f.setLocalizedDateFormatFromTemplate("dMMMM"); return f
    }()
    static let dShort: DateFormatter = {
        let f = DateFormatter(); f.locale = Locale(identifier: "ru_RU"); f.setLocalizedDateFormatFromTemplate("dMMM"); return f
    }()
    static let monthYear: DateFormatter = {
        let f = DateFormatter(); f.locale = Locale(identifier: "ru_RU"); f.setLocalizedDateFormatFromTemplate("yMMMM"); return f
    }()

    static func cap(_ s: String) -> String {
        guard let first = s.first else { return s }
        return String(first).uppercased() + s.dropFirst()
    }
}

// MARK: - Статус «сейчас»

struct Status {
    var emoji: String
    var headline: String
    var sub: String
    var hint: String
    var highlightSlot: Int
}

enum StatusBuilder {

    static func build(now: Date, anchor: Date) -> Status {
        let todaySlot = ShiftModel.slot(of: now, anchor: anchor)

        if let cur = ShiftModel.currentShift(now: now, anchor: anchor) {
            let s = slots[cur.slot]
            var sub = "\(Fmt.pad(s.startHour)):\(Fmt.pad(s.startMinute))–\(Fmt.pad(s.endHour)):\(Fmt.pad(s.endMinute)) · до конца \(Fmt.dur(cur.end.timeIntervalSince(now)))"
            if s.t == .night && !cal.isDate(cur.day, inSameDayAs: now) {
                sub += " (смена началась вчера в 19:00)"
            }
            return Status(
                emoji: s.t == .day ? "☀️" : "🌙",
                headline: "Сейчас: " + s.name.lowercased(),
                sub: sub,
                hint: "",
                highlightSlot: cur.slot)
        }

        let todayType = slots[todaySlot].t
        var out = Status(emoji: "😴", headline: "", sub: "", hint: "", highlightSlot: todaySlot)

        if let nx = ShiftModel.nextShift(from: now, anchor: anchor) {
            let s = slots[nx.slot]
            let sameDay = cal.isDate(nx.start, inSameDayAs: now)
            if sameDay {
                out.emoji = s.t == .day ? "☀️" : "🌙"
                out.headline = "Сегодня: " + s.name.lowercased() + " в " + Fmt.hhmm(nx.start)
                out.sub = "начало через " + Fmt.dur(nx.start.timeIntervalSince(now))
            } else if todayType == .day {
                out.emoji = "☀️"
                out.headline = "Смена закончилась"
                out.hint = "сегодня была дневная смена 07:00–19:00"
                out.sub = "след. смена: " + Fmt.cap(Fmt.wdShort.string(from: nx.start)) + ", " + Fmt.dShort.string(from: nx.start) +
                    " · " + s.name.lowercased() + " " + Fmt.hhmm(nx.start) + "–" + Fmt.hhmm(nx.end) + " · " +
                    Fmt.rel(nx.start, now)
            } else {
                out.emoji = "😴"
                out.headline = "Сегодня выходной"
                out.sub = "след. смена: " + Fmt.cap(Fmt.wdShort.string(from: nx.start)) + ", " + Fmt.dShort.string(from: nx.start) +
                    " · " + s.name.lowercased() + " в " + Fmt.hhmm(nx.start) + " · " + Fmt.rel(nx.start, now)
                if todayType == .off {
                    out.hint = offNames[todaySlot - 4]
                }
            }
        }
        return out
    }
}

// MARK: - Цвета

extension Color {
    static let smenyDay = Color(UIColor(red: 0.941, green: 0.639, blue: 0.184, alpha: 1))
    static let smenyNight = Color(UIColor { tc in
        tc.userInterfaceStyle == .dark
            ? UIColor(red: 0.478, green: 0.545, blue: 0.910, alpha: 1)
            : UIColor(red: 0.239, green: 0.306, blue: 0.659, alpha: 1)
    })
    static let smenyOff = Color(UIColor { tc in
        tc.userInterfaceStyle == .dark
            ? UIColor(red: 0.165, green: 0.176, blue: 0.208, alpha: 1)
            : UIColor(red: 0.894, green: 0.906, blue: 0.926, alpha: 1)
    })
    static let smenyNightText = Color(UIColor { tc in
        tc.userInterfaceStyle == .dark ? UIColor.black : UIColor.white
    })
    static let smenyDayText = Color(UIColor { tc in
        tc.userInterfaceStyle == .dark ? UIColor.black : UIColor.white
    })
}

// MARK: - Экраны

@main
struct SmenyApp: App {
    var body: some Scene {
        WindowGroup { RootView() }
    }
}

struct RootView: View {
    @AppStorage("smeny.base") private var base = ""
    @AppStorage("smeny.pos") private var pos = 0
    @AppStorage("smeny.theme") private var theme = "auto"
    @AppStorage("smeny.alarm") private var alarmMinutes = 60

    private var anchorDate: Date? {
        guard !base.isEmpty else { return nil }
        return ShiftModel.anchor(base: base, pos: pos)
    }

    var body: some View {
        Group {
            if let anchor = anchorDate {
                ContentView(anchor: anchor)
            } else {
                OnboardingView(base: $base, pos: $pos)
            }
        }
        .preferredColorScheme(scheme)
    }

    private var scheme: ColorScheme? {
        switch theme {
        case "light": return .light
        case "dark": return .dark
        default: return nil
        }
    }
}

//MARK: - Первый запуск

struct OnboardingView: View {
    @Binding var base: String
    @Binding var pos: Int
    @State private var pickedDate = Date()

    var body: some View {
        NavigationView {
            Form {
                Section {
                    Text("Это календарь смен по графику «2 дня → 2 ночи → 4 выходных» (цикл — 8 дней).")
                        .font(.subheadline)
                    Text("Нужна одна дата: **любой день, когда была дневная смена (07:00–19:00)**. Даже в прошлом.")
                        .font(.subheadline)
                }
                Section(header: Text("День с дневной сменой (07:00–19:00)")) {
                    DatePicker("Дата", selection: $pickedDate, displayedComponents: .date)
                        .labelsHidden()
                }
                Section(header: Text("Что было на следующий день?")) {
                    Picker("След. день", selection: $pos) {
                        Text("Дневная — этот день 1-й").tag(0)
                        Text("Ночная — этот день 2-й").tag(1)
                    }
                    .pickerStyle(.inline)
                    .labelsHidden()
                }
                Section {
                    Button("Готово") {
                        let df = DateFormatter()
                        df.locale = Locale(identifier: "en_US_POSIX")
                        df.dateFormat = "yyyy-MM-dd"
                        base = df.string(from: ShiftModel.dayStart(pickedDate))
                    }
                    Button("Скопировать вопрос для подруги") {
                        UIPasteboard.general.string = "Скажи, пожалуйста, какого числа у тебя была последняя дневная смена (07:00–19:00) в начале текущего цикла? И что было на следующий день — ещё дневная или ночная?"
                    }
                }
            }
            .navigationTitle("Настройка")
            .navigationBarTitleDisplayMode(.inline)
        }
        .navigationViewStyle(.stack)
    }
}

//MARK: - Основной экран

struct ContentView: View {
    let anchor: Date
    @State private var showSettings = false

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    TodaySection(anchor: anchor)
                    CalendarSection(now: Date(), anchor: anchor)
                    UpcomingSection(anchor: anchor)
                    Text("график 2–2–4 · цикл 8 дней · все данные только на телефоне")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.top, 2)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
            }
            .background(Color(uiColor: .systemGroupedBackground).ignoresSafeArea())
            .navigationTitle("Смены")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button { showSettings = true } label: { Image(systemName: "gearshape") }
                }
            }
            .sheet(isPresented: $showSettings) {
                SettingsView(anchor: anchor)
            }
        }
        .navigationViewStyle(.stack)
    }
}

//MARK: - Блок «Сегодня»

struct TodaySection: View {
    let anchor: Date

    var body: some View {
        Card {
            TimelineView(.periodic(from: .now, by: 30)) { timeline in
                TodayContent(now: timeline.date, anchor: anchor)
            }
        }
    }
}

struct TodayContent: View {
    let now: Date
    let anchor: Date

    var body: some View {
        let st = StatusBuilder.build(now: now, anchor: anchor)
        return VStack(alignment: .leading, spacing: 6) {
            Text("Сегодня — " + Fmt.cap(Fmt.wdLong.string(from: now)) + ", " + Fmt.dMonth.string(from: now))
                .font(.caption)
                .foregroundColor(.secondary)
            HStack(alignment: .top, spacing: 10) {
                Text(st.emoji).font(.title2)
                VStack(alignment: .leading, spacing: 2) {
                    Text(st.headline).font(.title3).fontWeight(.semibold)
                    Text(st.sub).font(.subheadline).foregroundColor(.secondary)
                }
            }
            if !st.hint.isEmpty {
                Text(st.hint).font(.caption).foregroundColor(.secondary)
            }
            CycleStrip(anchor: anchor, highlight: st.highlightSlot)
        }
    }
}

struct CycleStrip: View {
    let anchor: Date
    let highlight: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("Цикл · 8 дней").font(.caption2).foregroundColor(.secondary)
                Spacer()
                Text("\(highlight + 1)-й из 8").font(.caption2).foregroundColor(.secondary)
            }
            HStack(spacing: 4) {
                ForEach(0..<8, id: \.self) { i in
                    let s = slots[i]
                    ZStack {
                        Capsule()
                            .fill(colorFor(s.t))
                            .frame(maxWidth: .infinity)
                            .frame(height: 26)
                        Text(s.short)
                            .font(.system(size: 12, weight: .bold))
                            .foregroundColor(textFor(s.t))
                    }
                    .overlay(RoundedRectangle(cornerRadius: 13).stroke(Color.blue, lineWidth: i == highlight ? 2 : 0))
                }
            }
            Text("Д — дневная (07–19) · Н — ночная (19–07) · В — выходной")
                .font(.caption2).foregroundColor(.secondary)
        }
        .padding(.top, 6)
    }
}

func colorFor(_ t: ShiftType) -> Color {
    switch t {
    case .day: return .smenyDay
    case .night: return .smenyNight
    case .off: return .smenyOff
    }
}
func textFor(_ t: ShiftType) -> Color {
    switch t {
    case .day: return .smenyDayText
    case .night: return .smenyNightText
    case .off: return .secondary
    }
}

//MARK: - Карточка (контейнер)

struct Card<Content: View>: View {
    private let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        content
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Color(uiColor: .secondarySystemGroupedBackground))
            )
    }
}

//MARK: - Календарь на месяц

struct CalendarSection: View {
    let now: Date
    let anchor: Date
    @State private var month: Date
    @State private var selected: Date?

    init(now: Date, anchor: Date) {
        self.now = now
        self.anchor = anchor
        _month = State(initialValue: ShiftModel.dayStart(now))
        _selected = State(initialValue: nil)
    }

    var body: some View {
        Card {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Button { month = ShiftModel.addMonths(month, -1) } label: { Text("‹").font(.title3) }
                        .frame(width: 36)
                    Spacer()
                    Text(monthTitle).font(.headline)
                    Button { month = ShiftModel.dayStart(now); selected = nil } label: { Text("Сегодня").font(.footnote).padding(4) }
                        .opacity(isCurrent ? 0 : 1)
                    Spacer()
                    Button { month = ShiftModel.addMonths(month, 1) } label: { Text("›").font(.title3) }
                        .frame(width: 36)
                }

                HStack(spacing: 2) {
                    ForEach(["пн","вт","ср","чт","пт","сб","вс"], id: \.self) { d in
                        Text(d).font(.caption2).foregroundColor(.secondary).frame(maxWidth: .infinity)
                    }
                }

                ForEach(0..<chunked.count, id: \.self) { r in
                    HStack(spacing: 2) {
                        ForEach(0..<7, id: \.self) { c in
                            if let d = chunked[r][c] {
                                CellView(date: d, anchor: anchor, now: now, isToday: cal.isDate(d, inSameDayAs: now)) {
                                    selected = d
                                }
                            } else {
                                Color.clear.frame(height: 40)
                            }
                        }
                    }
                }

                if let sel = selected {
                    DetailRow(date: sel, anchor: anchor, now: now) { selected = nil }
                        .padding(.top, 4)
                }
            }
        }
    }

    private var monthDays: [Date] {
        let comps = cal.dateComponents([.year, .month], from: month)
        guard let first = cal.date(from: comps),
              let range = cal.range(of: .day, in: .month, for: first) else { return [] }
        return range.compactMap { cal.date(byAdding: .day, value: $0 - 1, to: first) }
    }
    private var leadCount: Int {
        guard let f = monthDays.first else { return 0 }
        let w = cal.component(.weekday, from: f) // 1 = вс … 7 = сб
        return (w + 5) % 7 // сдвиг от понедельника
    }
    private var chunked: [[Date?]] {
        var items: [Date?] = Array(repeating: nil, count: leadCount)
        items.append(contentsOf: monthDays)
        while items.count % 7 != 0 { items.append(nil) }
        var out: [[Date?]] = []
        var i = 0
        while i < items.count {
            out.append(Array(items[i..<(i + 7)]))
            i += 7
        }
        return out
    }
    private var monthTitle: String { Fmt.cap(Fmt.monthYear.string(from: month)) }
    private var isCurrent: Bool { cal.isDate(month, equalTo: now, toGranularity: .month) }
}

struct CellView: View {
    let date: Date
    let anchor: Date
    let now: Date
    let isToday: Bool
    let onTap: () -> Void

    var body: some View {
        let slot = ShiftModel.slot(of: date, anchor: anchor)
        let s = slots[slot]
        Button(action: onTap) {
            VStack(spacing: 3) {
                Text("\(cal.component(.day, from: date))")
                    .font(.caption)
                    .foregroundColor(s.t == .off ? .secondary : .primary)
                Text(s.t == .off ? "—" : chipFor(slot))
                    .font(.system(size: 9, weight: .semibold))
                    .padding(.vertical, 3)
                    .frame(maxWidth: .infinity)
                    .background(colorFor(s.t))
                    .foregroundColor(s.t == .off ? .secondary : (s.t == .day ? Color.smenyDayText : Color.smenyNightText))
                    .cornerRadius(6)
            }
            .overlay(RoundedRectangle(cornerRadius: 9).stroke(Color.blue, lineWidth: isToday ? 1.5 : 0))
            .padding(1)
        }
        .buttonStyle(.plain)
    }

    private func chipFor(_ slot: Int) -> String {
        let s = slots[slot]
        return "\(Fmt.pad(s.startHour))–\(Fmt.pad(s.endHour))"
    }
}

struct DetailData {
    let title: String
    let sub: String
}

func detailData(date: Date, anchor: Date, now: Date) -> DetailData {
    let slot = ShiftModel.slot(of: date, anchor: anchor)
    let s = slots[slot]
    if s.t == .off {
        return DetailData(title: s.name, sub: offNames[slot - 4] + " из 4")
    }
    let start = ShiftModel.atTime(date, s.startHour, s.startMinute)
    let end = s.t == .night ? ShiftModel.atTime(ShiftModel.addDays(date, 1), s.endHour, s.endMinute)
                            : ShiftModel.atTime(date, s.endHour, s.endMinute)
    let title = Fmt.cap(Fmt.wdLong.string(from: date)) + ", " + Fmt.dMonth.string(from: date) + " — " + s.name
    let sub = Fmt.hhmm(start) + " " + Fmt.dShort.string(from: start) + " → " + Fmt.hhmm(end) + " " +
        Fmt.dShort.string(from: end) + " · " + Fmt.relDay(date, now)
    return DetailData(title: title, sub: sub)
}

struct DetailRow: View {
    let date: Date
    let anchor: Date
    let now: Date
    let onClose: () -> Void

    var body: some View {
        let slot = ShiftModel.slot(of: date, anchor: anchor)
        let s = slots[slot]
        let data = detailData(date: date, anchor: anchor, now: now)
        return VStack(alignment: .leading, spacing: 3) {
            HStack {
                Text(data.title)
                    .font(.subheadline).fontWeight(.semibold)
                    .foregroundColor(s.t == .day ? .smenyDay : (s.t == .night ? .smenyNight : .secondary))
                Spacer()
                Button(action: onClose) { Image(systemName: "xmark").font(.caption).foregroundColor(.secondary) }
            }
            Text(data.sub).font(.caption).foregroundColor(.secondary)
        }
        .padding(.top, 2)
    }
}

//MARK: - Ближайшие смены

struct UpcomingSection: View {
    let anchor: Date

    struct CurrentOccurrence {
        let slot: Int
        let day: Date
        let start: Date
        let end: Date
        let isCurrent: Bool
    }

    var body: some View {
        Card {
            VStack(alignment: .leading, spacing: 10) {
                Text("Ближайшие смены").font(.headline)
                let rows = upcomingRows(Date())
                if rows.isEmpty {
                    Text("Настрой дату в ⚙️ Настройках").font(.subheadline).foregroundColor(.secondary)
                } else {
                    ForEach(0..<rows.count, id: \.self) { i in
                        UpcomingRow(o: rows[i])
                    }
                }
            }
        }
    }

    private func upcomingRows(_ now: Date) -> [CurrentOccurrence] {
        var rows: [CurrentOccurrence] = []
        if let cur = ShiftModel.currentShift(now: now, anchor: anchor) {
            rows.append(CurrentOccurrence(slot: cur.slot, day: cur.day, start: cur.start, end: cur.end, isCurrent: true))
        }
        var t = rows.isEmpty ? ShiftModel.dayStart(now) : ShiftModel.addDays(rows[0].day, 1)
        for _ in 0..<6 {
            guard let nx = ShiftModel.nextShift(from: t, anchor: anchor) else { break }
            rows.append(CurrentOccurrence(slot: nx.slot, day: nx.day, start: nx.start, end: nx.end, isCurrent: false))
            t = ShiftModel.addDays(nx.day, 1)
        }
        return rows
    }

    struct UpcomingRow: View {
        let o: CurrentOccurrence

        var body: some View {
            let s = slots[o.slot]
            return HStack(spacing: 10) {
                Circle().fill(colorFor(s.t)).frame(width: 10, height: 10)
                VStack(alignment: .leading, spacing: 2) {
                    Text(s.name).font(.subheadline).fontWeight(.medium)
                    TimelineView(.periodic(from: .now, by: 30)) { tl in
                        Text(o.isCurrent ? currentLine(tl.date) : whenLine)
                            .font(.caption).foregroundColor(.secondary)
                    }
                }
                Spacer()
                TimelineView(.periodic(from: .now, by: 30)) { tl in
                    Text(o.isCurrent ? "идёт сейчас" : rightText(tl.date))
                        .font(.caption2).foregroundColor(.secondary)
                }
            }
            .padding(.vertical, 2)
        }

        private func currentLine(_ now: Date) -> String {
            let dayWord = cal.isDate(o.day, inSameDayAs: now) ? "сегодня" : "вчера"
            return dayWord + " · " + Fmt.hhmm(o.start) + "–" + Fmt.hhmm(o.end) + " · до конца " + Fmt.dur(o.end.timeIntervalSince(now))
        }
        private var whenLine: String {
            Fmt.cap(Fmt.wdShort.string(from: o.start)) + ", " + Fmt.dShort.string(from: o.start) + " · " + Fmt.hhmm(o.start) + "–" + Fmt.hhmm(o.end)
        }
        private func rightText(_ now: Date) -> String {
            if cal.isDate(o.start, inSameDayAs: now) { return "сегодня" }
            return Fmt.rel(o.start, now)
        }
    }
}

//MARK: - Настройки

struct SettingsView: View {
    let anchor: Date
    @Environment(\.presentationMode) private var presentation

    @AppStorage("smeny.base") private var base = ""
    @AppStorage("smeny.pos") private var pos = 0
    @AppStorage("smeny.theme") private var theme = "auto"
    @AppStorage("smeny.alarm") private var alarmMinutes = 60

    @State private var pickedDate = Date()
    @State private var importStatus = ""

    var body: some View {
        NavigationView {
            Form {
                Section(header: Text("День с дневной сменой (07:00–19:00)")) {
                    DatePicker("Дата", selection: $pickedDate, displayedComponents: .date)
                        .labelsHidden()
                }
                Section(header: Text("Что было на следующий день?")) {
                    Picker("След. день", selection: $pos) {
                        Text("Дневная — 1-й день цикла").tag(0)
                        Text("Ночная — 2-й день цикла").tag(1)
                    }
                    .pickerStyle(.inline)
                    .labelsHidden()
                }
                Section(header: Text("Тема")) {
                    Picker("Тема", selection: $theme) {
                        Text("как на телефоне").tag("auto")
                        Text("светлая").tag("light")
                        Text("тёмная").tag("dark")
                    }
                    .pickerStyle(.menu)
                }
                Section(header: Text("Календарь iPhone"), footer: Text("Смены на год вперёд появятся в приложении «Календарь» с напоминаниями. Импортируй один раз — повторный импорт создаст дубли.")) {
                    Picker("Напоминание", selection: $alarmMinutes) {
                        Text("за 60 минут").tag(60)
                        Text("за 30 минут").tag(30)
                        Text("за 15 минут").tag(15)
                        Text("без напоминаний").tag(0)
                    }
                    Button("📅 Сохранить смены в «Календарь»") {
                        importStatus = "Импортирую…"
                        CalendarImporter.importEvents(pickedDate: ShiftModel.dayStart(pickedDate), pos: pos, reminderMinutes: alarmMinutes) { message in
                            importStatus = message
                        }
                    }
                    if !importStatus.isEmpty {
                        Text(importStatus).font(.caption).foregroundColor(.secondary)
                    }
                }
                Section {
                    Button("Сохранить") {
                        let df = DateFormatter()
                        df.locale = Locale(identifier: "en_US_POSIX")
                        df.dateFormat = "yyyy-MM-dd"
                        base = df.string(from: ShiftModel.dayStart(pickedDate))
                        presentation.wrappedValue.dismiss()
                    }
                    Button("Сбросить всё", role: .destructive) {
                        base = ""
                        presentation.wrappedValue.dismiss()
                    }
                }
            }
            .navigationTitle("Настройки")
            .navigationBarTitleDisplayMode(.inline)
            .onAppear {
                // предзаполнение даты из текущего якоря
                let cur = ShiftModel.addDays(anchor, pos)
                pickedDate = cur
            }
        }
        .navigationViewStyle(.stack)
    }
}

//MARK: - Импорт в системный календарь

enum CalendarImporter {

    static func importEvents(pickedDate: Date, pos: Int, reminderMinutes: Int, completion: @escaping (String) -> Void) {
        let store = EKEventStore()
        let handle: (Bool) -> Void = { granted in
            if !granted {
                completion("Нет доступа к календарю (проверь Настройки → Конфиденциальность)")
                return
            }
            DispatchQueue.main.async {
                doImport(store: store, pickedDate: pickedDate, pos: pos, reminderMinutes: reminderMinutes, completion: completion)
            }
        }
        if #available(iOS 17.0, *) {
            store.requestFullAccessToEvents { granted, _ in handle(granted) }
        } else {
            store.requestAccess(to: .event) { granted, _ in handle(granted) }
        }
    }

    private static func doImport(store: EKEventStore, pickedDate: Date, pos: Int, reminderMinutes: Int, completion: @escaping (String) -> Void) {
        guard let anchor = ShiftModel.anchor(base: iso(from: pickedDate), pos: pos) else {
            completion("Не удалось определить дату")
            return
        }
        // календарь «Смены»
        var target: EKCalendar?
        if let existing = store.calendars(for: .event).first(where: { $0.title == "Смены" }) {
            target = existing
        } else {
            let newCal = EKCalendar(for: .event, eventStore: store)
            newCal.title = "Смены"
            newCal.source = store.defaultCalendarForNewEvents?.source
            do {
                try store.saveCalendar(newCal, commit: true)
                target = newCal
            } catch {
                target = store.defaultCalendarForNewEvents
            }
        }
        guard let calendar = target else {
            completion("Не удалось создать календарь")
            return
        }

        let now = Date()
        let from = ShiftModel.addDays(now, -7)
        let until = ShiftModel.addDays(now, 370)
        var day = from
        var count = 0
        var commit: Error?
        while day <= until {
            let slot = ShiftModel.slot(of: day, anchor: anchor)
            let s = slots[slot]
            if s.t != .off {
                let start = ShiftModel.atTime(day, s.startHour, s.startMinute)
                let end: Date = s.t == .night
                    ? ShiftModel.atTime(ShiftModel.addDays(day, 1), s.endHour, s.endMinute)
                    : ShiftModel.atTime(day, s.endHour, s.endMinute)
                let ev = EKEvent(eventStore: store)
                ev.title = s.name + " " + Fmt.hhmm(start) + "–" + Fmt.hhmm(end)
                ev.startDate = start
                ev.endDate = end
                ev.calendar = calendar
                if reminderMinutes > 0 {
                    ev.addAlarm(EKAlarm(relativeOffset: -Double(reminderMinutes) * 60))
                }
                do {
                    try store.save(ev, span: .thisEvent)
                    count += 1
                } catch {
                    commit = error
                    break
                }
            }
            day = ShiftModel.addDays(day, 1)
        }
        DispatchQueue.main.async {
            if let e = commit {
                completion("Ошибка: \(e.localizedDescription)")
            } else {
                completion("Готово: \(count) смен в календаре «Смены»")
            }
        }
    }

    private static func iso(from date: Date) -> String {
        let df = DateFormatter()
        df.locale = Locale(identifier: "en_US_POSIX")
        df.dateFormat = "yyyy-MM-dd"
        return df.string(from: date)
    }
}
