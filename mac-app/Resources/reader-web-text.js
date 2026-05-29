(() => {
  const root = typeof globalThis !== 'undefined' ? globalThis : this;
  const canonicalTextParts = (char) => {
    if (char === '\u00AD') return [];
    if (char === '\u2018' || char === '\u2019') return ["'"];
    if (char === '\u201C' || char === '\u201D') return ['"'];
    if (/[\u2010-\u2015]/.test(char)) return ['-'];
    if (char === '\u2026') return ['.', '.', '.'];
    return [char.toLowerCase()];
  };
  const normalizedText = (value) => {
    let output = '';
    let previousWasSpace = true;
    for (const char of String(value || '')) {
      if (/\s/.test(char)) {
        if (!previousWasSpace) {
          output += ' ';
          previousWasSpace = true;
        }
        continue;
      }
      for (const part of canonicalTextParts(char)) {
        output += part;
        previousWasSpace = false;
      }
    }
    return output.trim();
  };
  const occurrenceIndexInText = (source, selected, before) => {
    const normalizedSelected = normalizedText(selected);
    const normalizedBefore = normalizedText(before);
    if (!normalizedSelected || !normalizedBefore) return 0;
    let count = 0;
    let index = normalizedBefore.indexOf(normalizedSelected);
    while (index >= 0) {
      count += 1;
      index = normalizedBefore.indexOf(normalizedSelected, index + Math.max(1, normalizedSelected.length));
    }
    return count;
  };
  const leafReaderFindSearchSpans = (value, query) => {
    const needle = String(query || '').toLowerCase();
    if (!needle) return [];
    const lower = String(value || '').toLowerCase();
    const matches = [];
    let index = lower.indexOf(needle);
    while (index >= 0) {
      matches.push({ start: index, end: index + needle.length });
      index = lower.indexOf(needle, index + Math.max(1, needle.length));
    }
    return matches;
  };
  const normalizedIndexForRoot = (rootNode) => {
    const walker = document.createTreeWalker(rootNode, NodeFilter.SHOW_TEXT);
    const positions = [];
    let normalized = '';
    let previousWasSpace = true;
    let node;
    while ((node = walker.nextNode())) {
      const raw = node.nodeValue || '';
      for (let i = 0; i < raw.length; i++) {
        const char = raw[i];
        if (/\s/.test(char)) {
          if (!previousWasSpace) {
            normalized += ' ';
            positions.push({ node, offset: i });
            previousWasSpace = true;
          }
        } else {
          for (const part of canonicalTextParts(char)) {
            normalized += part;
            positions.push({ node, offset: i });
            previousWasSpace = false;
          }
        }
      }
    }
    const leadingSpaces = normalized.length - normalized.trimStart().length;
    return { text: normalized.trim(), positions, leadingSpaces };
  };
  const rangeFromNormalizedSpan = (index, startIndex, length) => {
    const start = index.positions[index.leadingSpaces + startIndex];
    const end = index.positions[index.leadingSpaces + startIndex + length - 1];
    if (!start || !end) return null;
    const range = document.createRange();
    range.setStart(start.node, start.offset);
    range.setEnd(end.node, end.offset + 1);
    return range;
  };
  const rangeForNormalizedText = (rootNode, target, occurrenceIndex = 0) => {
    const normalizedTarget = normalizedText(target);
    if (!rootNode || !normalizedTarget) return null;
    const index = normalizedIndexForRoot(rootNode);
    const trimmed = index.text;
    let matchIndex = -1;
    let searchFrom = 0;
    const targetOccurrence = Math.max(0, Number(occurrenceIndex || 0));
    for (let seen = 0; seen <= targetOccurrence; seen++) {
      matchIndex = trimmed.indexOf(normalizedTarget, searchFrom);
      if (matchIndex < 0) break;
      searchFrom = matchIndex + Math.max(1, normalizedTarget.length);
    }
    if (matchIndex < 0) return null;
    return rangeFromNormalizedSpan(index, matchIndex, normalizedTarget.length);
  };
  const rangeForWordInContext = (rootNode, word, context, occurrenceIndex = 0) => {
    const normalizedWord = normalizedText(word);
    const normalizedContext = normalizedText(context);
    if (!rootNode || !normalizedWord || !normalizedContext) return null;
    const index = normalizedIndexForRoot(rootNode);
    const source = index.text;
    const contextNeedle = normalizedContext.slice(0, Math.min(160, normalizedContext.length));
    const contextIndex = source.indexOf(contextNeedle);
    if (contextIndex < 0) return null;
    const contextEnd = Math.min(source.length, contextIndex + normalizedContext.length);
    const contextSource = source.slice(contextIndex, contextEnd);
    let wordIndexInContext = contextSource.indexOf(normalizedWord);
    if (wordIndexInContext < 0) {
      wordIndexInContext = source.indexOf(normalizedWord, contextIndex);
      if (wordIndexInContext < 0 || wordIndexInContext >= contextEnd) return null;
      return rangeFromNormalizedSpan(index, wordIndexInContext, normalizedWord.length);
    }
    return rangeFromNormalizedSpan(index, contextIndex + wordIndexInContext, normalizedWord.length);
  };
  const leafReaderWordCount = (value) => String(value || '').split(/[^A-Za-z0-9]+/).filter(Boolean).length;
  const leafReaderHasCJK = (value) => /[\u3400-\u4DBF\u4E00-\u9FFF\uF900-\uFAFF]/.test(String(value || ''));
  const leafReaderMaxChineseTTSSegmentLength = 120;
  const leafReaderEnglishAbbreviations = new Set([
    'adm', 'approx', 'apr', 'aug', 'ave', 'capt', 'cf', 'ch', 'co', 'col', 'corp',
    'dec', 'dept', 'dr', 'e.g', 'etc', 'feb', 'fig', 'gen', 'gov', 'hon', 'i.e',
    'inc', 'jan', 'jr', 'jul', 'jun', 'ltd', 'maj', 'mar', 'mr', 'mrs', 'ms',
    'mt', 'no', 'nov', 'oct', 'p', 'pp', 'prof', 'rep', 'rev', 'sen', 'sep',
    'sept', 'sr', 'st', 'vs', 'vol'
  ]);
  const leafReaderIsTrailingSentenceCloser = (char) => /["'\u2019\u201D\u00BB\u203A\]\)\}]/.test(char || '');
  const leafReaderHasFollowingToken = (chars, index) => {
    for (let cursor = index + 1; cursor < chars.length; cursor += 1) {
      const char = chars[cursor];
      if (/\s/.test(char) || leafReaderIsTrailingSentenceCloser(char)) continue;
      return /[A-Za-z0-9]/.test(char);
    }
    return false;
  };
  const leafReaderTokenBeforePeriod = (chars, index) => {
    let start = index;
    while (start > 0 && /[A-Za-z.]/.test(chars[start - 1])) start -= 1;
    return chars.slice(start, index).join('').replace(/^\.+|\.+$/g, '');
  };
  const leafReaderPeriodEndsKnownNonTerminalToken = (chars, index) => {
    const token = leafReaderTokenBeforePeriod(chars, index);
    if (!token) return false;
    if (leafReaderEnglishAbbreviations.has(token.toLowerCase())) {
      return leafReaderHasFollowingToken(chars, index);
    }
    if (/^[A-Z]$/.test(token)) {
      return leafReaderHasFollowingToken(chars, index);
    }
    if (token.includes('.') && token.split('.').every((part) => /^[A-Za-z]$/.test(part))) {
      return leafReaderHasFollowingToken(chars, index);
    }
    return false;
  };
  const leafReaderIsEnglishSentenceBoundary = (chars, index) => {
    const char = chars[index];
    if (char !== '.') return true;
    if (chars[index + 1] === '.') return false;
    if (chars[index - 1] === '.' && chars[index + 1] !== '.') return true;
    if (/[0-9]/.test(chars[index - 1] || '') && /[0-9]/.test(chars[index + 1] || '')) return false;
    const immediateNextIsCloser = leafReaderIsTrailingSentenceCloser(chars[index + 1]);
    return immediateNextIsCloser || !leafReaderPeriodEndsKnownNonTerminalToken(chars, index);
  };
  const leafReaderEnglishSentenceUnits = (value) => {
    const source = String(value || '').replace(/\s+/g, ' ').trim();
    if (!source) return [];
    const chars = Array.from(source);
    const units = [];
    let sentenceStart = 0;
    for (let index = 0; index < chars.length;) {
      const char = chars[index];
      if ('.!?'.includes(char) && leafReaderIsEnglishSentenceBoundary(chars, index)) {
        let sentenceEnd = index + 1;
        while (sentenceEnd < chars.length && leafReaderIsTrailingSentenceCloser(chars[sentenceEnd])) {
          sentenceEnd += 1;
        }
        const unit = chars.slice(sentenceStart, sentenceEnd).join('').trim();
        if (unit) units.push(unit);
        sentenceStart = sentenceEnd;
        while (sentenceStart < chars.length && /\s/.test(chars[sentenceStart])) sentenceStart += 1;
        index = sentenceStart;
        continue;
      }
      index += 1;
    }
    if (sentenceStart < chars.length) {
      const tail = chars.slice(sentenceStart).join('').trim();
      if (tail) units.push(tail);
    }
    return units;
  };
  const leafReaderSplitByCharacterLimit = (value, limit) => {
    const chunks = [];
    let pending = '';
    for (const char of String(value || '')) {
      if (pending.length >= limit) {
        chunks.push(pending);
        pending = '';
      }
      pending += char;
    }
    if (pending) chunks.push(pending);
    return chunks;
  };
  const leafReaderSplitLongChineseSentence = (value) => {
    const source = String(value || '').trim();
    if (source.length <= leafReaderMaxChineseTTSSegmentLength) return [source];
    const chunks = [];
    let pending = '';
    for (const char of source) {
      pending += char;
      if ('，、：:,'.includes(char)) {
        if (pending.trim()) chunks.push(pending.trim());
        pending = '';
      }
    }
    if (pending.trim()) chunks.push(pending.trim());
    return chunks.flatMap((chunk) => (
      chunk.length > leafReaderMaxChineseTTSSegmentLength
        ? leafReaderSplitByCharacterLimit(chunk, leafReaderMaxChineseTTSSegmentLength)
        : [chunk]
    ));
  };
  const leafReaderChineseSentenceSegments = (value) => {
    const source = String(value || '').replace(/\s+/g, ' ').trim();
    if (!source) return [];
    const units = [];
    let pending = '';
    for (const char of source) {
      pending += char;
      if ('。！？；.!?;'.includes(char)) {
        if (pending.trim()) units.push(...leafReaderSplitLongChineseSentence(pending.trim()));
        pending = '';
      }
    }
    if (pending.trim()) units.push(...leafReaderSplitLongChineseSentence(pending.trim()));
    return units.filter(Boolean);
  };
  const leafReaderSentenceSegments = (value) => {
    const source = String(value || '').replace(/\s+/g, ' ').trim();
    if (!source) return [];
    if (leafReaderHasCJK(source)) return leafReaderChineseSentenceSegments(source);
    const sentenceUnits = leafReaderEnglishSentenceUnits(source);
    const units = sentenceUnits.length ? sentenceUnits : [source];
    const merged = [];
    let pending = '';
    let pendingWordCount = 0;
    for (const unit of units) {
      pending = pending ? `${pending} ${unit}` : unit;
      pendingWordCount += leafReaderWordCount(unit);
      if (pendingWordCount >= 4) {
        merged.push(pending);
        pending = '';
        pendingWordCount = 0;
      }
    }
    if (pending) {
      if (merged.length) merged[merged.length - 1] = `${merged[merged.length - 1]} ${pending}`;
      else merged.push(pending);
    }
    return merged;
  };
  const api = {
    normalizedText,
    occurrenceIndexInText,
    leafReaderFindSearchSpans,
    normalizedIndexForRoot,
    rangeForNormalizedText,
    rangeForWordInContext,
    leafReaderWordCount,
    leafReaderHasCJK,
    leafReaderSentenceSegments
  };
  if (typeof module !== 'undefined' && module.exports) module.exports = api;
  root.LeafReaderWebText = api;
})();
