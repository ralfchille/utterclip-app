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
