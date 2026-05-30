(() => {
  const root = typeof globalThis !== 'undefined' ? globalThis : this;

  const makeMarksAPI = ({ installReaderOverlayStyle, normalizedText, wrapRangeTextNodes, findTextRange, unwrapSpans }) => {
    const scrollToProgress = (fallbackProgress) => {
      const height = Math.max(1, document.documentElement.scrollHeight - window.innerHeight);
      window.scrollTo({
        top: height * Math.max(0, Math.min(1, Number(fallbackProgress || 0))),
        behavior: 'smooth'
      });
    };

    const removeMarkedSpans = (selector) => {
      document.querySelectorAll(selector).forEach((span) => {
        const parent = span.parentNode;
        if (!parent) return;
        while (span.firstChild) parent.insertBefore(span.firstChild, span);
        parent.removeChild(span);
        parent.normalize();
      });
    };

    const rangesIntersect = (left, right) => {
      try {
        return left.compareBoundaryPoints(Range.START_TO_END, right) < 0
          && left.compareBoundaryPoints(Range.END_TO_START, right) > 0;
      } catch (_) {
        return false;
      }
    };

    const keyForMarkedRanges = (ranges, selector, dataKey) => {
      const spans = Array.from(document.querySelectorAll(selector));
      if (!spans.length) return dataKey === 'leafWordId' ? [] : '';
      const ids = [];
      for (const range of ranges || []) {
        for (const span of spans) {
          const markRange = document.createRange();
          markRange.selectNodeContents(span);
          const intersects = rangesIntersect(range, markRange);
          markRange.detach && markRange.detach();
          const id = span.dataset[dataKey] || '';
          if (!intersects || !id) continue;
          if (dataKey !== 'leafWordId') return id;
          if (!ids.includes(id)) ids.push(id);
        }
      }
      return dataKey === 'leafWordId' ? ids : '';
    };

    const clearAISourceUnderlines = () => {
      if (window.CSS && CSS.highlights) CSS.highlights.delete('leaf-reader-ai-source');
      unwrapSpans('span.leaf-reader-ai-source-underline');
    };

    const addAISourceUnderlineForSelection = (key) => {
      const selection = window.getSelection();
      const text = String(selection || '').trim();
      if (!selection || selection.rangeCount === 0 || text.length === 0) return false;
      installReaderOverlayStyle();
      const range = selection.getRangeAt(0).cloneRange();
      return wrapRangeTextNodes(range, 'leaf-reader-ai-source-underline', (span) => {
        span.dataset.leafAiSourceKey = String(key || '');
      });
    };

    const restoreAISourceUnderlines = (sources) => {
      clearAISourceUnderlines();
      installReaderOverlayStyle();
      for (const source of sources || []) {
        const text = normalizedText(source.selectedText || '');
        if (!text) continue;
        const range = findTextRange(text, source.context || '', source.occurrenceIndex || 0);
        if (!range) continue;
        wrapRangeTextNodes(range, 'leaf-reader-ai-source-underline', (span) => {
          span.dataset.leafAiSourceKey = String(source.key || '');
        });
      }
    };

    const restoreWordHighlights = (records) => {
      installReaderOverlayStyle();
      removeMarkedSpans('span.leaf-reader-linked-word');
      for (const record of records || []) {
        try {
          const range = findTextRange(record.word, record.context, record.occurrenceIndex || 0);
          if (!range) continue;
          wrapRangeTextNodes(range, 'leaf-reader-linked-word', (span) => {
            span.dataset.leafWordId = record.id;
          });
        } catch (_) {}
      }
    };

    const markSelectionAsWord = (id) => {
      const selection = window.getSelection();
      const text = String(selection || '').trim();
      if (!selection || selection.rangeCount === 0 || !text || !id) return false;
      installReaderOverlayStyle();
      const range = selection.getRangeAt(0).cloneRange();
      const didWrap = wrapRangeTextNodes(range, 'leaf-reader-linked-word', (span) => {
        span.dataset.leafWordId = String(id);
      });
      selection.removeAllRanges();
      return didWrap;
    };

    const restoreNoteHighlights = (records) => {
      installReaderOverlayStyle();
      removeMarkedSpans('span.leaf-reader-note-highlight');
      for (const record of records || []) {
        try {
          const range = findTextRange(record.selectedText, record.context, record.occurrenceIndex || 0);
          if (!range) continue;
          wrapRangeTextNodes(range, 'leaf-reader-note-highlight', (span) => {
            span.dataset.leafNoteId = record.id;
          });
        } catch (_) {}
      }
    };

    const markSelectionAsNote = (id) => {
      const selection = window.getSelection();
      const text = String(selection || '').trim();
      if (!selection || selection.rangeCount === 0 || !text || !id) return false;
      installReaderOverlayStyle();
      const range = selection.getRangeAt(0).cloneRange();
      const didWrap = wrapRangeTextNodes(range, 'leaf-reader-note-highlight', (span) => {
        span.dataset.leafNoteId = String(id);
      });
      selection.removeAllRanges();
      return didWrap;
    };

    const scrollToNote = (id, fallbackProgress) => {
      const target = document.querySelector(`span.leaf-reader-note-highlight[data-leaf-note-id="${CSS.escape(String(id || ''))}"]`);
      if (target) {
        target.scrollIntoView({ behavior: 'smooth', block: 'center' });
        return true;
      }
      scrollToProgress(fallbackProgress);
      return false;
    };

    const removeNoteHighlight = (id) => {
      const selector = `span.leaf-reader-note-highlight[data-leaf-note-id="${CSS.escape(String(id || ''))}"]`;
      removeMarkedSpans(selector);
    };

    const removeWordHighlight = (id) => {
      const selector = `span.leaf-reader-linked-word[data-leaf-word-id="${CSS.escape(String(id || ''))}"]`;
      removeMarkedSpans(selector);
    };

    const scrollToWord = (id, fallbackProgress) => {
      const target = document.querySelector(`span.leaf-reader-linked-word[data-leaf-word-id="${CSS.escape(String(id || ''))}"]`);
      if (target) {
        target.scrollIntoView({ behavior: 'smooth', block: 'center' });
        return true;
      }
      scrollToProgress(fallbackProgress);
      return false;
    };

    return {
      clearAISourceUnderlines,
      addAISourceUnderlineForSelection,
      restoreAISourceUnderlines,
      restoreWordHighlights,
      markSelectionAsWord,
      restoreNoteHighlights,
      markSelectionAsNote,
      scrollToNote,
      removeNoteHighlight,
      removeWordHighlight,
      scrollToWord,
      aiSourceKeyForRanges: (ranges) => keyForMarkedRanges(
        ranges,
        'span.leaf-reader-ai-source-underline[data-leaf-ai-source-key]',
        'leafAiSourceKey'
      ),
      linkedWordIDsForRanges: (ranges) => keyForMarkedRanges(
        ranges,
        'span.leaf-reader-linked-word[data-leaf-word-id]',
        'leafWordId'
      )
    };
  };

  const api = { makeMarksAPI };
  if (typeof module !== 'undefined' && module.exports) module.exports = api;
  root.LeafReaderWebMarks = api;
})();
