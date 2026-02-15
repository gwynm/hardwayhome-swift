import SwiftUI

struct SettingsView: View {
    @Bindable var vm: SettingsVM
    let onBack: () -> Void
    @State private var seedConfirmation: String? = nil
    @State private var showClearConfirm = false
    @State private var clearConfirmation: String? = nil

    var body: some View {
        ScrollViewReader { scrollProxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    // Header
                    HStack {
                        Button(action: onBack) {
                            Text("← Back")
                                .font(.system(size: 17, weight: .semibold))
                                .foregroundStyle(.blue)
                        }
                        Spacer()
                        Text("Settings")
                            .font(.system(size: 20, weight: .bold))
                            .foregroundStyle(.white)
                        Spacer()
                        Color.clear.frame(width: 60)
                    }
                    .padding(.bottom, 32)

                    // WebDAV section
                    Text("REMOTE BACKUP (WEBDAV)")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Color(white: 0.56))
                        .tracking(0.5)
                        .padding(.bottom, 16)

                    InputField(label: "Server URL", text: $vm.url,
                               placeholder: "https://mywebdav.example/backups",
                               keyboard: .URL)
                    .onChange(of: vm.url) { vm.hasChanges = true }

                    InputField(label: "Username", text: $vm.username,
                               placeholder: "WebDAV username")
                    .onChange(of: vm.username) { vm.hasChanges = true }

                    InputField(label: "Password", text: $vm.password,
                               placeholder: "WebDAV password",
                               isSecure: true)
                    .onChange(of: vm.password) { vm.hasChanges = true }

                    Text("After each workout, the database is uploaded via HTTP PUT to this URL. A local backup is always saved to Files.app regardless of this setting.")
                        .font(.system(size: 13))
                        .foregroundStyle(Color(white: 0.56))
                        .lineSpacing(4)
                        .padding(.bottom, 24)

                    // Buttons
                    HStack(spacing: 12) {
                        Button(action: { Task { await vm.backupNow() } }) {
                            if vm.isRunning {
                                ProgressView().tint(.white)
                            } else {
                                Text("Backup Now")
                            }
                        }
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(.blue)
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                        .disabled(vm.isRunning)

                        if vm.hasChanges {
                            Button("Save") { vm.save() }
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundStyle(.white)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 14)
                                .background(Color(white: 0.17))
                                .clipShape(RoundedRectangle(cornerRadius: 10))
                        }
                    }
                    .padding(.bottom, 24)

                    // Log output
                    if !vm.logs.isEmpty {
                        VStack(alignment: .leading, spacing: 0) {
                            Text("BACKUP LOG")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(Color(white: 0.56))
                                .tracking(0.5)
                                .padding(.bottom, 8)

                            ForEach(Array(vm.logs.enumerated()), id: \.offset) { _, line in
                                Text(line)
                                    .font(.system(size: 12, design: .monospaced))
                                    .foregroundStyle(logColor(for: line))
                                    .lineSpacing(4)
                            }
                        }
                        .padding(12)
                        .background(Color(red: 0.11, green: 0.11, blue: 0.12))
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                        .padding(.bottom, 24)
                        .id("logBottom")
                        .onChange(of: vm.logs.count) {
                            withAnimation {
                                scrollProxy.scrollTo("logBottom", anchor: .bottom)
                            }
                        }
                    }

                    // Clear button
                    if !vm.url.trimmingCharacters(in: .whitespaces).isEmpty {
                        Button("Clear WebDAV Settings") {
                            vm.clearSettings()
                        }
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(.red)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                    }

                    // Developer tools
                    Text("DEVELOPER")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Color(white: 0.56))
                        .tracking(0.5)
                        .padding(.top, 32)
                        .padding(.bottom, 16)

                    Button(action: {
                        vm.generateSeedData()
                        seedConfirmation = "Added 3 sample workouts"
                        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                            seedConfirmation = nil
                        }
                    }) {
                        Text("Generate Sample Data")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(Color(white: 0.17))
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                    }

                    if let msg = seedConfirmation {
                        Text(msg)
                            .font(.system(size: 13))
                            .foregroundStyle(.green)
                            .padding(.top, 8)
                    }

                    Text("Replaces all existing workouts with 3 sample runs (5k, 3k, 8k).")
                        .font(.system(size: 13))
                        .foregroundStyle(Color(white: 0.56))
                        .lineSpacing(4)
                        .padding(.top, 8)

                    // Clear workout data
                    Button(action: { showClearConfirm = true }) {
                        Text("Clear Workout Data")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(.red)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(Color(white: 0.17))
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                    }
                    .padding(.top, 16)
                    .alert("Clear All Workout Data?",
                           isPresented: $showClearConfirm) {
                        Button("Delete All", role: .destructive) {
                            vm.clearAllWorkoutData()
                            clearConfirmation = "All workout data cleared"
                            DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                                clearConfirmation = nil
                            }
                        }
                        Button("Cancel", role: .cancel) {}
                    } message: {
                        Text("This will permanently delete all workouts, trackpoints, and heart rate data. This cannot be undone.")
                    }

                    if let msg = clearConfirmation {
                        Text(msg)
                            .font(.system(size: 13))
                            .foregroundStyle(.green)
                            .padding(.top, 8)
                    }

                    // Build info
                    Text("\(BuildInfo.gitSha) · \(BuildInfo.buildDate)")
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundStyle(Color(white: 0.39))
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.top, 32)
                }
                .padding(16)
                .padding(.bottom, 40)
            }
        }
        .onAppear { vm.load() }
    }

    private func logColor(for line: String) -> Color {
        if line.hasPrefix("ERROR") || line.hasPrefix("FAILED") { return .red }
        if line == "SUCCESS" { return .green }
        return Color(white: 0.68)
    }

}

// MARK: - Input Field

private struct InputField: View {
    let label: String
    @Binding var text: String
    var placeholder: String = ""
    var isSecure: Bool = false
    var keyboard: UIKeyboardType = .default

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.white)

            Group {
                if isSecure {
                    SecureField(placeholder, text: $text)
                } else {
                    TextField(placeholder, text: $text)
                        .keyboardType(keyboard)
                }
            }
            .autocorrectionDisabled()
            .textInputAutocapitalization(.never)
            .font(.system(size: 15))
            .foregroundStyle(.white)
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(Color(red: 0.17, green: 0.17, blue: 0.18))
            .clipShape(RoundedRectangle(cornerRadius: 10))
        }
        .padding(.bottom, 16)
    }
}
