import { useState } from "react";
import { Link, useLocation } from "react-router-dom";
import "./Navbar.css";

export function Navbar() {
  const [isMenuOpen, setIsMenuOpen] = useState(false);
  const location = useLocation();

  const isActive = (path: string) => location.pathname === path || location.hash === `#${path}`;

  const navLinks = [
    { path: "/", label: "Home" },
    { path: "/features", label: "Features" },
    { path: "/screenshots", label: "Screenshots" },
    { path: "/setup", label: "Setup" },
    { path: "/faq", label: "FAQ" },
    { path: "/support", label: "Support" },
  ];

  return (
    <nav className="navbar">
      <div className="navbar-container">
        <Link to="/" className="navbar-logo">
          <img src={`${import.meta.env.BASE_URL}Assets/Kartunes-logo.png`} alt="Kartunes" className="logo-img" />
          <span>Kartunes</span>
        </Link>

        <button
          className="navbar-toggle"
          aria-label="Toggle menu"
          onClick={() => setIsMenuOpen(!isMenuOpen)}
        >
          <span></span>
          <span></span>
          <span></span>
        </button>

        <div className={`navbar-menu ${isMenuOpen ? "active" : ""}`}>
          {navLinks.map((link) => (
            <Link
              key={link.path}
              to={link.path}
              className={`navbar-link ${isActive(link.path) ? "active" : ""}`}
              onClick={() => setIsMenuOpen(false)}
            >
              {link.label}
            </Link>
          ))}
          
          <div className="navbar-actions">
            <a
              href="https://github.com/KartulUdus/Kartunes"
              target="_blank"
              rel="noopener noreferrer"
              className="navbar-button"
            >
              View on GitHub
            </a>
            <a
              href="https://ko-fi.com/Y8Y21PQBY8"
              target="_blank"
              rel="noopener noreferrer"
              className="kofi-button"
            >
              <img
                height="36"
                style={{ border: 0, height: '36px' }}
                src="https://storage.ko-fi.com/cdn/kofi2.png?v=6"
                alt="Buy Me a Coffee at ko-fi.com"
              />
            </a>
          </div>
        </div>
      </div>
    </nav>
  );
}

