import SwiftUI

/// Default style preference + API key entry (plan Phase 6 + §5a).
/// The key is written straight to the Keychain and never leaves the device.
struct SettingsView: View {
    @Bindable var viewModel: RecorderViewModel
    @Environment(\.dismiss) private var dismiss

    @State private var apiKeyInput = ""
    @State private var hasStoredKey = KeyProvider.shared.hasKey
    @State private var keySaved = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("Default style", selection: defaultStyleBinding) {
                        ForEach(Styles.all) { style in
                            Text("\(style.emoji) \(style.name)").tag(style.id)
                        }
                    }
                } header: {
                    Text("One-tap rewrite")
                } footer: {
                    Text("Used automatically after every recording. You can always re-run with another style.")
                }

                Section {
                    ForEach(StyleStore.shared.styles) { style in
                        NavigationLink {
                            StylePromptEditor(style: style)
                        } label: {
                            HStack {
                                Text("\(style.emoji) \(style.name)")
                                Spacer()
                                if StyleStore.shared.isCustomized(style.id) {
                                    Text("Edited")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                } header: {
                    Text("Rewrite prompts")
                } footer: {
                    Text("Tap a style to edit the instructions used for its rewrite. Edits apply to the next rewrite.")
                }

                Section {
                    SecureField(
                        hasStoredKey ? "••••••••  (stored in Keychain)" : "sk-ant-…",
                        text: $apiKeyInput
                    )
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()

                    Button(keySaved ? "Saved ✓" : "Save key") {
                        if KeyProvider.shared.setApiKey(apiKeyInput) {
                            apiKeyInput = ""
                            hasStoredKey = KeyProvider.shared.hasKey
                            keySaved = true
                        }
                    }
                    .disabled(apiKeyInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

                    if hasStoredKey {
                        Button("Remove key", role: .destructive) {
                            KeyProvider.shared.deleteApiKey()
                            hasStoredKey = false
                            keySaved = false
                        }
                    }
                } header: {
                    Text("Anthropic API key")
                } footer: {
                    Text("Stored only in the device Keychain. Needed for style rewrites; transcription works without it.")
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    private var defaultStyleBinding: Binding<String> {
        Binding(
            get: { viewModel.defaultStyleID },
            set: { viewModel.defaultStyleID = $0 }
        )
    }
}

/// Edits one style's system prompt; saved as an override so the default is always
/// recoverable.
struct StylePromptEditor: View {
    let style: MessageStyle
    @State private var prompt: String
    @Environment(\.dismiss) private var dismiss

    init(style: MessageStyle) {
        self.style = style
        _prompt = State(initialValue: style.systemPrompt)
    }

    var body: some View {
        Form {
            Section {
                TextEditor(text: $prompt)
                    .font(.callout)
                    .frame(minHeight: 240)
                    .autocorrectionDisabled()
            } header: {
                Text("Prompt")
            } footer: {
                Text("Tip: keep “Preserve the original language.” and “Output only the message.” at the end for clean, language-correct results.")
            }

            Section {
                Button("Save") {
                    StyleStore.shared.setPrompt(prompt, for: style.id)
                    dismiss()
                }
                .disabled(prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

                if StyleStore.shared.isCustomized(style.id) {
                    Button("Reset to default", role: .destructive) {
                        StyleStore.shared.resetPrompt(for: style.id)
                        prompt = Styles.style(withID: style.id).systemPrompt
                    }
                }
            }
        }
        .navigationTitle("\(style.emoji) \(style.name)")
        .navigationBarTitleDisplayMode(.inline)
    }
}
