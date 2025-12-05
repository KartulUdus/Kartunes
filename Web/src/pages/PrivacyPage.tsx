import "./PrivacyPage.css";

export default function PrivacyPage() {
  return (
    <div className="privacy-page">
      <div className="page-header">
        <h1>Privacy</h1>
        <p className="page-subtitle">Your data stays yours</p>
      </div>

      <div className="privacy-content">
        <section className="privacy-section">
          <h2>Data Sources</h2>
          <p>
            Kartunes connects directly to your Jellyfin or Emby server and does not host or store your media.
            All music, metadata, and library information is retrieved directly from your own server. No media
            files or metadata are uploaded to any Kartunes backend or third-party service.
          </p>
        </section>

        <section className="privacy-section">
          <h2>Analytics & Tracking</h2>
          <p>
            <strong>Kartunes does not use third-party analytics or advertising.</strong> The app does not
            collect usage statistics, crash reports, or any user behavior data. Your listening habits and
            app usage remain completely private.
          </p>
        </section>

        <section className="privacy-section">
          <h2>Personal Data</h2>
          <p>
            Kartunes stores the following information locally on your device:
          </p>
          <ul>
            <li>
              <strong>Server credentials:</strong> Your server URL, username, and authentication tokens
              are stored securely in your device's keychain. These are never transmitted to any server
              other than your own Jellyfin or Emby instance.
            </li>
            <li>
              <strong>Library metadata:</strong> Artist, album, track, and playlist information is cached
              locally using Core Data for fast access. This data is synced from your server and stored
              only on your device.
            </li>
            <li>
              <strong>App preferences:</strong> Settings such as theme preference, sort options, and
              playback preferences are stored locally on your device.
            </li>
          </ul>
          <p>
            All of this data remains on your device and is never shared with third parties or uploaded
            to any external service.
          </p>
        </section>

        <section className="privacy-section">
          <h2>Network Communication</h2>
          <p>
            Kartunes only communicates with:
          </p>
          <ul>
            <li>Your Jellyfin or Emby server (for library data and media streaming)</li>
            <li>GitHub (for checking app updates, if you installed from source)</li>
          </ul>
          <p>
            No other network connections are made by the app.
          </p>
        </section>

        <section className="privacy-section">
          <h2>Third-Party Services</h2>
          <p>
            Kartunes does not integrate with any third-party analytics, advertising, or tracking services.
            The app is designed to be completely self-contained and privacy-focused.
          </p>
        </section>

        <section className="privacy-section">
          <h2>Your Rights</h2>
          <p>
            Since all data is stored locally on your device, you have complete control:
          </p>
          <ul>
            <li>You can delete the app at any time, which removes all stored data</li>
            <li>You can clear cached library data through the app settings</li>
            <li>You can revoke server access by removing your server configuration</li>
          </ul>
        </section>

        <section className="privacy-section">
          <h2>Questions</h2>
          <p>
            If you have questions about privacy or data handling, please open an issue on{" "}
            <a href="https://github.com/KartulUdus/Kartunes/issues" target="_blank" rel="noopener noreferrer">
              GitHub
            </a>.
          </p>
        </section>
      </div>
    </div>
  );
}

