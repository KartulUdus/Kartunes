import { Routes, Route } from "react-router-dom";
import { Layout } from "./components/Layout/Layout";
import HomePage from "./pages/HomePage";
import FeaturesPage from "./pages/FeaturesPage";
import ScreenshotsPage from "./pages/ScreenshotsPage";
import SetupPage from "./pages/SetupPage";
import PlatformsPage from "./pages/PlatformsPage";
import PrivacyPage from "./pages/PrivacyPage";
import FAQPage from "./pages/FAQPage";
import SupportPage from "./pages/SupportPage";
import NotFoundPage from "./pages/NotFoundPage";

export default function App() {
  return (
    <Layout>
      <Routes>
        <Route path="/" element={<HomePage />} />
        <Route path="/features" element={<FeaturesPage />} />
        <Route path="/screenshots" element={<ScreenshotsPage />} />
        <Route path="/setup" element={<SetupPage />} />
        <Route path="/platforms" element={<PlatformsPage />} />
        <Route path="/privacy" element={<PrivacyPage />} />
        <Route path="/faq" element={<FAQPage />} />
        <Route path="/support" element={<SupportPage />} />
        <Route path="*" element={<NotFoundPage />} />
      </Routes>
    </Layout>
  );
}

