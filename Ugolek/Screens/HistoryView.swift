import SwiftUI

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
                    }
                }
            }
            .navigationTitle("История")
        }
    }
}

struct RunDetailView: View {
    let run: RunRecord

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
        }
        .navigationTitle(Text(run.date, format: .dateTime.day().month().hour().minute()))
        .navigationBarTitleDisplayMode(.inline)
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
