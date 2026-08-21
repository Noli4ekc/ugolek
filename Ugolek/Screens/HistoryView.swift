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
                    List(store.runs) { run in
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
            .navigationTitle("История")
        }
    }
}
