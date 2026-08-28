//
//  ContentView.swift
//  mcom
//
//  主界面:左侧串口交互区(LLCOM 风格),右侧快捷命令栏。
//

import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @Environment(SerialManager.self) private var serial
    @Environment(QuickCommandStore.self) private var commandStore

    @State private var input = ""
    @State private var showSettings = false

    var body: some View {
        VStack(spacing: 0) {
            HSplitView {
                leftPanel
                    .frame(minWidth: 600)
                QuickCommandPanel()
                    .frame(minWidth: 160, idealWidth: 270)
            }
            Divider()
            statusBar
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
        }
        .alert("提示", isPresented: Binding(
            get: { serial.errorMessage != nil },
            set: { if !$0 { serial.errorMessage = nil } }
        )) {
            Button("确定") { serial.errorMessage = nil }
        } message: {
            Text(serial.errorMessage ?? "")
        }
    }

    // MARK: - 左栏

    private var leftPanel: some View {
        VStack(spacing: 8) {
            logView
            optionsRow
            actionRow
            sendRow
        }
        .padding(10)
    }

    /// 串口日志区:每条带时间戳与收/发标识,自动滚到底部。
    private var logView: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 2) {
                    ForEach(serial.entries) { entry in
                        LogEntryRow(entry: entry)
                            .id(entry.id)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(6)
            }
            .background(Color(nsColor: .textBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(Color.secondary.opacity(0.3))
            )
            .onChange(of: serial.entries.count) {
                scrollToBottom(proxy: proxy)
            }
            .onChange(of: serial.entries.last?.text) {
                // 连续接收的数据合并进最后一条时,条数不变,也要滚到底
                scrollToBottom(proxy: proxy)
            }
        }
        .frame(maxHeight: .infinity)
        .layoutPriority(1) // 多余空间全部给日志区
    }

    private func scrollToBottom(proxy: ScrollViewProxy) {
        if let last = serial.entries.last {
            proxy.scrollTo(last.id, anchor: .bottom)
        }
    }

    /// 选项行:一行放下,空间不足自动换行。所有选项持久化。
    private var optionsRow: some View {
        func bind(_ get: @escaping () -> Bool, _ set: @escaping (Bool) -> Void) -> Binding<Bool> {
            Binding(get: get, set: set)
        }
        return FlowLayout(spacing: 12) {
            Toggle("RTS", isOn: bind({ serial.rtsEnabled }, { serial.setRTS($0) }))
            Toggle("DTR", isOn: bind({ serial.dtrEnabled }, { serial.setDTR($0) }))
            Toggle("HEX显示", isOn: bind({ serial.hexDisplay }, { serial.setHexDisplay($0) }))
            Toggle("HEX发送", isOn: bind({ serial.hexSend }, { serial.setHexSend($0) }))
            Toggle("末尾加回车换行", isOn: bind({ serial.appendCRLF }, { serial.setAppendCRLF($0) }))
            Toggle("替换不可见字符", isOn: bind({ serial.replaceInvisible }, { serial.setReplaceInvisible($0) }))
            Toggle("停止打印", isOn: bind({ serial.paused }, { serial.setPaused($0) }))
        }
        .toggleStyle(.checkbox)
        .font(.callout)
    }

    /// 操作行:开关串口、清空日志、更多设置。
    private var actionRow: some View {
        HStack(spacing: 10) {
            Button(serial.isOpen ? "关闭串口" : "打开串口") {
                serial.toggleConnection()
            }
            .tint(serial.isOpen ? .red : .green)
            .buttonStyle(.borderedProminent)

            Button("清空日志") {
                serial.clearLog()
            }

            Button {
                showSettings.toggle()
            } label: {
                Label("更多设置", systemImage: "gearshape")
            }
            .popover(isPresented: $showSettings, arrowEdge: .bottom) {
                SettingsView()
            }

            Spacer()
        }
    }

    /// 发送区:多行输入框(固定 3 行高,超出滚动)+ 同高发送按钮(⌘Return 发送)。
    private var sendRow: some View {
        HStack(spacing: 8) {
            TextEditor(text: $input)
                .font(.system(.body, design: .monospaced))
                .scrollContentBackground(.hidden)
                .padding(4)
                .background(Color(nsColor: .textBackgroundColor))
                .clipShape(RoundedRectangle(cornerRadius: 6))
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(Color.secondary.opacity(0.3))
                )
            Button("发送") {
                serial.send(input)
            }
            .buttonStyle(FillHeightButtonStyle())
            .keyboardShortcut(.return, modifiers: .command)
            .disabled(!serial.isOpen)
        }
        .frame(height: 60)
    }

    /// 底部状态栏(通栏):刷新串口、串口选择、波特率、状态、字节统计。
    private var statusBar: some View {
        HStack(spacing: 10) {
            Button("刷新") {
                serial.refreshPorts()
            }
            .fixedSize()
            .help("刷新串口列表")

            Picker("串口", selection: Binding(
                get: { serial.selectedPort },
                set: { serial.setSelectedPort($0) }
            )) {
                if serial.availablePorts.isEmpty {
                    Text("无可用串口").tag("")
                }
                ForEach(serial.availablePorts, id: \.self) { port in
                    Text(port.replacingOccurrences(of: "/dev/cu.", with: ""))
                        .tag(port)
                }
            }
            .labelsHidden()
            .frame(minWidth: 180)
            .disabled(serial.isOpen)

            Picker("波特率", selection: Binding(
                get: { serial.selectedBaud },
                set: { serial.setSelectedBaud($0) }
            )) {
                ForEach(serial.baudRates, id: \.self) { baud in
                    Text(verbatim: "\(baud)").tag(baud)
                }
            }
            .labelsHidden()
            .frame(width: 110)
            .disabled(serial.isOpen)

            Circle()
                .fill(serial.isOpen ? Color.green : Color.red)
                .frame(width: 9, height: 9)
            Text(serial.isOpen ? "已打开" : "已关闭")
                .foregroundStyle(.secondary)

            Spacer()

            Text("已发送: \(serial.txBytes) 字节")
                .foregroundStyle(.secondary)
            Text("已接收: \(serial.rxBytes) 字节")
                .foregroundStyle(.secondary)
        }
        .font(.callout)
    }
}

