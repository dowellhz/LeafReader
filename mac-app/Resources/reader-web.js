(() => {
  var lastScrollSent = 0;
  var documentMouseDown = false;
  if (typeof module !== 'undefined' && module.exports) { module.exports = require('./reader-web-text.js'); return; }
  if (typeof window === 'undefined' || typeof document === 'undefined') return;
  const { installReaderOverlayStyle } = window.LeafReaderWebOverlay;
  const {
    normalizedText,
    occurrenceIndexInText,
    leafReaderFindSearchSpans,
    normalizedIndexForRoot,
    rangeFromNormalizedSpan,
    rangeForNormalizedText,
    rangeForWordInContext,
    leafReaderWordCount,
    leafReaderHasCJK,
    leafReaderSentenceSegments
  } = window.LeafReaderWebText;
  const leafReaderMaxChineseTTSSegmentLength = 120;
  const unwrapSpans = (selector) => {
    document.querySelectorAll(selector).forEach((span) => {
      const parent = span.parentNode;
      if (!parent) return;
      while (span.firstChild) parent.insertBefore(span.firstChild, span);
      parent.removeChild(span);
      parent.normalize();
    });
  };
  const leafReaderSearchAPI = window.LeafReaderWebSearch.makeSearchAPI({
    installReaderOverlayStyle,
    leafReaderFindSearchSpans
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
      let start = node === range.startContainer ? range.startOffset : 0;
      let end = node === range.endContainer ? range.endOffset : (node.nodeValue || '').length;
      if (end <= start) continue;
      if (!(node.nodeValue || '').slice(start, end).trim()) continue;
      targets.push({ node, start, end });
    }
    if (range.startContainer.nodeType === Node.TEXT_NODE && !targets.some((target) => target.node === range.startContainer)) {
      const node = range.startContainer;
      const end = node === range.endContainer ? range.endOffset : (node.nodeValue || '').length;
      if (end > range.startOffset) targets.push({ node, start: range.startOffset, end });
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
    return targets.length > 0;
  };
  const leafReaderMarksAPI = window.LeafReaderWebMarks.makeMarksAPI({
    installReaderOverlayStyle,
    normalizedText,
    wrapRangeTextNodes,
    findTextRange: window.leafReaderFindTextRange,
    unwrapSpans
  });
  const leafReaderAISourceKeyForRanges = leafReaderMarksAPI.aiSourceKeyForRanges;
  const leafReaderLinkedWordIDsForRanges = leafReaderMarksAPI.linkedWordIDsForRanges;
  window.leafReaderClearAISourceUnderlines = leafReaderMarksAPI.clearAISourceUnderlines;
  window.leafReaderAddAISourceUnderlineForSelection = leafReaderMarksAPI.addAISourceUnderlineForSelection;
  window.leafReaderRestoreAISourceUnderlines = leafReaderMarksAPI.restoreAISourceUnderlines;
  window.leafReaderRestoreWordHighlights = leafReaderMarksAPI.restoreWordHighlights;
  window.leafReaderMarkSelectionAsWord = leafReaderMarksAPI.markSelectionAsWord;
  window.leafReaderRestoreNoteHighlights = leafReaderMarksAPI.restoreNoteHighlights;
  window.leafReaderMarkSelectionAsNote = leafReaderMarksAPI.markSelectionAsNote;
  window.leafReaderScrollToNote = leafReaderMarksAPI.scrollToNote;
  window.leafReaderRemoveNoteHighlight = leafReaderMarksAPI.removeNoteHighlight;
  window.leafReaderRemoveWordHighlight = leafReaderMarksAPI.removeWordHighlight;
  window.leafReaderScrollToWord = leafReaderMarksAPI.scrollToWord;
  window.leafReaderClearTTSUnderline = () => {
    if (window.CSS && CSS.highlights) CSS.highlights.delete('leaf-reader-tts');
    unwrapSpans('span.leaf-reader-tts-underline');
  };
  const leafReaderCandidateTTSBlocks = () => {
    const primarySelector = 'p,li,blockquote,pre,td,th,h1,h2,h3,h4,h5,h6';
    const fallbackSelector = 'div,section,article';
    const primaryBlocks = Array.from(document.body.querySelectorAll(primarySelector));
    const fallbackBlocks = Array.from(document.body.querySelectorAll(fallbackSelector)).filter((block) => {
      return !block.querySelector(primarySelector);
    });
    const blocks = primaryBlocks.concat(fallbackBlocks).filter((block) => {
      if (!normalizedText(block.innerText || block.textContent || '')) return false;
      const rect = block.getBoundingClientRect();
      return rect.width > 0 && rect.height > 0;
    });
    const visible = blocks.filter((block) => {
      const rect = block.getBoundingClientRect();
      return rect.bottom >= 0 && rect.top <= window.innerHeight;
    });
    return visible.concat(blocks.filter((block) => !visible.includes(block)));
  };
  const leafReaderBlocksFromVisibleTop = () => {
    const blocks = leafReaderCandidateTTSBlocks().slice().sort((a, b) => {
      if (a === b) return 0;
      return a.compareDocumentPosition(b) & Node.DOCUMENT_POSITION_FOLLOWING ? -1 : 1;
    });
    const visibleTop = Math.max(0, window.scrollY || 0);
    const startIndex = blocks.findIndex((block) => {
      const rect = block.getBoundingClientRect();
      return rect.bottom + visibleTop >= visibleTop;
    });
    return startIndex >= 0 ? blocks.slice(startIndex) : blocks;
  };
  let leafReaderTTSAnchorRanges = [];
  let leafReaderReadAloudBatchEndRange = null;
  const leafReaderMaxReadAloudBatchSegments = 16;
  const leafReaderMaxReadAloudBatchCharacters = 2400;
  const leafReaderScrollProgress = () => {
    const height = Math.max(1, document.documentElement.scrollHeight - window.innerHeight);
    return Math.max(0, Math.min(1, window.scrollY / height));
  };
  const leafReaderVisibleRangeRect = (range) => {
    if (!range) return null;
    return Array.from(range.getClientRects()).find((item) => item.width > 0 && item.height > 0) || range.getBoundingClientRect();
  };
  const leafReaderProgressForRange = (range) => {
    const rect = leafReaderVisibleRangeRect(range);
    const height = Math.max(1, document.documentElement.scrollHeight - window.innerHeight);
    const top = Math.max(0, (window.scrollY || 0) + (rect?.top || 0));
    return Math.max(0, Math.min(1, top / height));
  };
  const leafReaderScrollRangeToCenter = (range) => {
    const rect = leafReaderVisibleRangeRect(range);
    if (rect && rect.height > 0) {
      window.scrollBy({ top: rect.top - window.innerHeight * 0.42, behavior: 'smooth' });
    }
  };
  const leafReaderContainedTTSRanges = (needle, blocks) => {
    const ranges = [];
    const seen = new Set();
    for (const block of blocks) {
      const source = normalizedText(block.innerText || block.textContent || '');
      if (source.length < 8) continue;
      if (!needle.includes(source.slice(0, Math.min(80, source.length)))) continue;
      const range = rangeForNormalizedText(block, source, 0);
      if (!range) continue;
      const key = `${range.startContainer}_${range.startOffset}_${range.endContainer}_${range.endOffset}`;
      if (seen.has(key)) continue;
      seen.add(key);
      ranges.push(range);
    }
    return ranges;
  };
  const leafReaderTTSRanges = (needle) => {
    const blocks = leafReaderCandidateTTSBlocks();
    for (const block of blocks) {
      const source = normalizedText(block.innerText || block.textContent || '');
      if (!source.includes(needle.slice(0, Math.min(80, needle.length)))) continue;
      const range = rangeForNormalizedText(block, needle, 0);
      if (range) return [range];
    }
    const bodyRange = rangeForNormalizedText(document.body, needle, 0);
    if (bodyRange) return [bodyRange];
    return leafReaderContainedTTSRanges(needle, blocks);
  };
  const leafReaderRangeKey = (range) => `${range.startContainer}_${range.startOffset}_${range.endContainer}_${range.endOffset}`;
  const leafReaderRangesText = (ranges) => ranges
    .map((range) => String(range.toString ? range.toString() : ''))
    .join(' ')
    .trim();
  const leafReaderRangesMatchText = (ranges, text) => {
    const rangeText = normalizedText(leafReaderRangesText(ranges));
    const targetText = normalizedText(text);
    if (!rangeText || !targetText) return false;
    return rangeText.includes(targetText) || targetText.includes(rangeText);
  };
  const leafReaderApplyTTSRanges = (ranges) => {
    for (const range of ranges.slice().reverse()) {
      wrapRangeTextNodes(range, 'leaf-reader-tts-underline');
    }
  };
  const leafReaderSegmentRangesForBlock = (block) => {
    const rawText = block.innerText || block.textContent || '';
    const segments = leafReaderSentenceSegments(rawText);
    if (!segments.length) return [];
    const normalizedIndex = normalizedIndexForRoot(block);
    let cursor = 0;
    const ranges = [];
    for (const segment of segments) {
      const needle = normalizedText(segment);
      if (!needle) continue;
      let matchIndex = normalizedIndex.text.indexOf(needle, cursor);
      if (matchIndex < 0) matchIndex = normalizedIndex.text.indexOf(needle);
      if (matchIndex < 0) continue;
      const range = rangeFromNormalizedSpan(normalizedIndex, matchIndex, needle.length);
      if (!range) continue;
      ranges.push({ range, text: segment });
      cursor = matchIndex + Math.max(1, needle.length);
    }
    return ranges;
  };
  window.leafReaderPrepareReadAloudBatch = () => {
    installReaderOverlayStyle();
    window.leafReaderClearTTSUnderline();
    if (window.leafReaderClearSelectionVisualOnly) {
      window.leafReaderClearSelectionVisualOnly();
    } else {
      const selection = window.getSelection && window.getSelection();
      if (selection) selection.removeAllRanges();
    }
    const blocks = leafReaderBlocksFromVisibleTop();
    const seen = new Set();
    const rawSegments = [];
    leafReaderTTSAnchorRanges = [];
    leafReaderReadAloudBatchEndRange = null;
    for (const block of blocks) {
      for (const item of leafReaderSegmentRangesForBlock(block)) {
        const rect = leafReaderVisibleRangeRect(item.range);
        if (rect && rect.bottom < window.innerHeight * 0.05) continue;
        const key = leafReaderRangeKey(item.range);
        if (seen.has(key)) continue;
        seen.add(key);
        rawSegments.push(item);
      }
    }
    const segments = [];
    let pendingText = '';
    let pendingRanges = [];
    let pendingWordCount = 0;
    let consumedRawCount = 0;
    let reachedBatchLimit = false;
    const flushPending = () => {
      const text = pendingText.trim();
      if (text && pendingRanges.length) {
        segments.push({ text, speechText: text });
        leafReaderTTSAnchorRanges.push(pendingRanges);
        leafReaderReadAloudBatchEndRange = pendingRanges[pendingRanges.length - 1] || leafReaderReadAloudBatchEndRange;
      }
      pendingText = '';
      pendingRanges = [];
      pendingWordCount = 0;
    };
    for (const item of rawSegments) {
      const text = String(item.text || '').trim();
      if (!text) continue;
      consumedRawCount += 1;
      pendingText = pendingText ? `${pendingText} ${text}` : text;
      pendingRanges.push(item.range);
      pendingWordCount += leafReaderWordCount(text);
      if (leafReaderHasCJK(pendingText) || pendingText.length >= leafReaderMaxChineseTTSSegmentLength || pendingWordCount >= 4) {
        flushPending();
        const totalCharacters = segments.reduce((sum, segment) => sum + String(segment.text || '').length, 0);
        if (segments.length >= leafReaderMaxReadAloudBatchSegments || totalCharacters >= leafReaderMaxReadAloudBatchCharacters) {
          reachedBatchLimit = true;
          break;
        }
      }
    }
    if (pendingText && !reachedBatchLimit) {
      if (segments.length && leafReaderTTSAnchorRanges.length) {
        const last = segments[segments.length - 1];
        last.text = `${last.text} ${pendingText.trim()}`;
        last.speechText = last.text;
        leafReaderTTSAnchorRanges[leafReaderTTSAnchorRanges.length - 1] =
          leafReaderTTSAnchorRanges[leafReaderTTSAnchorRanges.length - 1].concat(pendingRanges);
        leafReaderReadAloudBatchEndRange = pendingRanges[pendingRanges.length - 1] || leafReaderReadAloudBatchEndRange;
      } else {
        flushPending();
      }
    }
    return { segments, hasMore: consumedRawCount < rawSegments.length };
  };
  window.leafReaderPrepareReadAloudSegments = () => {
    const batch = window.leafReaderPrepareReadAloudBatch();
    return batch.segments || [];
  };
  window.leafReaderAdvanceReadAloudBatch = () => {
    const range = leafReaderReadAloudBatchEndRange;
    if (!range) return { ok: false, progress: leafReaderScrollProgress() };
    const rect = leafReaderVisibleRangeRect(range);
    if (!rect || rect.height <= 0) return { ok: false, progress: leafReaderScrollProgress() };
    const delta = rect.bottom - window.innerHeight * 0.18;
    if (Math.abs(delta) > 1) {
      window.scrollBy({ top: delta, behavior: 'auto' });
    }
    return { ok: true, progress: leafReaderScrollProgress() };
  };
  window.leafReaderUnderlineTTSIndex = (segmentIndex, fallbackText) => {
    installReaderOverlayStyle();
    window.leafReaderClearTTSUnderline();
    const numericIndex = Number(segmentIndex || 0);
    if (!numericIndex || numericIndex < 1) return window.leafReaderUnderlineTTS(fallbackText);
    const index = numericIndex - 1;
    const ranges = leafReaderTTSAnchorRanges[index] || [];
    if (!ranges.length || !leafReaderRangesMatchText(ranges, fallbackText)) {
      return window.leafReaderUnderlineTTS(fallbackText);
    }
    const sourceKey = leafReaderAISourceKeyForRanges(ranges);
    const wordIDs = leafReaderLinkedWordIDsForRanges(ranges);
    const progress = leafReaderProgressForRange(ranges[0]);
    leafReaderApplyTTSRanges(ranges);
    leafReaderScrollRangeToCenter(ranges[0]);
    return { ok: true, sourceKey, wordID: wordIDs[0] || '', wordIDs, progress };
  };
  window.leafReaderUnderlineTTS = (targetText) => {
    installReaderOverlayStyle();
    window.leafReaderClearTTSUnderline();
    const needle = normalizedText(targetText);
    if (!needle) return false;
    const ranges = leafReaderTTSRanges(needle);
    if (!ranges.length) return false;
    const sourceKey = leafReaderAISourceKeyForRanges(ranges);
    const wordIDs = leafReaderLinkedWordIDsForRanges(ranges);
    const progress = leafReaderProgressForRange(ranges[0]);
    leafReaderApplyTTSRanges(ranges);
    leafReaderScrollRangeToCenter(ranges[0]);
    return { ok: true, sourceKey, wordID: wordIDs[0] || '', wordIDs, progress };
  };
  const clearLegacySelectionSpanHighlights = () => {
    document.querySelectorAll('span.leaf-reader-selection-highlight').forEach((span) => {
      const parent = span.parentNode;
      if (!parent) return;
      while (span.firstChild) parent.insertBefore(span.firstChild, span);
      parent.removeChild(span);
      parent.normalize();
    });
  };
  const clearLegacySelectionOverlay = () => {
    if (window.CSS && CSS.highlights) CSS.highlights.delete('leaf-reader-selection');
    clearLegacySelectionSpanHighlights();
  };
  window.leafReaderClearSelection = () => {
    clearLegacySelectionOverlay();
    const selection = window.getSelection();
    if (selection) selection.removeAllRanges();
    window.webkit.messageHandlers.selectionChanged.postMessage({ text: "", context: "" });
  };
  window.leafReaderClearSelectionVisualOnly = () => {
    clearLegacySelectionOverlay();
    const selection = window.getSelection();
    if (selection) selection.removeAllRanges();
  };
  const sendSelection = () => {
    const selection = window.getSelection();
    const text = String(selection || "").trim();
    let context = "";
    if (selection && selection.rangeCount > 0 && text.length > 0) {
      const container = selection.getRangeAt(0).commonAncestorContainer;
      const element = container.nodeType === Node.ELEMENT_NODE ? container : container.parentElement;
      const block = element ? element.closest('p,li,blockquote,pre,td,th,h1,h2,h3,h4,h5,h6,div') : null;
      const source = block ? (block.innerText || block.textContent || "") : text;
      context = source.replace(/\s+/g, " ").trim().slice(0, 360);
      let occurrenceIndex = 0;
      const range = selection.getRangeAt(0);
      const firstLineRect = Array.from(range.getClientRects()).find((rect) => rect.width > 0 && rect.height > 0);
      const selectionRect = firstLineRect || range.getBoundingClientRect();
      const rect = {
        x: selectionRect.left,
        y: selectionRect.top,
        width: selectionRect.width,
        height: selectionRect.height
      };
      if (block) {
        try {
          const beforeRange = document.createRange();
          beforeRange.selectNodeContents(block);
          beforeRange.setEnd(selection.getRangeAt(0).startContainer, selection.getRangeAt(0).startOffset);
          occurrenceIndex = occurrenceIndexInText(source, text, beforeRange.toString());
        } catch (_) {}
      }
      window.webkit.messageHandlers.selectionChanged.postMessage({ text, context, occurrenceIndex, rect });
      return;
    } else if (documentMouseDown) {
      clearLegacySelectionOverlay();
    }
    window.webkit.messageHandlers.selectionChanged.postMessage({ text, context, occurrenceIndex: null, rect: null });
  };
  const sendScroll = (force = false) => {
    const now = Date.now();
    if (!force && now - lastScrollSent < 200) return;
    lastScrollSent = now;
    window.webkit.messageHandlers.scrollChanged.postMessage(leafReaderScrollProgress());
  };
  window.leafReaderJumpToHref = (href) => {
    href = String(href || '');
    const fragment = href.includes('#') ? href.split('#').pop() : (href.startsWith('#') ? href.slice(1) : '');
    const path = href.split('#')[0];
    const sections = Array.from(document.querySelectorAll('section.reader-section[data-leaf-href]'));
    const matchingSection = path ? sections.find((section) => {
      const value = section.dataset.leafHref || '';
      return value === path || value.endsWith('/' + path) || path.endsWith('/' + value);
    }) : null;
    if (fragment) {
      const target = matchingSection
        ? (window.CSS && CSS.escape
          ? matchingSection.querySelector(`#${CSS.escape(fragment)}`)
          : Array.from(matchingSection.querySelectorAll('[id]')).find(el => el.id === fragment))
        : document.getElementById(fragment);
      if (target) {
        target.scrollIntoView({ behavior: 'smooth', block: 'start' });
        return true;
      }
    }
    if (matchingSection) {
      matchingSection.scrollIntoView({ behavior: 'smooth', block: 'start' });
      return true;
    }
    return false;
  };
  document.addEventListener("mousedown", () => {
    documentMouseDown = true;
    clearLegacySelectionOverlay();
    const selection = window.getSelection();
    if (selection) selection.removeAllRanges();
    window.webkit.messageHandlers.selectionChanged.postMessage({ text: "", context: "" });
  });
  document.addEventListener("click", (event) => {
    const aiSource = event.target?.closest?.('span.leaf-reader-ai-source-underline');
    if (aiSource) {
      event.preventDefault();
      event.stopPropagation();
      window.webkit.messageHandlers.webAISourceClicked.postMessage(String(aiSource.dataset.leafAiSourceKey || ''));
      return;
    }
    const link = event.target?.closest?.('a[data-leaf-href]');
    if (link) {
      event.preventDefault();
      event.stopPropagation();
      window.leafReaderJumpToHref(link.dataset.leafHref || '');
      return;
    }
    const target = event.target?.closest?.('span.leaf-reader-linked-word');
    if (target) {
      event.preventDefault();
      event.stopPropagation();
      window.webkit.messageHandlers.webWordClicked.postMessage(String(target.dataset.leafWordId || ''));
      return;
    }
    const note = event.target?.closest?.('span.leaf-reader-note-highlight');
    if (!note) return;
    event.preventDefault();
    event.stopPropagation();
    window.webkit.messageHandlers.webNoteClicked.postMessage(String(note.dataset.leafNoteId || ''));
  }, true);
  document.addEventListener("selectionchange", () => setTimeout(sendSelection, 0));
  document.addEventListener("mouseup", () => {
    documentMouseDown = false;
    sendSelection();
  });
  document.addEventListener("keyup", sendSelection);
  window.addEventListener("scroll", () => sendScroll(false), { passive: true });
  window.addEventListener("load", () => sendScroll(true));
  setTimeout(() => sendScroll(true), 250);
})();
