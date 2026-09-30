import UIKit

fileprivate extension UIColor {
    static let clockAccent = UIColor(red: 1.0, green: 0.62, blue: 0.04, alpha: 1)
}

final class ViewController: UITabBarController {
    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        tabBar.barStyle = .black
        tabBar.tintColor = .clockAccent
        tabBar.unselectedItemTintColor = UIColor(white: 0.5, alpha: 1)
        setViewControllers(makeTabs(), animated: false)
    }

    private func makeTabs() -> [UIViewController] {
        let world = UINavigationController(rootViewController: WorldClockViewController())
        world.tabBarItem = UITabBarItem(title: "World Clock", image: UIImage(systemName: "globe"), tag: 0)
        world.tabBarItem.accessibilityIdentifier = "clock_tab_world"

        let alarms = UINavigationController(rootViewController: AlarmListViewController())
        alarms.tabBarItem = UITabBarItem(title: "Alarm", image: UIImage(systemName: "alarm"), tag: 1)
        alarms.tabBarItem.accessibilityIdentifier = "clock_tab_alarm"

        let stopwatch = UINavigationController(rootViewController: StopwatchViewController())
        stopwatch.tabBarItem = UITabBarItem(title: "Stopwatch", image: UIImage(systemName: "stopwatch"), tag: 2)
        stopwatch.tabBarItem.accessibilityIdentifier = "clock_tab_stopwatch"

        let timer = UINavigationController(rootViewController: TimerViewController())
        timer.tabBarItem = UITabBarItem(title: "Timer", image: UIImage(systemName: "timer"), tag: 3)
        timer.tabBarItem.accessibilityIdentifier = "clock_tab_timer"

        return [world, alarms, stopwatch, timer]
    }
}

struct ClockCity {
    let name: String
    let timeZone: TimeZone
}

final class WorldClockViewController: UIViewController, UITableViewDataSource, UITableViewDelegate {
    private let tableView = UITableView(frame: .zero, style: .plain)
    private var cities: [ClockCity] = [
        ClockCity(name: "Tehran", timeZone: TimeZone(identifier: "Asia/Tehran") ?? .current),
        ClockCity(name: "New York", timeZone: TimeZone(identifier: "America/New_York") ?? .current),
        ClockCity(name: "London", timeZone: TimeZone(identifier: "Europe/London") ?? .current),
        ClockCity(name: "Tokyo", timeZone: TimeZone(identifier: "Asia/Tokyo") ?? .current)
    ]

    private let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "h:mm a"
        formatter.amSymbol = "AM"
        formatter.pmSymbol = "PM"
        return formatter
    }()

    private var refreshTimer: Timer?

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "World Clock"
        view.backgroundColor = .black
        navigationItem.leftBarButtonItem = editButtonItem
        navigationItem.rightBarButtonItem = UIBarButtonItem(barButtonSystemItem: .add, target: self, action: #selector(addCity))
        navigationController?.navigationBar.prefersLargeTitles = true
        configureTable()
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        refreshTimer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
            self?.tableView.reloadData()
        }
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        refreshTimer?.invalidate()
        refreshTimer = nil
    }

    override func setEditing(_ editing: Bool, animated: Bool) {
        super.setEditing(editing, animated: animated)
        tableView.setEditing(editing, animated: animated)
    }

    @objc private func addCity() {
        let addController = AddWorldClockViewController()
        addController.existingIdentifiers = Set(cities.map { $0.timeZone.identifier })
        addController.onSelect = { [weak self] city in
            self?.cities.append(city)
            self?.tableView.reloadData()
        }
        let nav = UINavigationController(rootViewController: addController)
        nav.navigationBar.barStyle = .black
        nav.navigationBar.tintColor = .clockAccent
        present(nav, animated: true, completion: nil)
    }

    private func configureTable() {
        tableView.translatesAutoresizingMaskIntoConstraints = false
        tableView.backgroundColor = .black
        tableView.separatorColor = UIColor(white: 0.2, alpha: 1)
        tableView.dataSource = self
        tableView.delegate = self
        tableView.rowHeight = 70
        view.addSubview(tableView)

        NSLayoutConstraint.activate([
            tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            tableView.topAnchor.constraint(equalTo: view.topAnchor),
            tableView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
    }

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        cities.count
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "WorldCell") ?? UITableViewCell(style: .subtitle, reuseIdentifier: "WorldCell")
        let city = cities[indexPath.row]
        cell.backgroundColor = .black
        cell.selectionStyle = .none
        cell.textLabel?.textColor = .white
        cell.textLabel?.font = .systemFont(ofSize: 20, weight: .medium)
        cell.detailTextLabel?.textColor = UIColor(white: 0.6, alpha: 1)
        cell.detailTextLabel?.font = .systemFont(ofSize: 13, weight: .regular)
        cell.textLabel?.text = city.name
        cell.detailTextLabel?.text = offsetDescription(for: city.timeZone)
        cell.accessibilityIdentifier = "clock_world_city_\(city.name.lowercased().replacingOccurrences(of: " ", with: "_"))"

        let timeLabel: UILabel
        if let existing = cell.accessoryView as? UILabel {
            timeLabel = existing
        } else {
            timeLabel = UILabel()
            timeLabel.textColor = .white
            timeLabel.font = .systemFont(ofSize: 28, weight: .light)
            cell.accessoryView = timeLabel
        }
        timeFormatter.timeZone = city.timeZone
        timeLabel.text = timeFormatter.string(from: Date())
        timeLabel.sizeToFit()
        return cell
    }

    func tableView(_ tableView: UITableView, canEditRowAt indexPath: IndexPath) -> Bool {
        true
    }

    func tableView(_ tableView: UITableView, commit editingStyle: UITableViewCell.EditingStyle, forRowAt indexPath: IndexPath) {
        guard editingStyle == .delete else { return }
        cities.remove(at: indexPath.row)
        tableView.deleteRows(at: [indexPath], with: .automatic)
    }

    func tableView(_ tableView: UITableView, canMoveRowAt indexPath: IndexPath) -> Bool {
        true
    }

    func tableView(_ tableView: UITableView, moveRowAt sourceIndexPath: IndexPath, to destinationIndexPath: IndexPath) {
        let city = cities.remove(at: sourceIndexPath.row)
        cities.insert(city, at: destinationIndexPath.row)
    }

    private func offsetDescription(for timeZone: TimeZone) -> String {
        let now = Date()
        let local = TimeZone.current.secondsFromGMT(for: now)
        let remote = timeZone.secondsFromGMT(for: now)
        let diffSeconds = remote - local
        let totalMinutes = abs(diffSeconds) / 60
        let hours = totalMinutes / 60
        let minutes = totalMinutes % 60
        let sign = diffSeconds >= 0 ? "+" : "-"
        if minutes == 0 {
            return "Today, \(sign)\(hours)HRS"
        } else {
            return "Today, \(sign)\(hours):\(String(format: "%02d", minutes))HRS"
        }
    }
}

