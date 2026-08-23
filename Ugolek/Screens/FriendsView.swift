import SwiftUI
import UniformTypeIdentifiers

struct FriendsView: View {
    @State private var store = AppStore.shared
    @State private var search = ""
    @State private var editing: Friend?
    @State private var showingAdd = false
    @State private var showExportSheet = false
    @State private var showImportPicker = false
    @State private var importMessage: String?

    private var visible: [Friend] {
        let q = search.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !q.isEmpty else { return store.friends }
        return store.friends.filter {
            $0.handle.lowercased().contains(q) || $0.label.lowercased().contains(q)
        }
    }

    var body: some View {
        NavigationStack {
            Group {
                if store.friends.isEmpty {
                    ContentUnavailableView(
                        "Пока никого",
                        systemImage: "person.badge.plus",
                        description: Text("Добавь друзей — и Уголёк будет продлевать с ними огоньки")
                    )
                } else {
                    List {
                        ForEach(visible) { friend in
                            FriendRow(friend: friend) { editing = friend }
                        }
                        .onDelete { offsets in
                            for index in offsets { store.delete(visible[index]) }
                        }
                    }
                }
            }
            .navigationTitle("Друзья")
            .searchable(text: $search, prompt: "Поиск")
            .toolbar {
                Menu {
                    Button {
                        showingAdd = true
                    } label: {
                        Label("Добавить друга", systemImage: "plus")
                    }
                    Button {
                        showExportSheet = true
                    } label: {
                        Label("Экспорт в JSON", systemImage: "square.and.arrow.up")
                    }
                    Button {
                        showImportPicker = true
                    } label: {
                        Label("Импорт из JSON", systemImage: "square.and.arrow.down")
                    }
                } label: {
                    Image(systemName: "plus.circle")
                }
            }
            .sheet(isPresented: $showingAdd) {
                FriendEditor(friend: nil)
            }
            .sheet(item: $editing) { friend in
                FriendEditor(friend: friend)
            }
            .sheet(isPresented: $showExportSheet) {
                ShareSheet(items: [store.exportFriendsJSON()])
            }
            .fileImporter(
                isPresented: $showImportPicker,
                allowedContentTypes: [.json, .plainText]
            ) { result in
                switch result {
                case .success(let url):
                    guard url.startAccessingSecurityScopedResource(),
                          let json = try? String(contentsOf: url, encoding: .utf8) else {
                        importMessage = "Не удалось прочитать файл"
                        return
                    }
                    url.stopAccessingSecurityScopedResource()
                    let added = store.importFriendsJSON(json)
                    importMessage = added > 0 ? "Добавлено друзей: \(added)" : "Новых друзей не найдено"
                case .failure:
                    importMessage = "Ошибка импорта"
                }
            }
            .alert("Импорт", isPresented: Binding(
                get: { importMessage != nil },
                set: { if !$0 { importMessage = nil } }
            )) {
                Button("Ок", role: .cancel) {}
            } message: {
                Text(importMessage ?? "")
            }
        }
    }
}

private struct FriendRow: View {
    let friend: Friend
    let onEdit: () -> Void

    var body: some View {
        HStack {
            Button(action: onEdit) {
                HStack {
                    Image(systemName: friend.isGroup ? "person.3.fill" : "person.fill")
                        .foregroundStyle(.secondary)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(friend.displayName)
                            .foregroundStyle(.primary)
                        Text(friend.isGroup ? "групповой чат" : "@\(friend.handle)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .buttonStyle(.plain)
            Spacer()
            if friend.lastSentDay == Day.today() {
                Image(systemName: "flame.fill")
                    .foregroundStyle(.orange)
            }
            Toggle("", isOn: Binding(
                get: { friend.isEnabled },
                set: { on in
                    var f = friend
                    f.isEnabled = on
                    AppStore.shared.update(f)
                }
            ))
            .labelsHidden()
        }
    }
}

struct FriendEditor: View {
    let friend: Friend?

    @Environment(\.dismiss) private var dismiss
    @State private var handle = ""
    @State private var label = ""
    @State private var isGroup = false
    @State private var hasFlame = true

    private var canSave: Bool {
        handle.trimmingCharacters(in: .whitespaces).count >= 2
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField(
                        isGroup ? "Название чата группы" : "username (без @)",
                        text: $handle
                    )
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                    TextField("Метка (необязательно)", text: $label)
                } header: {
                    Text(isGroup ? "Группа" : "Друг")
                }
                Section {
                    Toggle("Это групповой чат", isOn: $isGroup)
                    Toggle("Есть огонёк 🔥", isOn: $hasFlame)
                } footer: {
                    Text("Для друга укажи username из TikTok. Для группового чата — точное название, под которым он отображается в сообщениях TikTok. Флажок «огонёк» включает друга в ежедневную рассылку (в веб-версии TikTok огонёк не виден, поэтому отмечаем вручную; погасший огонёк восстановим — просто оставь флажок включённым).")
                }
                if let friend {
                    Section {
                        Button("Удалить", role: .destructive) {
                            AppStore.shared.delete(friend)
                            dismiss()
                        }
                    }
                }
            }
            .navigationTitle(friend == nil ? "Новый друг" : "Изменить")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Отмена") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Сохранить") {
                        save()
                        dismiss()
                    }
                    .disabled(!canSave)
                }
            }
            .onAppear {
                if let f = friend {
                    handle = f.handle
                    label = f.label
                    isGroup = f.isGroup
                    hasFlame = f.hasFlame
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private func save() {
        var f = friend ?? Friend(handle: "")
        f.handle = handle
            .trimmingCharacters(in: .whitespaces)
            .trimmingCharacters(in: CharacterSet(charactersIn: "@"))
        f.label = label.trimmingCharacters(in: .whitespaces)
        f.isGroup = isGroup
        f.hasFlame = hasFlame
        guard !f.handle.isEmpty else { return }
        if friend == nil {
            AppStore.shared.add(f)
        } else {
            AppStore.shared.update(f)
        }
    }
}
