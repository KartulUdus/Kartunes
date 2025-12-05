
import Foundation

protocol PreferencesRepository {
    func getShuffleMode() async -> ShuffleMode
    func setShuffleMode(_ mode: ShuffleMode) async
}

