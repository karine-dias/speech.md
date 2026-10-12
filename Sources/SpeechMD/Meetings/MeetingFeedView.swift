import SwiftUI

struct MeetingFeedView: View {
    let days: [MeetingDay]
    let store: MeetingStore
    let model: MeetingSession
    let elapsed: TimeInterval
    let capturesSystemAudio: Bool
    let onStartMeeting: () -> Void
    let onUseMicrophoneOnly: () -> Void

    @State private var openMeeting: Meeting?
    @State private var summarizeOnOpen = false
    @State private var meetingToDelete: Meeting?
    @State private var meetingToRename: Meeting?
    @State private var renameText = ""

    private var isRecording: Bool { model.phase.isRunning }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 26) {
                if isRecording {
                    LiveMeetingView(model: model, elapsed: elapsed, onStop: onStartMeeting)
                } else {
                    startBar
                }
                if case .failed(let message) = model.phase {
                    failureCard(message)
                }

                if days.isEmpty, !isRecording {
                    emptyState
                }

                ForEach(days) { day in
                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            Text(day.label.uppercased())
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(Theme.textTertiary)
                                .tracking(0.6)
                            Spacer()
                            Image(systemName: "magnifyingglass")
                                .font(.system(size: 12))
                                .foregroundStyle(Theme.textTertiary)
                        }

                        VStack(spacing: 0) {
                            ForEach(Array(day.meetings.enumerated()), id: \.element.id) { index, meeting in
                                if index > 0 {
                                    Divider().overlay(Theme.border)
                                }
                                MeetingRow(
                                    meeting: meeting,
                                    onOpen: {
                                        summarizeOnOpen = false
                                        openMeeting = meeting
                                    },
                                    onSummarize: {
                                        summarizeOnOpen = true
                                        openMeeting = meeting
                                    },
                                    onCopy: { store.copyToPasteboard(meeting) },
                                    onReveal: { store.revealInFinder(meeting) },
                                    onRename: {
                                        renameText = meeting.title
                                        meetingToRename = meeting
                                    },
                                    onDelete: { meetingToDelete = meeting }
                                )
                            }
                        }
                        .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous))
                        .overlay {
                            RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous)
                                .stroke(Theme.border, lineWidth: 1)
                        }
                    }
                }
            }
            .padding(.horizontal, 36)
            .padding(.vertical, 30)
        }
        .sheet(item: $openMeeting) { meeting in
            MeetingDetailView(meetingID: meeting.id, store: store, summarizeOnAppear: summarizeOnOpen)
        }
        .alert(
            t("Renomear reunião", "Rename meeting"),
            isPresented: Binding(
                get: { meetingToRename != nil },
                set: { if !$0 { meetingToRename = nil } }
            ),
            presenting: meetingToRename
        ) { meeting in
            TextField(t("Ex.: Kickoff com Cliente X", "E.g. Kickoff with Client X"), text: $renameText)
            Button(t("Renomear", "Rename")) {
                store.rename(meeting, to: renameText)
            }
            Button(t("Cancelar", "Cancel"), role: .cancel) {}
        } message: { _ in
            Text(t("O arquivo .md é renomeado junto.", "The .md file is renamed too."))
        }
        .confirmationDialog(
            t("Excluir esta reunião?", "Delete this meeting?"),
            isPresented: Binding(
                get: { meetingToDelete != nil },
                set: { if !$0 { meetingToDelete = nil } }
            ),
            presenting: meetingToDelete
        ) { meeting in
            Button(t("Mover para o Lixo", "Move to Trash"), role: .destructive) {
                store.delete(meeting)
            }
        } message: { _ in
            Text(t("O arquivo .md vai para o Lixo e pode ser recuperado pelo Finder.", "The .md file goes to the Trash and can be recovered from the Finder."))
        }
    }

    private func failureCard(_ message: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(Theme.live)
            VStack(alignment: .leading, spacing: 6) {
                Text(t("A gravação não começou", "Recording did not start"))
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)
                Text(message)
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)

                if capturesSystemAudio {
                    HStack(spacing: 8) {
                        Button {
                            SystemPermission.screenRecording.requestIfPossible()
                        } label: {
                            Text(t("Permitir", "Allow"))
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(.white)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 6)
                                .background(Theme.contrastSurface, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                        }
                        .buttonStyle(.plain)
                        .pointerStyle(.link)

                        Button(t("Gravar só meu microfone", "Record my microphone only"), action: onUseMicrophoneOnly)
                            .font(.system(size: 12))
                            .controlSize(.small)
                            .pointerStyle(.link)
                    }
                    .padding(.top, 4)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(16)
        .background(Theme.live.opacity(0.08), in: RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous)
                .stroke(Theme.live.opacity(0.3), lineWidth: 1)
        }
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "waveform")
                .font(.system(size: 26, weight: .light))
                .foregroundStyle(Theme.textTertiary)
            Text(t("Nenhuma reunião gravada", "No meetings recorded"))
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Theme.textPrimary)
            Text(t("Clique em Começar para gravar sua primeira reunião.", "Click Start to record your first meeting."))
                .font(.system(size: 13))
                .foregroundStyle(Theme.textSecondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 64)
    }

    private var startBar: some View {
        HStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 3) {
                Text(isRecording ? t("Gravando reunião", "Recording meeting") : t("Gravar reunião", "Record meeting"))
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.white)
                Text(t("Sua voz e a dos outros participantes, separadas e no seu Mac.", "Your voice and the other participants, on separate channels, on your Mac."))
                    .font(.system(size: 12))
                    .foregroundStyle(.white.opacity(0.7))
            }
            Spacer(minLength: 12)

            Button(action: onStartMeeting) {
                HStack(spacing: 7) {
                    Image(systemName: isRecording ? "stop.fill" : "record.circle")
                        .font(.system(size: 12, weight: .semibold))
                    Text(isRecording ? t("Parar", "Stop") : t("Começar", "Start"))
                        .font(.system(size: 13, weight: .semibold))
                }
                .foregroundStyle(Theme.contrastSurface)
                .padding(.horizontal, 16)
                .padding(.vertical, 9)
                .background(.white, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
            }
            .buttonStyle(.plain)
            .pointerStyle(.link)
        }
        .padding(.horizontal, 22)
        .padding(.vertical, 18)
        .background(Theme.contrastSurface, in: RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous))
    }
}