final class AddWorldClockViewController: UIViewController, UITableViewDataSource, UITableViewDelegate, UISearchBarDelegate {
    var onSelect: ((ClockCity) -> Void)?
    var existingIdentifiers: Set<String> = []

    private let searchBar = UISearchBar()
    private let tableView = UITableView(frame: .zero, style: .plain)

    private static let allCities: [ClockCity] = {
        let mapping: [(String, String)] = [
            ("Abu Dhabi", "Asia/Dubai"),
            ("Anchorage", "America/Anchorage"),
            ("Athens", "Europe/Athens"),
            ("Auckland", "Pacific/Auckland"),
            ("Bangkok", "Asia/Bangkok"),
            ("Beijing", "Asia/Shanghai"),
            ("Berlin", "Europe/Berlin"),
            ("Bogota", "America/Bogota"),
            ("Buenos Aires", "America/Argentina/Buenos_Aires"),
            ("Cairo", "Africa/Cairo"),
            ("Chicago", "America/Chicago"),
            ("Dallas", "America/Chicago"),
            ("Delhi", "Asia/Kolkata"),
            ("Denver", "America/Denver"),
            ("Detroit", "America/Detroit"),
            ("Dubai", "Asia/Dubai"),
            ("Dublin", "Europe/Dublin"),
            ("Helsinki", "Europe/Helsinki"),
            ("Hong Kong", "Asia/Hong_Kong"),
            ("Honolulu", "Pacific/Honolulu"),
            ("Houston", "America/Chicago"),
            ("Istanbul", "Europe/Istanbul"),
            ("Jakarta", "Asia/Jakarta"),
            ("Johannesburg", "Africa/Johannesburg"),
            ("Kathmandu", "Asia/Kathmandu"),
            ("Kolkata", "Asia/Kolkata"),
            ("Kuala Lumpur", "Asia/Kuala_Lumpur"),
            ("Lima", "America/Lima"),
            ("Lisbon", "Europe/Lisbon"),
            ("London", "Europe/London"),
            ("Los Angeles", "America/Los_Angeles"),
            ("Madrid", "Europe/Madrid"),
            ("Manila", "Asia/Manila"),
            ("Melbourne", "Australia/Melbourne"),
            ("Mexico City", "America/Mexico_City"),
            ("Miami", "America/New_York"),
            ("Moscow", "Europe/Moscow"),
            ("Mumbai", "Asia/Kolkata"),
            ("Nairobi", "Africa/Nairobi"),
            ("New York", "America/New_York"),
            ("Oslo", "Europe/Oslo"),
            ("Paris", "Europe/Paris"),
            ("Phoenix", "America/Phoenix"),
            ("Rome", "Europe/Rome"),
            ("San Francisco", "America/Los_Angeles"),
            ("Santiago", "America/Santiago"),
            ("São Paulo", "America/Sao_Paulo"),
            ("Seattle", "America/Los_Angeles"),
            ("Seoul", "Asia/Seoul"),
            ("Shanghai", "Asia/Shanghai"),
            ("Singapore", "Asia/Singapore"),
            ("Stockholm", "Europe/Stockholm"),
            ("Sydney", "Australia/Sydney"),
            ("Taipei", "Asia/Taipei"),
            ("Tehran", "Asia/Tehran"),
            ("Tel Aviv", "Asia/Jerusalem"),
            ("Tokyo", "Asia/Tokyo"),
            ("Toronto", "America/Toronto"),
            ("Vancouver", "America/Vancouver"),
            ("Vienna", "Europe/Vienna"),
            ("Warsaw", "Europe/Warsaw"),
            ("Washington, D.C.", "America/New_York"),
            ("Zurich", "Europe/Zurich")
        ]
        return mapping.compactMap { (name, identifier) in
            guard let tz = TimeZone(identifier: identifier) else { return nil }
            return ClockCity(name: name, timeZone: tz)
        }
    }()