// MARK: - 日志条目

/// 发送按钮样式:背景填充整个行高(macOS 默认按钮边框不会随 frame 拉伸)。
struct FillHeightButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .padding(.horizontal, 16)
            .frame(maxHeight: .infinity)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(isEnabled
                          ? Color.accentColor.opacity(configuration.isPressed ? 0.7 : 1)
                          : Color.secondary.opacity(0.3))
            )
            .foregroundStyle(.white)
    }
}

struct LogEntryRow: View {
    @Environment(AppSettings.self) private var settings
    let entry: LogEntry

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            switch settings.timestampMode {
            case .none:
                EmptyView()
            case .time:
                Text(AppSettings.timeFormatter.string(from: entry.timestamp))
                    .foregroundStyle(.secondary)
            case .dateTime:
                Text(AppSettings.dateTimeFormatter.string(from: entry.timestamp))
                    .foregroundStyle(.secondary)
            }
            Text(settings.markerStyle.marker(isTX: entry.direction == .tx))
                .foregroundStyle(entry.direction == .tx ? Color.blue : Color.green)
                .fontWeight(.semibold)
            Text(entry.text.isEmpty ? " " : entry.text)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .font(.system(.body, design: .monospaced))
    }
}

// MARK: - 更多设置

struct SettingsView: View {
    @Environment(AppSettings.self) private var settings

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            LabeledContent("时间显示") {
                Picker("时间显示", selection: Binding(
                    get: { settings.timestampMode },
                    set: { settings.setTimestampMode($0) }
                )) {
                    ForEach(AppSettings.TimestampMode.allCases) { mode in
                        Text(mode.label).tag(mode)
                    }
                }
                .labelsHidden()
                .pickerStyle(.segmented)
                .frame(width: 220)
            }

