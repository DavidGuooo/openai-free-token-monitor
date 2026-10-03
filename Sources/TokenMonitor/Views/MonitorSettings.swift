import SwiftUI

struct MonitorSettings: View {
    @Bindable var store: MonitorStore
    @State private var key = ""
    @State private var message: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Admin API key").font(.headline)
            SecureField(store.hasKey ? "Paste key to replace saved key" : "Paste your organization Admin key", text: $key)
                .textFieldStyle(.roundedBorder)
            HStack {
                Text(store.hasKey ? "Saved in Keychain" : "Stored securely in Keychain")
                    .font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button("Save") {
                    do {
                        try store.saveKey(key)
                        key = ""
                        message = "Saved"
                    } catch { message = error.localizedDescription }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || store.isPreview || store.isRefreshing)
            }
            if let message { Text(message).font(.caption).foregroundStyle(.secondary) }
            if let error = store.errorMessage { Text(error).font(.caption).foregroundStyle(.orange) }
            Link("Create an Admin key ↗", destination: URL(string: "https://platform.openai.com/settings/organization/admin-keys")!)
                .font(.caption)
        }
        .padding(20)
        .frame(width: 380)
    }
}
