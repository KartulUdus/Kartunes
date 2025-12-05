
import Foundation

struct SearchLibraryUseCase {
    let libraryRepository: LibraryRepository

    func execute(query: String) async throws -> [Track] {
        try await libraryRepository.search(query: query)
    }
    
    func executeAll(query: String) async throws -> SearchResults {
        try await libraryRepository.searchAll(query: query)
    }
}