    private var filteredCities: [ClockCity] = []

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Choose a City"
        view.backgroundColor = .black
        navigationItem.leftBarButtonItem = UIBarButtonItem(title: "Cancel", style: .plain, target: self, action: #selector(cancel))
        filteredCities = Self.allCities.filter { !existingIdentifiers.contains($0.timeZone.identifier) }
        configureLayout()
    }

    private func configureLayout() {
        searchBar.translatesAutoresizingMaskIntoConstraints = false
        searchBar.placeholder = "Search"
        searchBar.barStyle = .black
        searchBar.delegate = self
        searchBar.accessibilityIdentifier = "worldclock.search"

        tableView.translatesAutoresizingMaskIntoConstraints = false
        tableView.backgroundColor = .black
        tableView.separatorColor = UIColor(white: 0.2, alpha: 1)
        tableView.dataSource = self
        tableView.delegate = self
        tableView.rowHeight = 50

        view.addSubview(searchBar)
        view.addSubview(tableView)

        NSLayoutConstraint.activate([
            searchBar.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            searchBar.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            searchBar.trailingAnchor.constraint(equalTo: view.trailingAnchor),

            tableView.topAnchor.constraint(equalTo: searchBar.bottomAnchor),
            tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            tableView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
    }

    @objc private func cancel() {
        dismiss(animated: true, completion: nil)
    }

    func searchBar(_ searchBar: UISearchBar, textDidChange searchText: String) {
        let available = Self.allCities.filter { !existingIdentifiers.contains($0.timeZone.identifier) }
        if searchText.isEmpty {
            filteredCities = available
        } else {
            filteredCities = available.filter { $0.name.localizedCaseInsensitiveContains(searchText) }
        }
        tableView.reloadData()
    }

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        filteredCities.count
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "CityCell") ?? UITableViewCell(style: .subtitle, reuseIdentifier: "CityCell")
        let city = filteredCities[indexPath.row]
        cell.backgroundColor = .black
        cell.textLabel?.textColor = .white
        cell.textLabel?.font = .systemFont(ofSize: 17, weight: .regular)
        cell.textLabel?.text = city.name
        cell.detailTextLabel?.textColor = UIColor(white: 0.5, alpha: 1)
        cell.detailTextLabel?.font = .systemFont(ofSize: 13, weight: .regular)
        cell.detailTextLabel?.text = city.timeZone.abbreviation() ?? city.timeZone.identifier
        return cell
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        let city = filteredCities[indexPath.row]
        onSelect?(city)
        dismiss(animated: true, completion: nil)
    }
}

struct AlarmItem: Codable {
    var time: Date
    var label: String
    var enabled: Bool
    /// Days of the week this alarm repeats on. Empty means one-time.
    /// 1 = Sunday, 2 = Monday, ..., 7 = Saturday (Calendar.component(.weekday))
    var repeatDays: Set<Int> = []

    var repeatSummary: String {
        if repeatDays.isEmpty { return "Never" }
        if repeatDays == Set([2, 3, 4, 5, 6]) { return "Weekdays" }
        if repeatDays == Set([1, 7]) { return "Weekends" }
        if repeatDays.count == 7 { return "Every day" }
        let names = ["", "Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"]
        return repeatDays.sorted().map { names[$0] }.joined(separator: " ")
    }
}

// Use a container file so deleting app data also clears alarms without a preferences cache.
enum AlarmStorage {
    static var fileURL: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Clock", isDirectory: true)
            .appendingPathComponent("alarms-v1.json")
    }

    static func load(from url: URL = fileURL) -> [AlarmItem]? {
        guard let data = try? Data(contentsOf: url),
              let alarms = try? JSONDecoder().decode([AlarmItem].self, from: data),
              alarms.allSatisfy({ $0.time.timeIntervalSinceReferenceDate.isFinite &&
                  $0.repeatDays.allSatisfy { (1...7).contains($0) } }) else { return nil }
        return alarms
    }

    static func save(_ alarms: [AlarmItem], to url: URL = fileURL) {
        do {
            let data = try JSONEncoder().encode(alarms)
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(),
                                                    withIntermediateDirectories: true)
            try data.write(to: url, options: .atomic)
        } catch {
            NSLog("Clock could not save alarms: %@", error.localizedDescription)
        }
    }
}

final class AlarmListViewController: UIViewController, UITableViewDataSource, UITableViewDelegate {
    private let tableView = UITableView(frame: .zero, style: .plain)
    private var alarms: [AlarmItem] = AlarmStorage.load() ?? AlarmListViewController.defaultAlarms() {
        // Array mutations also trigger didSet: create, edit, toggle, and delete.
        didSet { AlarmStorage.save(alarms) }
    }

