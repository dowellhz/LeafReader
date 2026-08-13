(() => {
  const root = typeof globalThis !== 'undefined' ? globalThis : this;

  const install = ({ occurrenceIndexInText, scrollProgress }) => {
    let lastScrollSent = 0;
    let documentMouseDown = false;

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
      window.webkit.messageHandlers.selectionChanged.postMessage({ text: '', context: '' });
    };
    window.leafReaderClearSelectionVisualOnly = () => {
      clearLegacySelectionOverlay();
      const selection = window.getSelection();
      if (selection) selection.removeAllRanges();
    };

    const sendSelection = () => {
      const selection = window.getSelection();
      const text = String(selection || '').trim();
      let context = '';
      if (selection && selection.rangeCount > 0 && text.length > 0) {
        const range = selection.getRangeAt(0);
        const container = range.commonAncestorContainer;
        const element = container.nodeType === Node.ELEMENT_NODE ? container : container.parentElement;
        const block = element ? element.closest('p,li,blockquote,pre,td,th,h1,h2,h3,h4,h5,h6,div') : null;
        const source = block ? (block.innerText || block.textContent || '') : text;
        context = source.replace(/\s+/g, ' ').trim().slice(0, 360);
        let occurrenceIndex = 0;
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
            beforeRange.setEnd(range.startContainer, range.startOffset);
            occurrenceIndex = occurrenceIndexInText(source, text, beforeRange.toString());
          } catch (_) {}
        }
        window.webkit.messageHandlers.selectionChanged.postMessage({ text, context, occurrenceIndex, rect });
        return;
      }
      if (documentMouseDown) clearLegacySelectionOverlay();
      window.webkit.messageHandlers.selectionChanged.postMessage({ text, context, occurrenceIndex: null, rect: null });
    };
    const sendScroll = (force = false) => {
      const now = Date.now();
      if (!force && now - lastScrollSent < 200) return;
      lastScrollSent = now;
      window.webkit.messageHandlers.scrollChanged.postMessage(scrollProgress());
    };

    window.leafReaderJumpToHref = (href) => {
      href = String(href || '');
      const fragment = href.includes('#') ? href.split('#').pop() : (href.startsWith('#') ? href.slice(1) : '');
      const path = href.split('#')[0];
      const sections = Array.from(document.querySelectorAll('section.reader-section[data-leaf-href]'));
      const matchingSection = path ? sections.find((section) => {
        const value = section.dataset.leafHref || '';
        return value === path || value.endsWith(`/${path}`) || path.endsWith(`/${value}`);
      }) : null;
      if (fragment) {
        const target = matchingSection
          ? (window.CSS && CSS.escape
            ? matchingSection.querySelector(`#${CSS.escape(fragment)}`)
            : Array.from(matchingSection.querySelectorAll('[id]')).find((element) => element.id === fragment))
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

    document.addEventListener('mousedown', () => {
      documentMouseDown = true;
      clearLegacySelectionOverlay();
      const selection = window.getSelection();
      if (selection) selection.removeAllRanges();
      window.webkit.messageHandlers.selectionChanged.postMessage({ text: '', context: '' });
    });
    document.addEventListener('click', (event) => {
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
      const word = event.target?.closest?.('span.leaf-reader-linked-word');
      if (word) {
        event.preventDefault();
        event.stopPropagation();
        window.webkit.messageHandlers.webWordClicked.postMessage(String(word.dataset.leafWordId || ''));
        return;
      }
      const note = event.target?.closest?.('span.leaf-reader-note-highlight');
      if (!note) return;
      event.preventDefault();
      event.stopPropagation();
      window.webkit.messageHandlers.webNoteClicked.postMessage(String(note.dataset.leafNoteId || ''));
    }, true);
    document.addEventListener('selectionchange', () => setTimeout(sendSelection, 0));
    document.addEventListener('mouseup', () => {
      documentMouseDown = false;
      sendSelection();
    });
    document.addEventListener('keyup', sendSelection);
    window.addEventListener('scroll', () => sendScroll(false), { passive: true });
    window.addEventListener('load', () => sendScroll(true));
    setTimeout(() => sendScroll(true), 250);
  };

  root.LeafReaderWebSelection = { install };
  if (typeof module !== 'undefined' && module.exports) module.exports = { install };
})();
