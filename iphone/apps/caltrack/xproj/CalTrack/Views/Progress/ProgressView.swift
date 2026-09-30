import SwiftUI

struct ProgressTabView: View {
    @ObservedObject var viewModel: ProgressViewModel

    @State private var showWeightSheet = false

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                rangeCard
                summaryCard
                insightCard
                calorieChartCard
                weightChartCard
                exerciseChartCard
                weightHistoryCard
                dailyHistoryCard
                exerciseHistoryCard
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
        .background(FitnessTheme.canvasGradient.ignoresSafeArea())
        .navigationTitle("Progress")
        .accessibilityIdentifier("screen_progress")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Log Weight") {
                    showWeightSheet = true
                }
                .accessibilityIdentifier("progress_weight_log_button")
            }
        }
        .sheet(isPresented: $showWeightSheet) {
            NavigationStack {
                LogWeightSheetView(
                    title: "Log Weight",
                    initialWeightText: AppFormatters.editableWeight(
                        viewModel.store.state.userProfile.weight,
                        unitSystem: viewModel.store.state.userProfile.unitSystem
                    ),
                    unitSystem: viewModel.store.state.userProfile.unitSystem
                ) { pounds in
                    _ = viewModel.logWeight(pounds)
                }
            }
        }
    }

    private var rangeCard: some View {
        ProgressCard(title: "Time Range") {
            Picker("Time Range", selection: $viewModel.selectedRange) {
                ForEach(ProgressRange.allCases) { range in
                    Text(range.displayName).tag(range)
                }
            }
            .pickerStyle(.segmented)
            .accessibilityIdentifier("progress_range_picker")
        }
    }

    private var summaryCard: some View {
        ProgressCard(title: "Summary") {
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                summaryTile(title: "Streak", value: "\(viewModel.summary.streakCount) days", id: "progress_streak_counter")
                summaryTile(title: "Avg Intake", value: "\(viewModel.summary.averageCalories) cal", id: "progress_average_calories")
                summaryTile(title: "Avg Burn", value: "\(viewModel.summary.averageBurned) cal", id: "progress_average_burned")
                summaryTile(title: "Avg Water", value: "\(viewModel.summary.averageWaterCups) cups", id: "progress_average_water")
                summaryTile(title: "Avg Steps", value: "\(viewModel.summary.averageSteps)", id: "progress_average_steps")
                summaryTile(
                    title: "Current Weight",
                    value: viewModel.summary.latestWeight.map {
                        AppFormatters.displayWeight($0, unitSystem: viewModel.store.state.userProfile.unitSystem)
                    } ?? "No data",
                    id: "progress_current_weight"
                )
            }

            Text("Range delta: \(weightDeltaText)")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var insightCard: some View {
        ProgressCard(title: "Insight") {
            Label(progressInsightTitle, systemImage: progressInsightSymbol)
                .font(.headline)
                .foregroundStyle(FitnessTheme.deepText)

            Text(progressInsightBody)
                .font(.subheadline)
                .foregroundStyle(FitnessTheme.secondaryText)
        }
    }

    private var calorieChartCard: some View {
        ProgressCard(title: "Weekly Calories") {
            BarChartView(points: viewModel.caloriePoints, chartID: "calorie_chart")
        }
    }

    private var weightChartCard: some View {
        ProgressCard(title: "Weight Change") {
            LineChartView(points: viewModel.weightPoints, chartID: "weight_chart")
        }
    }

    private var exerciseChartCard: some View {
        ProgressCard(title: "Exercise Frequency") {
            BarChartView(points: viewModel.exercisePoints, chartID: "exercise_chart")
        }
    }

    private var weightHistoryCard: some View {
        ProgressCard(title: "Weight History") {
            if viewModel.weightEntries.isEmpty {
                Text("No weight history yet.")
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("weight_history_empty_state")
            } else {
                ForEach(Array(viewModel.weightEntries.enumerated()), id: \.element.id) { index, entry in
                    NavigationLink {
                        WeightEntryDetailView(viewModel: viewModel, entry: entry)
                    } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(AppFormatters.longDateFormatter.string(from: entry.date))
                                    .font(.headline)
                                Text(AppFormatters.displayWeight(entry.weight, unitSystem: viewModel.store.state.userProfile.unitSystem))
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.caption.weight(.bold))
                                .foregroundStyle(.tertiary)
                        }
                        .padding(.vertical, 4)
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("weight_entry_row_\(String(format: "%03d", index + 1))")
                }
            }
        }
    }

    private var dailyHistoryCard: some View {
        ProgressCard(title: "Calorie Intake History") {
            ForEach(Array(viewModel.dailyHistory.enumerated()), id: \.element.id) { index, summary in
                NavigationLink {
                    DailyHistoryDetailView(log: viewModel.store.dailyLog(for: summary.date))
                } label: {
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(AppFormatters.longDateFormatter.string(from: summary.date))
                                .font(.headline)
                            Text("\(summary.mealCount) foods, \(summary.exerciseCount) exercises")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        VStack(alignment: .trailing, spacing: 4) {
                            Text("\(summary.consumedCalories) cal")
                                .font(.subheadline.weight(.semibold))
                            Text("-\(summary.burnedCalories) burn")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.vertical, 4)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("daily_history_row_\(String(format: "%03d", index + 1))")
            }
        }
    }

    private var exerciseHistoryCard: some View {
        ProgressCard(title: "Exercise History") {
            if viewModel.exerciseHistory.isEmpty {
                Text("No exercise logged in this range.")
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("exercise_history_empty_state")
            } else {
                ForEach(Array(viewModel.exerciseHistory.enumerated()), id: \.element.id) { index, entry in
                    NavigationLink {
                        LoggedExerciseEditorView(viewModel: ExerciseViewModel(store: viewModel.store), entry: entry)
                    } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(entry.exerciseName)
                                    .font(.headline)
                                Text(AppFormatters.monthDayFormatter.string(from: entry.date))
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Text("\(entry.caloriesBurned) cal")
                                .font(.subheadline.weight(.semibold))
                        }
                        .padding(.vertical, 4)
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("exercise_history_row_\(String(format: "%03d", index + 1))")
                }
            }
        }
    }

    private func summaryTile(title: String, value: String, id: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.caption)
                .foregroundStyle(FitnessTheme.secondaryText)
            Text(value)
                .font(.headline)
                .foregroundStyle(FitnessTheme.deepText)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(FitnessTheme.mutedCard)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .accessibilityIdentifier(id)
    }

    private var weightDeltaText: String {
        let delta = viewModel.summary.weightChange
        let prefix = delta > 0 ? "+" : ""
        return "\(prefix)\(AppFormatters.displayWeight(delta, unitSystem: viewModel.store.state.userProfile.unitSystem))"
    }

    private var progressInsightTitle: String {
        if viewModel.summary.averageWaterCups < 6 {
            return "Hydration is the cleanest trend to improve"
        }
        if viewModel.summary.averageSteps < 8_000 {
            return "Daily movement has room to rise"
        }
        if viewModel.summary.weightChange < 0 {
            return "Your trend is moving downward"
        }
        return "Your habits are showing up consistently"
    }

    private var progressInsightBody: String {
        if viewModel.summary.averageWaterCups < 6 {
            return "Your average is \(viewModel.summary.averageWaterCups) cups per day in this range. Pushing that closer to 7 or 8 is the simplest recovery and appetite win."
        }
        if viewModel.summary.averageSteps < 8_000 {
            return "You are averaging \(viewModel.summary.averageSteps) steps. A short walk after lunch or dinner would close most of the gap."
        }
        if viewModel.summary.weightChange < 0 {
            return "You are down \(AppFormatters.displayWeight(abs(viewModel.summary.weightChange), unitSystem: viewModel.store.state.userProfile.unitSystem)) over the selected range."
        }
        return "Calories burned, hydration, and logging frequency are all stable enough to make the data trustworthy."
    }

    private var progressInsightSymbol: String {
        if viewModel.summary.averageWaterCups < 6 {
            return "drop.fill"
        }
        if viewModel.summary.averageSteps < 8_000 {
            return "figure.walk.motion"
        }
        if viewModel.summary.weightChange < 0 {
            return "arrow.down.forward.circle.fill"
        }
        return "checkmark.seal.fill"
    }
}

