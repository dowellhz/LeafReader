(() => {
  const root = typeof globalThis !== 'undefined' ? globalThis : this;

  const makeMarksAPI = ({
    installReaderOverlayStyle,
    normalizedText,
    wrapRangeTextNodes,
    findTextRange,
    rangeForWordInContext,
    rangeForNormalizedText,
    unwrapSpans,
    invalidateTextIndex = () => {}
  }) => {
    const aiSourceRanges = new Map();
    const wordRanges = new Map();
    const noteRanges = new Map();
    let anchorBlockIndex = null;

    const supportsCustomHighlights = () => Boolean(
      window.CSS && CSS.highlights && window.Highlight
    );

    const applyHighlight = (name, ranges) => {
      if (!supportsCustomHighlights()) return false;
      const values = Array.from(ranges.values());
      if (values.length) CSS.highlights.set(name, new Highlight(...values));
      else CSS.highlights.delete(name);
      return true;
    };

    const invalidateAnchorIndexes = () => {
      anchorBlockIndex = null;
      invalidateTextIndex(document.body);
    };

    const removeMarkedSpans = (selector) => {
      const removed = unwrapSpans(selector) || 0;
      if (removed > 0) invalidateAnchorIndexes();
      return removed;
    };

    const makePatternMatcher = (patterns) => {
      const nodes = [{ transitions: new Map(), failure: 0, outputs: [] }];
      patterns.forEach((pattern, patternIndex) => {
        let nodeIndex = 0;
        for (const character of pattern) {
          let nextIndex = nodes[nodeIndex].transitions.get(character);
          if (nextIndex === undefined) {
            nextIndex = nodes.length;
            nodes[nodeIndex].transitions.set(character, nextIndex);
            nodes.push({ transitions: new Map(), failure: 0, outputs: [] });
          }
          nodeIndex = nextIndex;
        }
        nodes[nodeIndex].outputs.push(patternIndex);
      });

      const queue = Array.from(nodes[0].transitions.values());
      for (let cursor = 0; cursor < queue.length; cursor += 1) {
        const nodeIndex = queue[cursor];
        const node = nodes[nodeIndex];
        for (const [character, nextIndex] of node.transitions) {
          queue.push(nextIndex);
          let failure = node.failure;
          while (failure !== 0 && !nodes[failure].transitions.has(character)) {
            failure = nodes[failure].failure;
          }
          const fallback = nodes[failure].transitions.get(character);
          nodes[nextIndex].failure = fallback === undefined || fallback === nextIndex ? 0 : fallback;
          nodes[nextIndex].outputs.push(...nodes[nodes[nextIndex].failure].outputs);
        }
      }

      return (text, didMatch) => {
        let nodeIndex = 0;
        for (const character of text) {
          while (nodeIndex !== 0 && !nodes[nodeIndex].transitions.has(character)) {
            nodeIndex = nodes[nodeIndex].failure;
          }
          nodeIndex = nodes[nodeIndex].transitions.get(character) ?? 0;
          for (const patternIndex of nodes[nodeIndex].outputs) didMatch(patternIndex);
        }
      };
    };

    const indexedAnchorBlocks = () => {
      if (anchorBlockIndex) return anchorBlockIndex;
      const elements = Array.from(document.body.querySelectorAll(
        'p,li,blockquote,pre,td,th,h1,h2,h3,h4,h5,h6,div'
      ));
      anchorBlockIndex = elements.map((element) => ({
        element,
        text: normalizedText(element.innerText || element.textContent || '')
      }));
      return anchorBlockIndex;
    };

    const batchRanges = (records, { idKey, textKey }) => {
      const anchors = (records || []).map((record) => {
        const text = normalizedText(record[textKey] || '');
        const context = normalizedText(record.context || '');
        return {
          id: String(record[idKey] || ''),
          originalText: record[textKey] || '',
          originalContext: record.context || '',
          occurrenceIndex: record.occurrenceIndex || 0,
          text,
          pattern: context ? context.slice(0, Math.min(120, context.length)) : text
        };
      });
      const patterns = [];
      const patternIndexes = new Map();
      for (const anchor of anchors) {
        if (!anchor.pattern || patternIndexes.has(anchor.pattern)) continue;
        patternIndexes.set(anchor.pattern, patterns.length);
        patterns.push(anchor.pattern);
      }

      const blocks = anchors.length ? indexedAnchorBlocks() : [];
      const blockIndexesByPattern = patterns.map(() => []);
      if (patterns.length) {
        const scan = makePatternMatcher(patterns);
        blocks.forEach((block, blockIndex) => {
          const matches = new Set();
          scan(block.text, (patternIndex) => matches.add(patternIndex));
          for (const patternIndex of matches) blockIndexesByPattern[patternIndex].push(blockIndex);
        });
      }

      const resolved = new Map();
      let fallbacks = 0;
      for (const anchor of anchors) {
        if (!anchor.id || !anchor.text || !anchor.pattern) continue;
        const patternIndex = patternIndexes.get(anchor.pattern);
        const candidates = patternIndex === undefined ? [] : blockIndexesByPattern[patternIndex];
        let range = null;
        for (const blockIndex of candidates) {
          const block = blocks[blockIndex];
          if (!block.text.includes(anchor.text)) continue;
          range = anchor.originalContext
            ? rangeForWordInContext?.(
              block.element,
              anchor.originalText,
              anchor.originalContext,
              anchor.occurrenceIndex
            )
            : rangeForNormalizedText?.(block.element, anchor.originalText, anchor.occurrenceIndex);
          if (range) break;
        }
        if (!range) {
          fallbacks += 1;
          range = findTextRange(
            anchor.originalText,
            anchor.originalContext,
            anchor.occurrenceIndex
          );
        }
        if (range) resolved.set(anchor.id, range);
      }
      return {
        ranges: resolved,
        stats: {
          strategy: 'batch-custom-highlight',
          records: anchors.length,
          ranges: resolved.size,
          blocks: blocks.length,
          patterns: patterns.length,
          fallbacks
        }
      };
    };

    const rangesIntersect = (left, right) => {
      try {
        return left.compareBoundaryPoints(Range.START_TO_END, right) < 0
          && left.compareBoundaryPoints(Range.END_TO_START, right) > 0;
      } catch (_) {
        return false;
      }
    };

    const keysForRanges = (ranges, storedRanges, multiple) => {
      const ids = [];
      for (const range of ranges || []) {
        for (const [id, storedRange] of storedRanges) {
          if (!rangesIntersect(range, storedRange)) continue;
          if (!multiple) return id;
          if (!ids.includes(id)) ids.push(id);
        }
      }
      return multiple ? ids : '';
    };

    const legacyKeyForMarkedRanges = (ranges, selector, dataKey, multiple) => {
      const spans = Array.from(document.querySelectorAll(selector));
      const ids = [];
      for (const range of ranges || []) {
        for (const span of spans) {
          const markRange = document.createRange();
          markRange.selectNodeContents(span);
          const intersects = rangesIntersect(range, markRange);
          markRange.detach && markRange.detach();
          const id = span.dataset[dataKey] || '';
          if (!intersects || !id) continue;
          if (!multiple) return id;
          if (!ids.includes(id)) ids.push(id);
        }
      }
      return multiple ? ids : '';
    };

    const pointRange = (x, y) => {
      if (document.caretRangeFromPoint) return document.caretRangeFromPoint(x, y);
      if (!document.caretPositionFromPoint) return null;
      const position = document.caretPositionFromPoint(x, y);
      if (!position) return null;
      const range = document.createRange();
      range.setStart(position.offsetNode, position.offset);
      range.collapse(true);
      return range;
    };

    const keyAtPoint = (ranges, x, y) => {
      const point = pointRange(x, y);
      if (!point) return '';
      for (const [id, range] of ranges) {
        try {
          const startsBeforePoint = range.compareBoundaryPoints(Range.START_TO_START, point) <= 0;
          const endsAfterPoint = range.compareBoundaryPoints(Range.END_TO_START, point) >= 0;
          if (startsBeforePoint && endsAfterPoint) return id;
        } catch (_) {}
      }
      return '';
    };

    const wrapLegacyRange = (range, className, configureSpan) => {
      const didWrap = wrapRangeTextNodes(range, className, configureSpan);
      if (didWrap) invalidateAnchorIndexes();
      return didWrap;
    };

    const restoreRanges = (records, options) => {
      installReaderOverlayStyle();
      options.ranges.clear();
      if (window.CSS && CSS.highlights) CSS.highlights.delete(options.highlightName);
      removeMarkedSpans(options.selector);
      if (supportsCustomHighlights()) {
        const batch = batchRanges(records, { idKey: options.idKey, textKey: options.textKey });
        for (const [id, range] of batch.ranges) options.ranges.set(id, range);
        applyHighlight(options.highlightName, options.ranges);
        return batch.stats;
      }
      let restoredRanges = 0;
      for (const record of records || []) {
        const range = findTextRange(
          record[options.textKey],
          record.context,
          record.occurrenceIndex || 0
        );
        if (!range) continue;
        if (wrapLegacyRange(range, options.className, (span) => {
          span.dataset[options.dataKey] = String(record[options.idKey] || '');
        })) restoredRanges += 1;
      }
      return {
        strategy: 'legacy-dom',
        records: (records || []).length,
        ranges: restoredRanges,
        blocks: 0,
        patterns: 0,
        fallbacks: 0
      };
    };

    const markSelection = (id, options) => {
      const selection = window.getSelection();
      const text = String(selection || '').trim();
      if (!selection || selection.rangeCount === 0 || !text || !id) return false;
      installReaderOverlayStyle();
      const range = selection.getRangeAt(0).cloneRange();
      let didMark = true;
      if (supportsCustomHighlights()) {
        options.ranges.set(String(id), range);
        applyHighlight(options.highlightName, options.ranges);
      } else {
        didMark = wrapLegacyRange(range, options.className, (span) => {
          span.dataset[options.dataKey] = String(id);
        });
      }
      selection.removeAllRanges();
      return didMark;
    };

    const scrollToProgress = (fallbackProgress) => {
      const height = Math.max(1, document.documentElement.scrollHeight - window.innerHeight);
      window.scrollTo({
        top: height * Math.max(0, Math.min(1, Number(fallbackProgress || 0))),
        behavior: 'smooth'
      });
    };

    const scrollToRange = (range) => {
      if (!range) return false;
      const rect = range.getBoundingClientRect();
      window.scrollBy({ top: rect.top - (window.innerHeight * 0.35), behavior: 'smooth' });
      return true;
    };

    const scrollToMark = (id, fallbackProgress, options) => {
      if (scrollToRange(options.ranges.get(String(id || '')))) return true;
      const target = document.querySelector(options.selectorForID(String(id || '')));
      if (target) {
        target.scrollIntoView({ behavior: 'smooth', block: 'center' });
        return true;
      }
      scrollToProgress(fallbackProgress);
      return false;
    };

    const removeMark = (id, options) => {
      options.ranges.delete(String(id || ''));
      applyHighlight(options.highlightName, options.ranges);
      removeMarkedSpans(options.selectorForID(String(id || '')));
    };

    const wordOptions = {
      ranges: wordRanges,
      highlightName: 'leaf-reader-linked-word',
      selector: 'span.leaf-reader-linked-word',
      className: 'leaf-reader-linked-word',
      dataKey: 'leafWordId',
      idKey: 'id',
      textKey: 'word',
      selectorForID: (id) => `span.leaf-reader-linked-word[data-leaf-word-id="${CSS.escape(id)}"]`
    };
    const noteOptions = {
      ranges: noteRanges,
      highlightName: 'leaf-reader-note-highlight',
      selector: 'span.leaf-reader-note-highlight',
      className: 'leaf-reader-note-highlight',
      dataKey: 'leafNoteId',
      idKey: 'id',
      textKey: 'selectedText',
      selectorForID: (id) => `span.leaf-reader-note-highlight[data-leaf-note-id="${CSS.escape(id)}"]`
    };
    const aiOptions = {
      ranges: aiSourceRanges,
      highlightName: 'leaf-reader-ai-source',
      selector: 'span.leaf-reader-ai-source-underline',
      className: 'leaf-reader-ai-source-underline',
      dataKey: 'leafAiSourceKey',
      idKey: 'key',
      textKey: 'selectedText'
    };

    const clearAISourceUnderlines = () => {
      aiSourceRanges.clear();
      if (window.CSS && CSS.highlights) CSS.highlights.delete('leaf-reader-ai-source');
      removeMarkedSpans(aiOptions.selector);
    };

    const addAISourceUnderlineForSelection = (key) => markSelection(key, aiOptions);

    return {
      clearAISourceUnderlines,
      addAISourceUnderlineForSelection,
      restoreAISourceUnderlines: (records) => restoreRanges(records, aiOptions),
      restoreWordHighlights: (records) => restoreRanges(records, wordOptions),
      markSelectionAsWord: (id) => markSelection(id, wordOptions),
      restoreNoteHighlights: (records) => restoreRanges(records, noteOptions),
      markSelectionAsNote: (id) => markSelection(id, noteOptions),
      scrollToNote: (id, progress) => scrollToMark(id, progress, noteOptions),
      removeNoteHighlight: (id) => removeMark(id, noteOptions),
      removeWordHighlight: (id) => removeMark(id, wordOptions),
      scrollToWord: (id, progress) => scrollToMark(id, progress, wordOptions),
      aiSourceKeyAtPoint: (x, y) => keyAtPoint(aiSourceRanges, x, y),
      linkedWordIDAtPoint: (x, y) => keyAtPoint(wordRanges, x, y),
      noteIDAtPoint: (x, y) => keyAtPoint(noteRanges, x, y),
      aiSourceKeyForRanges: (ranges) => supportsCustomHighlights()
        ? keysForRanges(ranges, aiSourceRanges, false)
        : legacyKeyForMarkedRanges(
          ranges,
          'span.leaf-reader-ai-source-underline[data-leaf-ai-source-key]',
          'leafAiSourceKey',
          false
        ),
      linkedWordIDsForRanges: (ranges) => supportsCustomHighlights()
        ? keysForRanges(ranges, wordRanges, true)
        : legacyKeyForMarkedRanges(
          ranges,
          'span.leaf-reader-linked-word[data-leaf-word-id]',
          'leafWordId',
          true
        )
    };
  };

  const api = { makeMarksAPI };
  if (typeof module !== 'undefined' && module.exports) module.exports = api;
  root.LeafReaderWebMarks = api;
})();
