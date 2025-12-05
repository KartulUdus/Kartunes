import "./SetupPage.css";

export default function SetupPage() {
  return (
    <div className="setup-page">
      <div className="page-header">
        <h1>Setup</h1>
        <p className="page-subtitle">Get started with Kartunes in minutes</p>
      </div>

      <div className="setup-content">
        <section className="setup-section">
          <h2>Prerequisites</h2>
          <div className="prerequisites">
            <p>Before you begin, make sure you have:</p>
            <ul>
              <li>A running Jellyfin or Emby server with a music library configured</li>
              <li>Network access to your media server (local network or remote access)</li>
              <li>An iOS device running iOS 16.0 or later</li>
            </ul>
          </div>
        </section>

        <section className="setup-section">
          <h2>Step-by-Step Setup</h2>
          <div className="steps">
            <div className="step">
              <div className="step-number">1</div>
              <div className="step-content">
                <h3>Install Kartunes</h3>
                <p>Download Kartunes from the App Store (coming soon) or build from source.</p>
              </div>
            </div>
            <div className="step">
              <div className="step-number">2</div>
              <div className="step-content">
                <h3>Enter Your Server URL</h3>
                <p>Open the app and enter your Jellyfin or Emby server URL. This can be a local IP address (e.g., <code>http://192.168.1.100:8096</code>) or a remote domain (e.g., <code>https://jellyfin.example.com</code>).</p>
              </div>
            </div>
            <div className="step">
              <div className="step-number">3</div>
              <div className="step-content">
                <h3>Log In</h3>
                <p>Enter your Jellyfin or Emby username and password. The app will automatically detect your server type.</p>
              </div>
            </div>
            <div className="step">
              <div className="step-number">4</div>
              <div className="step-content">
                <h3>Choose Your Music Library</h3>
                <p>Select which music library you want to use if your server has multiple libraries configured.</p>
              </div>
            </div>
            <div className="step">
              <div className="step-number">5</div>
              <div className="step-content">
                <h3>Start Playing</h3>
                <p>Your library will begin syncing automatically. Once complete, you can start exploring and playing your music!</p>
              </div>
            </div>
          </div>
        </section>

        <section className="setup-section">
          <h2>Technical Notes</h2>
          <div className="notes">
            <div className="note-card">
              <h3>🔒 Your Data, Your Server</h3>
              <p>
                Kartunes connects directly to your Jellyfin/Emby server and does not host or store your media.
                Everything is streamed from your own server. No media or metadata is uploaded to any Kartunes backend.
              </p>
            </div>
            <div className="note-card">
              <h3>🌐 Remote Access</h3>
              <p>
                To connect from outside your local network, you'll need to set up remote access to your server.
                This typically involves configuring port forwarding, using a reverse proxy, or setting up a VPN.
                Make sure your server is accessible via HTTPS for secure connections.
              </p>
            </div>
            <div className="note-card">
              <h3>🔐 SSL/HTTPS</h3>
              <p>
                While not strictly required for local network access, using HTTPS is recommended for security,
                especially when accessing your server remotely. Most modern Jellyfin and Emby setups support SSL certificates.
              </p>
            </div>
          </div>
        </section>
      </div>
    </div>
  );
}

