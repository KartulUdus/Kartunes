import "./FeaturesPage.css";

export default function FeaturesPage() {
  return (
    <div className="features-page">
      <div className="page-header">
        <h1>Features</h1>
        <p className="page-subtitle">
          Everything you need to enjoy your music library on iOS
        </p>
      </div>

      <div className="features-content">
        <section className="feature-section">
          <h2>🎵 Music Library</h2>
          <div className="feature-grid">
            <div className="feature-card">
              <h3>Browse by Artists, Albums, Tracks, Genres, and Playlists</h3>
              <p>Navigate your music collection with ease. Organize and explore your library the way you want.</p>
            </div>
            <div className="feature-card">
              <h3>Search</h3>
              <p>Quickly find songs, artists, albums, or playlists with fast, intuitive search.</p>
            </div>
            <div className="feature-card">
              <h3>Recently Played & Recently Added</h3>
              <p>Quick access to your latest music and recently discovered tracks.</p>
            </div>
            <div className="feature-card">
              <h3>Liked Tracks</h3>
              <p>Build and manage your favorite songs playlist with a single tap.</p>
            </div>
            <div className="feature-card">
              <h3>Genre Browsing</h3>
              <p>Explore music by genre with organized umbrella categories.</p>
            </div>
          </div>
        </section>

        <section className="feature-section">
          <h2>🎧 Playback & UI</h2>
          <div className="feature-grid">
            <div className="feature-card">
              <h3>Native SwiftUI Interface</h3>
              <p>Beautiful, modern interface built with SwiftUI for a truly native iOS experience.</p>
            </div>
            <div className="feature-card">
              <h3>Queue Management</h3>
              <p>Build and manage your playback queue with full control over what plays next.</p>
            </div>
            <div className="feature-card">
              <h3>Shuffle & Repeat</h3>
              <p>Control playback with shuffle and repeat modes to match your listening style.</p>
            </div>
            <div className="feature-card">
              <h3>Shuffle by Artist</h3>
              <p>Discover music by shuffling entire artist catalogs.</p>
            </div>
            <div className="feature-card">
              <h3>Shuffle by Genre</h3>
              <p>Discover music by shuffling random songs from your library by genre.</p>
            </div>
            <div className="feature-card">
              <h3>Instant Mix</h3>
              <p>Generate smart playlists based on artists, tracks, or albums.</p>
            </div>
            <div className="feature-card">
              <h3>Now Playing</h3>
              <p>Beautiful full-screen now playing view with album art and playback controls.</p>
            </div>
            <div className="feature-card">
              <h3>Mini Player</h3>
              <p>Quick access player that follows you throughout the app.</p>
            </div>
            <div className="feature-card">
              <h3>Dynamic Island & Lock Screen Controls</h3>
              <p>Live playback controls in the Dynamic Island (iPhone 14 Pro and later) and control playback from your lock screen.</p>
            </div>
            <div className="feature-card">
              <h3>Control Center</h3>
              <p>Quick access from Control Center for seamless playback control.</p>
            </div>
            <div className="feature-card">
              <h3>Theme Support</h3>
              <p>Light, dark, and system theme options to match your preferences.</p>
            </div>
          </div>
        </section>

        <section className="feature-section">
          <h2>🖥️ Server Support</h2>
          <div className="feature-grid">
            <div className="feature-card">
              <h3>Jellyfin & Emby</h3>
              <p>Works seamlessly with both Jellyfin and Emby music libraries. The app automatically detects your server type and adapts accordingly.</p>
            </div>
            <div className="feature-card">
              <h3>Your Existing Library</h3>
              <p>Reads your existing artists, albums, tracks, and playlists directly from your media server.</p>
            </div>
          </div>
        </section>

        <section className="feature-section">
          <h2>⌚ Companion Experiences</h2>
          <div className="feature-grid">
            <div className="feature-card">
              <h3>Apple Watch</h3>
              <p>Control playback from your wrist. View now playing information and manage playback without reaching for your phone. Perfect for workouts and on-the-go listening.</p>
            </div>
            <div className="feature-card">
              <h3>CarPlay</h3>
              <p>
                <strong>Status: Pending Apple Review</strong>
                <br />
                Full CarPlay integration for safe, hands-free music control while driving. Browse your library and control playback directly from your car's infotainment system.
              </p>
            </div>
          </div>
        </section>

        <section className="feature-section">
          <h2>🔄 Sync & Storage</h2>
          <div className="feature-grid">
            <div className="feature-card">
              <h3>Automatic Library Sync</h3>
              <p>Keep your library up to date with your media server automatically.</p>
            </div>
            <div className="feature-card">
              <h3>Progress Tracking</h3>
              <p>Real-time sync progress with detailed stage information so you always know what's happening.</p>
            </div>
            <div className="feature-card">
              <h3>Core Data Storage</h3>
              <p>Efficient local caching for fast access to your library, even when offline metadata is available.</p>
            </div>
          </div>
        </section>
      </div>
    </div>
  );
}

