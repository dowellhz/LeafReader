(() => {
  if (typeof module !== 'undefined' && module.exports) {
    module.exports = require('./reader-web-text.js');
    return;
  }
  if (typeof window === 'undefined' || typeof document === 'undefined') return;

  const { installReaderOverlayStyle } = window.LeafReaderWebOverlay;
  const {
    normalizedText,
    occurrenceIndexInText,
    leafReaderFindSearchSpans,
    normalizedIndexForRoot,
    invalidateNormalizedIndex,
    rangeFromNormalizedSpan,
    rangeForNormalizedText,
    rangeForWordInContext,
    leafReaderWordCount,
    leafReaderHasCJK,
    leafReaderSentenceSegments
  } = window.LeafReaderWebText;

  const unwrapSpans = (selector) => {
    let removed = 0;
    document.querySelectorAll(selector).forEach((span) => {
      const parent = span.parentNode;
      if (!parent) return;
      while (span.firstChild) parent.insertBefore(span.firstChild, span);
      parent.removeChild(span);
      parent.normalize();
      removed += 1;
    });
    return removed;
  };

  const leafReaderSearchAPI = window.LeafReaderWebSearch.makeSearchAPI({
    installReaderOverlayStyle,
    leafReaderFindSearchSpans,
    normalizedText,
    normalizedIndexForRoot,
    rangeFromNormalizedSpan
  });
  window.leafReaderClearSearchHighlights = leafReaderSearchAPI.clearSearchHighlights;
  window.leafReaderSearch = leafReaderSearchAPI.search;

  window.leafReaderFindTextRange = (word, context, occurrenceIndex = 0) => {
    const normalizedWord = normalizedText(word);
    const normalizedContext = normalizedText(context);
    if (!normalizedWord) return null;
    const blocks = Array.from(document.body.querySelectorAll('p,li,blockquote,pre,td,th,h1,h2,h3,h4,h5,h6,div'));
    for (const block of blocks) {
      const source = normalizedText(block.innerText || block.textContent || '');
      if (normalizedContext && !source.includes(normalizedContext.slice(0, Math.min(120, normalizedContext.length)))) continue;
      if (!source.includes(normalizedWord)) continue;
      const range = normalizedContext
        ? (rangeForWordInContext(block, normalizedWord, normalizedContext, occurrenceIndex) || rangeForNormalizedText(block, normalizedWord, occurrenceIndex))
        : rangeForNormalizedText(block, normalizedWord, occurrenceIndex);
      if (range) return range;
    }
    const walker = document.createTreeWalker(document.body, NodeFilter.SHOW_TEXT);
    let node;
    while ((node = walker.nextNode())) {
      const value = node.nodeValue || '';
      const lower = value.toLowerCase();
      let index = lower.indexOf(normalizedWord);
      while (index >= 0) {
        const block = node.parentElement?.closest('p,li,blockquote,pre,td,th,h1,h2,h3,h4,h5,h6,div');
        const source = (block ? (block.innerText || block.textContent || '') : value).replace(/\s+/g, ' ').trim().toLowerCase();
        if (!normalizedContext || source.includes(normalizedContext.slice(0, Math.min(80, normalizedContext.length)))) {
          if (occurrenceIndex > 0) {
            occurrenceIndex -= 1;
            index = lower.indexOf(normalizedWord, index + normalizedWord.length);
            continue;
          }
          const range = document.createRange();
          range.setStart(node, index);
          range.setEnd(node, index + normalizedWord.length);
          return range;
        }
        index = lower.indexOf(normalizedWord, index + normalizedWord.length);
      }
    }
    return null;
  };

  const wrapRangeTextNodes = (range, className, configureSpan = null) => {
    const walker = document.createTreeWalker(range.commonAncestorContainer, NodeFilter.SHOW_TEXT);
    const targets = [];
    let node;
    while ((node = walker.nextNode())) {
      if (!range.intersectsNode(node)) continue;
      const start = node === range.startContainer ? range.startOffset : 0;
      const end = node === range.endContainer ? range.endOffset : (node.nodeValue || '').length;
      if (end <= start || !(node.nodeValue || '').slice(start, end).trim()) continue;
      targets.push({ node, start, end });
    }
    if (range.startContainer.nodeType === Node.TEXT_NODE && !targets.some((target) => target.node === range.startContainer)) {
      const node = range.startContainer;
      const end = node === range.endContainer ? range.endOffset : (node.nodeValue || '').length;
      if (end > range.startOffset) targets.push({ node, start: range.startOffset, end });
    }
    const rootsToInvalidate = new Set([document.body]);
    for (const target of targets) {
      let element = target.node.parentElement;
      while (element) {
        rootsToInvalidate.add(element);
        if (element === document.body) break;
        element = element.parentElement;
      }
    }
    for (const target of targets.reverse()) {
      const textNode = target.node;
      let middle = textNode;
      if (target.end < middle.nodeValue.length) middle.splitText(target.end);
      if (target.start > 0) middle = middle.splitText(target.start);
      const span = document.createElement('span');
      span.className = className;
      if (configureSpan) configureSpan(span);
      middle.parentNode.insertBefore(span, middle);
      span.appendChild(middle);
    }
    if (targets.length > 0) {
      rootsToInvalidate.forEach(invalidateNormalizedIndex);
    }
    return targets.length > 0;
  };

  const marks = window.LeafReaderWebMarks.makeMarksAPI({
    installReaderOverlayStyle,
    normalizedText,
    wrapRangeTextNodes,
    findTextRange: window.leafReaderFindTextRange,
    rangeForWordInContext,
    rangeForNormalizedText,
    unwrapSpans,
    invalidateTextIndex: invalidateNormalizedIndex
  });
  window.leafReaderClearAISourceUnderlines = marks.clearAISourceUnderlines;
  window.leafReaderAddAISourceUnderlineForSelection = marks.addAISourceUnderlineForSelection;
  window.leafReaderRestoreAISourceUnderlines = marks.restoreAISourceUnderlines;
  window.leafReaderRestoreWordHighlights = marks.restoreWordHighlights;
  window.leafReaderMarkSelectionAsWord = marks.markSelectionAsWord;
  window.leafReaderRestoreNoteHighlights = marks.restoreNoteHighlights;
  window.leafReaderMarkSelectionAsNote = marks.markSelectionAsNote;
  window.leafReaderScrollToNote = marks.scrollToNote;
  window.leafReaderRemoveNoteHighlight = marks.removeNoteHighlight;
  window.leafReaderRemoveWordHighlight = marks.removeWordHighlight;
  window.leafReaderScrollToWord = marks.scrollToWord;

  const tts = window.LeafReaderWebTTS.install({
    installReaderOverlayStyle,
    normalizedText,
    normalizedIndexForRoot,
    rangeFromNormalizedSpan,
    rangeForNormalizedText,
    leafReaderWordCount,
    leafReaderHasCJK,
    leafReaderSentenceSegments,
    wrapRangeTextNodes,
    unwrapSpans,
    aiSourceKeyForRanges: marks.aiSourceKeyForRanges,
    linkedWordIDsForRanges: marks.linkedWordIDsForRanges
  });
  window.LeafReaderWebSelection.install({
    occurrenceIndexInText,
    scrollProgress: tts.scrollProgress,
    aiSourceKeyAtPoint: marks.aiSourceKeyAtPoint,
    linkedWordIDAtPoint: marks.linkedWordIDAtPoint,
    noteIDAtPoint: marks.noteIDAtPoint
  });
})();
