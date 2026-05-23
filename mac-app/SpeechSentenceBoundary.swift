import Foundation

extension SpeechTextPolicy {
    static let englishAbbreviations: Set<String> = [
        "adm", "approx", "apr", "aug", "ave", "capt", "cf", "ch", "co", "col", "corp",
        "dec", "dept", "dr", "e.g", "etc", "feb", "fig", "gen", "gov", "hon", "i.e",
        "inc", "jan", "jr", "jul", "jun", "ltd", "maj", "mar", "mr", "mrs", "ms",
        "mt", "no", "nov", "oct", "p", "pp", "prof", "rep", "rev", "sen", "sep",
        "sept", "sr", "st", "vs", "vol"
    ]

    static func englishSentenceUnits(for text: String) -> [String] {
        var sentenceUnits: [String] = []
        let characters = Array(text)
        var sentenceStart = characters.startIndex
        var index = characters.startIndex

        func appendSentence(upTo end: Int) {
            let value = String(characters[sentenceStart..<end]).trimmingCharacters(in: .whitespacesAndNewlines)
            if !value.isEmpty {
                sentenceUnits.append(value)
            }
        }

        while index < characters.endIndex {
            let character = characters[index]
            if isEnglishSentenceTerminator(character),
               isEnglishSentenceBoundary(at: index, in: characters) {
                var sentenceEnd = index + 1
                while sentenceEnd < characters.endIndex,
                      isTrailingSentenceCloser(characters[sentenceEnd]) {
                    sentenceEnd += 1
                }
                appendSentence(upTo: sentenceEnd)
                sentenceStart = sentenceEnd
                while sentenceStart < characters.endIndex,
                      characters[sentenceStart].isWhitespace {
                    sentenceStart += 1
                }
                index = sentenceStart
                continue
            }
            index += 1
        }

        if sentenceStart < characters.endIndex {
            appendSentence(upTo: characters.endIndex)
        }
        return sentenceUnits
    }

    static func isEnglishSentenceTerminator(_ character: Character) -> Bool {
        character == "." || character == "!" || character == "?"
    }

    static func isEnglishSentenceBoundary(at index: Int, in characters: [Character]) -> Bool {
        let character = characters[index]
        guard character == "." else { return true }
        if index + 1 < characters.endIndex,
           characters[index + 1] == "." {
            return false
        }
        if index > characters.startIndex,
           index + 1 < characters.endIndex,
           characters[index - 1] == ".",
           characters[index + 1] != "." {
            return true
        }
        if index > characters.startIndex,
           index + 1 < characters.endIndex,
           characters[index - 1].isNumber,
           characters[index + 1].isNumber {
            return false
        }
        let immediateNextIsCloser = index + 1 < characters.endIndex
            && isTrailingSentenceCloser(characters[index + 1])
        if !immediateNextIsCloser,
           periodEndsKnownNonTerminalToken(at: index, in: characters) {
            return false
        }
        return true
    }

    static func periodEndsKnownNonTerminalToken(at index: Int, in characters: [Character]) -> Bool {
        let token = tokenBeforePeriod(at: index, in: characters)
        guard !token.isEmpty else { return false }
        if englishAbbreviations.contains(token.lowercased()) {
            return hasFollowingToken(after: index, in: characters)
        }
        if token.count == 1,
           token.unicodeScalars.allSatisfy({ CharacterSet.uppercaseLetters.contains($0) }) {
            return hasFollowingToken(after: index, in: characters)
        }
        if token.contains("."),
           token.split(separator: ".").allSatisfy({ $0.count == 1 }) {
            return hasFollowingToken(after: index, in: characters)
        }
        return false
    }

    static func tokenBeforePeriod(at index: Int, in characters: [Character]) -> String {
        var start = index
        while start > characters.startIndex {
            let candidate = characters[start - 1]
            guard candidate.isLetter || candidate == "." else { break }
            start -= 1
        }
        return String(characters[start..<index])
            .trimmingCharacters(in: CharacterSet(charactersIn: "."))
    }

    static func hasFollowingToken(after index: Int, in characters: [Character]) -> Bool {
        var cursor = index + 1
        while cursor < characters.endIndex {
            let character = characters[cursor]
            if character.isWhitespace || isTrailingSentenceCloser(character) {
                cursor += 1
                continue
            }
            return character.isLetter || character.isNumber
        }
        return false
    }

    static func isTrailingSentenceCloser(_ character: Character) -> Bool {
        "\"'”’»›)]}".contains(character)
    }
}
