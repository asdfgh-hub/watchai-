import SwiftUI
import Photos
import UIKit

struct RootView: View {
    @EnvironmentObject private var settings: AppSettings
    @EnvironmentObject private var bridge: PhoneWatchBridge
    @State private var selectedTab = 0

    var body: some View {
        Group {
            if selectedTab == 0 {
                SettingsView()
            } else {
                HistoryView()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(uiColor: .systemGroupedBackground).ignoresSafeArea())
        .safeAreaInset(edge: .bottom, spacing: 0) {
            bottomBar
        }
        .tint(.indigo)
    }

    // A fixed, opaque bar avoids the floating/translucent iOS 26 tab bar
    // covering the last rows of the Settings form.
    private var bottomBar: some View {
        HStack(spacing: 0) {
            tabButton(title: "Настройки", systemImage: "slider.horizontal.3", tag: 0)
            tabButton(title: "История", systemImage: "clock.arrow.circlepath", tag: 1)
        }
        .padding(.top, 9)
        .padding(.bottom, 7)
        .background(Color(uiColor: .secondarySystemBackground).ignoresSafeArea(edges: .bottom))
        .overlay(alignment: .top) { Divider() }
    }

    private func tabButton(title: String, systemImage: String, tag: Int) -> some View {
        Button {
            selectedTab = tag
        } label: {
            VStack(spacing: 4) {
                Image(systemName: systemImage).font(.system(size: 19, weight: .semibold))
                Text(title).font(.caption.weight(.medium))
            }
            .foregroundStyle(selectedTab == tag ? Color.indigo : Color.secondary)
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

struct SettingsView: View {
    @EnvironmentObject private var settings: AppSettings
    @EnvironmentObject private var bridge: PhoneWatchBridge
    @State private var apiKey = ""
    @State private var showKey = false
    @State private var permissionText = "Проверка доступа к фото"
    @State private var saved = false

    var body: some View {
        NavigationStack {
            Form {
                Section("Router.cheap API") {
                    HStack {
                        Group {
                            if showKey { TextField("API-ключ Router.cheap", text: $apiKey) }
                            else { SecureField("API-ключ Router.cheap", text: $apiKey) }
                        }
                        Button(showKey ? "Скрыть" : "Показать") { showKey.toggle() }
                            .font(.caption)
                    }
                    Button("Сохранить ключ Router.cheap") {
                        settings.apiKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
                        saved = true
                    }
                    .disabled(apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    if saved { Label("Ключ сохранён в Keychain", systemImage: "checkmark.circle.fill").foregroundStyle(.green) }
                    Picker("Модель", selection: $settings.modelID) {
                        if settings.models.isEmpty { Text(settings.modelID).tag(settings.modelID) }
                        ForEach(settings.models) { model in Text(model.name).tag(model.id) }
                    }
                    Button {
                        Task { await loadModels() }
                    } label: {
                        HStack(spacing: 8) {
                            if settings.isLoadingModels {
                                ProgressView()
                            } else {
                                Image(systemName: "arrow.clockwise")
                            }
                            Text(settings.isLoadingModels ? "Загружаю модели…" : "Обновить список моделей")
                        }
                        .frame(maxWidth: .infinity, alignment: .center)
                    }
                    .disabled(settings.isLoadingModels || settings.apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    if !settings.models.isEmpty {
                        Text("Доступно моделей: \(settings.models.count)")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    if let error = settings.modelError {
                        Text(error).font(.caption).foregroundStyle(.red).fixedSize(horizontal: false, vertical: true)
                    }
                }

                Section("Анализ фотографий") {
                    Stepper("Количество последних фото: \(settings.photoCount)", value: $settings.photoCount, in: 1...10)
                    Text("Каждая фотография отправляется в Claude отдельным запросом. Одновременно выполняются не более двух запросов.")
                        .font(.footnote).foregroundStyle(.secondary)
                }

                Section("Общий промпт") {
                    TextEditor(text: $settings.prompt)
                        .frame(minHeight: 130)
                    Text("Инструкция применяется и к голосовым запросам, и к каждой фотографии.")
                        .font(.footnote).foregroundStyle(.secondary)
                }

                Section("Разрешения и связь") {
                    Button("Разрешить доступ к фотографиям") { requestPhotos() }
                    Text(permissionText).font(.caption).foregroundStyle(.secondary)
                    Label(bridge.status, systemImage: "applewatch")
                    if let error = bridge.lastError { Text(error).font(.caption).foregroundStyle(.red) }
                }

                Section {
                    Text("WristAI не воспроизводит звуки и не озвучивает ответы. Для работы с заблокированным iPhone приложение использует фоновые события WatchConnectivity и ограниченное фоновое время iOS; гарантировать выполнение длинного запроса при любых условиях iOS не позволяет.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
            }
            .scrollContentBackground(.hidden)
            .background(Color(uiColor: .systemGroupedBackground).ignoresSafeArea())
            .navigationTitle("WristAI")
            .navigationBarTitleDisplayMode(.large)
            .toolbarBackground(.visible, for: .navigationBar)
            .onAppear {
                apiKey = settings.apiKey
                checkPhotos()
            }
        }
    }

    private func loadModels() async {
        settings.isLoadingModels = true
        settings.modelError = nil
        defer { settings.isLoadingModels = false }
        do {
            let models = try await ClaudeService().fetchModels(apiKey: settings.apiKey)
            settings.models = models
            if !models.contains(where: { $0.id == settings.modelID }), let first = models.first { settings.modelID = first.id }
        } catch { settings.modelError = error.localizedDescription }
    }

    private func requestPhotos() {
        PHPhotoLibrary.requestAuthorization(for: .readWrite) { status in
            DispatchQueue.main.async { permissionText = Self.photoStatus(status) }
        }
    }

    private func checkPhotos() { permissionText = Self.photoStatus(PHPhotoLibrary.authorizationStatus(for: .readWrite)) }
    private static func photoStatus(_ status: PHAuthorizationStatus) -> String {
        switch status {
        case .authorized: return "Доступ к медиатеке разрешён"
        case .limited: return "Разрешён ограниченный доступ к фотографиям"
        case .denied: return "Доступ запрещён — измени разрешение в Настройках iOS"
        case .restricted: return "Доступ ограничен системой"
        case .notDetermined: return "Доступ ещё не запрашивался"
        @unknown default: return "Статус доступа неизвестен"
        }
    }
}

struct HistoryView: View {
    @StateObject private var history = HistoryStore.shared
    var body: some View {
        NavigationStack {
            List {
                if history.chats.isEmpty {
                    ContentUnavailableView("История пока пуста", systemImage: "bubble.left.and.bubble.right", description: Text("Запросы с Apple Watch появятся здесь."))
                }
                ForEach(history.chats) { chat in
                    NavigationLink {
                        ChatDetailView(chat: chat)
                    } label: {
                        VStack(alignment: .leading, spacing: 5) {
                            HStack {
                                Text(chat.title).font(.headline).lineLimit(2)
                                Spacer()
                                Text(chat.kind).font(.caption).foregroundStyle(.secondary)
                            }
                            Text(chat.createdAt.formatted(date: .abbreviated, time: .shortened))
                                .font(.caption).foregroundStyle(.secondary)
                            if let answer = chat.messages.last?.text {
                                Text(answer).font(.subheadline).foregroundStyle(.secondary).lineLimit(2)
                            }
                        }.padding(.vertical, 4)
                    }
                }
            }
            .navigationTitle("История")
        }
    }
}

struct ChatDetailView: View {
    let chat: ChatRecord
    @State private var copied = false
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text(chat.createdAt.formatted(date: .complete, time: .shortened)).font(.caption).foregroundStyle(.secondary)
                ForEach(chat.messages) { message in
                    VStack(alignment: .leading, spacing: 7) {
                        Text(message.role == .user ? "ЗАПРОС" : "CLAUDE")
                            .font(.caption.bold()).foregroundStyle(message.role == .user ? .indigo : .green)
                        Text(message.text).textSelection(.enabled)
                        if message.role == .assistant {
                            Button {
                                UIPasteboard.general.string = message.text
                                copied = true
                            } label: { Label(copied ? "Скопировано" : "Копировать ответ", systemImage: copied ? "checkmark" : "doc.on.doc") }
                            .font(.subheadline)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding().background(.thinMaterial, in: RoundedRectangle(cornerRadius: 14))
                }
            }.padding()
        }
        .navigationTitle("Диалог")
        .navigationBarTitleDisplayMode(.inline)
    }
}