struct LogWeightSheetView: View {
    let title: String
    let initialWeightText: String
    let unitSystem: UnitSystem
    let onSave: (Double) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var weightText = ""
    @State private var validationMessage: String?

    var body: some View {
        Form {
            Section("Weight") {
                TextField("Weight", text: $weightText)
                    .keyboardType(.decimalPad)
                    .accessibilityIdentifier("weight_value_field")
                Text(unitSystem.shortLabel.uppercased())
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
            }

            if let validationMessage {
                Section {
                    Text(validationMessage)
                        .foregroundStyle(.red)
                        .accessibilityIdentifier("weight_validation_error")
                }
            }

            Section {
                Button("Save Weight") {
                    guard let value = Double(weightText.replacingOccurrences(of: ",", with: ".")), value > 0 else {
                        validationMessage = "Enter a valid weight."
                        return
                    }
                    validationMessage = nil
                    onSave(AppFormatters.pounds(fromEditableWeight: value, unitSystem: unitSystem))
                    dismiss()
                }
                .frame(maxWidth: .infinity, alignment: .center)
                .accessibilityIdentifier("weight_log_confirm_button")
            }
        }
        .navigationTitle(title)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button("Cancel") {
                    dismiss()
                }
                .accessibilityIdentifier("weight_log_cancel_button")
            }
        }
        .onAppear {
            weightText = initialWeightText
        }
    }
}

