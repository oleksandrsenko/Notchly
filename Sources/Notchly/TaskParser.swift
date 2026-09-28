import Foundation

/// Разбирает строку задачи, набранную руками: «спортзал 18:30», «в чт, пт и сб бег в 7»,
/// «немецкий каждый вторник 19:00 4 недели», «сдать эссе 12 октября». Время и дни вырезаются из текста.
enum TaskParser {
    struct Parsed: Equatable {
        var text: String
        var time: String?
        /// Дни задачи (начало дня). Пусто — день не назван.
        var days: [Date] = []
        /// Сколько недель подряд повторять (1 — без повтора).
        var weeks = 1
    }

    static let maxWeeks = 26

    static func parse(_ raw: String, now: Date = Date()) -> Parsed {
        var text = " " + raw + " "
        let cal = Calendar.current
        let today = cal.startOfDay(for: now)
        var time: String?
        var days: [Date] = []
        var weeks = 1
        var repeating = false

        /// Находит первое совпадение, вырезает его из текста и отдаёт группы.
        func take(_ pattern: String) -> [String?]? {
            guard let re = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]),
                  let m = re.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
                  let whole = Range(m.range, in: text) else { return nil }
            let groups = (0..<m.numberOfRanges).map { i in Range(m.range(at: i), in: text).map { String(text[$0]) } }
            text.replaceSubrange(whole, with: " ")
            return groups
        }

        // Повтор: «каждый вторник», «каждую неделю», «every monday», «4 недели», «на 3 недели вперёд».
        var daily = false
        if take(#"(?<=\s)(?:каждый\s+день|ежедневно|every\s+day|daily)(?=[\s,.;!])"#) != nil { daily = true }
        if take(#"(?<=\s)(?:каждую|каждый|каждое|каждые|every)(?=\s)"#) != nil { repeating = true }
        // «по вторникам» — тоже повтор; сам день недели разберём ниже.
        if text.range(of: #"(?<=\s)по\s+(?:понедельникам|вторникам|средам|четвергам|пятницам|субботам|воскресеньям)"#,
                      options: [.regularExpression, .caseInsensitive]) != nil { repeating = true }
        if let g = take(#"(?<=\s)(?:на\s+|for\s+)?(\d{1,2})\s*(?:недел[юиь]|нед\.?|weeks?|w)(?:\s+вперёд|\s+вперед|\s+ahead)?(?=[\s,.;!]|$)"#),
           let n = g[1].flatMap({ Int($0) }) {
            weeks = min(max(n, 1), maxWeeks)
        } else if take(#"(?<=\s)(?:неделю|week)(?=[\s,.;!])"#) != nil, repeating {
            // «каждую неделю» без числа — на месяц вперёд.
            weeks = 4
        } else if repeating {
            weeks = 4
        }

        // Время: «18:30», «в 7», «в 5 вечера», «7pm».
        if let g = take(#"(?<=[\s,])(?:в|во|к|at|@)?\s*(\d{1,2})[:.](\d{2})(?=[\s,.;!])"#),
           let h = g[1].flatMap({ Int($0) }), let m = g[2].flatMap({ Int($0) }), h < 24, m < 60 {
            time = String(format: "%02d:%02d", h, m)
        } else if let g = take(#"(?<=[\s,])(\d{1,2})\s*(am|pm)(?=[\s,.;!])"#),
                  var h = g[1].flatMap({ Int($0) }), (1...12).contains(h) {
            if g[2]?.lowercased() == "pm", h < 12 { h += 12 }
            if g[2]?.lowercased() == "am", h == 12 { h = 0 }
            time = String(format: "%02d:00", h)
        } else if let g = take(#"(?<=[\s,])(?:в|во|к|at)\s+(\d{1,2})(?:\s*(утра|дня|вечера|ночи|ч\.?|часов|часа|час))?(?=[\s,.;!])"#),
                  var h = g[1].flatMap({ Int($0) }), h < 24 {
            switch g[2]?.lowercased() {
            case "дня", "вечера": if h < 12 { h += 12 }
            case "ночи": if h == 12 { h = 0 }
            case "утра": break
            // «в 5» без уточнения — скорее вечер, как и у Gemini.
            default: if (1...6).contains(h) { h += 12 }
            }
            time = String(format: "%02d:00", h)
        }

        // Относительные дни.
        let relative: [(String, Int)] = [("послезавтра", 2), ("завтра", 1), ("сегодня", 0),
                                         ("day after tomorrow", 2), ("tomorrow", 1), ("today", 0)]
        for (word, offset) in relative where take("(?<=\\s)(?:на\\s+)?" + word + "(?=[\\s,.;!])") != nil {
            if let d = cal.date(byAdding: .day, value: offset, to: today) { days.append(d) }
        }

        // Дата: «12 октября», «12 окт», «Oct 12».
        let months: [(String, Int)] = [("янв", 1), ("фев", 2), ("мар", 3), ("апр", 4), ("ма[яй]", 5), ("июн", 6),
                                       ("июл", 7), ("авг", 8), ("сен", 9), ("окт", 10), ("ноя", 11), ("дек", 12),
                                       ("jan", 1), ("feb", 2), ("mar", 3), ("apr", 4), ("may", 5), ("jun", 6),
                                       ("jul", 7), ("aug", 8), ("sep", 9), ("oct", 10), ("nov", 11), ("dec", 12)]
        for (stem, month) in months {
            let word = stem + "[a-zа-яё]*\\.?"
            var day: Int?
            if let g = take("(?<=\\s)(?:на\\s+|on\\s+)?(\\d{1,2})\\s+" + word + "(?=[\\s,;!]|$)") {
                day = g[1].flatMap { Int($0) }
            } else if let g = take("(?<=\\s)(?:on\\s+)?" + word + "\\s+(\\d{1,2})(?:st|nd|rd|th)?(?=[\\s,;!]|$)") {
                day = g[1].flatMap { Int($0) }
            }
            if let day, let d = nextDate(month: month, day: day, from: today) { days.append(d) }
        }

        // Дни недели: «в чт, пт и сб», «во вторник», «on friday». Несколько дней — по задаче на каждый.
        let weekdays: [(String, Int)] = [
            ("понедельникам|понедельника|понедельник|пн", 2), ("вторникам|вторника|вторник|вт", 3),
            ("средам|среду|среды|среда|ср", 4), ("четвергам|четверга|четверг|чт", 5),
            ("пятницам|пятницу|пятницы|пятница|пт", 6), ("субботам|субботу|субботы|суббота|сб", 7),
            ("воскресеньям|воскресенья|воскресенье|вс", 1),
            ("mondays?", 2), ("tuesdays?", 3), ("wednesdays?", 4), ("thursdays?", 5),
            ("fridays?", 6), ("saturdays?", 7), ("sundays?", 1)]
        var found: [(position: Int, weekday: Int)] = []
        for (pattern, weekday) in weekdays {
            let full = "(?<=[\\s,])(?:в|во|на|по|on)?\\s*(?:" + pattern + ")\\.?(?=[\\s,;!]|$)"
            while let re = try? NSRegularExpression(pattern: full, options: [.caseInsensitive]),
                  let m = re.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
                  let r = Range(m.range, in: text) {
                found.append((m.range.location, weekday))
                text.replaceSubrange(r, with: " ")
            }
        }
        for item in found.sorted(by: { $0.position < $1.position }) {
            if let d = nextDate(weekday: item.weekday, from: today), !days.contains(d) { days.append(d) }
        }

        // «Каждый день» — неделя вперёд, начиная с названного дня или с сегодняшнего.
        if daily {
            let start = days.first ?? today
            days = (0..<7).compactMap { cal.date(byAdding: .day, value: $0, to: start) }
            weeks = weeks > 1 ? weeks : 1
        }

        // Остатки связок: «и», запятые, предлоги на краях.
        var cleaned = text.replacingOccurrences(of: #"(?<=\s)(?:и|and|,)(?=\s)"#, with: " ", options: .regularExpression)
        cleaned = cleaned.replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
        cleaned = cleaned.trimmingCharacters(in: CharacterSet(charactersIn: " ,;—-"))
        cleaned = cleaned.replacingOccurrences(of: #"^(?:в|во|на|к|at|on)\s+|\s+(?:в|во|на|к|at|on)$"#, with: "",
                                               options: [.regularExpression, .caseInsensitive])
        if cleaned.isEmpty { cleaned = raw.trimmingCharacters(in: .whitespaces) }
        if !cleaned.isEmpty { cleaned = cleaned.prefix(1).uppercased() + cleaned.dropFirst() }
        return Parsed(text: cleaned, time: time, days: days, weeks: weeks)
    }

    /// Ближайший такой день недели, считая сегодняшний.
    private static func nextDate(weekday: Int, from today: Date) -> Date? {
        let cal = Calendar.current
        let current = cal.component(.weekday, from: today)
        return cal.date(byAdding: .day, value: (weekday - current + 7) % 7, to: today)
    }

    /// Ближайшая такая дата: если в этом году уже прошла — в следующем.
    private static func nextDate(month: Int, day: Int, from today: Date) -> Date? {
        let cal = Calendar.current
        let year = cal.component(.year, from: today)
        for y in [year, year + 1] {
            if let d = cal.date(from: DateComponents(year: y, month: month, day: day)),
               cal.component(.day, from: d) == day, d >= today { return d }
        }
        return nil
    }
}
