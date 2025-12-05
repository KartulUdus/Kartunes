import "./PlatformsPage.css";

export default function PlatformsPage() {
  return (
    <div className="platforms-page">
      <div className="page-header">
        <h1>Platforms</h1>
        <p className="page-subtitle">Available on iOS, watchOS, and coming soon to CarPlay</p>
      </div>

      <div className="platforms-content">
        <section className="platform-section">
          <div className="platform-card">
            <div className="platform-icon">📱</div>
            <h2>iPhone</h2>
            <p className="platform-status">Available</p>
            <p>
              The main Kartunes experience is built for iPhone. Enjoy a full-featured music player
              with native SwiftUI interface, seamless library browsing, and powerful playback controls.
              All features are available on iOS 16.0 and later.
            </p>
            <ul className="platform-features">
              <li>Full library browsing and search</li>
              <li>Queue management and playback controls</li>
              <li>Dynamic Island support (iPhone 14 Pro+)</li>
              <li>Lock screen and Control Center integration</li>
              <li>Light and dark theme support</li>
            </ul>
          </div>
        </section>

        <section className="platform-section">
          <div className="platform-card">
            <div className="platform-icon">⌚</div>
            <h2>Apple Watch</h2>
            <p className="platform-status">Available</p>
            <p>
              Control playback from your wrist with the Kartunes Watch app. Perfect for workouts,
              running, or any time you want to control your music without reaching for your phone.
            </p>
            <ul className="platform-features">
              <li>Remote playback control</li>
              <li>Now playing information</li>
              <li>Play, pause, skip, and volume control</li>
              <li>Works independently when iPhone is nearby</li>
            </ul>
          </div>
        </section>

        <section className="platform-section">
          <div className="platform-card pending">
            <div className="platform-icon">🚗</div>
            <h2>CarPlay</h2>
            <p className="platform-status pending">Pending Apple Review</p>
            <p>
              CarPlay support is fully implemented in Kartunes and is currently pending approval from Apple.
              Once approved, you'll be able to browse your library and control playback directly from your
              car's infotainment system.
            </p>
            <ul className="platform-features">
              <li>Browse your music library</li>
              <li>Full Now Playing view</li>
              <li>Safe, hands-free music control</li>
              <li>Voice control integration</li>
            </ul>
            <div className="pending-notice">
              <strong>Note:</strong> CarPlay functionality is complete but availability depends on Apple's
              App Store review process.
            </div>
          </div>
        </section>

        <section className="platform-section">
          <h2>Future Platforms</h2>
          <div className="future-platforms">
            <div className="future-platform-card">
              <h3>iPad</h3>
              <p>Native iPad support is being explored to take advantage of the larger screen.</p>
            </div>
            <div className="future-platform-card">
              <h3>tvOS</h3>
              <p>Apple TV support is under consideration for home listening experiences.</p>
            </div>
          </div>
        </section>
      </div>
    </div>
  );
}

