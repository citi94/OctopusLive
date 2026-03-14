import SwiftUI
import WidgetKit

struct SettingsView: View {
    @State private var apiKey: String = SharedConfig.apiKey
    @State private var accountNumber: String = SharedConfig.accountNumber
    @State private var status: ConnectionStatus = SharedConfig.isConfigured ? .connected : .idle
    @State private var errorMessage: String?
    @State private var isConnecting = false
    @State private var showDeleteConfirmation = false

    var onConnect: (() -> Void)?
    var onDisconnect: (() -> Void)?

    enum ConnectionStatus {
        case idle, connecting, connected, error
    }

    var body: some View {
        ZStack {
            Color(red: 0.06, green: 0.06, blue: 0.12)
                .ignoresSafeArea()

            ScrollView {
                VStack(spacing: 24) {
                    header
                    credentialsForm
                    connectButton
                    statusSection

                    if status == .connected {
                        widgetInstructions
                    }

                    disclaimer
                    deleteSection
                }
                .padding()
                .padding(.bottom, 40)
            }
        }
        .navigationTitle(onDisconnect != nil ? "Settings" : "")
        .navigationBarTitleDisplayMode(.inline)
        .preferredColorScheme(.dark)
        .alert("Delete All Data", isPresented: $showDeleteConfirmation) {
            Button("Delete", role: .destructive) { deleteAllData() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This will remove your API key, account details, and all stored data. You will need to reconnect.")
        }
    }

    // MARK: - Header

    private var header: some View {
        VStack(spacing: 8) {
            Image(systemName: "bolt.fill")
                .font(.system(size: 48))
                .foregroundStyle(.yellow)

            Text("Octopus Live")
                .font(.title.bold())
                .foregroundStyle(.white)

            Text("Connect your Octopus Energy account to see live electricity usage on your home screen.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(.top, onDisconnect != nil ? 10 : 40)
    }

    // MARK: - Form

    private var credentialsForm: some View {
        VStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 6) {
                Text("API Key")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                TextField("sk_live_...", text: $apiKey)
                    .textFieldStyle(.plain)
                    .font(.system(.body, design: .monospaced))
                    .padding(12)
                    .background(Color.white.opacity(0.08))
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                    .accessibilityHint("Your Octopus Energy API key, starts with sk_live_")
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("Account Number")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                TextField("A-XXXXXXXX", text: $accountNumber)
                    .textFieldStyle(.plain)
                    .font(.system(.body, design: .monospaced))
                    .padding(12)
                    .background(Color.white.opacity(0.08))
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.characters)
                    .accessibilityHint("Your Octopus Energy account number, starts with A-")
            }

            Text("Find these in your Octopus Energy account under Developer Settings.")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Connect Button

    private var connectButton: some View {
        Button {
            connect()
        } label: {
            HStack(spacing: 8) {
                if isConnecting {
                    ProgressView()
                        .tint(.black)
                } else {
                    Image(systemName: status == .connected ? "checkmark.circle.fill" : "link")
                }
                Text(status == .connected ? "Reconnect" : "Connect")
                    .fontWeight(.semibold)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(apiKey.isEmpty || accountNumber.isEmpty ? Color.gray : Color.yellow)
            .foregroundStyle(.black)
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
        .disabled(apiKey.isEmpty || accountNumber.isEmpty || isConnecting)
    }

    // MARK: - Status

    @ViewBuilder
    private var statusSection: some View {
        switch status {
        case .idle:
            EmptyView()
        case .connecting:
            EmptyView()
        case .connected:
            VStack(spacing: 8) {
                Label("Connected", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                    .font(.headline)

                if !SharedConfig.deviceId.isEmpty {
                    Text("Home Mini: \(SharedConfig.deviceId)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }
            .padding()
            .frame(maxWidth: .infinity)
            .background(Color.green.opacity(0.1))
            .clipShape(RoundedRectangle(cornerRadius: 12))
        case .error:
            VStack(spacing: 8) {
                Label("Connection Failed", systemImage: "xmark.circle.fill")
                    .foregroundStyle(.red)
                    .font(.headline)

                if let errorMessage {
                    Text(errorMessage)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
            }
            .padding()
            .frame(maxWidth: .infinity)
            .background(Color.red.opacity(0.1))
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
    }

    // MARK: - Widget Instructions

    private var widgetInstructions: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Add the Widget")
                .font(.headline)
                .foregroundStyle(.white)

            VStack(alignment: .leading, spacing: 8) {
                instructionRow(number: "1", text: "Go to your home screen and long-press")
                instructionRow(number: "2", text: "Tap the + button (top left)")
                instructionRow(number: "3", text: "Search for \"Octopus Live\"")
                instructionRow(number: "4", text: "Choose small or medium size")
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white.opacity(0.05))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private func instructionRow(number: String, text: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Text(number)
                .font(.caption.bold())
                .frame(width: 22, height: 22)
                .background(Color.yellow.opacity(0.2))
                .foregroundStyle(.yellow)
                .clipShape(Circle())
            Text(text)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Disclaimer

    private var disclaimer: some View {
        VStack(spacing: 6) {
            Text("This app is not affiliated with, endorsed by, or connected to Octopus Energy Ltd.")
                .font(.caption2)
                .foregroundStyle(.secondary.opacity(0.6))
                .multilineTextAlignment(.center)

            Text("Octopus Energy is a trade name of Octopus Energy Ltd.")
                .font(.caption2)
                .foregroundStyle(.secondary.opacity(0.5))
                .multilineTextAlignment(.center)
        }
        .padding(.top, 8)
    }

    // MARK: - Delete Data

    private var deleteSection: some View {
        Button(role: .destructive) {
            showDeleteConfirmation = true
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "trash")
                Text("Delete All Data")
            }
            .font(.subheadline)
            .foregroundStyle(.red.opacity(0.8))
        }
        .padding(.top, 4)
    }

    // MARK: - Actions

    private func connect() {
        isConnecting = true
        status = .connecting
        errorMessage = nil

        Task {
            do {
                let result = try await OctopusAPI.shared.discoverDevice(
                    apiKey: apiKey,
                    accountNumber: accountNumber
                )

                SharedConfig.apiKey = apiKey
                SharedConfig.accountNumber = accountNumber
                SharedConfig.deviceId = result.deviceId
                SharedConfig.mpan = result.mpan
                SharedConfig.meterSerial = result.serial

                await OctopusAPI.shared.clearTokenCache()
                WidgetCenter.shared.reloadAllTimelines()

                await MainActor.run {
                    status = .connected
                    isConnecting = false
                    onConnect?()
                }
            } catch {
                await MainActor.run {
                    status = .error
                    errorMessage = error.localizedDescription
                    isConnecting = false
                }
            }
        }
    }

    private func deleteAllData() {
        SharedConfig.deleteAll()
        WidgetCenter.shared.reloadAllTimelines()
        apiKey = ""
        accountNumber = ""
        status = .idle
        errorMessage = nil
        onDisconnect?()
    }
}

#Preview {
    SettingsView()
}
