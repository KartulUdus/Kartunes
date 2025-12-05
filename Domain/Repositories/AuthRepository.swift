
import Foundation

protocol AuthRepository {
    func addServer(host: URL, username: String, password: String, friendlyName: String, serverType: MediaServerType) async throws -> Server
    func listServers() async throws -> [Server]
    func setActiveServer(_ server: Server) async
    func deactivateAllServers() async
    func deleteServer(serverId: UUID) async
    func getActiveServer() async throws -> Server
    func updateServerURL(serverId: UUID, newURL: URL) async
}

