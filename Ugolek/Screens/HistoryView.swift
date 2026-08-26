import SwiftUI
import UIKit

struct HistoryView: View {
    @State private var store = AppStore.shared

    private let calendar = Calendar.current

    var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()

                if store.runs.isEmpty {
                    emptyState
                } else {
                    ScrollView(showsIndicators: false) {
                        VStack(alignment: .leading, spacing: 24) {
                            summary

                            VStack(alignment: .leading, spacing: 14) {
                                Text("ИСТОРИЯ ПРОГОНОВ")
                                    .font(.caption.weight(.bold))
                                    .tracking(1.2)
                                    .foregroundStyle(.white.opacity(0.45))

                                ForEach(groupedRuns) { group in
                                    VStack(alignment: .leading, spacing: 10) {
                                        Text(group.title)
                                            .font(.subheadline.weight(.semibold))
                                            .foregroundStyle(.white.opacity(0.7))

                                    ForEach(group.runs) { run in
                                        NavigationLink {
                                            RunDetailView(run: run)
                                        } label: {
                                            RunRow(run: run)
                                        }
                                        .buttonStyle(.plain)
                                        .accessibilityHint("Открыть детали прогона")
                                        }
                                    }
                                }
                            }
                        }
                        .padding(.horizontal, 20)
                        .padding(.top, 12)
                        .padding(.bottom, 32)
                    }
                }
            }
            .navigationTitle("История")
            .navigationBarTitleDisplayMode(.large)
            .toolbarColorScheme(.dark, for: .navigationBar)
        }
        .preferredColorScheme(.dark)
    }

    private var emptyState: some View {
        VStack(spacing: 18) {
            Image(systemName: "clock.arrow.circlepath")
                .font(.system(size: 36, weight: .medium))
                .foregroundStyle(.purple.opacity(0.9))
            VStack(spacing: 6) {
                Text("История пуста")
                    .font(.title3.weight(.semibold))
                Text("После первого прогона здесь появится статистика")
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.55))
                    .multilineTextAlignment(.center)
            }
        }
        .padding(32)
    }

    private var summary: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("СВОДКА")
                .font(.caption.weight(.bold))
                .tracking(1.2)
                .foregroundStyle(.white.opacity(0.45))

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                SummaryCard(title: "Прогоны", value: "\(store.runs.count)", tint: .purple)
                SummaryCard(title: "Успешность", value: successRate, tint: .green)
                SummaryCard(title: "Отправлено", value: "\(totalSent)", tint: .blue)
                SummaryCard(title: "Ошибки", value: "\(totalFailed)", tint: .orange)
            }
        }
    }

    private var groupedRuns: [RunGroup] {
        let groups = Dictionary(grouping: store.runs) { calendar.startOfDay(for: $0.date) }
        return groups.keys.sorted(by: >).map { date in
            let title: String
            if calendar.isDateInToday(date) {
                title = "Сегодня"
            } else if calendar.isDateInYesterday(date) {
                title = "Вчера"
            } else {
                title = date.formatted(.dateTime.day().month(.wide).year())
            }
            return RunGroup(date: date, title: title, runs: (groups[date] ?? []).sorted { $0.date > $1.date })
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

private struct RunGroup: Identifiable {
    let date: Date
    let title: String
    let runs: [RunRecord]
    var id: Date { date }
}

private struct SummaryCard: View {
    let title: String
    let value: String
    let tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Circle()
                .fill(tint)
                .frame(width: 7, height: 7)
            Text(value)
                .font(.title2.weight(.bold))
                .foregroundStyle(.white)
                .contentTransition(.numericText())
            Text(title)
                .font(.caption)
                .foregroundStyle(.white.opacity(0.52))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(Color.white.opacity(0.075), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Color.white.opacity(0.09), lineWidth: 1)
        }
    }
}

private struct RunRow: View {
    let run: RunRecord

    private var hasErrors: Bool { run.failedCount > 0 }

