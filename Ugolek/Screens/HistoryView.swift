import SwiftUI
import UniformTypeIdentifiers

struct HistoryView: View {
    @State private var store = AppStore.shared

    var body: some View {
        NavigationStack {
            Group {
                if store.runs.isEmpty {
                    ContentUnavailableView(
                        "История пуста",
                        systemImage: "clock.arrow.circlepath",
                        description: Text("После первого прогона здесь появится статистика")
                    )
                } else {
                    List {
                        if !store.runs.isEmpty {
                            Section {
                                LabeledContent("Всего прогонов", value: "\(store.runs.count)")
                                LabeledContent("Успешных", value: successRate)
                                LabeledContent("Отправлено сообщений", value: "\(totalSent)")
                                LabeledContent("Ошибок", value: "\(totalFailed)")
                            } header: {
                                Text("Сводка")
                            }
                        }

                        Section {
                            ForEach(store.runs) { run in
                                NavigationLink {
                                    RunDetailView(run: run)
                                } label: {
                                    VStack(alignment: .leading, spacing: 4) {
                                        HStack {
                                            Text(run.date, format: .dateTime.day().month().hour().minute())
                                            Spacer()
                                            Text(String(format: "%.0f с", run.durationSeconds))
                                                .foregroundStyle(.secondary)
                                        }
                                        Text("Отправлено: \(run.sentCount) · Ошибки: \(run.failedCount) · Пропущено: \(run.skippedCount)")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                            }
                        } header: {
                            Text("Прогоны")
                        }
                    }
                }
            }
            .navigationTitle("История")
        }
    }

    private var totalSent: Int { store.runs.reduce(0) { $0 + $1.sentCount } }
    private var totalFailed: Int { store.runs.reduce(0) { $0 + $1.failedCount } }
    private var successRate: String {
        let total = totalSent + totalFailed
        guard total > 0 else { return "—" }
        return String(format: "%.0f%%", Double(totalSent) / Double(total) * 100)
    }
}

struct RunDetailView: View {
    let run: RunRecord
    @State private var showShareSheet = false

    var body: some View {
        List {
            Section {
                LabeledContent("Отправлено", value: "\(run.sentCount)")
                LabeledContent("Ошибки", value: "\(run.failedCount)")
                LabeledContent("Пропущено", value: "\(run.skippedCount)")
                LabeledContent("Длительность", value: String(format: "%.0f с", run.durationSeconds))
            } header: {
                Text("Прогон")
            }

            Section("Результаты по друзьям") {
                ForEach(run.results) { result in
                    VStack(alignment: .leading, spacing: 3) {
                        HStack {
                            Image(systemName: iconName(result.status))
                                .foregroundStyle(iconColor(result.status))
                            Text(result.handle)
                                .fontWeight(.medium)
                            Spacer()
                            Text(statusName(result.status))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        if let detail = result.detail, !detail.isEmpty {
                            Text(detail)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .textSelection(.enabled)
                        }
                    }
                    .padding(.vertical, 2)
                }
            }

            if let log = run.log, !log.isEmpty {
                Section("Лог") {
                    Text(log)
                        .font(.system(size: 12, design: .monospaced))
                        .textSelection(.enabled)
                }
            }

            if let log = run.log, !log.isEmpty {
                Section {
                    Button {
                        showShareSheet = true
                    } label: {
                        Label("Экспортировать лог", systemImage: "square.and.arrow.up")
                    }
                }
            }
        }
        .navigationTitle(Text(run.date, format: .dateTime.day().month().hour().minute()))
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showShareSheet) {
            if let log = run.log {
                ShareSheet(items: [log])
            }
        }
    }

    private func iconName(_ status: FriendSendStatus) -> String {
        switch status {
        case .sent: return "checkmark.circle.fill"
        case .failed: return "xmark.circle.fill"
        case .skipped: return "minus.circle.fill"
        }
    }

    private func iconColor(_ status: FriendSendStatus) -> Color {
        switch status {
        case .sent: return .green
        case .failed: return .red
        case .skipped: return .gray
        }
    }

    private func statusName(_ status: FriendSendStatus) -> String {
        switch status {
        case .sent: return "отправлено"
        case .failed: return "ошибка"
        case .skipped: return "пропущено"
        }
    }
}

struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