private struct MeetingRow: View {
    let meeting: Meeting
    let onOpen: () -> Void
    let onSummarize: () -> Void
    let onCopy: () -> Void
    let onReveal: () -> Void
    let onRename: () -> Void
    let onDelete: () -> Void

    @State private var copied = false

    @State private var isHovering = false

    var body: some View {
        HStack(alignment: .top, spacing: 18) {
            VStack(alignment: .leading, spacing: 5) {
                Text(meeting.formattedTime)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Theme.textSecondary)
                    .monospacedDigit()
                if meeting.isLive {
                    LiveBadge()
                }
            }
            .frame(width: 66, alignment: .leading)

            VStack(alignment: .leading, spacing: 6) {
                Text(meeting.title)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)

                Text(meeting.excerpt)
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.textSecondary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)

                HStack(spacing: 12) {
                    MetaLabel(systemImage: "clock", text: meeting.formattedDuration)
                    MetaLabel(systemImage: "person.2", text: "\(meeting.participants)")
                }
                .padding(.top, 2)
            }

            Spacer(minLength: 12)

            HStack(spacing: 4) {
                RowAction(systemImage: "doc.text", help: t("Abrir transcrição", "Open transcript"), action: onOpen)
                RowAction(
                    systemImage: copied ? "checkmark" : "doc.on.doc",
                    help: t("Copiar transcrição", "Copy transcript")
                ) {
                    onCopy()
                    copied = true
                    Task {
                        try? await Task.sleep(for: .seconds(1.5))
                        copied = false
                    }
                }
                RowAction(
                    systemImage: "sparkles",
                    help: meeting.summary.isEmpty
                        ? t("Resumir com Apple Intelligence", "Summarize with Apple Intelligence")
                        : t("Ver resumo", "View summary"),
                    action: meeting.summary.isEmpty ? onSummarize : onOpen
                )
                Menu {
                    Button(t("Renomear…", "Rename…"), action: onRename)
                    Button(t("Mostrar no Finder", "Show in Finder"), action: onReveal)
                    Divider()
                    Button(t("Excluir…", "Delete…"), role: .destructive, action: onDelete)
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.textSecondary)
                        .frame(width: 28, height: 28)
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .fixedSize()
                .help(t("Mais opções", "More options"))
            }
            .opacity(isHovering ? 1 : 0)
        }
        .contentShape(Rectangle())
        .onTapGesture(count: 2, perform: onOpen)
        .padding(.horizontal, 18)
        .padding(.vertical, 16)
        .background(isHovering ? Theme.surfaceHover.opacity(0.6) : .clear)
        .onHover { isHovering = $0 }
        .animation(.easeOut(duration: 0.12), value: isHovering)
    }
}

private struct LiveBadge: View {
    var body: some View {
        HStack(spacing: 4) {
            Circle()
                .fill(Theme.live)
                .frame(width: 5, height: 5)
            Text(t("AO VIVO", "LIVE"))
                .font(.system(size: 9, weight: .bold))
                .tracking(0.4)
        }
        .foregroundStyle(Theme.live)
        .padding(.horizontal, 6)
        .padding(.vertical, 3)
        .background(Theme.live.opacity(0.1), in: Capsule())
    }
}

private struct MetaLabel: View {
    let systemImage: String
    let text: String

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: systemImage)
                .font(.system(size: 10))
            Text(text)
                .font(.system(size: 11))
        }
        .foregroundStyle(Theme.textTertiary)
    }
}

private struct RowAction: View {
    let systemImage: String
    let help: String
    let action: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 12))
                .foregroundStyle(Theme.textSecondary)
                .frame(width: 28, height: 28)
                .background {
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(isHovering ? Theme.border.opacity(0.6) : .clear)
                }
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .pointerStyle(.link)
        .help(help)
        .onHover { isHovering = $0 }
    }
}

