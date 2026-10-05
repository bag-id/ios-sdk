import SwiftUI
import UIKit

enum MapFlowTheme {
    static var primary: Color { ManagedBleFlowTheme.current.primary }
    static var background: Color { ManagedBleFlowTheme.current.background }
    static var text: Color { ManagedBleFlowTheme.current.text }
    static var onPrimary: Color { ManagedBleFlowTheme.current.onPrimary }
    static var onLight: Color { ManagedBleFlowTheme.current.onLight }
    static var accent: Color { primary }
    static var cardBackground: Color { ManagedBleFlowTheme.current.cardBackground }
    static var surface: Color { ManagedBleFlowTheme.current.surface }
    static var cornerRadius: CGFloat { ManagedBleFlowTheme.current.borderRadius }
    static var buttonHeight: CGFloat { ManagedBleFlowTheme.current.primaryButtonHeight() }
    static var cardRadius: CGFloat { max(ManagedBleFlowTheme.current.borderRadius, 16) }
}
