import Combine
import Foundation

final class DisplayPreferences: ObservableObject {
    @Published var enabledKinds: Set<MetricKind> {
        didSet {
            if enabledKinds.isEmpty {
                enabledKinds = [.memory]
            }
            save()
        }
    }

    @Published var refreshInterval: TimeInterval {
        didSet { save() }
    }

    @Published var showPercentLabels: Bool {
        didSet { save() }
    }

    private let defaults: UserDefaults
    private let enabledKey = "enabledKinds"
    private let refreshKey = "refreshInterval"
    private let percentKey = "showPercentLabels"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults

        let savedKinds = defaults.stringArray(forKey: enabledKey)?
            .compactMap(MetricKind.init(rawValue:))

        enabledKinds = Set(savedKinds?.isEmpty == false ? savedKinds! : [.memory, .network])

        let savedRefresh = defaults.double(forKey: refreshKey)
        refreshInterval = savedRefresh > 0 ? savedRefresh : 2
        showPercentLabels = defaults.object(forKey: percentKey) as? Bool ?? true
    }

    func isEnabled(_ kind: MetricKind) -> Bool {
        enabledKinds.contains(kind)
    }

    func set(_ kind: MetricKind, enabled: Bool) {
        if enabled {
            enabledKinds.insert(kind)
        } else {
            enabledKinds.remove(kind)
        }
    }

    private func save() {
        defaults.set(enabledKinds.map(\.rawValue), forKey: enabledKey)
        defaults.set(refreshInterval, forKey: refreshKey)
        defaults.set(showPercentLabels, forKey: percentKey)
    }
}
