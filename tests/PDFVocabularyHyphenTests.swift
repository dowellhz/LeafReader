import Foundation

enum PDFVocabularyHyphenTests {
    static func testLayoutHyphenNormalization() throws {
        try expectEqual(
            VocabularyTextPolicy.normalizedPDFVocabularyText(
                "Schadenser-satzforderung",
                lineBrokenHyphenRange: NSRange(location: 10, length: 1),
                isKnownWord: { $0 == "Schadensersatzforderung" }
            ),
            "Schadensersatzforderung",
            "a marked PDF layout hyphen should be removed when the joined word is known"
        )
        try expectEqual(
            VocabularyTextPolicy.normalizedPDFVocabularyText(
                "E-Mail",
                lineBrokenHyphenRange: NSRange(location: 1, length: 1),
                isKnownHyphenatedWord: { $0 == "E-Mail" }
            ),
            "E-Mail",
            "a genuine known hyphenated word should preserve its hyphen"
        )
    }

    static func testSplitSuffixPatternFindsWholeWord() throws {
        let sample = "Damit die Nutzung si-\ncherzustellen ist."
        let regex = try NSRegularExpression(
            pattern: #"(?i)"# + VocabularyTextPolicy.lineBrokenHyphenWordPattern(suffix: "cherzustellen")
        )
        let matches = regex.matches(
            in: sample,
            range: NSRange(location: 0, length: (sample as NSString).length)
        )
        try expectEqual(matches.count, 1, "a selection on the second PDF line should find the whole wrapped word")
        try expectEqual(
            matches[0].range(withName: "layoutHyphen"),
            NSRange(location: 20, length: 1),
            "the layout hyphen should remain identifiable for normalization"
        )
    }
}
