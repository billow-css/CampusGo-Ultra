import Foundation
import CryptoKit

enum ICalendarError: LocalizedError {
    case invalidFile, invalidEvent, recurringEvents, emptyCalendar, tooLarge
    var errorDescription: String? {
        switch self {
        case .invalidFile: return "内容不是有效的 iCalendar 课表，请检查链接是否返回了登录页面。"
        case .invalidEvent: return "课表中有无法识别的上课时间，未替换现有数据。"
        case .recurringEvents: return "此日历使用重复规则；请通过系统日历读取。直接导入目前支持学校提供的逐次课程格式。"
        case .emptyCalendar: return "订阅中没有可读取的非全天课程，未替换现有数据。"
        case .tooLarge: return "日历文件超过 15 MB，请选择学校课表文件。"
        }
    }
}

struct ParsedCalendar {
    var name: String
    var events: [CourseOccurrence]
}

enum ICalendarParser {
    struct Field {
        var value: String
        var parameters: [String: String]
    }

    static func sourceID(for url: URL) -> String {
        "ics:" + SHA256.hash(data: Data(url.absoluteString.utf8)).map { String(format: "%02x", $0) }.joined()
    }

    static func parse(_ data: Data, sourceID: String, defaultTimeZone: TimeZone = .current) throws -> ParsedCalendar {
        guard data.count <= 15 * 1024 * 1024 else { throw ICalendarError.tooLarge }
        guard let text = String(data: data, encoding: .utf8), text.contains("BEGIN:VCALENDAR"), text.contains("END:VCALENDAR") else {
            throw ICalendarError.invalidFile
        }
        var lines: [String] = []
        for raw in text.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n").components(separatedBy: "\n") {
            if (raw.hasPrefix(" ") || raw.hasPrefix("\t")), !lines.isEmpty { lines[lines.count - 1] += raw.dropFirst() }
            else { lines.append(raw.trimmingCharacters(in: .init(charactersIn: "\u{feff}"))) }
        }
        var name = "学校课表"
        var timeZone = defaultTimeZone
        var current: [String: Field]?
        var events: [CourseOccurrence] = []
        var seen = Set<String>()
        var nestedDepth = 0
        for line in lines {
            guard let colon = line.firstIndex(of: ":") else { continue }
            let keyParts = line[..<colon].split(separator: ";", omittingEmptySubsequences: false).map(String.init)
            let key = keyParts[0].uppercased()
            let value = String(line[line.index(after: colon)...])
            if key == "BEGIN", value == "VEVENT" {
                guard current == nil else { throw ICalendarError.invalidFile }
                current = [:]; nestedDepth = 0; continue
            }
            if key == "END", value == "VEVENT" {
                guard let fields = current else { throw ICalendarError.invalidFile }
                if let event = try occurrence(fields, sourceID: sourceID, defaultTimeZone: timeZone), seen.insert(event.id).inserted {
                    events.append(event)
                }
                current = nil; continue
            }
            if current != nil {
                if key == "BEGIN" { nestedDepth += 1; continue }
                if key == "END" { nestedDepth = max(0, nestedDepth - 1); continue }
                guard nestedDepth == 0 else { continue }
                var parameters: [String: String] = [:]
                for part in keyParts.dropFirst() {
                    let pieces = part.split(separator: "=", maxSplits: 1).map(String.init)
                    if pieces.count == 2 { parameters[pieces[0].uppercased()] = pieces[1].trimmingCharacters(in: .init(charactersIn: "\"")) }
                }
                current?[key] = Field(value: value, parameters: parameters)
            } else {
                if key == "X-WR-CALNAME" { name = unescape(value) }
                if key == "X-WR-TIMEZONE", let zone = TimeZone(identifier: value) { timeZone = zone }
            }
        }
        guard current == nil else { throw ICalendarError.invalidFile }
        guard !events.isEmpty else { throw ICalendarError.emptyCalendar }
        return .init(name: name, events: events.sorted { $0.start < $1.start })
    }

    private static func occurrence(_ fields: [String: Field], sourceID: String, defaultTimeZone: TimeZone) throws -> CourseOccurrence? {
        if fields["STATUS"]?.value.uppercased() == "CANCELLED" { return nil }
        guard let startField = fields["DTSTART"] else { throw ICalendarError.invalidEvent }
        if startField.parameters["VALUE"] == "DATE" || startField.value.count == 8 { return nil }
        if fields["RRULE"] != nil || fields["RDATE"] != nil { throw ICalendarError.recurringEvents }
        let fallbackZone = fields["TZID"].flatMap { TimeZone(identifier: $0.value) } ?? defaultTimeZone
        guard let endField = fields["DTEND"], let start = date(startField, defaultTimeZone: fallbackZone),
              let end = date(endField, defaultTimeZone: fallbackZone), end > start else { throw ICalendarError.invalidEvent }
        let title = unescape(fields["SUMMARY"]?.value ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { throw ICalendarError.invalidEvent }
        let identifier = fields["UID"]?.value ?? title
        return .init(id: sourceID + "::" + identifier + "::" + String(start.timeIntervalSince1970), calendarID: sourceID,
            title: title, start: start, end: end, location: unescape(fields["LOCATION"]?.value ?? ""),
            notes: unescape(fields["DESCRIPTION"]?.value ?? ""))
    }

    private static func date(_ field: Field, defaultTimeZone: TimeZone) -> Date? {
        let utc = field.value.hasSuffix("Z")
        let value = utc ? String(field.value.dropLast()) : field.value
        guard value.count == 15, value[value.index(value.startIndex, offsetBy: 8)] == "T" else { return nil }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = utc ? TimeZone(secondsFromGMT: 0) : (field.parameters["TZID"].flatMap { TimeZone(identifier: $0) } ?? defaultTimeZone)
        formatter.dateFormat = "yyyyMMdd'T'HHmmss"
        formatter.isLenient = false
        return formatter.date(from: value)
    }

    private static func unescape(_ input: String) -> String {
        var result = ""
        var escaped = false
        for character in input {
            if escaped {
                if character == "n" || character == "N" { result.append("\n") }
                else { result.append(character) }
                escaped = false
            } else if character == "\\" { escaped = true }
            else { result.append(character) }
        }
        if escaped { result.append("\\") }
        return result
    }
}
