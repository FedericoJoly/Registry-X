import SwiftUI

// MARK: - Color Hex Extension
extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hex.count {
        case 3: // RGB (12-bit)
            (a, r, g, b) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6: // RGB (24-bit)
            (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8: // ARGB (32-bit)
            (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default:
            (a, r, g, b) = (255, 1, 1, 1)
        }
        
        self.init(
            .sRGB,
            red: Double(r) / 255,
            green: Double(g) / 255,
            blue: Double(b) / 255,
            opacity: Double(a) / 255
        )
    }
    
    func toHex() -> String? {
        guard let components = UIColor(self).cgColor.components, components.count >= 3 else {
            return nil
        }
        let r = Int(components[0] * 255.0)
        let g = Int(components[1] * 255.0)
        let b = Int(components[2] * 255.0)
        return String(format: "#%02X%02X%02X", r, g, b)
    }
    
    // Darken color by percentage (0.0 to 1.0)
    func darken(by percentage: Double) -> Color {
        guard let components = UIColor(self).cgColor.components, components.count >= 3 else {
            return self
        }
        
        let r = max(0, components[0] * (1.0 - percentage))
        let g = max(0, components[1] * (1.0 - percentage))
        let b = max(0, components[2] * (1.0 - percentage))
        let alpha = components.count >= 4 ? components[3] : 1.0
        
        return Color(.sRGB, red: r, green: g, blue: b, opacity: alpha)
    }
    
    // Normalize color to column 3 intensity for Registry display
    // Converts any color (from columns 1-6) to column 3 equivalent for optimal contrast
    func normalizeForRegistry() -> Color {
        guard let components = UIColor(self).cgColor.components, components.count >= 3 else {
            return self
        }
        
        let r = components[0]
        let g = components[1]
        let b = components[2]
        let alpha = components.count >= 4 ? components[3] : 1.0
        
        // Convert RGB to HSL
        let maxC = max(r, g, b)
        let minC = min(r, g, b)
        let delta = maxC - minC
        
        var hue: Double = 0
        var saturation: Double = 0
        let lightness = (maxC + minC) / 2.0
        
        if delta != 0 {
            saturation = lightness < 0.5 ? delta / (maxC + minC) : delta / (2.0 - maxC - minC)
            
            if maxC == r {
                hue = ((g - b) / delta + (g < b ? 6 : 0)) / 6.0
            } else if maxC == g {
                hue = ((b - r) / delta + 2) / 6.0
            } else {
                hue = ((r - g) / delta + 4) / 6.0
            }
        }
        
        // Normalize to column 3: lightness ~45%, saturation ~70%
        let normalizedLightness = 0.45
        let normalizedSaturation = min(saturation * 1.2, 0.85) // Boost saturation slightly
        
        // Convert back to RGB
        let c = (1.0 - abs(2.0 * normalizedLightness - 1.0)) * normalizedSaturation
        let x = c * (1.0 - abs((hue * 6.0).truncatingRemainder(dividingBy: 2.0) - 1.0))
        let m = normalizedLightness - c / 2.0
        
        var newR: Double = 0, newG: Double = 0, newB: Double = 0
        let hueSegment = Int(hue * 6.0)
        
        switch hueSegment {
        case 0: (newR, newG, newB) = (c, x, 0)
        case 1: (newR, newG, newB) = (x, c, 0)
        case 2: (newR, newG, newB) = (0, c, x)
        case 3: (newR, newG, newB) = (0, x, c)
        case 4: (newR, newG, newB) = (x, 0, c)
        default: (newR, newG, newB) = (c, 0, x)
        }
        
        return Color(.sRGB, 
                    red: newR + m, 
                    green: newG + m, 
                    blue: newB + m, 
                    opacity: alpha)
    }
}