    private let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "h:mm"
        formatter.amSymbol = "AM"
        formatter.pmSymbol = "PM"
        return formatter
    }()

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Alarms"
        view.backgroundColor = .black
        navigationItem.leftBarButtonItem = editButtonItem
        navigationItem.rightBarButtonItem = UIBarButtonItem(barButtonSystemItem: .add, target: self, action: #selector(addAlarm))
        navigationController?.navigationBar.prefersLargeTitles = true
        configureTable()
    }

    override func setEditing(_ editing: Bool, animated: Bool) {
        super.setEditing(editing, animated: animated)
        tableView.setEditing(editing, animated: animated)
    }

    private func configureTable() {
        tableView.translatesAutoresizingMaskIntoConstraints = false
        tableView.backgroundColor = .black
        tableView.separatorColor = UIColor(white: 0.2, alpha: 1)
        tableView.dataSource = self
        tableView.delegate = self
        tableView.rowHeight = 76
        view.addSubview(tableView)

        NSLayoutConstraint.activate([
            tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            tableView.topAnchor.constraint(equalTo: view.topAnchor),
            tableView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
    }

    @objc private func addAlarm() {
        let addController = AddAlarmViewController()
        addController.onSave = { [weak self] newAlarm in
            self?.alarms.insert(newAlarm, at: 0)
            self?.tableView.reloadData()
        }
        let nav = UINavigationController(rootViewController: addController)
        nav.navigationBar.barStyle = .black
        nav.navigationBar.tintColor = .white
        present(nav, animated: true, completion: nil)
    }

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        alarms.count
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "AlarmCell") ?? UITableViewCell(style: .subtitle, reuseIdentifier: "AlarmCell")
        let alarm = alarms[indexPath.row]
        cell.backgroundColor = .black
        cell.selectionStyle = .default
        cell.textLabel?.textColor = alarm.enabled ? .white : UIColor(white: 0.5, alpha: 1)
        cell.textLabel?.font = .systemFont(ofSize: 32, weight: .light)
        cell.detailTextLabel?.textColor = UIColor(white: 0.6, alpha: 1)
        cell.detailTextLabel?.font = .systemFont(ofSize: 14, weight: .regular)
        cell.textLabel?.text = timeFormatter.string(from: alarm.time)
        let detail = alarm.repeatDays.isEmpty ? alarm.label : "\(alarm.label), \(alarm.repeatSummary)"
        cell.detailTextLabel?.text = detail
        let labelSlug = alarm.label.lowercased().replacingOccurrences(of: " ", with: "_")
        cell.accessibilityIdentifier = "clock_alarm_row_\(labelSlug.isEmpty ? "idx\(indexPath.row)" : labelSlug)"

        let toggle = UISwitch()
        toggle.isOn = alarm.enabled
        toggle.onTintColor = UIColor(red: 0.15, green: 0.85, blue: 0.33, alpha: 1)
        toggle.tag = indexPath.row
        toggle.addTarget(self, action: #selector(toggleChanged(_:)), for: .valueChanged)
        toggle.accessibilityIdentifier = "clock_alarm_toggle_\(labelSlug.isEmpty ? "idx\(indexPath.row)" : labelSlug)"
        cell.accessoryView = toggle
        return cell
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        let alarm = alarms[indexPath.row]
        let editController = AddAlarmViewController(alarm: alarm)
        editController.onSave = { [weak self] updatedAlarm in
            self?.alarms[indexPath.row] = updatedAlarm
            self?.tableView.reloadRows(at: [indexPath], with: .automatic)
        }
        let nav = UINavigationController(rootViewController: editController)
        nav.navigationBar.barStyle = .black
        nav.navigationBar.tintColor = .white
        present(nav, animated: true, completion: nil)
    }

    func tableView(_ tableView: UITableView, canEditRowAt indexPath: IndexPath) -> Bool {
        true
    }

    func tableView(_ tableView: UITableView, commit editingStyle: UITableViewCell.EditingStyle, forRowAt indexPath: IndexPath) {
        guard editingStyle == .delete else { return }
        alarms.remove(at: indexPath.row)
        tableView.deleteRows(at: [indexPath], with: .automatic)
    }

    @objc private func toggleChanged(_ sender: UISwitch) {
        alarms[sender.tag].enabled = sender.isOn
        tableView.reloadRows(at: [IndexPath(row: sender.tag, section: 0)], with: .none)
    }

    private static func makeTime(hour: Int, minute: Int) -> Date {
        var components = DateComponents()
        components.calendar = Calendar.current
        components.hour = hour
        components.minute = minute
        return components.date ?? Date()
    }

    private static func defaultAlarms() -> [AlarmItem] {
        [
            AlarmItem(time: makeTime(hour: 7, minute: 0), label: "Morning run", enabled: true, repeatDays: [2, 3, 4, 5, 6]),   // Weekdays
            AlarmItem(time: makeTime(hour: 9, minute: 30), label: "Client call", enabled: true, repeatDays: [2, 3, 4, 5, 6]),  // Weekdays
            AlarmItem(time: makeTime(hour: 12, minute: 30), label: "Lunch", enabled: false),
            AlarmItem(time: makeTime(hour: 18, minute: 15), label: "Wrap up", enabled: false, repeatDays: [2, 3, 4, 5, 6])     // Weekdays
        ]
    }
}

final class AddAlarmViewController: UIViewController {
    var onSave: ((AlarmItem) -> Void)?

    private let initialAlarm: AlarmItem?
    private let timePicker = UIDatePicker()
    private let labelField = UITextField()
    private let repeatButton = UIButton(type: .system)
    private var selectedRepeatDays: Set<Int> = []

