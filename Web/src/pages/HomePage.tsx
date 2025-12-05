import { Link } from "react-router-dom";
import "./HomePage.css";

export default function HomePage() {
  return (
    <div className="home-page">
      <section className="hero">
        <div className="hero-content">
          <img 
            src={`${import.meta.env.BASE_URL}Assets/Kartunes-logo.png`} 
            alt="Kartunes Logo" 
            className="hero-logo"
          />
          <h1 className="hero-title">Kartunes</h1>
          <p className="hero-subtitle">
            A native Jellyfin & Emby music player for iOS
          </p>
          <p className="hero-description">
            Stream your own music library with a fast, native experience on iPhone and Apple Watch.
          </p>
          <div className="hero-actions">
            <button className="hero-button primary" disabled>
              Download on the App Store
              <span className="coming-soon">Coming Soon</span>
            </button>
            <a
              href="https://github.com/KartulUdus/Kartunes"
              target="_blank"
              rel="noopener noreferrer"
              className="hero-button secondary"
            >
              View on GitHub
            </a>
          </div>
        </div>
      </section>

      <section className="highlights">
        <div className="highlights-grid">
          <div className="highlight-card">
            <div className="highlight-icon">🎵</div>
            <h3>Jellyfin & Emby support</h3>
            <p>Works seamlessly with your existing media server</p>
          </div>
          <div className="highlight-card">
            <div className="highlight-icon">📱</div>
            <h3>Native iOS & watchOS apps</h3>
            <p>Built with SwiftUI for a native experience</p>
          </div>
          <div className="highlight-card">
            <div className="highlight-icon">🚗</div>
            <h3>CarPlay support</h3>
            <p>Pending Apple review</p>
          </div>
          <div className="highlight-card">
            <div className="highlight-icon">🔒</div>
            <h3>Your library, your server</h3>
            <p>All data stays on your own server</p>
          </div>
        </div>
      </section>

      <section className="cta-section">
        <p className="cta-text">
          Want more details? <Link to="/features">Explore the Features page</Link>
        </p>
      </section>
    </div>
  );
}