            LabeledContent("收发标识") {
                Picker("收发标识", selection: Binding(
                    get: { settings.markerStyle },
                    set: { settings.setMarkerStyle($0) }
                )) {
                    ForEach(AppSettings.MarkerStyle.allCases) { style in
                        Text(style.label).tag(style)
                    }
                }
                .labelsHidden()
                .pickerStyle(.segmented)
                .frame(width: 220)
            }

            Toggle("保存收发日志到文件", isOn: Binding(
                get: { settings.logEnabled },
                set: { settings.setLogEnabled($0) }
            ))
            .toggleStyle(.checkbox)

            LabeledContent("日志目录") {
                HStack(spacing: 6) {
                    Text(settings.logDirectory.path(percentEncoded: false))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .help(settings.logDirectory.path(percentEncoded: false))
                    Button("选择…") { pickDirectory() }
                    Button {
                        NSWorkspace.shared.open(settings.logDirectory)
                    } label: {
                        Label("打开目录", systemImage: "folder")
                    }
                }
            }

            if settings.logDirectory != AppSettings.defaultLogDirectory {
                Button("恢复默认目录") { settings.resetLogDirectory() }
                    .controlSize(.small)
            }
        }
        .padding(16)
        .frame(width: 420)
    }

    private func pickDirectory() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.prompt = "选择"
        panel.message = "选择收发日志保存目录"
        panel.directoryURL = settings.logDirectory
        if panel.runModal() == .OK, let url = panel.url {
            settings.setLogDirectory(url)
        }
    }
}

// MARK: - 流式布局(一行放不下自动换行)

struct FlowLayout: Layout {
    var spacing: CGFloat = 12

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let rows = computeRows(proposal: proposal, subviews: subviews)
        let height = rows.map(\.height).reduce(0) { $0 + $1 } + spacing * CGFloat(max(rows.count - 1, 0))
        return CGSize(width: proposal.width ?? 0, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let rows = computeRows(proposal: proposal, subviews: subviews)
        var y = bounds.minY
        for row in rows {
            var x = bounds.minX
            for index in row.indices {
                let size = subviews[index].sizeThatFits(.unspecified)
                subviews[index].place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
                x += size.width + spacing
            }
            y += row.height + spacing
        }
    }

    private struct Row {
        var indices: [Int] = []
        var height: CGFloat = 0
    }

    private func computeRows(proposal: ProposedViewSize, subviews: Subviews) -> [Row] {
        let maxWidth = proposal.width ?? .infinity
        var rows: [Row] = [Row()]
        var x: CGFloat = 0
        for (index, subview) in subviews.enumerated() {
            let size = subview.sizeThatFits(.unspecified)
            if x > 0, x + size.width > maxWidth {
                rows.append(Row())
                x = 0
            }
            rows[rows.count - 1].indices.append(index)
            rows[rows.count - 1].height = max(rows[rows.count - 1].height, size.height)
            x += size.width + spacing
        }
        return rows
    }
}

// MARK: - 右栏:快捷命令(分页)

struct QuickCommandPanel: View {
    @Environment(SerialManager.self) private var serial
    @Environment(QuickCommandStore.self) private var store

    @State private var renaming: QuickCommand?
    @State private var renamingPage: QuickCommandPage?
    @State private var deletingPage: QuickCommandPage?
    @State private var importError: String?

    var body: some View {
        VStack(spacing: 0) {
            pageTabBar

            Divider()

            // 不用 List:NSTableView 驱动下行内 TextField 点击聚焦很慢
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(Array(store.selectedPage.commands.enumerated()), id: \.element.id) { index, command in
                        QuickCommandRow(
                            index: index + 1,
                            command: command,
                            onCommit: { newText in
                                var edited = command
                                edited.command = newText
                                store.update(edited)
                            },
                            onSend: { text in serial.send(text) },
                            onDropCommand: { draggedID in
                                store.move(draggedID: draggedID, to: command.id)
                            }
                        )
                        .padding(.horizontal, 8)
                        .contextMenu {
                            Button("修改按钮名称") { renaming = command }
                            Divider()
                            Button("上移") { store.moveUp(command) }
                                .disabled(index == 0)
                            Button("下移") { store.moveDown(command) }
                                .disabled(index == store.selectedPage.commands.count - 1)
                            Divider()
                            Button("删除", role: .destructive) { store.delete(command) }
                        }
                        if index < store.selectedPage.commands.count - 1 {
                            Divider().padding(.leading, 32)
                        }
                    }
                }
                .padding(.vertical, 4)
            }

