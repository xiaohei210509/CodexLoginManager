import SwiftUI

struct ContentView: View {
    @ObservedObject var viewModel: AuthViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            header
            statusPanel
            actionRow
            detailGrid
            logPanel
            Spacer(minLength: 0)
        }
        .padding(24)
        .toolbar {
            ToolbarItemGroup {
                Button {
                    Task { await viewModel.refresh() }
                } label: {
                    Label("重新检查", systemImage: "arrow.clockwise")
                }
                .help("重新检查登录态")
                .disabled(viewModel.isBusy)

                Button {
                    Task { await viewModel.startLogin() }
                } label: {
                    Label("登录", systemImage: "key.fill")
                }
                .help("启动浏览器登录")
                .disabled(!viewModel.canStartLogin)
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Codex 登录管理")
                .font(.system(size: 28, weight: .semibold))
            Text("ChatGPT OAuth")
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
            .help("启动 Codex 浏览器登录")

            Button {
                Task { await viewModel.refresh() }
            } label: {
                Label("重新检查", systemImage: "arrow.clockwise")
            }
            .controlSize(.large)
            .disabled(viewModel.isBusy)
            .help("重新读取 auth.json 并调用 Codex CLI")

            Button {
                viewModel.openCodexApp()
            } label: {
                Label("打开 Codex", systemImage: "app")
            }
            .controlSize(.large)
            .disabled(!viewModel.canOpenCodexApp)
            .help("打开 \(viewModel.status.paths.codexAppPath)")

            Spacer()
        }
    }

    private var detailGrid: some View {
        Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 10) {
            GridRow {
                DetailTile(
                    title: "本地登录态",
                    value: viewModel.status.localAuthSummary,
                    systemImage: "doc.text.magnifyingglass"
                )

                DetailTile(
                    title: "上次检查",
                    value: viewModel.status.checkedAt?.statusTimestamp ?? "未完成",
                    systemImage: "clock"
                )
            }

            GridRow {
                DetailTile(
                    title: "auth.json",
                    value: viewModel.status.paths.authPath,
                    systemImage: "folder"
                )

                DetailTile(
                    title: "Codex CLI",
                    value: viewModel.status.paths.codexCLIPath,
                    systemImage: "terminal"
                )
            }

            GridRow {
                DetailTile(
                    title: "config.toml",
                    value: "\(viewModel.status.paths.configPath)\n本工具不直接写入此文件",
                    systemImage: "checklist.unchecked"
                )

                DetailTile(
                    title: "CLI 状态",
                    value: viewModel.status.cliStatus,
                    systemImage: "text.badge.checkmark"
                )
            }
        }
    }

    private var logPanel: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("输出", systemImage: "scroll")
                .font(.headline)

            ScrollView {
                Text(viewModel.activityLog.isEmpty ? "暂无输出" : viewModel.activityLog)
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
        viewModel.status.isLoggedIn ? "重新登录" : "一键登录"
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
