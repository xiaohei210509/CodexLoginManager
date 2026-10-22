import SwiftUI

struct ContentView: View {
    @ObservedObject var viewModel: AuthViewModel
    var patchBusy = false
    var showsToolbar = true

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                header
                statusPanel
                actionRow
                detailGrid
                logPanel
                Spacer(minLength: 0)
            }
            .padding(24)
        }
        .disabled(patchBusy)
        .toolbar {
            if showsToolbar {
                ToolbarItemGroup {
                    Button {
                        Task { await viewModel.refresh() }
                    } label: {
                        Label(L10n.text("toolbar.refresh"), systemImage: "arrow.clockwise")
                    }
                    .help(L10n.text("toolbar.refresh_help"))
                    .disabled(viewModel.isBusy || patchBusy)

                    Button {
                        Task { await viewModel.startLogin() }
                    } label: {
                        Label(L10n.text("toolbar.login"), systemImage: "key.fill")
                    }
                    .help(L10n.text("toolbar.login_help"))
                    .disabled(!viewModel.canStartLogin || patchBusy)
                }
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(L10n.text("header.title"))
                .font(.system(size: 28, weight: .semibold))
            Text(L10n.text("header.subtitle"))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var statusPanel: some View {
        HStack(alignment: .center, spacing: 16) {
            ZStack {
                Circle()
                    .fill(viewModel.status.tint.opacity(0.16))
                Image(systemName: viewModel.status.symbolName)
                    .font(.system(size: 28, weight: .semibold))
                    .foregroundStyle(viewModel.status.tint)
            }
            .frame(width: 58, height: 58)

            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    Text(viewModel.status.title)
                        .font(.title3.weight(.semibold))
                    if viewModel.isBusy {
                        ProgressView()
                            .controlSize(.small)
                    }
                }

                Text(viewModel.status.message)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer()
        }
        .padding(16)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private var actionRow: some View {
        HStack(spacing: 10) {
            Button {
                Task { await viewModel.startLogin() }
            } label: {
                Label(primaryActionTitle, systemImage: "person.crop.circle.badge.plus")
                    .frame(minWidth: 120)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(!viewModel.canStartLogin)
            .help(L10n.text("action.login_help"))

            Button {
                Task { await viewModel.refresh() }
            } label: {
                Label(L10n.text("toolbar.refresh"), systemImage: "arrow.clockwise")
            }
            .controlSize(.large)
            .disabled(viewModel.isBusy)
            .help(L10n.text("action.refresh_help"))

            Button {
                viewModel.openCodexApp()
            } label: {
                Label(L10n.text("action.open_codex"), systemImage: "app")
            }
            .controlSize(.large)
            .disabled(!viewModel.canOpenCodexApp)
            .help(L10n.format("action.open_help", viewModel.status.paths.codexAppPath))

            Spacer()
        }
    }

    private var detailGrid: some View {
        Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 10) {
            GridRow {
                DetailTile(
                    title: L10n.text("detail.local_auth"),
                    value: viewModel.status.localAuthSummary,
                    systemImage: "doc.text.magnifyingglass"
                )

                DetailTile(
                    title: L10n.text("detail.last_checked"),
                    value: viewModel.status.checkedAt?.statusTimestamp ?? L10n.text("detail.not_completed"),
                    systemImage: "clock"
                )
            }

            GridRow {
                DetailTile(
                    title: "auth.json",
                    value: viewModel.status.paths.displayAuthPath,
                    systemImage: "folder"
                )

                DetailTile(
                    title: "Codex CLI",
                    value: viewModel.status.paths.displayCLIPath,
                    systemImage: "terminal"
                )
            }

            GridRow {
                DetailTile(
                    title: "config.toml",
                    value: L10n.format("detail.config_note", viewModel.status.paths.displayConfigPath),
                    systemImage: "checklist.unchecked"
                )

                DetailTile(
                    title: L10n.text("detail.cli_status"),
                    value: viewModel.status.cliStatus,
                    systemImage: "text.badge.checkmark"
                )
            }
        }
    }

    private var logPanel: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(L10n.text("detail.output"), systemImage: "scroll")
                .font(.headline)

            ScrollView {
                Text(viewModel.activityLog.isEmpty ? L10n.text("detail.no_output") : viewModel.activityLog)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)
                    .padding(10)
            }
            .frame(minHeight: 72, maxHeight: 130)
            .background(.quaternary.opacity(0.45), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
    }

    private var primaryActionTitle: String {
        viewModel.status.isLoggedIn ? L10n.text("action.relogin") : L10n.text("action.login")
    }
}

private struct DetailTile: View {
    let title: String
    let value: String
    let systemImage: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(title, systemImage: systemImage)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.primary)

            Text(value)
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(.secondary)
                .lineLimit(4)
                .truncationMode(.middle)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(12)
        .frame(maxWidth: .infinity, minHeight: 86, alignment: .topLeading)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

private extension AuthStatus {
    var symbolName: String {
        switch kind {
        case .checking:
            return "magnifyingglass.circle.fill"
        case .loggedIn:
            return "checkmark.seal.fill"
        case .needsLogin, .apiKeyMode, .missingAuth:
            return "key.slash.fill"
        case .missingCLI:
            return "exclamationmark.triangle.fill"
        case .invalidAuth, .failed:
            return "xmark.octagon.fill"
        case .loginRunning:
            return "person.crop.circle.badge.clock"
        }
    }

    var tint: Color {
        switch kind {
        case .checking, .loginRunning:
            return .blue
        case .loggedIn:
            return .green
        case .needsLogin, .apiKeyMode, .missingAuth:
            return .orange
        case .missingCLI, .invalidAuth, .failed:
            return .red
        }
    }
}

private extension Date {
    var statusTimestamp: String {
        formatted(date: .numeric, time: .standard)
    }
}