/// Transcrição completa de uma reunião, com as duas trilhas separadas.
private struct MeetingDetailView: View {
    let meetingID: UUID
    let store: MeetingStore
    let summarizeOnAppear: Bool

    @Environment(\.dismiss) private var dismiss
    @State private var copied = false
    @State private var isSummarizing = false
    @State private var summaryError: String?
    @State private var titleDraft = ""
    @FocusState private var isEditingTitle: Bool

    /// Lido da store a cada render: o resumo novo aparece sem reabrir.
    private var meeting: Meeting {
        store.meetings.first { $0.id == meetingID }
            ?? Meeting(title: "", startedAt: Date(), duration: 0, you: "", others: "")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 4) {
                    // Clicar no título edita; Enter ou sair do campo salva.
                    TextField(t("Título da reunião", "Meeting title"), text: $titleDraft)
                        .textFieldStyle(.plain)
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(Theme.textPrimary)
                        .focused($isEditingTitle)
                        .onSubmit { store.rename(meeting, to: titleDraft) }
                        .onChange(of: isEditingTitle) { _, editing in
                            if !editing { store.rename(meeting, to: titleDraft) }
                        }
                        .help(t("Clique para renomear", "Click to rename"))
                    HStack(spacing: 12) {
                        MetaLabel(systemImage: "clock", text: meeting.formattedDuration)
                        MetaLabel(systemImage: "text.word.spacing", text: "\(meeting.wordCount)")
                    }
                }
                Spacer()
                Button {
                    summarize()
                } label: {
                    Label(
                        meeting.summary.isEmpty ? t("Resumir", "Summarize") : t("Refazer resumo", "Redo summary"),
                        systemImage: "sparkles"
                    )
                }
                .disabled(isSummarizing)
                Button {
                    store.copyToPasteboard(meeting)
                    copied = true
                } label: {
                    Label(
                        copied ? t("Copiado", "Copied") : t("Copiar", "Copy"),
                        systemImage: copied ? "checkmark" : "doc.on.doc"
                    )
                }
                Button(t("Mostrar no Finder", "Show in Finder")) {
                    store.revealInFinder(meeting)
                }
                Button(t("Fechar", "Close")) { dismiss() }
                    .keyboardShortcut(.cancelAction)
            }
            .padding(20)

            Divider().overlay(Theme.border)

            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    summarySection
                    if !meeting.you.isEmpty {
                        track(t("Você", "You"), meeting.you)
                    }
                    if !meeting.others.isEmpty {
                        track(t("Outros", "Others"), meeting.others)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(20)
            }
        }
        .frame(minWidth: 620, idealWidth: 720, minHeight: 460, idealHeight: 620)
        .background(Theme.canvas)
        .onAppear {
            titleDraft = meeting.title
            if summarizeOnAppear, meeting.summary.isEmpty { summarize() }
        }
    }

    @ViewBuilder
    private var summarySection: some View {
        if isSummarizing {
            HStack(spacing: 10) {
                ProgressView().controlSize(.small)
                Text(t("Resumindo com Apple Intelligence…", "Summarizing with Apple Intelligence…"))
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.textSecondary)
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.accent.opacity(0.07), in: RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous))
        } else if let summaryError {
            Text(summaryError)
                .font(.system(size: 13))
                .foregroundStyle(Theme.live)
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Theme.live.opacity(0.08), in: RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous))
        } else if !meeting.summary.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Label(t("RESUMO", "SUMMARY"), systemImage: "sparkles")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Theme.accent)
                    .tracking(0.6)
                Text(Self.rendered(meeting.summary))
                    .font(.system(size: 14))
                    .foregroundStyle(Theme.textPrimary)
                    .lineSpacing(3)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.accent.opacity(0.07), in: RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous))
        }
    }

    private func summarize() {
        let target = meeting
        isSummarizing = true
        summaryError = nil
        Task {
            do {
                let summary = try await MeetingSummarizer.summarize(target)
                store.setSummary(summary, for: target)
            } catch {
                summaryError = error.localizedDescription
            }
            isSummarizing = false
        }
    }

    /// Markdown do modelo em texto com negrito, itálico e listas legíveis.
    private static func rendered(_ markdown: String) -> AttributedString {
        let options = AttributedString.MarkdownParsingOptions(
            interpretedSyntax: .inlineOnlyPreservingWhitespace
        )
        let cleaned = markdown
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map { line -> String in
                // Título ("### Decisões") vira linha em negrito.
                guard line.hasPrefix("#") else { return String(line) }
                let title = line.drop { $0 == "#" }.trimmingCharacters(in: .whitespaces)
                return "**\(title)**"
            }
            .joined(separator: "\n")
        return (try? AttributedString(markdown: cleaned, options: options)) ?? AttributedString(markdown)
    }

    private func track(_ title: String, _ text: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title.uppercased())
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Theme.textTertiary)
                .tracking(0.6)
            Text(text)
                .font(.system(size: 14))
                .foregroundStyle(Theme.textPrimary)
                .lineSpacing(3)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
