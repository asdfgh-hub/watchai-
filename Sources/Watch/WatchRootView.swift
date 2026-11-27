import SwiftUI
import WatchKit

struct WatchRootView: View {
    @EnvironmentObject private var bridge: WatchBridge
    @State private var showingVoice = false

    var body: some View {
        Group {
            if bridge.isLoading {
                loadingView
            } else if let answer = bridge.answer {
                responseView(answer)
            } else if let error = bridge.error {
                errorView(error)
            } else {
                mainView
            }
        }
        .sheet(isPresented: $showingVoice) {
            VoiceInputView { text in
                showingVoice = false
                bridge.sendVoiceRequest(text)
            }
        }
    }

    private var mainView: some View {
        VStack(spacing: 10) {
            Text("WristAI").font(.headline)
            Button {
                bridge.sendPhotoRequest()
            } label: {
                Label("Анализ фото", systemImage: "photo.stack")
                    .frame(maxWidth: .infinity)
            }
            .tint(.blue)
            Button {
                showingVoice = true
            } label: {
                Label("Спросить голосом", systemImage: "mic")
                    .frame(maxWidth: .infinity)
            }
            .tint(.green)
            Text(bridge.status).font(.system(size: 10)).foregroundStyle(.secondary).lineLimit(2)
        }
        .padding(.horizontal, 5)
    }

    private var loadingView: some View {
        VStack(spacing: 12) {
            ProgressView()
            Text("Claude думает…").font(.headline)
            Text(bridge.status).font(.caption2).foregroundStyle(.secondary).multilineTextAlignment(.center)
            Button("Отменить запрос", role: .destructive) { bridge.cancelRequest() }
        }
        .padding()
    }

    private func responseView(_ answer: String) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                Text("ОТВЕТ CLAUDE").font(.caption2.bold()).foregroundStyle(.green)
                Text(answer).font(.system(size: 14)).frame(maxWidth: .infinity, alignment: .leading)
                Divider()
                Button("Повторить запрос") {
                    guard let last = bridge.lastRequest else { bridge.reset(); return }
                    if last.kind == "photos" { bridge.sendPhotoRequest() }
                    else { bridge.sendVoiceRequest(last.text ?? "") }
                }
                Button("На главную") { bridge.reset() }
            }
            .padding(.horizontal, 4)
        }
    }

    private func errorView(_ message: String) -> some View {
        ScrollView {
            VStack(spacing: 10) {
                Image(systemName: "exclamationmark.triangle").foregroundStyle(.orange)
                Text("Не удалось выполнить запрос").font(.headline)
                Text(message).font(.caption).multilineTextAlignment(.center)
                Button("На главную") { bridge.reset() }
            }.padding(4)
        }
    }
}

struct VoiceInputView: View {
    let onSend: (String) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var text = ""
    @FocusState private var focused: Bool

    var body: some View {
        VStack(spacing: 10) {
            Text("Продиктуй вопрос").font(.headline)
            TextField("Нажми и выбери микрофон", text: $text, axis: .vertical)
                .focused($focused)
                .lineLimit(3...6)
                .onSubmit { submit() }
            Button("Отправить") { submit() }
                .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            Button("Отмена", role: .cancel) { dismiss() }
        }
        .padding()
        .onAppear { DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { focused = true } }
    }

    private func submit() {
        let value = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return }
        onSend(value)
    }
}
