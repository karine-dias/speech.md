import AppKit
import Foundation
import Observation

/// Guarda cada reunião como um arquivo Markdown em
/// `~/Documents/Speech.md/Reuniões`.
///
/// O arquivo é a fonte da verdade: dá pra abrir em qualquer editor (ou no
/// Obsidian), e o app relê a pasta ao abrir. Os metadados ficam num
/// frontmatter simples no topo; as duas trilhas vêm logo abaixo, uma seção
/// para cada.
@MainActor
@Observable
final class MeetingStore {
    private(set) var meetings: [Meeting] = []

    static let folder: URL = URL.documentsDirectory
        .appending(path: "Speech.md", directoryHint: .isDirectory)
        .appending(path: "Reuniões", directoryHint: .isDirectory)

    init() {
        load()
    }

    func load() {
        let urls = (try? FileManager.default.contentsOfDirectory(
            at: Self.folder,
            includingPropertiesForKeys: nil
        )) ?? []
        meetings = urls
            .filter { $0.pathExtension == "md" }
            .compactMap(Self.read)
            .sorted { $0.startedAt > $1.startedAt }
    }

    /// Grava a reunião em disco e coloca no topo da lista. Se a gravação
    /// falhar, a reunião continua na lista da sessão — perder o arquivo não
    /// pode significar perder o texto que está na tela.
    func add(_ meeting: Meeting) {
        var meeting = meeting
        do {
            try FileManager.default.createDirectory(at: Self.folder, withIntermediateDirectories: true)
            let url = uniqueURL(for: meeting)
            try Self.markdown(for: meeting, frontmatter: true)
                .write(to: url, atomically: true, encoding: .utf8)
            meeting.fileURL = url
        } catch {
            NSLog("Speech.md: não foi possível salvar a reunião: \(error.localizedDescription)")
        }
        meetings.insert(meeting, at: 0)
    }

    /// Manda o arquivo pro Lixo em vez de apagar: dá pra recuperar pelo Finder.
    func delete(_ meeting: Meeting) {
        if let url = meeting.fileURL {
            try? FileManager.default.trashItem(at: url, resultingItemURL: nil)
        }
        meetings.removeAll { $0.id == meeting.id }
    }

    /// Guarda o resumo na reunião e regrava o arquivo, que já existe.
    func setSummary(_ summary: String, for meeting: Meeting) {
        guard let index = meetings.firstIndex(where: { $0.id == meeting.id }) else { return }
        // "## " encerra uma seção no arquivo; título do resumo desce um nível
        // pra não cortar o texto na releitura.
        meetings[index].summary = summary
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map { $0.hasPrefix("## ") ? "#\($0)" : String($0) }
            .joined(separator: "\n")
        let updated = meetings[index]
        if let url = updated.fileURL {
            try? Self.markdown(for: updated, frontmatter: true)
                .write(to: url, atomically: true, encoding: .utf8)
        }
    }

    func revealInFinder(_ meeting: Meeting) {
        if let url = meeting.fileURL {
            NSWorkspace.shared.activateFileViewerSelecting([url])
        } else {
            NSWorkspace.shared.open(Self.folder)
        }
    }

    func copyToPasteboard(_ meeting: Meeting) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(Self.markdown(for: meeting, frontmatter: false), forType: .string)
    }

    // MARK: - Formato do arquivo

    private static let summaryHeading = "## Resumo"
    private static let youHeading = "## Você"
    private static let othersHeading = "## Outros"

    static func markdown(for meeting: Meeting, frontmatter: Bool) -> String {
        var lines: [String] = []
        if frontmatter {
            lines += [
                "---",
                "id: \(meeting.id.uuidString)",
                "title: \(meeting.title)",
                "started: \(isoFormatter.string(from: meeting.startedAt))",
                "duration: \(Int(meeting.duration.rounded()))",
                "---",
                ""
            ]
        }
        lines += [
            "# \(meeting.title)",
            "",
            "\(headerFormatter.string(from: meeting.startedAt)) · \(meeting.formattedDuration)",
            ""
        ]
        if !meeting.summary.isEmpty {
            lines += [summaryHeading, "", meeting.summary, ""]
        }
        if !meeting.you.isEmpty {
            lines += [youHeading, "", meeting.you, ""]
        }
        if !meeting.others.isEmpty {
            lines += [othersHeading, "", meeting.others, ""]
        }
        return lines.joined(separator: "\n")
    }

    private static func read(_ url: URL) -> Meeting? {
        guard let text = try? String(contentsOf: url, encoding: .utf8),
              text.hasPrefix("---\n") else { return nil }

        let afterOpening = text.dropFirst(4)
        guard let closing = afterOpening.range(of: "\n---\n") else { return nil }
        var fields: [String: String] = [:]
        for line in afterOpening[..<closing.lowerBound].split(separator: "\n") {
            guard let colon = line.firstIndex(of: ":") else { continue }
            let key = line[..<colon].trimmingCharacters(in: .whitespaces)
            let value = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
            fields[key] = value
        }
        guard let started = fields["started"].flatMap(isoFormatter.date(from:)) else { return nil }

        let body = String(afterOpening[closing.upperBound...])
        return Meeting(
            id: fields["id"].flatMap(UUID.init(uuidString:)) ?? UUID(),
            title: fields["title"] ?? url.deletingPathExtension().lastPathComponent,
            startedAt: started,
            duration: fields["duration"].flatMap(TimeInterval.init) ?? 0,
            you: section(youHeading, in: body),
            others: section(othersHeading, in: body),
            summary: section(summaryHeading, in: body),
            fileURL: url
        )
    }

    /// Texto entre o título da seção e o próximo título `## ` (ou o fim).
    private static func section(_ heading: String, in body: String) -> String {
        guard let start = body.range(of: "\n\(heading)\n") ?? body.range(of: "\(heading)\n") else {
            return ""
        }
        let rest = body[start.upperBound...]
        let end = rest.range(of: "\n## ")?.lowerBound ?? rest.endIndex
        return rest[..<end].trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// `2026-10-12 1403 - Reunião.md`; se já existir, ganha " 2", " 3"…
    private func uniqueURL(for meeting: Meeting) -> URL {
        let base = "\(Self.fileFormatter.string(from: meeting.startedAt)) - \(t("Reunião", "Meeting"))"
        var url = Self.folder.appending(path: "\(base).md")
        var counter = 2
        while FileManager.default.fileExists(atPath: url.path(percentEncoded: false)) {
            url = Self.folder.appending(path: "\(base) \(counter).md")
            counter += 1
        }
        return url
    }

    private static let isoFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()

    private static let fileFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd HHmm"
        return formatter
    }()

    private static let headerFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: t("pt_BR", "en_US"))
        formatter.dateFormat = t("d 'de' MMMM 'de' yyyy, HH:mm", "MMMM d, yyyy, HH:mm")
        return formatter
    }()
}
