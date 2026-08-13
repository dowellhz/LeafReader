(() => {
  const root = typeof globalThis !== 'undefined' ? globalThis : this;
  const readerOverlayStyleID = 'leaf-reader-overlay-style';
  const installReaderOverlayStyle = () => {
    if (document.getElementById(readerOverlayStyleID)) return;
    const style = document.createElement('style');
    style.id = readerOverlayStyleID;
    style.textContent = `
      ::highlight(leaf-reader-ai-source) { text-decoration-line: underline; text-decoration-color: var(--leaf-reader-ai-source-underline, rgba(0, 122, 255, .72)); text-decoration-thickness: 1.5px; text-underline-offset: .16em; }
      ::highlight(leaf-reader-tts) { background: rgba(143, 199, 125, .32); color: inherit; }
      .leaf-reader-ai-source-underline { text-decoration-line: underline; text-decoration-color: var(--leaf-reader-ai-source-underline, rgba(0, 122, 255, .72)); text-decoration-thickness: 1.5px; text-underline-offset: .16em; }
      .leaf-reader-tts-underline { background: rgba(143, 199, 125, .32); border-radius: 2px; -webkit-user-select: text; user-select: text; }
      .leaf-reader-linked-word { background: transparent; border-radius: 2px; cursor: pointer; text-decoration-line: underline; text-decoration-style: solid; text-decoration-color: var(--leaf-reader-ai-source-underline, rgba(0, 122, 255, .72)); text-decoration-thickness: 3px; text-underline-offset: .16em; }
      .leaf-reader-note-highlight { background: var(--leaf-reader-note-highlight-background, rgba(145, 202, 255, .34)); border-radius: 3px; cursor: pointer; }
      ::highlight(leaf-reader-linked-word) { background: transparent; text-decoration-line: underline; text-decoration-style: solid; text-decoration-color: var(--leaf-reader-ai-source-underline, rgba(0, 122, 255, .72)); text-decoration-thickness: 3px; text-underline-offset: .16em; }
      ::highlight(leaf-reader-note-highlight) { background: var(--leaf-reader-note-highlight-background, rgba(145, 202, 255, .34)); color: inherit; }
      ::highlight(leaf-reader-search) { background: rgba(255, 221, 87, .52); color: inherit; }
      ::highlight(leaf-reader-search-current) { background: rgba(255, 149, 0, .72); color: inherit; }
    `;
    document.head.appendChild(style);
  };
  const api = { installReaderOverlayStyle };
  if (typeof module !== 'undefined' && module.exports) module.exports = api;
  root.LeafReaderWebOverlay = api;
})();
