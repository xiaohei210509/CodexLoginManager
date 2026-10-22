import SwiftUI
import UniformTypeIdentifiers

struct DictationPatchView: View {
    @ObservedObject var viewModel: DictationPatchViewModel
    let loginBusy: Bool
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(L10n.text("patch.title")).font(.title2.weight(.semibold))
                        Text(L10n.text("patch.subtitle")).foregroundStyle(.secondary)
                    }
                    Spacer()
                    if viewModel.isBusy { ProgressView().controlSize(.small) }
                    Button { Task { await viewModel.refresh() } } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                    .help(L10n.text("patch.refresh"))
                    .accessibilityLabel(L10n.text("patch.refresh"))
                    .disabled(viewModel.isBusy)
                }

                if let status = viewModel.status {
                    statusSection(status)
                    installationSection(status)
                } else if viewModel.isBusy {
                    HStack {
                        ProgressView().controlSize(.small)
                        Text(L10n.text("patch.checking")).foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, minHeight: 84, alignment: .leading)
                }

                if let message = viewModel.errorMessage {
                    Label {
                        Text(message).textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
                    } icon: { Image(systemName: "exclamationmark.triangle.fill") }
                    .foregroundStyle(.red)
                    .accessibilityIdentifier("patch.error")
                }
                toolSection
                if !viewModel.activityLog.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(L10n.text("detail.output")).font(.headline)
                        ScrollView {
                            Text(viewModel.activityLog)
                                .font(.system(.caption, design: .monospaced))
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .textSelection(.enabled)
                        }
                        .frame(maxHeight: 120)
                    }
                }
            }
            .padding(24)
        }
        .fileImporter(isPresented: $viewModel.choosingDirectory, allowedContentTypes: [.folder]) { result in
            if case let .success(url) = result {
                Task { await viewModel.selectToolDirectory(url) }
            }
        }
        .confirmationDialog(
            viewModel.pendingCommand?.title ?? "",
            isPresented: Binding(
                get: { viewModel.pendingCommand != nil },
                set: { if !$0 { viewModel.pendingCommand = nil } }
            ),
            titleVisibility: .visible
        ) {
            if let command = viewModel.pendingCommand {
                Button(command.title) { Task { await viewModel.confirmCommand(command) } }
                    .disabled(loginBusy || viewModel.isBusy)
            }
            Button(L10n.text("patch.cancel"), role: .cancel) { viewModel.pendingCommand = nil }
        } message: {
            Text(L10n.text(viewModel.pendingCommand == .on ? "patch.confirm_on" : "patch.confirm_restore"))
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { Task { await viewModel.refresh() } }
        }
    }

    private func statusSection(_ status: DictationPatchStatus) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 12) {
                Image(systemName: status.state == .on ? "mic.fill" : "mic.slash")
                    .font(.title2)
                    .foregroundStyle(status.state == .on ? Color.green : Color.secondary)
                    .frame(width: 32)
                VStack(alignment: .leading, spacing: 4) {
                    Text(status.title).font(.headline).accessibilityIdentifier("patch.state")
                    Text(L10n.text(status.state == .on ? "patch.signature.local" : "patch.signature.original"))
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Toggle(L10n.text("patch.toggle"), isOn: Binding(
                    get: { status.state == .on },
                    set: { viewModel.pendingCommand = $0 ? .on : .off }
                ))
                .labelsHidden()
                .toggleStyle(.switch)
                .accessibilityIdentifier("patch.toggle")
                .disabled(!viewModel.canSwitch || loginBusy)
            }
            if status.isRunning {
                Label(L10n.text("patch.running_warning"), systemImage: "pause.circle")
                    .foregroundStyle(.orange)
            } else if loginBusy {
                Label(L10n.text("patch.login_busy"), systemImage: "key")
                    .foregroundStyle(.secondary)
            }
            if status.recoveryRequired {
                HStack {
                    Label(L10n.text("patch.recovery_required"), systemImage: "arrow.uturn.backward.circle")
                        .foregroundStyle(.orange)
                    Spacer()
                    Button(L10n.text("patch.command.recover")) { viewModel.pendingCommand = .recover }
                        .disabled(!viewModel.canRecover || loginBusy)
                }
            } else if !status.isSupported {
                Label(L10n.text("patch.unsupported"), systemImage: "exclamationmark.shield")
                    .foregroundStyle(.orange)
            } else if !status.officialBackupAvailable || !status.patchedArtifactAvailable {
                Label(L10n.text("patch.artifacts_missing"), systemImage: "externaldrive.badge.exclamationmark")
                    .foregroundStyle(.orange)
            } else if !status.installationWritable {
                Label(L10n.text("patch.not_writable"), systemImage: "lock")
                    .foregroundStyle(.orange)
            }
        }
        .padding(.vertical, 16)
        .overlay(alignment: .bottom) { Divider() }
    }

    private func installationSection(_ status: DictationPatchStatus) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(L10n.text("patch.installation")).font(.headline)
            Grid(alignment: .leading, horizontalSpacing: 24, verticalSpacing: 12) {
                infoRow("patch.installed_version", status.installedVersion ?? L10n.text("detail.not_completed"))
                infoRow("patch.supported_version", status.supportedVersion)
                infoRow("patch.backup", L10n.text(status.officialBackupAvailable ? "patch.ready" : "patch.absent"))
                infoRow("patch.app_path", status.installedApp)
            }
            HStack {
                Button { viewModel.openCodex() } label: {
                    Label(L10n.text("action.open_codex"), systemImage: "app")
                }
                .disabled(viewModel.isBusy || status.recoveryRequired || status.state == .missing)
                Spacer()
            }
        }
    }

    private func infoRow(_ key: String, _ value: String) -> some View {
        GridRow {
            Text(L10n.text(key)).foregroundStyle(.secondary)
            Text(value)
                .font(.system(.body, design: .monospaced))
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var toolSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Divider()
            HStack {
                Label(L10n.text("patch.tool"), systemImage: "folder")
                    .font(.headline)
                Spacer()
                Button { viewModel.showToolDirectory() } label: {
                    Image(systemName: "arrow.up.forward.square")
                }
                .help(L10n.text("patch.reveal"))
                .accessibilityLabel(L10n.text("patch.reveal"))
                Button { viewModel.choosingDirectory = true } label: {
                    Image(systemName: "folder.badge.gearshape")
                }
                .help(L10n.text("patch.choose_directory"))
                .accessibilityLabel(L10n.text("patch.choose_directory"))
                .disabled(viewModel.isBusy)
            }
            Text(CodexPaths.abbreviatingHomeDirectory(in: viewModel.toolDirectory.path))
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