    var body: some View {
        HStack(spacing: 13) {
            ZStack {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill((hasErrors ? Color.orange : Color.green).opacity(0.14))
                    .frame(width: 44, height: 44)
                Image(systemName: hasErrors ? "exclamationmark" : "checkmark")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(hasErrors ? .orange : .green)
            }

            VStack(alignment: .leading, spacing: 5) {
                Text(run.date, format: .dateTime.hour().minute())
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white)
                Text("\(run.sentCount) отправлено · \(run.failedCount) ошибок · \(run.skippedCount) пропущено")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.5))
                    .lineLimit(1)
            }

            Spacer(minLength: 8)
            VStack(alignment: .trailing, spacing: 4) {
                Text(String(format: "%.0f с", run.durationSeconds))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.white.opacity(0.5))
                Image(systemName: "chevron.right")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(.white.opacity(0.28))
            }
        }
        .padding(14)
        .background(Color.white.opacity(0.075), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Color.white.opacity(0.08), lineWidth: 1)
        }
    }
}

struct RunDetailView: View {
    let run: RunRecord
    @State private var showShareSheet = false

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 24) {
                    detailSummary
                    results
                    if let log = run.log, !log.isEmpty { logSection(log) }
                }
                .padding(20)
                .padding(.bottom, 28)
            }
        }
        .navigationTitle(Text(run.date, format: .dateTime.day().month().hour().minute()))
        .navigationBarTitleDisplayMode(.inline)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .preferredColorScheme(.dark)
        .sheet(isPresented: $showShareSheet) {
            if let log = run.log { ShareSheet(items: [log]) }
        }
    }

    private var detailSummary: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("РЕЗУЛЬТАТ")
                .font(.caption.weight(.bold))
                .tracking(1.2)
                .foregroundStyle(.white.opacity(0.45))
            HStack(spacing: 10) {
                DetailMetric(title: "Отправлено", value: "\(run.sentCount)", tint: .green)
                DetailMetric(title: "Ошибки", value: "\(run.failedCount)", tint: .orange)
                DetailMetric(title: "Время", value: String(format: "%.0f с", run.durationSeconds), tint: .purple)
            }
        }
    }

    private var results: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("РЕЗУЛЬТАТЫ ПО ДРУЗЬЯМ")
                .font(.caption.weight(.bold))
                .tracking(1.2)
                .foregroundStyle(.white.opacity(0.45))
            VStack(spacing: 1) {
                ForEach(run.results) { result in
                    ResultRow(result: result)
                }
            }
            .background(Color.white.opacity(0.075), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
    }

    private func logSection(_ log: String) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("ЛОГ")
                    .font(.caption.weight(.bold))
                    .tracking(1.2)
                    .foregroundStyle(.white.opacity(0.45))
                Spacer()
                Button { showShareSheet = true } label: {
                    Image(systemName: "square.and.arrow.up")
                        .foregroundStyle(.purple)
                }
                .accessibilityLabel("Экспортировать лог")
            }
            Text(log)
                .font(.system(size: 12, design: .monospaced))
                .foregroundStyle(.white.opacity(0.7))
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(14)
                .background(Color.white.opacity(0.075), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
    }
}

private struct DetailMetric: View {
    let title: String
    let value: String
    let tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(value).font(.headline.weight(.bold)).foregroundStyle(.white)
            Text(title).font(.caption2).foregroundStyle(.white.opacity(0.5)).lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(tint.opacity(0.12), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}

private struct ResultRow: View {
    let result: FriendResult

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: iconName(result.status))
                .foregroundStyle(iconColor(result.status))
            VStack(alignment: .leading, spacing: 3) {
                Text(result.handle).font(.subheadline.weight(.medium)).foregroundStyle(.white)
                if let detail = result.detail, !detail.isEmpty {
                    Text(detail).font(.caption).foregroundStyle(.white.opacity(0.5)).textSelection(.enabled)
                }
            }
            Spacer()
            Text(statusName(result.status))
                .font(.caption)
                .foregroundStyle(.white.opacity(0.5))
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
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

#Preview("History") {
    HistoryView()
        .preferredColorScheme(.dark)
}