            Divider()

            HStack {
                Button {
                    // 直接在列表末尾追加一个空白行,不弹窗
                    store.add(QuickCommand(title: "", command: ""))
                } label: {
                    Image(systemName: "plus")
                        .frame(width: 24, height: 16)
                }
                .help("添加命令")

                Button {
                    store.removeLast()
                } label: {
                    Image(systemName: "minus")
                        .frame(width: 24, height: 16)
                }
                .disabled(store.selectedPage.commands.isEmpty)
                .help("删除最后一条命令")

                Spacer()

                Button {
                    exportCurrentPage()
                } label: {
                    Image(systemName: "square.and.arrow.up")
                        .frame(width: 24, height: 16)
                }
                .help("导出当前页")

                Button {
                    importPage()
                } label: {
                    Image(systemName: "square.and.arrow.down")
                        .frame(width: 24, height: 16)
                }
                .help("导入为新页")
            }
            .padding(8)
            .controlSize(.small)
        }
        .sheet(item: $renaming) { command in
            QuickCommandNameEditor(command: command) { edited in
                store.update(edited)
            }
        }
        .sheet(item: $renamingPage) { page in
            PageNameEditor(name: page.name) { name in
                store.renamePage(page, name: name)
            }
        }
        .alert("删除页", isPresented: Binding(
            get: { deletingPage != nil },
            set: { if !$0 { deletingPage = nil } }
        )) {
            Button("删除", role: .destructive) {
                if let page = deletingPage { store.deletePage(page) }
                deletingPage = nil
            }
            Button("取消", role: .cancel) { deletingPage = nil }
        } message: {
            if let page = deletingPage {
                Text("「\(page.name)」包含 \(page.commands.count) 条命令,确定删除吗?")
            }
        }
        .alert("导入失败", isPresented: Binding(
            get: { importError != nil },
            set: { if !$0 { importError = nil } }
        )) {
            Button("确定") { importError = nil }
        } message: {
            Text(importError ?? "")
        }
    }

    /// 页签条:点击切换,尾部 + 添加页,右键重命名/导出/删除。
    private var pageTabBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(store.pages) { page in
                    let selected = page.id == store.selectedPageID
                    Text(page.name)
                        .font(.callout)
                        .lineLimit(1)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(
                            Capsule().fill(selected
                                           ? Color.accentColor
                                           : Color.secondary.opacity(0.15))
                        )
                        .foregroundStyle(selected ? .white : .primary)
                        .contentShape(Capsule())
                        .onTapGesture { store.selectPage(page) }
                        .contextMenu {
                            Button("重命名") { renamingPage = page }
                            Button("导出此页") { export(page) }
                            Divider()
                            Button("删除", role: .destructive) {
                                if page.commands.isEmpty {
                                    store.deletePage(page)
                                } else {
                                    deletingPage = page
                                }
                            }
                            .disabled(store.pages.count <= 1)
                        }
                }

                Button {
                    store.addPage()
                } label: {
                    Image(systemName: "plus")
                        .font(.callout)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .help("添加页")
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
        }
    }

    // MARK: - 导入导出

    private func exportCurrentPage() {
        export(store.selectedPage)
    }

    private func export(_ page: QuickCommandPage) {
        guard let data = store.exportPage(page) else {
            importError = "导出失败:无法编码当前页"
            return
        }
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "\(page.name).json"
        panel.allowedContentTypes = [.json]
        panel.message = "导出快捷命令页"
        if panel.runModal() == .OK, let url = panel.url {
            do {
                try data.write(to: url)
            } catch {
                importError = "写入文件失败:\(error.localizedDescription)"
            }
        }
    }

    private func importPage() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowedContentTypes = [.json]
        panel.message = "选择要导入的快捷命令 JSON 文件"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let data = try Data(contentsOf: url)
            let fallback = url.deletingPathExtension().lastPathComponent
            try store.importPage(from: data, fallbackName: fallback)
        } catch {
            importError = error.localizedDescription
        }
    }
}

