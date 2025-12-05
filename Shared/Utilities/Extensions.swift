
import Foundation
import UIKit

// MARK: - Haptic Feedback

extension UIImpactFeedbackGenerator {
    /// Convenience method to trigger haptic feedback with a specific style
    static func impact(style: UIImpactFeedbackGenerator.FeedbackStyle = .medium) {
        let generator = UIImpactFeedbackGenerator(style: style)
        generator.impactOccurred()
    }
    
    /// Light haptic feedback for subtle interactions
    static func light() {
        impact(style: .light)
    }
    
    /// Medium haptic feedback for standard button taps
    static func medium() {
        impact(style: .medium)
    }
    
    /// Heavy haptic feedback for important actions
    static func heavy() {
        impact(style: .heavy)
    }
}

extension UINotificationFeedbackGenerator {
    /// Success haptic feedback
    static func success() {
        let generator = UINotificationFeedbackGenerator()
        generator.notificationOccurred(.success)
    }
    
    /// Warning haptic feedback
    static func warning() {
        let generator = UINotificationFeedbackGenerator()
        generator.notificationOccurred(.warning)
    }
    
    /// Error haptic feedback
    static func error() {
        let generator = UINotificationFeedbackGenerator()
        generator.notificationOccurred(.error)
    }
}

extension UISelectionFeedbackGenerator {
    /// Selection haptic feedback for picker-like interactions
    static func selection() {
        let generator = UISelectionFeedbackGenerator()
        generator.selectionChanged()
    }
}

