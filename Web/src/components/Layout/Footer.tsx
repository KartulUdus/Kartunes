import "./Footer.css";

export function Footer() {
  return (
    <footer className="footer">
      <div className="footer-container">
        <p>
          Made with ❤️ for music lovers who want a beautiful, native iOS experience for their
          self-hosted music libraries.
        </p>
        <p className="footer-copyright">
          © {new Date().getFullYear()} Kartunes. All rights reserved.
        </p>
      </div>
    </footer>
  );
}