/// 快捷命令行:序号(可拖拽排序)+ 可编辑命令输入框 + 发送按钮(名称可自定义)。
/// 编辑在行内本地进行,停顿 300ms 后才写回 Store,避免每个按键都触发全量持久化和列表重建。
struct QuickCommandRow: View {
    let index: Int
    let command: QuickCommand
    let onCommit: (String) -> Void
    let onSend: (String) -> Void
    /// 拖拽排序:参数是被拖动的命令 id,本行是放置目标
    let onDropCommand: (UUID) -> Void

    @State private var text = ""
    @State private var commitTask: Task<Void, Never>?
    @State private var isDropTargeted = false

    var body: some View {
        HStack(spacing: 6) {
            Text(verbatim: "\(index)")
                .monospacedDigit()
                .foregroundStyle(.secondary)
                .frame(minWidth: 18, alignment: .trailing)
                .draggable(command.id.uuidString)

            TextField("命令内容", text: $text)
                .textFieldStyle(.roundedBorder)
                .font(.system(.body, design: .monospaced))
                .onAppear { text = command.command }
                .onChange(of: command.command) {
                    // 外部变更(如导入/其他编辑)时同步,避免覆盖正在输入的内容
                    if text != command.command { text = command.command }
                }
                .onChange(of: text) {
                    commitTask?.cancel()
                    commitTask = Task {
                        try? await Task.sleep(for: .milliseconds(300))
                        guard !Task.isCancelled else { return }
                        onCommit(text)
                    }
                }
                // 接管输入框上的放置,防止拖来的命令 id 被当文本插入
                .dropDestination(for: String.self) { items, _ in
                    handleDrop(items)
                } isTargeted: { targeted in
                    isDropTargeted = targeted
                }

            Button(command.title.isEmpty ? "发送" : command.title) {
                flushCommit()
                onSend(text)
            }
            .disabled(text.isEmpty)
        }
        .padding(.vertical, 2)
        .padding(.horizontal, 4)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(isDropTargeted ? Color.accentColor.opacity(0.15) : .clear)
        )
        .dropDestination(for: String.self) { items, _ in
            handleDrop(items)
        } isTargeted: { targeted in
            isDropTargeted = targeted
        }
        .onDisappear { flushCommit() } // 切换页/关闭时兜底保存
    }

    private func handleDrop(_ items: [String]) -> Bool {
        guard let idString = items.first,
              let id = UUID(uuidString: idString),
              id != command.id else { return false }
        onDropCommand(id)
        return true
    }

    /// 立即把编辑中的内容写回 Store(发送前调用)。
    private func flushCommit() {
        commitTask?.cancel()
        if text != command.command { onCommit(text) }
    }
}

/// 修改快捷命令按钮名称(添加/重命名共用)。
struct QuickCommandNameEditor: View {
    @Environment(\.dismiss) private var dismiss
    @State var command: QuickCommand
    let onSave: (QuickCommand) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("快捷命令").font(.headline)
            TextField("按钮名称(留空显示「发送」)", text: $command.title)
            TextField("命令内容(如:AT+CSQ)", text: $command.command)
                .font(.system(.body, design: .monospaced))
            HStack {
                Spacer()
                Button("取消") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("保存") {
                    onSave(command)
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(command.command.isEmpty)
            }
        }
        .padding(16)
        .frame(width: 320)
    }
}

/// 页重命名弹窗。
struct PageNameEditor: View {
    @Environment(\.dismiss) private var dismiss
    @State var name: String
    let onSave: (String) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("重命名页").font(.headline)
            TextField("页名称", text: $name)
            HStack {
                Spacer()
                Button("取消") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("保存") {
                    onSave(name)
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(16)
        .frame(width: 280)
    }
}

#Preview {
    ContentView()
        .environment(SerialManager(settings: AppSettings()))
        .environment(QuickCommandStore())
        .environment(AppSettings())
}
