import { useState, useEffect } from "react";
import "./ScreenshotsPage.css";

interface Screenshot {
  name: string;
  caption: string;
  lightMode: string;
  darkMode: string;
}

const getAssetPath = (path: string) => {
  const base = import.meta.env.BASE_URL; // "/Kartunes/"
  // Remove leading slash from path if present, then combine with base
  const cleanPath = path.startsWith('/') ? path.slice(1) : path;
  return `${base}${cleanPath}`;
};

const screenshots: Screenshot[] = [
  {
    name: "Home View",
    caption: "Browse your library with ease",
    lightMode: getAssetPath("/Assets/LightMode/homeView.png"),
    darkMode: getAssetPath("/Assets/DarkMode/homeView.png"),
  },
  {
    name: "Library View",
    caption: "Navigate artists, albums, and tracks",
    lightMode: getAssetPath("/Assets/LightMode/libraryView.png"),
    darkMode: getAssetPath("/Assets/DarkMode/libraryView.png"),
  },
  {
    name: "Now Playing",
    caption: "Full-screen Now Playing with album art",
    lightMode: getAssetPath("/Assets/LightMode/nowPlayingView.png"),
    darkMode: getAssetPath("/Assets/DarkMode/nowPlayingView.png"),
  },
  {
    name: "Mini Player",
    caption: "Quick access player throughout the app",
    lightMode: getAssetPath("/Assets/LightMode/miniPlayerView.png"),
    darkMode: getAssetPath("/Assets/DarkMode/miniPlayerView.png"),
  },
  {
    name: "Search",
    caption: "Quickly find songs, artists, and albums",
    lightMode: getAssetPath("/Assets/LightMode/searchView.png"),
    darkMode: getAssetPath("/Assets/DarkMode/searchView.png"),
  },
  {
    name: "Settings",
    caption: "Customize your experience",
    lightMode: getAssetPath("/Assets/LightMode/settingsView.png"),
    darkMode: getAssetPath("/Assets/DarkMode/settingsView.png"),
  },
];

export default function ScreenshotsPage() {
  const [theme, setTheme] = useState<"light" | "dark">("dark");
  const [isFullscreen, setIsFullscreen] = useState(false);
  const [currentIndex, setCurrentIndex] = useState(0);

  const currentScreenshots = screenshots.map((screenshot) => ({
    src: theme === "light" ? screenshot.lightMode : screenshot.darkMode,
    alt: screenshot.name,
  }));

  const handleImageClick = (index: number) => {
    setCurrentIndex(index);
    setIsFullscreen(true);
  };

  const handlePrev = (e: React.MouseEvent) => {
    e.stopPropagation();
    setCurrentIndex((prev) => (prev > 0 ? prev - 1 : currentScreenshots.length - 1));
  };

  const handleNext = (e: React.MouseEvent) => {
    e.stopPropagation();
    setCurrentIndex((prev) => (prev < currentScreenshots.length - 1 ? prev + 1 : 0));
  };

  const handleClose = () => {
    setIsFullscreen(false);
  };

  // Keyboard navigation and prevent body scroll when fullscreen
  useEffect(() => {
    if (!isFullscreen) return;

    // Prevent body scroll when fullscreen is open
    document.body.style.overflow = "hidden";

    const handleKeyDown = (e: KeyboardEvent) => {
      if (e.key === "Escape") {
        handleClose();
      } else if (e.key === "ArrowLeft") {
        setCurrentIndex((prev) => (prev > 0 ? prev - 1 : currentScreenshots.length - 1));
      } else if (e.key === "ArrowRight") {
        setCurrentIndex((prev) => (prev < currentScreenshots.length - 1 ? prev + 1 : 0));
      }
    };

    window.addEventListener("keydown", handleKeyDown);
    return () => {
      window.removeEventListener("keydown", handleKeyDown);
      document.body.style.overflow = "";
    };
  }, [isFullscreen, currentScreenshots.length]);

  return (
    <div className="screenshots-page">
      <div className="page-header">
        <h1>Screenshots</h1>
        <p className="page-subtitle">See Kartunes in action</p>
      </div>

      <div className="theme-toggle">
        <button
          className={`theme-button ${theme === "light" ? "active" : ""}`}
          onClick={() => setTheme("light")}
        >
          Light Mode
        </button>
        <button
          className={`theme-button ${theme === "dark" ? "active" : ""}`}
          onClick={() => setTheme("dark")}
        >
          Dark Mode
        </button>
      </div>

      <div className="screenshots-grid">
        {screenshots.map((screenshot, index) => (
          <div key={screenshot.name} className="screenshot-card">
            <div 
              className="screenshot-image-container"
              onClick={() => handleImageClick(index)}
              role="button"
              tabIndex={0}
              onKeyDown={(e) => {
                if (e.key === "Enter" || e.key === " ") {
                  e.preventDefault();
                  handleImageClick(index);
                }
              }}
              aria-label={`View ${screenshot.name} in full screen`}
            >
              <img
                src={theme === "light" ? screenshot.lightMode : screenshot.darkMode}
                alt={screenshot.name}
                className="screenshot-image"
              />
              <div className="screenshot-overlay">
                <span className="screenshot-view-text">Click to view full size</span>
              </div>
            </div>
            <div className="screenshot-info">
              <h3>{screenshot.name}</h3>
              <p>{screenshot.caption}</p>
            </div>
          </div>
        ))}
      </div>

      {isFullscreen && (
        <div className="fullscreen-viewer" onClick={handleClose}>
          <button 
            className="fullscreen-close" 
            onClick={handleClose} 
            aria-label="Close"
            onMouseDown={(e) => e.stopPropagation()}
          >
            <span>×</span>
          </button>
          <button 
            className="fullscreen-nav fullscreen-prev" 
            onClick={handlePrev}
            aria-label="Previous image"
            onMouseDown={(e) => e.stopPropagation()}
          >
            <span>‹</span>
          </button>
          <button 
            className="fullscreen-nav fullscreen-next" 
            onClick={handleNext}
            aria-label="Next image"
            onMouseDown={(e) => e.stopPropagation()}
          >
            <span>›</span>
          </button>
          <div className="fullscreen-image-container" onClick={(e) => e.stopPropagation()}>
            <img
              src={currentScreenshots[currentIndex].src}
              alt={currentScreenshots[currentIndex].alt}
              className="fullscreen-image"
            />
          </div>
          <div className="fullscreen-counter">
            {currentIndex + 1} / {currentScreenshots.length}
          </div>
        </div>
      )}
    </div>
  );
}

