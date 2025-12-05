# Kartunes

<div align="center">
  <img src="https://raw.githubusercontent.com/KartulUdus/Kartunes/master/Web/public/Assets/Kartunes-logo.png" alt="Kartunes Logo" width="200"/>
</div>

A beautiful, native iOS music player for your Jellyfin and Emby media servers. Stream your entire music library with a modern, intuitive interface designed for iOS.

## Features

### 🎵 Music Library
- **Browse by Artists, Albums, Tracks, Genres, and Playlists** - Navigate your music collection with ease
- **Search** - Quickly find songs, artists, albums, or playlists
- **Recently Played & Recently Added** - Quick access to your latest music
- **Liked Tracks** - Build and manage your favorite songs playlist
- **Genre Browsing** - Explore music by genre with organized umbrella categories

### 🎧 Playback
- **Queue Management** - Build and manage your playback queue
- **Shuffle & Repeat** - Control playback with shuffle and repeat modes
- **Shuffle by Artist** - Discover music by shuffling entire artist catalogs
- **Shuffle by Genre** - Discover music by shuffling random songs from your library by genre
- **Instant Mix** - Generate smart playlists based on artists, tracks or albums
- **Now Playing** - Beautiful full-screen now playing view with album art
- **Mini Player** - Quick access player that follows you throughout the app

### 🚗 CarPlay Support
- ~~Full CarPlay integration for safe, hands-free music control while driving~~
- ~~Browse your library and control playback directly from your car's infotainment system~~
- **Status:** Waiting on approval from Apple

### ⌚ Apple Watch Companion
- Control playback from your wrist
- View now playing information
- Perfect for workouts and on-the-go listening

### 🎨 iOS Integration
- **Dynamic Island** - Live playback controls in the Dynamic Island (iPhone 14 Pro and later)
- **Lock Screen Controls** - Control playback from your lock screen
- **Control Center** - Quick access from Control Center
- **Theme Support** - Light, dark, and system theme options

### 🔄 Sync & Offline
- **Automatic Library Sync** - Keep your library up to date with your media server
- **Progress Tracking** - Real-time sync progress with detailed stage information
- **Core Data Storage** - Efficient local caching for fast access

## Supported Media Servers

Kartunes works with:
- **Jellyfin** - Open-source media server
- **Emby** - Media server platform

The app automatically detects your server type and adapts accordingly.

## Requirements

- iOS 16.0 or later
- A Jellyfin or Emby media server with music library configured
- Network access to your media server

## Getting Started

1. Launch Kartunes on your iOS device
2. Enter your media server URL, username, and password
3. The app will automatically detect your server type (Jellyfin or Emby)
4. Your library will begin syncing automatically
5. Start exploring and playing your music!

## Architecture

Kartunes is built with:
- **SwiftUI** - Modern declarative UI framework
- **Core Data** - Efficient local data storage
- **AVFoundation** - High-quality audio playback
- **Combine** - Reactive programming for state management
- **Async/Await** - Modern concurrency for network operations

The app follows a clean architecture pattern with clear separation between:
- **Domain Layer** - Business logic and entities
- **Data Layer** - Networking, storage, and repositories
- **Features Layer** - UI and user interactions

## Support

If you enjoy using Kartunes, consider supporting its development:

[![ko-fi](https://ko-fi.com/img/githubbutton_sm.svg)](https://ko-fi.com/Y8Y21PQBY8)

## License

This project is private and proprietary. All rights reserved.

---

Made with ❤️ for music lovers who want a beautiful, native iOS experience for their self-hosted music libraries.