private struct WeightEntryDetailView: View {
    @ObservedObject var viewModel: ProgressViewModel
    let entry: WeightEntry

    @Environment(\.dismiss) private var dismiss
    @State private var weightText: String
    @State private var selectedDate: Date
    @State private var validationMessage: String?
    @State private var showDeleteConfirmation = false

    init(viewModel: ProgressViewModel, entry: WeightEntry) {
        self.viewModel = viewModel
        self.entry = entry
        _weightText = State(initialValue: AppFormatters.editableWeight(entry.weight, unitSystem: viewModel.store.state.userProfile.unitSystem))
        _selectedDate = State(initialValue: entry.date)
    }

    var body: some View {
        Form {
            Section("Entry") {
                DatePicker("Date", selection: $selectedDate, displayedComponents: .date)
                    .accessibilityIdentifier("weight_entry_date_picker")
                TextField("Weight", text: $weightText)
                    .keyboardType(.decimalPad)
                    .accessibilityIdentifier("weight_entry_value_field")
            }

            if let validationMessage {
                Section {
                    Text(validationMessage)
                        .foregroundStyle(.red)
                        .accessibilityIdentifier("weight_validation_error")
                }
            }

            Section {
                Button("Save Changes") {
                    guard let value = Double(weightText.replacingOccurrences(of: ",", with: ".")), value > 0 else {
                        validationMessage = "Enter a valid weight."
                        return
                    }
                    validationMessage = nil
                    if viewModel.updateWeightEntry(
                        entryID: entry.id,
                        weight: AppFormatters.pounds(fromEditableWeight: value, unitSystem: viewModel.store.state.userProfile.unitSystem),
                        date: selectedDate
                    ) {
                        dismiss()
                    }
                }
                .accessibilityIdentifier("weight_entry_save_button")
            }

            Section {
                Button("Delete Weight Entry", role: .destructive) {
                    showDeleteConfirmation = true
                }
                .accessibilityIdentifier("weight_entry_delete_button")
            }
        }
        .navigationTitle("Weight Entry")
        .alert("Delete Weight Entry?", isPresented: $showDeleteConfirmation) {
            Button("Delete", role: .destructive) {
                viewModel.removeWeightEntry(entryID: entry.id)
                dismiss()
            }
            .accessibilityIdentifier("weight_entry_delete_confirm_button")

            Button("Cancel", role: .cancel) {}
                .accessibilityIdentifier("weight_entry_delete_cancel_button")
        } message: {
            Text("This permanently removes the saved weight entry.")
        }
    }
}

private struct DailyHistoryDetailView: View {
    let log: DailyLog?

    var body: some View {
        List {
            if let log {
                Section {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(AppFormatters.longDateFormatter.string(from: log.date))
                            .font(.headline)
                        Text("\(log.consumedCalories) consumed, \(log.burnedCalories) burned")
                            .foregroundStyle(.secondary)
                        Text("Protein: \(AppFormatters.displayNumber(log.nutritionTotals.protein)) g")
                            .accessibilityIdentifier("daily_history_protein_total")
                        Text("Carbs: \(AppFormatters.displayNumber(log.nutritionTotals.carbs)) g")
                            .accessibilityIdentifier("daily_history_carbs_total")
                        Text("Fat: \(AppFormatters.displayNumber(log.nutritionTotals.fat)) g")
                            .accessibilityIdentifier("daily_history_fat_total")
                    }
                }

                Section("Meals") {
                    if log.mealEntries.isEmpty {
                        Text("No foods logged.")
                    } else {
                        ForEach(log.mealEntries, id: \.id) { entry in
                            HStack {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(entry.foodName)
                                    Text(entry.mealType.rawValue)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                Text("\(entry.calories) cal")
                            }
                        }
                    }
                }

                Section("Exercise") {
                    if log.exerciseEntries.isEmpty {
                        Text("No exercise logged.")
                    } else {
                        ForEach(log.exerciseEntries, id: \.id) { entry in
                            HStack {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(entry.exerciseName)
                                    Text("\(entry.durationMinutes) min")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                Text("\(entry.caloriesBurned) cal")
                            }
                        }
                    }
                }
            } else {
                Section {
                    Text("No history is available for this day.")
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("Day Detail")
        .accessibilityIdentifier("daily_history_detail_screen")
    }
}

private struct ProgressCard<Content: View>: View {
    let title: String
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(title)
                .font(.headline)
                .foregroundStyle(FitnessTheme.deepText)
            content
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(FitnessTheme.cardBackground.opacity(0.96))
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .shadow(color: Color.black.opacity(0.06), radius: 16, y: 8)
    }
}

private struct BarChartView: View {
    let points: [HistoryPoint]
    let chartID: String