    init(alarm: AlarmItem? = nil) {
        self.initialAlarm = alarm
        if let alarm {
            self.selectedRepeatDays = alarm.repeatDays
        }
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        self.initialAlarm = nil
        super.init(coder: coder)
    }

    private var repeatButtonTitle: String {
        if selectedRepeatDays.isEmpty { return "Never" }
        if selectedRepeatDays == Set([2, 3, 4, 5, 6]) { return "Weekdays" }
        if selectedRepeatDays == Set([1, 7]) { return "Weekends" }
        if selectedRepeatDays.count == 7 { return "Every day" }
        let names = ["", "Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"]
        return selectedRepeatDays.sorted().map { names[$0] }.joined(separator: " ")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = initialAlarm == nil ? "Add Alarm" : "Edit Alarm"
        view.backgroundColor = .black
        navigationItem.leftBarButtonItem = UIBarButtonItem(title: "Cancel", style: .plain, target: self, action: #selector(cancel))
        navigationItem.rightBarButtonItem = UIBarButtonItem(title: "Save", style: .done, target: self, action: #selector(save))
        configureLayout()
        if let alarm = initialAlarm {
            timePicker.date = alarm.time
            labelField.text = alarm.label
            repeatButton.setTitle(repeatButtonTitle, for: .normal)
        }
    }

    private func configureLayout() {
        timePicker.translatesAutoresizingMaskIntoConstraints = false
        timePicker.datePickerMode = .time
        if #available(iOS 13.4, *) {
            timePicker.preferredDatePickerStyle = .wheels
        }
        timePicker.setValue(UIColor.white, forKey: "textColor")

        labelField.translatesAutoresizingMaskIntoConstraints = false
        labelField.placeholder = "Label"
        labelField.textColor = .white
        labelField.backgroundColor = UIColor(white: 0.15, alpha: 1)
        labelField.layer.cornerRadius = 12
        labelField.leftView = UIView(frame: CGRect(x: 0, y: 0, width: 12, height: 1))
        labelField.leftViewMode = .always

        let labelTitle = UILabel()
        labelTitle.translatesAutoresizingMaskIntoConstraints = false
        labelTitle.text = "Label"
        labelTitle.textColor = UIColor(white: 0.7, alpha: 1)
        labelTitle.font = .systemFont(ofSize: 13, weight: .regular)

        let repeatTitle = UILabel()
        repeatTitle.translatesAutoresizingMaskIntoConstraints = false
        repeatTitle.text = "Repeat"
        repeatTitle.textColor = UIColor(white: 0.7, alpha: 1)
        repeatTitle.font = .systemFont(ofSize: 13, weight: .regular)

        repeatButton.translatesAutoresizingMaskIntoConstraints = false
        repeatButton.contentHorizontalAlignment = .leading
        repeatButton.backgroundColor = UIColor(white: 0.15, alpha: 1)
        repeatButton.layer.cornerRadius = 12
        repeatButton.tintColor = .white
        repeatButton.setTitleColor(.white, for: .normal)
        repeatButton.titleLabel?.font = .systemFont(ofSize: 16, weight: .regular)
        repeatButton.contentEdgeInsets = UIEdgeInsets(top: 0, left: 12, bottom: 0, right: 12)
        repeatButton.setTitle(repeatButtonTitle, for: .normal)
        repeatButton.accessibilityIdentifier = "alarm_repeat_button"
        repeatButton.addTarget(self, action: #selector(presentRepeatPicker), for: .touchUpInside)

        view.addSubview(timePicker)
        view.addSubview(labelTitle)
        view.addSubview(labelField)
        view.addSubview(repeatTitle)
        view.addSubview(repeatButton)

        NSLayoutConstraint.activate([
            timePicker.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 8),
            timePicker.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            timePicker.trailingAnchor.constraint(equalTo: view.trailingAnchor),

            labelTitle.topAnchor.constraint(equalTo: timePicker.bottomAnchor, constant: 24),
            labelTitle.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),

            labelField.topAnchor.constraint(equalTo: labelTitle.bottomAnchor, constant: 8),
            labelField.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
            labelField.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20),
            labelField.heightAnchor.constraint(equalToConstant: 44),

            repeatTitle.topAnchor.constraint(equalTo: labelField.bottomAnchor, constant: 20),
            repeatTitle.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),

            repeatButton.topAnchor.constraint(equalTo: repeatTitle.bottomAnchor, constant: 8),
            repeatButton.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
            repeatButton.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20),
            repeatButton.heightAnchor.constraint(equalToConstant: 44)
        ])
    }

    @objc private func presentRepeatPicker() {
        let picker = RepeatPickerViewController()
        picker.selectedDays = selectedRepeatDays
        picker.onDone = { [weak self] days in
            self?.selectedRepeatDays = days
            self?.repeatButton.setTitle(self?.repeatButtonTitle ?? "Never", for: .normal)
        }
        let nav = UINavigationController(rootViewController: picker)
        nav.navigationBar.barStyle = .black
        nav.navigationBar.tintColor = .clockAccent
        present(nav, animated: true)
    }

    @objc private func cancel() {
        dismiss(animated: true, completion: nil)
    }

    @objc private func save() {
        let labelText = labelField.text?.trimmingCharacters(in: .whitespacesAndNewlines)
        let label = (labelText?.isEmpty == false) ? labelText ?? "Alarm" : "Alarm"
        let enabled = initialAlarm?.enabled ?? true
        let newAlarm = AlarmItem(time: timePicker.date, label: label, enabled: enabled, repeatDays: selectedRepeatDays)
        onSave?(newAlarm)
        dismiss(animated: true, completion: nil)
    }
}

