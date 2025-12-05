import { useState } from "react";
import "./FAQPage.css";

interface FAQItem {
  question: string;
  answer: string;
}

const faqs: FAQItem[] = [
  {
    question: "What servers does Kartunes support?",
    answer: "Kartunes supports both Jellyfin and Emby media servers. The app automatically detects your server type when you connect and adapts accordingly. You need a server with at least one music library configured.",
  },
  {
    question: "Do I need another account?",
    answer: "No, you don't need a Kartunes account. You only use your existing Jellyfin or Emby login credentials. Kartunes connects directly to your server using your existing account.",
  },
  {
    question: "Is CarPlay supported?",
    answer: "CarPlay support is fully implemented in Kartunes but is currently pending approval from Apple. Once approved through the App Store review process, CarPlay functionality will be available. The implementation includes library browsing and full playback controls.",
  },
  {
    question: "Does Kartunes store or upload my library?",
    answer: "No. Kartunes does not store or upload your media or library metadata to any external service. All music is streamed directly from your own Jellyfin or Emby server. Library metadata is cached locally on your device for fast access, but this data never leaves your device.",
  },
  {
    question: "Is there Android support?",
    answer: "No, Kartunes is iOS-only for now. The app is built with SwiftUI and is designed specifically for the iOS ecosystem, including iPhone, Apple Watch, and CarPlay. Android support is not currently planned.",
  },
  {
    question: "Can I use Kartunes offline?",
    answer: "Kartunes requires an active connection to your media server to stream music. However, cached library metadata (artists, albums, track lists) remains available when offline, so you can browse your library structure. Actual playback requires a connection to stream from your server.",
  },
  {
    question: "What iOS version do I need?",
    answer: "Kartunes requires iOS 16.0 or later. This ensures compatibility with modern SwiftUI features and the latest iOS APIs used throughout the app.",
  },
  {
    question: "How do I connect to my server remotely?",
    answer: "To connect from outside your local network, you'll need to set up remote access to your Jellyfin or Emby server. This typically involves configuring port forwarding, using a reverse proxy (like nginx or Caddy), or setting up a VPN. Make sure your server is accessible via HTTPS for secure connections.",
  },
  {
    question: "Does Kartunes work with multiple libraries?",
    answer: "Yes, if your Jellyfin or Emby server has multiple music libraries configured, Kartunes will let you choose which library to use when you first connect. You can switch libraries by removing and re-adding your server configuration.",
  },
  {
    question: "How do I report a bug or request a feature?",
    answer: "Please open an issue on GitHub at https://github.com/KartulUdus/Kartunes/issues. Before opening an issue, make sure you're on the latest version of the app and check if a similar issue already exists. Include your device model, iOS version, and server type/version when reporting bugs.",
  },
];

export default function FAQPage() {
  const [openIndex, setOpenIndex] = useState<number | null>(null);

  const toggleFAQ = (index: number) => {
    setOpenIndex(openIndex === index ? null : index);
  };

  return (
    <div className="faq-page">
      <div className="page-header">
        <h1>Frequently Asked Questions</h1>
        <p className="page-subtitle">Everything you need to know about Kartunes</p>
      </div>

      <div className="faq-content">
        {faqs.map((faq, index) => (
          <div key={index} className="faq-item">
            <button
              className={`faq-question ${openIndex === index ? "open" : ""}`}
              onClick={() => toggleFAQ(index)}
              aria-expanded={openIndex === index}
            >
              <span>{faq.question}</span>
              <span className="faq-icon">{openIndex === index ? "−" : "+"}</span>
            </button>
            {openIndex === index && (
              <div className="faq-answer">
                <p>{faq.answer}</p>
              </div>
            )}
          </div>
        ))}
      </div>
    </div>
  );
}

