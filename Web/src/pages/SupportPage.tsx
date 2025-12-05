import "./SupportPage.css";

export default function SupportPage() {
  return (
    <div className="support-page">
      <div className="page-header">
        <h1>Support</h1>
        <p className="page-subtitle">Need help or want to request a feature?</p>
      </div>

      <div className="support-content">
        <section className="support-section">
          <p className="support-intro">
            Kartunes is an independent project hosted on GitHub. If you encounter a bug, have feedback,
            or want to suggest a feature, please open an issue on GitHub.
          </p>

          <div className="support-actions">
            <a
              href="https://github.com/KartulUdus/Kartunes/issues"
              target="_blank"
              rel="noopener noreferrer"
              className="support-button"
            >
              Open GitHub Issues
            </a>
            <a
              href="https://github.com/KartulUdus/Kartunes"
              target="_blank"
              rel="noopener noreferrer"
              className="support-button secondary"
            >
              View Repository
            </a>
          </div>
        </section>

        <section className="support-section">
          <h2>Before You Open an Issue</h2>
          <div className="checklist">
            <div className="checklist-item">
              <span className="checklist-icon">✓</span>
              <span>Confirm you're on the latest version of the app</span>
            </div>
            <div className="checklist-item">
              <span className="checklist-icon">✓</span>
              <span>Check if a similar issue already exists</span>
            </div>
            <div className="checklist-item">
              <span className="checklist-icon">✓</span>
              <span>Include your device model and iOS version</span>
            </div>
            <div className="checklist-item">
              <span className="checklist-icon">✓</span>
              <span>Include your server type and version (Jellyfin/Emby)</span>
            </div>
            <div className="checklist-item">
              <span className="checklist-icon">✓</span>
              <span>Provide steps to reproduce the issue (if applicable)</span>
            </div>
          </div>
        </section>

        <section className="support-section">
          <h2>Getting Help</h2>
          <p>
            The best way to get help is through GitHub Issues. This allows the community to see
            questions and answers, and helps others who might have the same issue. Please be patient
            as this is an independent project maintained in spare time.
          </p>
        </section>

        <section className="support-section">
          <h2>Contributing</h2>
          <p>
            Kartunes is open source! If you're interested in contributing code, documentation, or
            translations, please check out the repository and open a pull request. All contributions
            are welcome and appreciated.
          </p>
          <a
            href="https://github.com/KartulUdus/Kartunes"
            target="_blank"
            rel="noopener noreferrer"
            className="support-link"
          >
            View on GitHub →
          </a>
        </section>
      </div>
    </div>
  );
}

