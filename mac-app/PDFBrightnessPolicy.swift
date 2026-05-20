import Foundation

enum PDFBrightnessPolicy {
    static let sliderMaximum = 0.6

    static func sliderValue(forDimmingStrength dimmingStrength: Double) -> Double {
        sliderMaximum - clamped(dimmingStrength)
    }

    static func dimmingStrength(forSliderValue sliderValue: Double) -> Double {
        sliderMaximum - clamped(sliderValue)
    }

    private static func clamped(_ value: Double) -> Double {
        min(max(value, 0), sliderMaximum)
    }
}
