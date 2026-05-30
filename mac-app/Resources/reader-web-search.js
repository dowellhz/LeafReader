(() => {
  const root = typeof globalThis !== 'undefined' ? globalThis : this;

  const makeSearchAPI = ({ installReaderOverlayStyle, leafReaderFindSearchSpans }) => {
    let searchQuery = '';
    let searchIndex = -1;
    let searchRanges = [];

    const clearSearchHighlights = () => {
      searchRanges = [];
      if (window.CSS && CSS.highlights) {
        CSS.highlights.delete('leaf-reader-search');
        CSS.highlights.delete('leaf-reader-search-current');
      }
      searchQuery = '';
      searchIndex = -1;
    };

    const findSearchRanges = (query) => {
      const needle = String(query || '').toLowerCase();
      if (!needle) return [];
      const walker = document.createTreeWalker(document.body, NodeFilter.SHOW_TEXT, {
        acceptNode(node) {
          const parent = node.parentElement;
          if (!parent || parent.closest('script,style,noscript')) return NodeFilter.FILTER_REJECT;
          if (!(node.nodeValue || '').toLowerCase().includes(needle)) return NodeFilter.FILTER_SKIP;
          return NodeFilter.FILTER_ACCEPT;
        }
      });
      const matches = [];
      let node;
      while ((node = walker.nextNode())) {
        const value = node.nodeValue || '';
        for (const span of leafReaderFindSearchSpans(value, needle)) {
          matches.push({ node, start: span.start, end: span.end });
        }
      }
      return matches.map((match) => {
        const range = document.createRange();
        range.setStart(match.node, match.start);
        range.setEnd(match.node, match.end);
        return range;
      });
    };

    const applySearchHighlights = () => {
      if (!(window.CSS && CSS.highlights && window.Highlight)) return false;
      if (searchRanges.length > 0) {
        CSS.highlights.set('leaf-reader-search', new Highlight(...searchRanges));
      } else {
        CSS.highlights.delete('leaf-reader-search');
      }
      const current = searchRanges[searchIndex];
      if (current) {
        CSS.highlights.set('leaf-reader-search-current', new Highlight(current));
      } else {
        CSS.highlights.delete('leaf-reader-search-current');
      }
      return true;
    };

    const search = (query, direction, reset) => {
      installReaderOverlayStyle();
      if (!(window.CSS && CSS.highlights && window.Highlight)) {
        const found = window.find(String(query || ''), false, direction < 0, true, false, true, false);
        return { index: found ? 1 : 0, total: found ? 1 : 0 };
      }
      const normalizedQuery = String(query || '').trim();
      if (!normalizedQuery) {
        clearSearchHighlights();
        return { index: 0, total: 0 };
      }
      if (reset || normalizedQuery !== searchQuery) {
        searchQuery = normalizedQuery;
        searchIndex = -1;
        searchRanges = findSearchRanges(normalizedQuery);
      }
      const total = searchRanges.length;
      if (!total) return { index: 0, total: 0 };
      searchIndex = (searchIndex + (direction < 0 ? -1 : 1) + total) % total;
      applySearchHighlights();
      const current = searchRanges[searchIndex];
      const rect = current.getBoundingClientRect();
      window.scrollBy({ top: rect.top - (window.innerHeight * 0.35), behavior: 'smooth' });
      return { index: searchIndex + 1, total };
    };

    return { clearSearchHighlights, search };
  };

  const api = { makeSearchAPI };
  if (typeof module !== 'undefined' && module.exports) module.exports = api;
  root.LeafReaderWebSearch = api;
})();