// MARK: - Repeat Day Picker

final class RepeatPickerViewController: UITableViewController {
    var selectedDays: Set<Int> = []
    var onDone: ((Set<Int>) -> Void)?

    private let dayOrder = [2, 3, 4, 5, 6, 7, 1]  // Mon..Sun display order
    private let dayNames = [1: "Sunday", 2: "Monday", 3: "Tuesday", 4: "Wednesday",
                            5: "Thursday", 6: "Friday", 7: "Saturday"]

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Repeat"
        view.backgroundColor = .black
        tableView.backgroundColor = .black
        tableView.separatorColor = UIColor(white: 0.2, alpha: 1)
        navigationItem.leftBarButtonItem = UIBarButtonItem(title: "Cancel", style: .plain, target: self, action: #selector(cancel))
        navigationItem.rightBarButtonItem = UIBarButtonItem(title: "Done", style: .done, target: self, action: #selector(done))
    }

    override func numberOfSections(in tableView: UITableView) -> Int { 2 }

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        section == 0 ? 3 : dayOrder.count  // shortcuts / individual days
    }

    override func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        section == 0 ? "Presets" : "Days"
    }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "Cell") ?? UITableViewCell(style: .default, reuseIdentifier: "Cell")
        cell.backgroundColor = UIColor(white: 0.08, alpha: 1)
        cell.textLabel?.textColor = .white
        cell.tintColor = UIColor(red: 0.2, green: 0.8, blue: 0.3, alpha: 1)

        if indexPath.section == 0 {
            let presets = ["Weekdays", "Weekends", "Every day"]
            let presetValues: [Set<Int>] = [Set([2, 3, 4, 5, 6]), Set([1, 7]), Set([1, 2, 3, 4, 5, 6, 7])]
            cell.textLabel?.text = presets[indexPath.row]
            cell.accessoryType = (selectedDays == presetValues[indexPath.row]) ? .checkmark : .none
            cell.accessibilityIdentifier = "repeat_preset_\(presets[indexPath.row].lowercased().replacingOccurrences(of: " ", with: "_"))"
        } else {
            let day = dayOrder[indexPath.row]
            cell.textLabel?.text = dayNames[day]
            cell.accessoryType = selectedDays.contains(day) ? .checkmark : .none
            cell.accessibilityIdentifier = "repeat_day_\(dayNames[day]?.lowercased() ?? "")"
        }
        return cell
    }

    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        if indexPath.section == 0 {
            let presetValues: [Set<Int>] = [Set([2, 3, 4, 5, 6]), Set([1, 7]), Set([1, 2, 3, 4, 5, 6, 7])]
            selectedDays = presetValues[indexPath.row]
        } else {
            let day = dayOrder[indexPath.row]
            if selectedDays.contains(day) { selectedDays.remove(day) } else { selectedDays.insert(day) }
        }
        tableView.reloadData()
    }

    @objc private func cancel() { dismiss(animated: true, completion: nil) }

    @objc private func done() {
        onDone?(selectedDays)
        dismiss(animated: true, completion: nil)
    }
}

final class StopwatchViewController: UIViewController, UITableViewDataSource {
    private let timeLabel = UILabel()
    private let lapButton = CircleButton(title: "Lap", color: UIColor(white: 0.25, alpha: 1), textColor: .white)
    private let startStopButton = CircleButton(title: "Start", color: UIColor(red: 0.2, green: 0.8, blue: 0.3, alpha: 1), textColor: .white)
    private let tableView = UITableView(frame: .zero, style: .plain)

    private var timer: Timer?
    private var startTime: Date?
    private var elapsed: TimeInterval = 0
    private var laps: [TimeInterval] = []
    private var lapStartElapsed: TimeInterval = 0
    private var isRunning = false

    deinit {
        timer?.invalidate()
        timer = nil
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Stopwatch"
        view.backgroundColor = .black
        navigationController?.navigationBar.prefersLargeTitles = true
        configureUI()
        updateDisplay()
    }

