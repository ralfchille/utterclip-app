import SwiftUI
import UtterclipCore

/// Default style preference, the editable rewrite-prompt list, and API key entry
/// (plan Phase 6 + §5a). The key is written straight to the Keychain and never leaves
/// the device.
struct SettingsView: View {
    @Bindable var viewModel: RecorderViewModel
    @Environment(\.dismiss) private var dismiss

    @State private var store = StyleStore.shared
    @State private var apiKeyInput = ""
    @State private var hasStoredKey = KeyProvider.shared.hasKey
    @State private var keySaved = false
    @State private var storedProvider = KeyProvider.shared.provider?.displayName
    @State private var keyError: String?
    @State private var syncEnabled = SyncPreference.isEnabled
    @State private var syncStatus = SyncStatus.shared
    /// The switch was flipped this session: history and settings pick it up after a relaunch.
    @State private var syncChangePending = false

    var body: some View {
        SheetNavigation {
            VStack(spacing: 0) {
            #if os(macOS)
            MacHeader(title: "Settings") {
                // Settings saves as you go, so leaving is plain navigation: a close glyph, like
                // History. Only the editor, which can save or discard, keeps Cancel / Done.
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark")
                }
                .accessibilityLabel("Close")
                .keyboardShortcut(.cancelAction) // Escape closes; Return stays with the fields
            }
            #endif
            Form {
                Section {
                    Picker("Default style", selection: defaultStyleBinding) {
                        ForEach(store.styles) { style in
                            Text(style.name).tag(style.id)
                        }
                    }
                } header: {
                    Text("One-tap rewrite")
                } footer: {
                    Text("The style selected when the app opens. The pills above the mic pick the style for the next recording; tap one after a result to re-run it.")
                }

                Section {
                    ForEach(store.styles) { style in
                        NavigationLink {
                            StylePromptEditor(mode: .edit(style))
                        } label: {
                            HStack {
                                Text(style.name)
                                Spacer()
                                if store.isCustomized(style.id) {
                                    Text("Edited")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                        .deleteDisabled(!store.canDelete(style.id)) // the last style stays
                    }
                    .onDelete(perform: deleteStyles)

                    if store.canAddStyle {
                        NavigationLink("Add rewrite prompt…") {
                            StylePromptEditor(mode: .new)
                        }
                    }
                    if store.hasHiddenBuiltIns {
                        Button("Restore deleted defaults") {
                            store.restoreDeletedDefaults()
                        }
                    }
                } header: {
                    Text("Rewrite prompts")
                } footer: {
                    Text(PlatformText.stylesFooter)
                }

                Section {
                    if hasStoredKey, let storedProvider {
                        LabeledContent("Provider", value: storedProvider)
                    }

                    SecureField(
                        hasStoredKey ? "••••••••  (stored in Keychain)" : "Anthropic, OpenAI, Gemini or Groq key",
                        text: $apiKeyInput
                    )
                    .autocapitalizationNever()
                    .autocorrectionDisabled()
                    .onSubmit(saveKey) // Return saves the key (and does not close the sheet)

                    if let keyError {
                        Text(keyError)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }

                    Button(keySaved ? "Saved ✓" : "Save key", action: saveKey)
                        .disabled(apiKeyInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

                    if hasStoredKey {
                        Button("Remove key", role: .destructive) {
                            KeyProvider.shared.deleteApiKey()
                            hasStoredKey = false
                            storedProvider = nil
                            keySaved = false
                        }
                    }
                } header: {
                    Text("AI provider API key")
                } footer: {
                    Text("Kept in the Keychain — and, with iCloud sync on, in your iCloud Keychain so your other devices have it too. The provider is detected from the key. Needed for style rewrites; transcription works without it.")
                }

                // Only on devices that can run Apple's model at all (iOS 26, Apple
                // Intelligence-capable). Elsewhere the section is omitted rather than shown
                // greyed out — there is nothing the user could do about it.
                if viewModel.onDeviceSupported {
                    Section {
                        Toggle("Rewrite on device (Apple Intelligence)", isOn: $viewModel.useOnDeviceModel)
                            .disabled(!viewModel.onDeviceAvailable)
                    } header: {
                        Text("Rewrite engine")
                    } footer: {
                        if let reason = viewModel.onDeviceUnavailabilityReason {
                            Text("Unavailable — \(reason)")
                        } else {
                            Text("Apple's on-device model rewrites without an API key and nothing leaves the device. Quality is a notch below the cloud models — best for Plain and light restyling. Off: rewrites use the API key above.")
                        }
                    }
                }

                Section {
                    Toggle("Sync with iCloud", isOn: $syncEnabled)
                        .onChange(of: syncEnabled) { _, on in
                            SyncPreference.isEnabled = on
                            KeyProvider.shared.applySyncPreference()
                            syncChangePending = true
                        }
                } header: {
                    Text("iCloud")
                } footer: {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("History, rewrite styles, settings and the API key follow you to your other devices, inside your own iCloud account and encrypted by Apple. Nothing passes through anyone else. Off: everything stays on this device.")
                        if syncStatus.accountAvailable == false {
                            Text("Not signed in to iCloud on this device — everything stays here until you are.")
                                .foregroundStyle(.secondary)
                        }
                        if syncChangePending {
                            Text("History and styles switch over the next time you open Utterclip; the API key already has.")
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                Section {
                    Toggle("Redact personal details", isOn: $viewModel.redactPersonalData)
                } header: {
                    Text("Privacy")
                } footer: {
                    Text("Emails, phone numbers, links and addresses are swapped for placeholders before the transcript is sent to the AI provider, and put back in the result. Names stay as they are — detecting them is unreliable and they matter for tone. Audio never leaves the device.")
                }
            }
            .groupedFormStyle()
            .subtleSeparators()
            }
            .ignoreHiddenTitleBar()
            .barChrome(title: "Settings") {
                ToolbarItem(placement: .sheetCancel) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    /// Validates and stores the key; every failure is shown, including a Keychain refusal.
    private func saveKey() {
        let key = apiKeyInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else { return }
        guard AIProvider.detect(key) != nil else {
            keyError = "Unrecognized key. Supported: Anthropic (sk-ant-…), OpenAI (sk-…), Google Gemini (AIza…), Groq (gsk_…)."
            return
        }
        guard KeyProvider.shared.setApiKey(key) else {
            keyError = "The key could not be saved to the Keychain. Try again; if it keeps failing, restart the app."
            return
        }
        keyError = nil
        apiKeyInput = ""
        hasStoredKey = KeyProvider.shared.hasKey
        storedProvider = KeyProvider.shared.provider?.displayName
        keySaved = true
    }

    /// The store refuses to delete the last style; the view model's default-style getter
    /// falls back on its own if the default was deleted.
    private func deleteStyles(at offsets: IndexSet) {
        let styles = store.styles
        for index in offsets {
            store.removeStyle(id: styles[index].id)
        }
    }

    private var defaultStyleBinding: Binding<String> {
        Binding(
            get: { viewModel.defaultStyleID },
            set: { viewModel.defaultStyleID = $0 }
        )
    }
}

/// Creates a user-added style, or edits an existing one. A built-in's name and prompt are
/// saved as overrides so the defaults are always recoverable; a user-added style is edited
/// in place.
struct StylePromptEditor: View {
    enum Mode {
        case new
        case edit(MessageStyle)
    }

    let mode: Mode
    @State private var name: String
    @State private var prompt: String
    @State private var store = StyleStore.shared
    /// Set by Delete so leaving the page afterwards doesn't re-create the style.
    @State private var deleted = false
    @Environment(\.dismiss) private var dismiss

    init(mode: Mode) {
        self.mode = mode
        switch mode {
        case .new:
            _name = State(initialValue: "")
            _prompt = State(initialValue: "")
        case .edit(let style):
            _name = State(initialValue: style.name)
            _prompt = State(initialValue: style.systemPrompt)
        }
    }

    private var editedStyle: MessageStyle? {
        if case .edit(let style) = mode { return style }
        return nil
    }

    private var canSave: Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// Built-ins whose name or prompt was changed can go back to their defaults.
    private var showsReset: Bool {
        guard let style = editedStyle else { return false }
        return !store.isCustom(style.id) && store.isCustomized(style.id)
    }

    /// Anything but the last remaining style can be deleted.
    private var showsDelete: Bool {
        editedStyle.map { store.canDelete($0.id) } ?? false
    }

    var body: some View {
        VStack(spacing: 0) {
        #if os(macOS)
        MacHeader(title: editedStyle?.name ?? "New rewrite prompt", back: { dismiss() }) { EmptyView() }
        #endif
        Form {
            Section {
                TextField("Name", text: $name)
                    .autocapitalizationWords()
            } header: {
                Text("Name")
            } footer: {
                Text("Shown on the style pill.")
            }

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

            if let style = editedStyle, showsReset || showsDelete {
                Section {
                    if showsReset {
                        Button(role: .destructive) {
                            store.resetToDefault(for: style.id)
                            let original = Styles.style(withID: style.id)
                            name = original.name
                            prompt = original.systemPrompt
                        } label: {
                            Text("Reset to default").frame(maxWidth: .infinity)
                        }
                    }
                    if showsDelete {
                        Button(role: .destructive) {
                            deleted = true
                            store.removeStyle(id: style.id)
                            dismiss()
                        } label: {
                            Text("Delete prompt").frame(maxWidth: .infinity)
                        }
                    }
                }
            }
        }
        .groupedFormStyle()
        .subtleSeparators()
        }
        .ignoreHiddenTitleBar()
        .barTitle(editedStyle?.name ?? "New rewrite prompt")
        // No Save button: like the rest of Settings, edits apply when you leave the page —
        // back arrow, Done, or the sheet closing. Empty fields are ignored rather than saved.
        .onDisappear {
            guard !deleted, canSave else { return }
            save()
        }
    }

    private func save() {
        switch mode {
        case .new:
            store.addStyle(name: name, prompt: prompt)
        case .edit(let style):
            if store.isCustom(style.id) {
                store.updateStyle(id: style.id, name: name, prompt: prompt)
            } else {
                store.setName(name, for: style.id)
                store.setPrompt(prompt, for: style.id)
            }
        }
    }
}
