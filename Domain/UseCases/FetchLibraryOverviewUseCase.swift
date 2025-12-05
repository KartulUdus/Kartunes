
import Foundation

struct FetchLibraryOverviewUseCase {
    let libraryRepository: LibraryRepository

    func execute() async throws {
        try await libraryRepository.refreshLibrary()
    }
}

