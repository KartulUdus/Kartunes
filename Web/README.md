# Kartunes Website

This is the marketing website for Kartunes, built with React + Vite + React Router.

## Development

```bash
# Install dependencies
npm install

# Start development server
npm run dev

# Build for production
npm run build

# Preview production build
npm run preview
```

## Deployment

The website is automatically deployed to GitHub Pages via GitHub Actions when changes are pushed to the `master` branch.

The site is configured to deploy to `https://kartuludus.github.io/Kartunes/` (or your GitHub Pages URL).

## Project Structure

```
Web/
├── src/
│   ├── components/     # Reusable components (Layout, etc.)
│   ├── pages/          # Page components
│   ├── styles/         # Global styles
│   ├── types/          # TypeScript type definitions
│   ├── App.tsx         # Main app component with routes
│   └── main.tsx        # Entry point
├── public/
│   ├── Assets/         # Static assets (images, screenshots) - move from Web/Assets/
│   └── robots.txt      # SEO robots file
├── index.html          # HTML template
├── vite.config.ts      # Vite configuration
└── package.json        # Dependencies
```

## Setup Note

**Important:** The `Assets` folder needs to be moved from `Web/Assets/` to `Web/public/Assets/` for Vite to serve the images correctly. Vite serves files from the `public` folder at the root URL path.

You can do this with:
```bash
cd Web
mv Assets public/Assets
```

## Notes

- Uses HashRouter for GitHub Pages compatibility
- Base path is set to `/Kartunes/` in vite.config.ts
- Screenshots are stored in `Assets/LightMode/` and `Assets/DarkMode/`
- Ko-fi widget is loaded dynamically in the Navbar component

