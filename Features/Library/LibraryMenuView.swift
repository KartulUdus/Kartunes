
import SwiftUI

struct LibraryMenuView: View {
    var body: some View {
        List {
            NavigationLink(value: LibraryCategory.songs) {
                HStack {
                    Image(systemName: "music.note")
                        .font(.title2)
                        .foregroundColor(.blue)
                        .frame(width: 40)
                    Text("Songs")
                        .font(.headline)
                }
                .padding(.vertical, 8)
            }
            
            NavigationLink(value: LibraryCategory.albums) {
                HStack {
                    Image(systemName: "square.stack")
                        .font(.title2)
                        .foregroundColor(.green)
                        .frame(width: 40)
                    Text("Albums")
                        .font(.headline)
                }
                .padding(.vertical, 8)
            }
            
            NavigationLink(value: LibraryCategory.artists) {
                HStack {
                    Image(systemName: "person.2")
                        .font(.title2)
                        .foregroundColor(.purple)
                        .frame(width: 40)
                    Text("Artists")
                        .font(.headline)
                }
                .padding(.vertical, 8)
            }
            
            NavigationLink(value: LibraryCategory.playlists) {
                HStack {
                    Image(systemName: "music.note.list")
                        .font(.title2)
                        .foregroundColor(.orange)
                        .frame(width: 40)
                    Text("Playlists")
                        .font(.headline)
                }
                .padding(.vertical, 8)
            }
            
            NavigationLink(value: LibraryCategory.genres) {
                HStack {
                    Image(systemName: "guitars")
                        .font(.title2)
                        .foregroundColor(.pink)
                        .frame(width: 40)
                    Text("Genres")
                        .font(.headline)
                }
                .padding(.vertical, 8)
            }
        }
        .scrollContentBackground(.hidden)
        .background(Color("AppBackground"))
        .navigationTitle("Library")
    }
}

enum LibraryCategory: Hashable {
    case songs
    case albums
    case artists
    case playlists
    case genres
}