    var body: some View {
        if points.isEmpty {
            Text("No chart data available.")
                .foregroundStyle(.secondary)
                .accessibilityIdentifier("\(chartID)_empty_state")
        } else {
            let maxValue = max(points.map(\.value).max() ?? 1, 1)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .bottom, spacing: 10) {
                    ForEach(Array(points.enumerated()), id: \.element.id) { index, point in
                        VStack(spacing: 8) {
                            Text(String(format: "%.0f", point.value))
                                .font(.caption2)
                                .foregroundStyle(FitnessTheme.secondaryText)
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .fill(chartColor)
                                .frame(width: 22, height: CGFloat(point.value / maxValue) * 140 + 10)
                                .accessibilityIdentifier("\(chartID)_bar_\(String(format: "%03d", index + 1))")
                            Text(point.label)
                                .font(.caption2)
                                .foregroundStyle(FitnessTheme.secondaryText)
                                .accessibilityIdentifier("\(chartID)_label_\(String(format: "%03d", index + 1))")
                        }
                    }
                }
                .frame(height: 200, alignment: .bottom)
                .padding(.vertical, 4)
            }
        }
    }

    private var chartColor: Color {
        switch chartID {
        case "exercise_chart":
            return FitnessTheme.accentBlue
        default:
            return FitnessTheme.accent
        }
    }
}

private struct LineChartView: View {
    let points: [HistoryPoint]
    let chartID: String

    var body: some View {
        if points.isEmpty {
            Text("No chart data available.")
                .foregroundStyle(.secondary)
                .accessibilityIdentifier("\(chartID)_empty_state")
        } else {
            GeometryReader { proxy in
                let values = points.map(\.value)
                let minValue = values.min() ?? 0
                let maxValue = values.max() ?? 0
                let range = max(maxValue - minValue, 1)
                let horizontalInset: CGFloat = 14
                let contentWidth = max(proxy.size.width - horizontalInset * 2, 1)
                let step = points.count > 1 ? contentWidth / CGFloat(points.count - 1) : 0

                ZStack(alignment: .topLeading) {
                    Path { path in
                        for (index, point) in points.enumerated() {
                            let x = horizontalInset + CGFloat(index) * step
                            let normalized = (point.value - minValue) / range
                            let y = proxy.size.height - CGFloat(normalized) * (proxy.size.height - 24) - 12
                            if index == 0 {
                                path.move(to: CGPoint(x: x, y: y))
                            } else {
                                path.addLine(to: CGPoint(x: x, y: y))
                            }
                        }
                    }
                    .stroke(FitnessTheme.accentBlue, style: StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round))

                    ForEach(Array(points.enumerated()), id: \.element.id) { index, point in
                        let x = horizontalInset + CGFloat(index) * step
                        let normalized = (point.value - minValue) / range
                        let y = proxy.size.height - CGFloat(normalized) * (proxy.size.height - 24) - 12

                        Circle()
                            .fill(FitnessTheme.accentBlue)
                            .frame(width: 10, height: 10)
                            .position(x: x, y: y)
                            .accessibilityIdentifier("\(chartID)_point_\(String(format: "%03d", index + 1))")

                        if showLabel(at: index, total: points.count) {
                            Text(point.label)
                                .font(.caption2)
                                .foregroundStyle(FitnessTheme.secondaryText)
                                .position(x: x, y: proxy.size.height - 4)
                        }
                    }
                }
            }
            .frame(height: 210)
        }
    }

    private func showLabel(at index: Int, total: Int) -> Bool {
        let maxLabels = 5
        if total <= maxLabels { return true }
        if index == 0 || index == total - 1 { return true }
        let interval = max((total - 1) / (maxLabels - 1), 1)
        return index % interval == 0
    }
}
