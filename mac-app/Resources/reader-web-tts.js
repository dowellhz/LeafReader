(() => {
  const root = typeof globalThis !== 'undefined' ? globalThis : this;

  const install = (dependencies) => {
    const {
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
      aiSourceKeyForRanges,
      linkedWordIDsForRanges
    } = dependencies;
    const maxChineseSegmentLength = 120;
    const maxBatchSegments = 16;
    const maxBatchCharacters = 2400;
    let anchorRanges = [];
    let batchEndRange = null;

    const scrollProgress = () => {
      const height = Math.max(1, document.documentElement.scrollHeight - window.innerHeight);
      return Math.max(0, Math.min(1, window.scrollY / height));
    };
    const visibleRangeRect = (range) => {
      if (!range) return null;
      return Array.from(range.getClientRects()).find((item) => item.width > 0 && item.height > 0) || range.getBoundingClientRect();
    };
    const progressForRange = (range) => {
      const rect = visibleRangeRect(range);
      const height = Math.max(1, document.documentElement.scrollHeight - window.innerHeight);
      const top = Math.max(0, (window.scrollY || 0) + (rect?.top || 0));
      return Math.max(0, Math.min(1, top / height));
    };
    const scrollRangeToCenter = (range) => {
      const rect = visibleRangeRect(range);
      if (rect && rect.height > 0) {
        window.scrollBy({ top: rect.top - window.innerHeight * 0.42, behavior: 'smooth' });
      }
    };
    const candidateBlocks = () => {
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
    const blocksFromVisibleTop = () => {
      const blocks = candidateBlocks().slice().sort((a, b) => {
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
    const containedRanges = (needle, blocks) => {
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
    const rangesForText = (needle) => {
      const blocks = candidateBlocks();
      for (const block of blocks) {
        const source = normalizedText(block.innerText || block.textContent || '');
        if (!source.includes(needle.slice(0, Math.min(80, needle.length)))) continue;
        const range = rangeForNormalizedText(block, needle, 0);
        if (range) return [range];
      }
      const bodyRange = rangeForNormalizedText(document.body, needle, 0);
      return bodyRange ? [bodyRange] : containedRanges(needle, blocks);
    };
    const rangeKey = (range) => `${range.startContainer}_${range.startOffset}_${range.endContainer}_${range.endOffset}`;
    const rangesText = (ranges) => ranges
      .map((range) => String(range.toString ? range.toString() : ''))
      .join(' ')
      .trim();
    const rangesMatchText = (ranges, text) => {
      const rangeText = normalizedText(rangesText(ranges));
      const targetText = normalizedText(text);
      if (!rangeText || !targetText) return false;
      return rangeText.includes(targetText) || targetText.includes(rangeText);
    };
    const applyRanges = (ranges) => {
      for (const range of ranges.slice().reverse()) {
        wrapRangeTextNodes(range, 'leaf-reader-tts-underline');
      }
    };
    const segmentRangesForBlock = (block) => {
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

    window.leafReaderClearTTSUnderline = () => {
      if (window.CSS && CSS.highlights) CSS.highlights.delete('leaf-reader-tts');
      unwrapSpans('span.leaf-reader-tts-underline');
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
      const blocks = blocksFromVisibleTop();
      const seen = new Set();
      const rawSegments = [];
      anchorRanges = [];
      batchEndRange = null;
      for (const block of blocks) {
        for (const item of segmentRangesForBlock(block)) {
          const rect = visibleRangeRect(item.range);
          if (rect && rect.bottom < window.innerHeight * 0.05) continue;
          const key = rangeKey(item.range);
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
          anchorRanges.push(pendingRanges);
          batchEndRange = pendingRanges[pendingRanges.length - 1] || batchEndRange;
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
        if (leafReaderHasCJK(pendingText) || pendingText.length >= maxChineseSegmentLength || pendingWordCount >= 4) {
          flushPending();
          const totalCharacters = segments.reduce((sum, segment) => sum + String(segment.text || '').length, 0);
          if (segments.length >= maxBatchSegments || totalCharacters >= maxBatchCharacters) {
            reachedBatchLimit = true;
            break;
          }
        }
      }
      if (pendingText && !reachedBatchLimit) {
        if (segments.length && anchorRanges.length) {
          const last = segments[segments.length - 1];
          last.text = `${last.text} ${pendingText.trim()}`;
          last.speechText = last.text;
          anchorRanges[anchorRanges.length - 1] = anchorRanges[anchorRanges.length - 1].concat(pendingRanges);
          batchEndRange = pendingRanges[pendingRanges.length - 1] || batchEndRange;
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
      const range = batchEndRange;
      if (!range) return { ok: false, progress: scrollProgress() };
      const rect = visibleRangeRect(range);
      if (!rect || rect.height <= 0) return { ok: false, progress: scrollProgress() };
      const delta = rect.bottom - window.innerHeight * 0.18;
      if (Math.abs(delta) > 1) window.scrollBy({ top: delta, behavior: 'auto' });
      return { ok: true, progress: scrollProgress() };
    };
    window.leafReaderUnderlineTTSIndex = (segmentIndex, fallbackText) => {
      installReaderOverlayStyle();
      window.leafReaderClearTTSUnderline();
      const numericIndex = Number(segmentIndex || 0);
      if (!numericIndex || numericIndex < 1) return window.leafReaderUnderlineTTS(fallbackText);
      const ranges = anchorRanges[numericIndex - 1] || [];
      if (!ranges.length || !rangesMatchText(ranges, fallbackText)) return window.leafReaderUnderlineTTS(fallbackText);
      return underlineRanges(ranges);
    };
    const underlineRanges = (ranges) => {
      const sourceKey = aiSourceKeyForRanges(ranges);
      const wordIDs = linkedWordIDsForRanges(ranges);
      const progress = progressForRange(ranges[0]);
      applyRanges(ranges);
      scrollRangeToCenter(ranges[0]);
      return { ok: true, sourceKey, wordID: wordIDs[0] || '', wordIDs, progress };
    };
    window.leafReaderUnderlineTTS = (targetText) => {
      installReaderOverlayStyle();
      window.leafReaderClearTTSUnderline();
      const needle = normalizedText(targetText);
      if (!needle) return false;
      const ranges = rangesForText(needle);
      return ranges.length ? underlineRanges(ranges) : false;
    };
    return { scrollProgress };
  };

  root.LeafReaderWebTTS = { install };
  if (typeof module !== 'undefined' && module.exports) module.exports = { install };
})();
