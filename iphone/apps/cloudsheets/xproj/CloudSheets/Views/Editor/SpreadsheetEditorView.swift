import SwiftUI

private enum SpreadsheetEditorChange {
    case value(sheetId: String, address: String, oldValue: String, newValue: String)
    case style(sheetId: String, address: String, oldStyle: SpreadsheetCellStyle, newStyle: SpreadsheetCellStyle)
}

struct SpreadsheetEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var store: WorkspaceStore
    @ObservedObject var coordinator: SpreadsheetActionCoordinator
    let fileId: String

    @FocusState private var isFormulaFieldFocused: Bool
    @State private var selectedSheetId = ""
    @State private var selectedCellAddress: String?
    @State private var showRenameTabSheet = false
    @State private var renameTabValue = ""
    @State private var showCommentsSheet = false
    @State private var showSheetNavigator = false
    @State private var commentDraft = ""
    @State private var formulaDraft = ""
    @State private var undoStack: [SpreadsheetEditorChange] = []
    @State private var redoStack: [SpreadsheetEditorChange] = []

    private var viewModel: SpreadsheetEditorViewModel {
        SpreadsheetEditorViewModel(store: store, fileId: fileId)
    }

    private var spreadsheet: SpreadsheetFile? {
        viewModel.spreadsheet
    }

    private var file: WorkspaceFile? {
        viewModel.file
    }

    private var selectedSheet: SpreadsheetSheet? {
        spreadsheet?.sheets.first(where: { $0.id == selectedSheetId }) ?? spreadsheet?.sheets.first
    }

    private var comments: [FileComment] {
        (file?.comments ?? []).sorted { $0.createdAt > $1.createdAt }
    }

    private var selectedCellStyle: SpreadsheetCellStyle {
        guard let selectedSheet, let selectedCellAddress else { return SpreadsheetCellStyle() }
        return store.cellStyle(fileId: fileId, sheetId: selectedSheet.id, address: selectedCellAddress)
    }

    var body: some View {
        ZStack {
            SheetsTheme.background.ignoresSafeArea()

            if let spreadsheet, let file, let selectedSheet {
                VStack(spacing: 0) {
                    Text(file.name)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 20)
                        .padding(.vertical, 8)
                        .accessibilityIdentifier("spreadsheet_workbook_title")
                    topToolbar(file: file)
                    Divider().background(SheetsTheme.divider)
                    gridView(sheet: selectedSheet)
                }
                .safeAreaInset(edge: .bottom, spacing: 0) {
                    if selectedCellAddress != nil {
                        formulaComposer
                    } else {
                        sheetTabsBar(spreadsheet: spreadsheet)
                    }
                }
                .sheet(isPresented: $showRenameTabSheet) {
                    RenameItemSheet(
                        title: "Rename tab",
                        name: $renameTabValue,
                        onCancel: { showRenameTabSheet = false }
                    ) {
                        store.renameSpreadsheetTab(fileId: fileId, sheetId: selectedSheetId, newName: renameTabValue)
                        showRenameTabSheet = false
                    }
                }
                .sheet(isPresented: $showCommentsSheet) {
                    SheetsCommentsSheet(
                        comments: comments,
                        commentDraft: $commentDraft,
                        onAddComment: addComment
                    )
                }
                .sheet(isPresented: $showSheetNavigator) {
                    SheetsSheetNavigatorSheet(
                        spreadsheet: spreadsheet,
                        selectedSheetId: $selectedSheetId,
                        onRename: { sheet in
                            renameTabValue = sheet.name
                            selectedSheetId = sheet.id
                            showSheetNavigator = false
                            showRenameTabSheet = true
                        },
                        onDuplicate: { sheet in
                            store.duplicateSpreadsheetTab(fileId: fileId, sheetId: sheet.id)
                        },
                        onDelete: { sheet in
                            store.deleteSpreadsheetTab(fileId: fileId, sheetId: sheet.id)
                        },
                        onAdd: {
                            store.addSpreadsheetTab(fileId: fileId)
                            if let lastSheet = store.spreadsheet(id: fileId)?.sheets.last {
                                selectedSheetId = lastSheet.id
                            }
                        }
                    )
                }
                .onAppear {
                    syncSelectedSheet(with: spreadsheet)
                    syncFormulaDraft()
                }
                .onChange(of: spreadsheet.sheets.count) { _, _ in
                    syncSelectedSheet(with: spreadsheet)
                }
                .onChange(of: selectedSheetId) { _, _ in
                    syncFormulaDraft()
                }
                .onChange(of: selectedCellAddress) { _, _ in
                    syncFormulaDraft()
                }
            } else {
                EmptyStateCard(
                    title: "File unavailable",
                    message: "This spreadsheet could not be loaded from the current workspace source.",
                    systemImage: "tablecells.badge.questionmark",
                    accessibilityIdentifier: AccessibilityID.emptyState("sheets_file_unavailable")
                )
                .padding()
            }
        }
    }

    private func topToolbar(file: WorkspaceFile) -> some View {
        HStack(spacing: 0) {
            Button {
                if selectedCellAddress == nil {
                    dismiss()
                } else {
                    closeSelection()
                }
            } label: {
                Image(systemName: selectedCellAddress == nil ? "chevron.left" : "checkmark")
                    .font(.system(size: 26, weight: .medium))
                    .foregroundStyle(selectedCellAddress == nil ? .white : SheetsTheme.accent)
                    .frame(width: 56, height: 56)
            }
            .buttonStyle(.plain)

            Spacer()

            HStack(spacing: 20) {
                toolbarIcon("arrow.uturn.backward", enabled: !undoStack.isEmpty, action: undoLastChange)
                toolbarIcon("arrow.uturn.forward", enabled: !redoStack.isEmpty, action: redoLastChange)

                if selectedCellAddress == nil {
                    Button {
                        coordinator.beginShare(file: file)
                    } label: {
                        Image(systemName: "person.badge.plus")
                            .font(.system(size: 24, weight: .regular))
                            .foregroundStyle(.white)
                    }
                    .buttonStyle(.plain)

                    Button {
                        showCommentsSheet = true
                    } label: {
                        ZStack(alignment: .topTrailing) {
                            Image(systemName: "message")
                                .font(.system(size: 24, weight: .regular))
                                .foregroundStyle(.white)

                            if comments.isEmpty == false {
                                Text("\(min(comments.count, 9))")
                                    .font(.system(size: 10, weight: .bold))
                                    .foregroundStyle(.black)
                                    .padding(4)
                                    .background(SheetsTheme.accent, in: Circle())
                                    .offset(x: 9, y: -9)
                            }
                        }
                    }
                    .buttonStyle(.plain)
                } else {
                    toolbarIcon("textformat.bold", enabled: true, action: toggleBold)

                    Menu {
                        Button("Align left") { setAlignment(.leading) }
                        Button("Align center") { setAlignment(.center) }
                        Button("Cycle fill color", action: cycleFillStyle)
                        Divider()
                        Button("Insert row below", action: insertRowBelowSelected)
                        Button("Insert column right", action: insertColumnRight)
                        Button("Clear cell", role: .destructive, action: clearSelectedCell)
                    } label: {
                        Image(systemName: "plus")
                            .font(.system(size: 26, weight: .regular))
                            .foregroundStyle(.white)
                    }
                    .buttonStyle(.plain)
                }

                Menu {
                    Button("Comments") {
                        showCommentsSheet = true
                    }
                    Button("Rename spreadsheet") {
                        coordinator.beginRename(file: file)
                    }
                    Button("Share") {
                        coordinator.beginShare(file: file)
                    }
                    Button("Move") {
                        coordinator.beginMove(file: file)
                    }
                    Button("Duplicate spreadsheet") {
                        _ = store.duplicateFile(id: file.id)
                    }
                    Button(file.trashed ? "Restore" : "Move to trash", role: file.trashed ? nil : .destructive) {
                        file.trashed ? store.restoreItem(id: file.id) : store.trashItem(id: file.id)
                    }
                    if let selectedSheet {
                        Button("Insert row below") {
                            store.addSpreadsheetRow(fileId: fileId, sheetId: selectedSheet.id)
                        }
                        Button("Insert column right") {
                            store.addSpreadsheetColumn(fileId: fileId, sheetId: selectedSheet.id)
                        }
                    }
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.system(size: 28, weight: .medium))
                        .foregroundStyle(.white)
                }
                .buttonStyle(.plain)
            }
            .frame(height: 56)
            .padding(.trailing, 20)
        }
        .padding(.top, 12)
        .padding(.bottom, 10)
        .background(SheetsTheme.chrome)
    }

    private func toolbarIcon(_ systemName: String, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 24, weight: .regular))
                .foregroundStyle(enabled ? .white : SheetsTheme.mutedText.opacity(0.45))
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
    }

    private func gridView(sheet: SpreadsheetSheet) -> some View {
        ScrollViewReader { proxy in
            ScrollView([.horizontal, .vertical], showsIndicators: false) {
                LazyVStack(spacing: 0, pinnedViews: []) {
                    HStack(spacing: 0) {
                        rowHeaderCell(text: "", highlighted: false)

                        ForEach(1...sheet.columnCount, id: \.self) { column in
                            let columnLabel = columnName(for: column)
                            headerCell(
                                text: columnLabel,
                                width: cellWidth(for: column),
                                highlighted: selectedColumnLabel == columnLabel
                            )
                        }
                    }

                    ForEach(1...sheet.rowCount, id: \.self) { row in
                        HStack(spacing: 0) {
                            rowHeaderCell(text: "\(row)", highlighted: selectedRowNumber == row)

                            ForEach(1...sheet.columnCount, id: \.self) { column in
                                let address = "\(columnName(for: column))\(row)"
                                let value = store.displayValue(fileId: fileId, sheetId: sheet.id, address: address)
                                let style = store.cellStyle(fileId: fileId, sheetId: sheet.id, address: address)

                                Button {
                                    selectedCellAddress = address
                                    formulaDraft = store.cellRawValue(fileId: fileId, sheetId: sheet.id, address: address)
                                    isFormulaFieldFocused = false
                                } label: {
                                    cellView(
                                        value: value,
                                        style: style,
                                        width: cellWidth(for: column),
                                        isSelected: selectedCellAddress == address,
                                        isHeaderRow: row == 1
                                    )
                                }
                                .buttonStyle(.plain)
                                .id(address)
                                .accessibilityIdentifier(AccessibilityID.sheetCell(address))
                            }
                        }
                    }
                }
                .padding(.bottom, 6)
            }
            .background(SheetsTheme.background)
            .onChange(of: selectedCellAddress) { _, newAddress in
                if let newAddress {
                    withAnimation(.easeInOut(duration: 0.25)) {
                        proxy.scrollTo(newAddress, anchor: .center)
                    }
                }
            }
        }
    }

    private var selectionToolbar: some View {
        VStack(spacing: 0) {
            Divider().background(SheetsTheme.divider)

            HStack(spacing: 14) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(selectedCellAddress ?? "")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(SheetsTheme.accent)
                    Text(selectedRawValue.isEmpty ? "Tap pencil to edit" : selectedRawValue)
                        .font(.system(size: 17, weight: .medium))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
                Spacer()
                Button {
                    formulaDraft = selectedRawValue
                    isFormulaFieldFocused = true
                } label: {
                    Circle()
                        .fill(Color.white.opacity(0.08))
                        .frame(width: 52, height: 52)
                        .overlay {
                            Image(systemName: "pencil")
                                .font(.system(size: 20, weight: .medium))
                                .foregroundStyle(SheetsTheme.mutedText)
                        }
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 22)
            .padding(.vertical, 18)

            Divider().background(SheetsTheme.divider)

            HStack(spacing: 0) {
                toolbarCapsuleLabel
                toolbarButton(icon: "textformat.bold", highlighted: selectedCellStyle.bold, action: toggleBold)
                toolbarButton(icon: "text.alignleft", highlighted: selectedCellStyle.alignment == .leading, action: { setAlignment(.leading) })
                toolbarButton(icon: "text.aligncenter", highlighted: selectedCellStyle.alignment == .center, action: { setAlignment(.center) })
                toolbarButton(icon: "paintbrush", highlighted: selectedCellStyle.fill != .none, action: cycleFillStyle)
                toolbarButton(icon: "rectangle.split.3x1", action: insertRowBelowSelected)
                toolbarButton(icon: "square.grid.3x1.folder.badge.plus", action: insertColumnRight)
            }
            .frame(height: 82)
        }
        .background(SheetsTheme.chrome)
    }

    private var formulaComposer: some View {
        VStack(spacing: 0) {
            Divider().background(SheetsTheme.divider)

            HStack(spacing: 16) {
                Text("fx")
                    .font(.system(size: 36, weight: .regular, design: .serif))
                    .italic()
                    .foregroundStyle(.white)

                Text(selectedCellAddress ?? "")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(SheetsTheme.accent)
                    .frame(width: 40, alignment: .leading)

                TextField("Value", text: $formulaDraft)
                    .font(.system(size: 18, weight: .medium))
                    .foregroundStyle(.white)
                    .textInputAutocapitalization(.never)
                    .disableAutocorrection(true)
                    .focused($isFormulaFieldFocused)
                    .submitLabel(.done)
                    .onSubmit {
                        commitFormulaDraft()
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .background(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(Color.white.opacity(0.08))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .stroke(SheetsTheme.accent.opacity(0.3), lineWidth: 1)
                    )
                    .accessibilityIdentifier(AccessibilityID.sheetFormulaBar)

                Button {
                    commitFormulaDraft()
                } label: {
                    Image(systemName: "checkmark")
                        .font(.system(size: 26, weight: .medium))
                        .foregroundStyle(SheetsTheme.accent)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 12)
        }
        .background(SheetsTheme.chrome)
    }

    private func sheetTabsBar(spreadsheet: SpreadsheetFile) -> some View {
        HStack(spacing: 0) {
            Button {
                showSheetNavigator = true
            } label: {
                Image(systemName: "list.bullet")
                    .font(.system(size: 25, weight: .medium))
                    .foregroundStyle(SheetsTheme.accent)
                    .frame(width: 72, height: 72)
            }
            .buttonStyle(.plain)

            Divider().background(SheetsTheme.divider)

            ForEach(Array(spreadsheet.sheets.enumerated()), id: \.element.id) { _, sheet in
                Button {
                    selectedSheetId = sheet.id
                    closeSelection()
                } label: {
                    HStack(spacing: 8) {
                        Text(sheet.name)
                            .font(.system(size: 22, weight: .medium))
                        if sheet.id == selectedSheetId {
                            Image(systemName: "chevron.down")
                                .font(.system(size: 14, weight: .semibold))
                        }
                    }
                    .foregroundStyle(sheet.id == selectedSheetId ? SheetsTheme.accent : SheetsTheme.mutedText)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(sheet.id == selectedSheetId ? SheetsTheme.panel : SheetsTheme.chrome)
                }
                .buttonStyle(.plain)
                .contextMenu {
                    Button("Rename") {
                        renameTabValue = sheet.name
                        selectedSheetId = sheet.id
                        showRenameTabSheet = true
                    }
                    Button("Duplicate") {
                        store.duplicateSpreadsheetTab(fileId: fileId, sheetId: sheet.id)
                    }
                    if spreadsheet.sheets.count > 1 {
                        Button("Delete", role: .destructive) {
                            store.deleteSpreadsheetTab(fileId: fileId, sheetId: sheet.id)
                        }
                    }
                }
                .accessibilityIdentifier(AccessibilityID.sheetTab(spreadsheet.sheets.firstIndex(where: { $0.id == sheet.id }).map { $0 + 1 } ?? 1))

                Divider().background(SheetsTheme.divider)
            }

            Button {
                store.addSpreadsheetTab(fileId: fileId)
                if let lastSheet = store.spreadsheet(id: fileId)?.sheets.last {
                    selectedSheetId = lastSheet.id
                }
                closeSelection()
            } label: {
                Image(systemName: "plus")
                    .font(.system(size: 28, weight: .regular))
                    .foregroundStyle(SheetsTheme.accent)
                    .frame(width: 72, height: 72)
            }
            .buttonStyle(.plain)
        }
        .frame(height: 72)
        .background(SheetsTheme.chrome)
    }

    private var toolbarCapsuleLabel: some View {
        Text(selectedCellAddress ?? "A1")
            .font(.system(size: 20, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: 92, height: 72)
    }

    private func toolbarButton(icon: String, highlighted: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 24, weight: .regular))
                .foregroundStyle(highlighted ? SheetsTheme.accent : .white)
                .frame(width: 74, height: 72)
                .background(highlighted ? SheetsTheme.accentSoft : Color.clear, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private func headerCell(text: String, width: CGFloat, highlighted: Bool) -> some View {
        Text(text)
            .font(.system(size: 18, weight: .medium))
            .foregroundStyle(SheetsTheme.mutedText)
            .frame(width: width, height: 44)
            .background(highlighted ? SheetsTheme.chromeSecondary : SheetsTheme.headerCell)
            .overlay(alignment: .bottomTrailing) {
                Rectangle()
                    .fill(SheetsTheme.divider)
                    .frame(width: 1)
            }
            .overlay(alignment: .bottom) {
                Rectangle()
                    .fill(SheetsTheme.divider)
                    .frame(height: 1)
            }
    }

    private func rowHeaderCell(text: String, highlighted: Bool) -> some View {
        Text(text)
            .font(.system(size: 18, weight: .medium))
            .foregroundStyle(SheetsTheme.mutedText)
            .frame(width: 56, height: 46)
            .background(highlighted ? SheetsTheme.chromeSecondary : SheetsTheme.chrome)
            .overlay(alignment: .trailing) {
                Rectangle()
                    .fill(SheetsTheme.divider)
                    .frame(width: 1)
            }
            .overlay(alignment: .bottom) {
                Rectangle()
                    .fill(SheetsTheme.divider)
                    .frame(height: 1)
            }
    }

    private func cellView(
        value: String,
        style: SpreadsheetCellStyle,
        width: CGFloat,
        isSelected: Bool,
        isHeaderRow: Bool
    ) -> some View {
        let resolvedValue = value.isEmpty ? " " : value

        return Text(resolvedValue)
            .font(.system(size: isHeaderRow ? 18 : 17, weight: style.bold || isHeaderRow ? .semibold : .regular))
            .foregroundStyle(.white)
            .lineLimit(1)
            .padding(.horizontal, 10)
            .frame(width: width, height: 46, alignment: frameAlignment(for: style.alignment))
            .background(backgroundColor(for: style.fill, isSelected: isSelected))
            .overlay {
                Rectangle()
                    .stroke(isSelected ? SheetsTheme.selection : SheetsTheme.divider, lineWidth: isSelected ? 2 : 1)
            }
    }

    private var selectedRawValue: String {
        guard let selectedSheet, let selectedCellAddress else { return "" }
        return store.cellRawValue(fileId: fileId, sheetId: selectedSheet.id, address: selectedCellAddress)
    }

    private var selectedColumnLabel: String? {
        guard let selectedCellAddress else { return nil }
        return String(selectedCellAddress.prefix(while: { $0.isLetter }))
    }

    private var selectedRowNumber: Int? {
        guard let selectedCellAddress else { return nil }
        return Int(selectedCellAddress.drop(while: { $0.isLetter }))
    }

    private func syncFormulaDraft() {
        guard isFormulaFieldFocused == false else { return }
        formulaDraft = selectedRawValue
    }

    private func closeSelection() {
        isFormulaFieldFocused = false
        selectedCellAddress = nil
        formulaDraft = ""
    }

    private func commitFormulaDraft() {
        guard let selectedSheet, let selectedCellAddress else { return }
        let oldValue = store.cellRawValue(fileId: fileId, sheetId: selectedSheet.id, address: selectedCellAddress)
        guard oldValue != formulaDraft else {
            isFormulaFieldFocused = false
            return
        }

        undoStack.append(.value(sheetId: selectedSheet.id, address: selectedCellAddress, oldValue: oldValue, newValue: formulaDraft))
        redoStack.removeAll()
        store.updateSpreadsheetCell(fileId: fileId, sheetId: selectedSheet.id, address: selectedCellAddress, rawValue: formulaDraft)
        store.transientMessage = "Cell updated"
        isFormulaFieldFocused = false
    }

    private func toggleBold() {
        updateSelectedStyle { style in
            style.bold.toggle()
        }
    }

    private func setAlignment(_ alignment: SpreadsheetCellAlignment) {
        updateSelectedStyle { style in
            style.alignment = alignment
        }
    }

    private func cycleFillStyle() {
        updateSelectedStyle { style in
            switch style.fill {
            case .none:
                style.fill = .mint
            case .mint:
                style.fill = .amber
            case .amber:
                style.fill = .blue
            case .blue:
                style.fill = .none
            }
        }
    }

    private func updateSelectedStyle(_ transform: (inout SpreadsheetCellStyle) -> Void) {
        guard let selectedSheet, let selectedCellAddress else { return }

        let oldStyle = store.cellStyle(fileId: fileId, sheetId: selectedSheet.id, address: selectedCellAddress)
        var newStyle = oldStyle
        transform(&newStyle)
        guard oldStyle != newStyle else { return }

        undoStack.append(.style(sheetId: selectedSheet.id, address: selectedCellAddress, oldStyle: oldStyle, newStyle: newStyle))
        redoStack.removeAll()
        store.updateSpreadsheetCellStyle(fileId: fileId, sheetId: selectedSheet.id, address: selectedCellAddress, style: newStyle)
        store.transientMessage = "Cell style updated"
    }

    private func insertRowBelowSelected() {
        guard let selectedSheet else { return }
        store.addSpreadsheetRow(fileId: fileId, sheetId: selectedSheet.id)
        store.transientMessage = "Inserted row"
    }

    private func insertColumnRight() {
        guard let selectedSheet else { return }
        store.addSpreadsheetColumn(fileId: fileId, sheetId: selectedSheet.id)
        store.transientMessage = "Inserted column"
    }

    private func clearSelectedCell() {
        guard let selectedSheet, let selectedCellAddress else { return }
        formulaDraft = ""
        let oldValue = store.cellRawValue(fileId: fileId, sheetId: selectedSheet.id, address: selectedCellAddress)
        guard oldValue.isEmpty == false else { return }
        undoStack.append(.value(sheetId: selectedSheet.id, address: selectedCellAddress, oldValue: oldValue, newValue: ""))
        redoStack.removeAll()
        store.updateSpreadsheetCell(fileId: fileId, sheetId: selectedSheet.id, address: selectedCellAddress, rawValue: "")
        store.transientMessage = "Cell cleared"
    }

    private func undoLastChange() {
        guard let change = undoStack.popLast() else { return }
        apply(change, useNewValue: false)
        redoStack.append(change)
        store.transientMessage = "Undid last change"
    }

    private func redoLastChange() {
        guard let change = redoStack.popLast() else { return }
        apply(change, useNewValue: true)
        undoStack.append(change)
        store.transientMessage = "Redid last change"
    }

    private func apply(_ change: SpreadsheetEditorChange, useNewValue: Bool) {
        switch change {
        case .value(let sheetId, let address, let oldValue, let newValue):
            selectedSheetId = sheetId
            selectedCellAddress = address
            let value = useNewValue ? newValue : oldValue
            formulaDraft = value
            store.updateSpreadsheetCell(fileId: fileId, sheetId: sheetId, address: address, rawValue: value)
        case .style(let sheetId, let address, let oldStyle, let newStyle):
            selectedSheetId = sheetId
            selectedCellAddress = address
            store.updateSpreadsheetCellStyle(fileId: fileId, sheetId: sheetId, address: address, style: useNewValue ? newStyle : oldStyle)
        }
    }

    private func addComment() {
        let trimmed = commentDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.isEmpty == false else { return }
        store.addComment(fileId: fileId, authorName: store.profile.displayName, body: trimmed)
        commentDraft = ""
        store.transientMessage = "Comment added"
    }

    private func backgroundColor(for fill: SpreadsheetCellFill, isSelected: Bool) -> Color {
        if isSelected {
            return SheetsTheme.selection.opacity(0.20)
        }

        switch fill {
        case .none:
            return SheetsTheme.gridCell
        case .mint:
            return Color(red: 0.12, green: 0.24, blue: 0.18)
        case .amber:
            return Color(red: 0.28, green: 0.20, blue: 0.06)
        case .blue:
            return Color(red: 0.08, green: 0.19, blue: 0.30)
        }
    }

    private func frameAlignment(for alignment: SpreadsheetCellAlignment) -> Alignment {
        switch alignment {
        case .leading:
            return .leading
        case .center:
            return .center
        case .trailing:
            return .trailing
        }
    }

    private func cellWidth(for column: Int) -> CGFloat {
        switch column {
        case 1:
            return 238
        case 2:
            return 198
        default:
            return 176
        }
    }

    private func columnName(for index: Int) -> String {
        var value = index
        var name = ""
        while value > 0 {
            let remainder = (value - 1) % 26
            if let scalar = UnicodeScalar(65 + remainder) {
                name = String(Character(scalar)) + name
            }
            value = (value - 1) / 26
        }
        return name
    }

    private func syncSelectedSheet(with spreadsheet: SpreadsheetFile) {
        if spreadsheet.sheets.contains(where: { $0.id == selectedSheetId }) == false {
            selectedSheetId = spreadsheet.sheets.first?.id ?? ""
        }
    }
}

private struct SheetsCommentsSheet: View {
    @Environment(\.dismiss) private var dismiss
    let comments: [FileComment]
    @Binding var commentDraft: String
    let onAddComment: () -> Void

    var body: some View {
        NavigationStack {
            ZStack {
                SheetsTheme.background.ignoresSafeArea()

                VStack(spacing: 18) {
                    if comments.isEmpty {
                        EmptyStateCard(
                            title: "No comments yet",
                            message: "Use comments to keep spreadsheet feedback inside the file.",
                            systemImage: "message",
                            accessibilityIdentifier: AccessibilityID.emptyState("sheets_comments")
                        )
                    } else {
                        ScrollView {
                            LazyVStack(alignment: .leading, spacing: 12) {
                                ForEach(comments) { comment in
                                    VStack(alignment: .leading, spacing: 6) {
                                        HStack {
                                            Text(comment.authorName)
                                                .font(.system(size: 15, weight: .semibold))
                                                .foregroundStyle(.white)
                                            Spacer()
                                            Text(AppFormatters.shortDate.string(from: comment.createdAt))
                                                .font(.system(size: 12, weight: .medium))
                                                .foregroundStyle(SheetsTheme.mutedText)
                                        }
                                        Text(comment.body)
                                            .font(.system(size: 15))
                                            .foregroundStyle(.white)
                                    }
                                    .padding(14)
                                    .background(SheetsTheme.chrome, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                                }
                            }
                            .padding(.horizontal, 20)
                        }
                    }

                    VStack(spacing: 10) {
                        TextEditor(text: $commentDraft)
                            .frame(height: 110)
                            .padding(8)
                            .background(SheetsTheme.chrome, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                            .foregroundStyle(.white)

                        Button("Add Comment") {
                            onAddComment()
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(SheetsTheme.accent)
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, 12)
                }
                .padding(.top, 16)
            }
            .navigationTitle("Comments")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}

private struct SheetsSheetNavigatorSheet: View {
    @Environment(\.dismiss) private var dismiss
    let spreadsheet: SpreadsheetFile
    @Binding var selectedSheetId: String
    let onRename: (SpreadsheetSheet) -> Void
    let onDuplicate: (SpreadsheetSheet) -> Void
    let onDelete: (SpreadsheetSheet) -> Void
    let onAdd: () -> Void

    var body: some View {
        NavigationStack {
            List {
                ForEach(spreadsheet.sheets) { sheet in
                    HStack {
                        Button {
                            selectedSheetId = sheet.id
                            dismiss()
                        } label: {
                            HStack {
                                Text(sheet.name)
                                    .foregroundStyle(.primary)
                                Spacer()
                                if sheet.id == selectedSheetId {
                                    Image(systemName: "checkmark")
                                        .foregroundStyle(.green)
                                }
                            }
                        }
                        .buttonStyle(.plain)

                        Menu {
                            Button("Rename") {
                                onRename(sheet)
                            }
                            Button("Duplicate") {
                                onDuplicate(sheet)
                            }
                            if spreadsheet.sheets.count > 1 {
                                Button("Delete", role: .destructive) {
                                    onDelete(sheet)
                                }
                            }
                        } label: {
                            Image(systemName: "ellipsis.circle")
                                .font(.system(size: 20))
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .navigationTitle("Sheets")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Close") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Add Tab") {
                        onAdd()
                    }
                }
            }
        }
    }
}