    private func configureUI() {
        timeLabel.translatesAutoresizingMaskIntoConstraints = false
        timeLabel.textColor = .white
        timeLabel.font = .systemFont(ofSize: 64, weight: .light)
        timeLabel.textAlignment = .center

        let buttonStack = UIStackView(arrangedSubviews: [lapButton, startStopButton])
        buttonStack.translatesAutoresizingMaskIntoConstraints = false
        buttonStack.axis = .horizontal
        buttonStack.spacing = 32
        buttonStack.distribution = .fillEqually

        lapButton.addTarget(self, action: #selector(handleLapReset), for: .touchUpInside)
        startStopButton.addTarget(self, action: #selector(handleStartStop), for: .touchUpInside)
        timeLabel.accessibilityIdentifier = "clock_stopwatch_display"
        lapButton.accessibilityIdentifier = "clock_stopwatch_lap_reset"
        startStopButton.accessibilityIdentifier = "clock_stopwatch_start_stop"

        tableView.translatesAutoresizingMaskIntoConstraints = false
        tableView.backgroundColor = .black
        tableView.separatorColor = UIColor(white: 0.2, alpha: 1)
        tableView.dataSource = self
        tableView.rowHeight = 44
        tableView.register(LapCell.self, forCellReuseIdentifier: "LapCell")

        view.addSubview(timeLabel)
        view.addSubview(buttonStack)
        view.addSubview(tableView)

        NSLayoutConstraint.activate([
            timeLabel.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 24),
            timeLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 24),
            timeLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -24),

            buttonStack.topAnchor.constraint(equalTo: timeLabel.bottomAnchor, constant: 24),
            buttonStack.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 24),
            buttonStack.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -24),
            buttonStack.heightAnchor.constraint(equalToConstant: 72),

            tableView.topAnchor.constraint(equalTo: buttonStack.bottomAnchor, constant: 16),
            tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            tableView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
    }

    private func updateDisplay() {
        timeLabel.text = formatStopwatch(elapsed)
        updateButtons()
    }

    private func updateButtons() {
        lapButton.setTitle(isRunning ? "Lap" : "Reset", for: .normal)
        if isRunning {
            startStopButton.setTitle("Stop", for: .normal)
            startStopButton.backgroundColor = UIColor(red: 0.85, green: 0.2, blue: 0.2, alpha: 1)
        } else {
            startStopButton.setTitle("Start", for: .normal)
            startStopButton.backgroundColor = UIColor(red: 0.2, green: 0.8, blue: 0.3, alpha: 1)
        }
    }

    @objc private func handleStartStop() {
        if isRunning {
            stopTimer()
        } else {
            startTimer()
        }
        updateButtons()
    }

    @objc private func handleLapReset() {
        if isRunning {
            // Record the split (time since the last lap) and continue timing.
            let totalElapsed = currentTotalElapsed()
            let split = totalElapsed - lapStartElapsed
            laps.insert(split, at: 0)
            lapStartElapsed = totalElapsed
            tableView.reloadData()
        } else {
            // Reset both the total timer and lap history.
            elapsed = 0
            lapStartElapsed = 0
            laps.removeAll()
            tableView.reloadData()
            updateDisplay()
        }
    }

    private func currentTotalElapsed() -> TimeInterval {
        if let start = startTime {
            return elapsed + Date().timeIntervalSince(start)
        }
        return elapsed
    }

    private func startTimer() {
        isRunning = true
        startTime = Date()
        timer = Timer.scheduledTimer(withTimeInterval: 0.01, repeats: true) { [weak self] _ in
            self?.tick()
        }
    }

    private func stopTimer() {
        isRunning = false
        if let start = startTime {
            elapsed += Date().timeIntervalSince(start)
        }
        startTime = nil
        timer?.invalidate()
        timer = nil
    }

    private func tick() {
        guard let start = startTime else { return }
        let current = elapsed + Date().timeIntervalSince(start)
        timeLabel.text = formatStopwatch(current)
    }

    private func formatStopwatch(_ interval: TimeInterval) -> String {
        let totalHundredths = Int(interval * 100)
        let minutes = totalHundredths / 6000
        let seconds = (totalHundredths / 100) % 60
        let hundredths = totalHundredths % 100
        return String(format: "%02d:%02d.%02d", minutes, seconds, hundredths)
    }

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        laps.count
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "LapCell", for: indexPath) as! LapCell
        let lapIndex = laps.count - indexPath.row
        cell.configure(lapNumber: lapIndex, time: formatStopwatch(laps[indexPath.row]))
        return cell
    }
}

private final class LapCell: UITableViewCell {
    private let nameLabel = UILabel()
    private let timeLabel = UILabel()

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        backgroundColor = .black
        selectionStyle = .none
        nameLabel.textColor = .white
        nameLabel.font = .systemFont(ofSize: 17, weight: .regular)
        nameLabel.translatesAutoresizingMaskIntoConstraints = false
        timeLabel.textColor = .white
        timeLabel.font = .monospacedDigitSystemFont(ofSize: 17, weight: .regular)
        timeLabel.textAlignment = .right
        timeLabel.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(nameLabel)
        contentView.addSubview(timeLabel)
        NSLayoutConstraint.activate([
            nameLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 20),
            nameLabel.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            timeLabel.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -20),
            timeLabel.centerYAnchor.constraint(equalTo: contentView.centerYAnchor)
        ])
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func configure(lapNumber: Int, time: String) {
        nameLabel.text = "Lap \(lapNumber)"
        timeLabel.text = time
    }
}

final class TimerViewController: UIViewController, UIPickerViewDataSource, UIPickerViewDelegate {
    private let pickerView = UIPickerView()
    private let timeLabel = UILabel()
    private let startStopButton = CircleButton(title: "Start", color: UIColor(red: 0.2, green: 0.8, blue: 0.3, alpha: 1), textColor: .white)
    private let resetButton = CircleButton(title: "Reset", color: UIColor(white: 0.25, alpha: 1), textColor: .white)

    private var timer: Timer?
    private var remainingSeconds: Int = 0
    private var isRunning = false

