
import Foundation

final class MediaServerPreferencesRepository: PreferencesRepository {
    private let userDefaults: UserDefaults
    
    init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
    }
    
    func getShuffleMode() async -> ShuffleMode {
        let isOn = userDefaults.bool(forKey: "shuffleMode")
        return isOn ? .on : .off
    }
    
    func setShuffleMode(_ mode: ShuffleMode) async {
        userDefaults.set(mode == .on, forKey: "shuffleMode")
    }
}

