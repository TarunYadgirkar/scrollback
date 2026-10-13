import SwiftUI
import ScrollbackCore

struct AskBar: View {
    @Bindable var model: AppModel
    @FocusState private var isFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: Space.s) {
            field
            answer
        }
    }

    private var field: some View {
        HStack(spacing: Space.s) {
            Image(systemName: "text.magnifyingglass").foregroundStyle(Palette.inkMuted)
            TextField("What was I doing 7–8pm yesterday?", text: $model.question)
                .textFieldStyle(.plain)
                .font(TypeScale.body)
                .focused($isFocused)
                .submitLabel(.search)
                .onSubmit { Task { await model.ask() } }
                .disabled(!Asker.isAvailable)
            if model.askState == .thinking {
                ProgressView().controlSize(.small)
            } else if !model.question.isEmpty {
                Button("Ask") { Task { await model.ask() } }
                    .buttonStyle(PressScale())
                    .font(TypeScale.bodyStrong)
                    .foregroundStyle(Palette.ink)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(.horizontal, Space.m)
        .padding(.vertical, Space.s + Space.xxs)
        .background(Palette.raised, in: RoundedRectangle(cornerRadius: Radius.control))
        .shadow(color: .black.opacity(0.06), radius: 1, y: 1)
        .shadow(color: .black.opacity(isFocused ? 0.1 : 0.04), radius: isFocused ? 8 : 4, y: 2)
        .animation(Motion.quick, value: isFocused)
        #if os(macOS)
        .background { Button("") { isFocused = true }.keyboardShortcut("k").hidden() }
        #endif
    }

    static let suggestions = ["What did I do last night?", "When did I stop scrolling?", "How much social today?"]

    private var suggestions: some View {
        ScrollView(.horizontal) {
            HStack(spacing: Space.s) {
                ForEach(Self.suggestions, id: \.self) { text in
                    Button { Task { await model.ask(text) } } label: {
                        Text(text)
                            .font(TypeScale.label)
                            .foregroundStyle(Palette.ink)
                            .padding(.horizontal, Space.m)
                            .padding(.vertical, Space.xs + Space.xxs)
                            .background(Palette.raised, in: Capsule())
                            .shadow(color: .black.opacity(0.05), radius: 2, y: 1)
                    }
                    .buttonStyle(PressScale())
                }
            }
            .padding(.vertical, Space.xxs)
        }
        .scrollIndicators(.never)
    }

    @ViewBuilder private var answer: some View {
        switch model.askState {
        case .answered(let text):
            AnswerCard(text: text, isError: false) { model.dismissAnswer() }
        case .failed(let message):
            AnswerCard(text: message, isError: true) { model.dismissAnswer() }
        case .idle where Asker.isAvailable && model.question.isEmpty:
            suggestions
        case .idle where !Asker.isAvailable:
            Text("Ask needs Apple Intelligence. Turn it on in System Settings, then reopen Scrollback.")
                .font(TypeScale.label).foregroundStyle(Palette.inkMuted)
        default:
            EmptyView()
        }
    }
}

private struct AnswerCard: View {
    let text: String
    let isError: Bool
    let onDismiss: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: Space.m) {
            Rectangle().fill(isError ? Palette.critical : Palette.ink).frame(width: 2)
            Text(text)
                .font(TypeScale.body)
                .foregroundStyle(Palette.ink)
                .frame(maxWidth: 560, alignment: .leading)
                .textSelection(.enabled)
            Spacer(minLength: 0)
            Button(action: onDismiss) {
                Image(systemName: "xmark").font(TypeScale.label).foregroundStyle(Palette.inkMuted).padding(Space.xs)
            }
            .buttonStyle(PressScale())
            .accessibilityLabel("Dismiss answer")
        }
        .fixedSize(horizontal: false, vertical: true)
        .transition(.opacity.combined(with: .offset(y: -4)))
    }
}