    deinit {
        timer?.invalidate()
        timer = nil
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Timer"
        view.backgroundColor = .black
        navigationController?.navigationBar.prefersLargeTitles = true
        configureUI()
        updateTimeLabel()
    }

    private func configureUI() {
        pickerView.translatesAutoresizingMaskIntoConstraints = false
        pickerView.dataSource = self
        pickerView.delegate = self
        pickerView.setValue(UIColor.white, forKey: "textColor")

        timeLabel.translatesAutoresizingMaskIntoConstraints = false
        timeLabel.textColor = .white
        timeLabel.font = .systemFont(ofSize: 48, weight: .light)
        timeLabel.textAlignment = .center

        let buttonStack = UIStackView(arrangedSubviews: [resetButton, startStopButton])
        buttonStack.translatesAutoresizingMaskIntoConstraints = false
        buttonStack.axis = .horizontal
        buttonStack.spacing = 32
        buttonStack.distribution = .fillEqually

        startStopButton.addTarget(self, action: #selector(handleStartStop), for: .touchUpInside)
        resetButton.addTarget(self, action: #selector(handleReset), for: .touchUpInside)
        timeLabel.accessibilityIdentifier = "clock_timer_display"
        startStopButton.accessibilityIdentifier = "clock_timer_start_stop"
        resetButton.accessibilityIdentifier = "clock_timer_reset"
        pickerView.accessibilityIdentifier = "clock_timer_duration_picker"

        view.addSubview(timeLabel)
        view.addSubview(pickerView)
        view.addSubview(buttonStack)

        NSLayoutConstraint.activate([
            timeLabel.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 24),
            timeLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 24),
            timeLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -24),

            pickerView.topAnchor.constraint(equalTo: timeLabel.bottomAnchor, constant: 16),
            pickerView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            pickerView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            pickerView.heightAnchor.constraint(equalToConstant: 180),

            buttonStack.topAnchor.constraint(equalTo: pickerView.bottomAnchor, constant: 24),
            buttonStack.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 24),
            buttonStack.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -24),
            buttonStack.heightAnchor.constraint(equalToConstant: 72)
        ])
    }

    @objc private func handleStartStop() {
        if isRunning {
            pauseTimer()
        } else {
            startTimer()
        }
    }

    @objc private func handleReset() {
        pauseTimer()
        remainingSeconds = selectedTotalSeconds()
        updateTimeLabel()
    }

    private func startTimer() {
        if remainingSeconds == 0 {
            remainingSeconds = selectedTotalSeconds()
        }
        guard remainingSeconds > 0 else { return }
        isRunning = true
        startStopButton.setTitle("Pause", for: .normal)
        startStopButton.backgroundColor = UIColor(red: 0.85, green: 0.2, blue: 0.2, alpha: 1)
        pickerView.isUserInteractionEnabled = false

        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            self?.tick()
        }
    }

    private func pauseTimer() {
        isRunning = false
        timer?.invalidate()
        timer = nil
        startStopButton.setTitle("Start", for: .normal)
        startStopButton.backgroundColor = UIColor(red: 0.2, green: 0.8, blue: 0.3, alpha: 1)
        pickerView.isUserInteractionEnabled = true
    }

    private func tick() {
        guard remainingSeconds > 0 else { return }
        remainingSeconds -= 1
        updateTimeLabel()

        if remainingSeconds == 0 {
            pauseTimer()
            let alert = UIAlertController(title: "Timer Done", message: "Time is up.", preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: "OK", style: .default, handler: nil))
            present(alert, animated: true, completion: nil)
        }
    }

    private func updateTimeLabel() {
        let hours = remainingSeconds / 3600
        let minutes = (remainingSeconds % 3600) / 60
        let seconds = remainingSeconds % 60
        timeLabel.text = String(format: "%02d:%02d:%02d", hours, minutes, seconds)
    }

    private func selectedTotalSeconds() -> Int {
        let hours = pickerView.selectedRow(inComponent: 0)
        let minutes = pickerView.selectedRow(inComponent: 1)
        let seconds = pickerView.selectedRow(inComponent: 2)
        return hours * 3600 + minutes * 60 + seconds
    }

    func numberOfComponents(in pickerView: UIPickerView) -> Int {
        3
    }

    func pickerView(_ pickerView: UIPickerView, numberOfRowsInComponent component: Int) -> Int {
        switch component {
        case 0: return 24
        case 1: return 60
        default: return 60
        }
    }

    func pickerView(_ pickerView: UIPickerView, titleForRow row: Int, forComponent component: Int) -> String? {
        return String(format: "%02d", row)
    }

    func pickerView(_ pickerView: UIPickerView, didSelectRow row: Int, inComponent component: Int) {
        if !isRunning {
            remainingSeconds = selectedTotalSeconds()
            updateTimeLabel()
        }
    }
}

final class CircleButton: UIButton {
    init(title: String, color: UIColor, textColor: UIColor) {
        super.init(frame: .zero)
        setTitle(title, for: .normal)
        setTitleColor(textColor, for: .normal)
        titleLabel?.font = .systemFont(ofSize: 18, weight: .semibold)
        backgroundColor = color
        translatesAutoresizingMaskIntoConstraints = false
        heightAnchor.constraint(equalToConstant: 72).isActive = true
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        layer.cornerRadius = bounds.height / 2
    }
}
