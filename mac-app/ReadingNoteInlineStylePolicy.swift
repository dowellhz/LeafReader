import Cocoa

enum ReadingNoteInlineStylePolicy {
    static func toggled(
        attributed: NSAttributedString,
        trait: NSFontTraitMask,
        defaultFont: NSFont
    ) -> NSAttributedString {
        let selected = NSMutableAttributedString(attributedString: attributed)
        let shouldRemove = containsTrait(selected, trait: trait)
        let fullRange = NSRange(location: 0, length: selected.length)
        var fontUpdates: [(font: NSFont, range: NSRange)] = []
        selected.enumerateAttribute(.font, in: fullRange) { value, subrange, _ in
            let font = (value as? NSFont) ?? defaultFont
            let toggled = shouldRemove
                ? NSFontManager.shared.convert(font, toNotHaveTrait: trait)
                : NSFontManager.shared.convert(font, toHaveTrait: trait)
            fontUpdates.append((toggled, subrange))
        }
        for update in fontUpdates {
            selected.addAttribute(.font, value: update.font, range: update.range)
        }
        return selected
    }

    static func containsTrait(_ attributed: NSAttributedString, trait: NSFontTraitMask) -> Bool {
        guard attributed.length > 0 else { return false }
        let symbolicTrait: NSFontDescriptor.SymbolicTraits = trait == .boldFontMask ? .bold : .italic
        var containsTrait = false
        attributed.enumerateAttribute(.font, in: NSRange(location: 0, length: attributed.length)) { value, _, stop in
            guard let font = value as? NSFont else { return }
            if font.fontDescriptor.symbolicTraits.contains(symbolicTrait) {
                containsTrait = true
                stop.pointee = true
            }
        }
        return containsTrait
    }
}
