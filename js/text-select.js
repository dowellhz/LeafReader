const TextSelect = (() => {
  const FLOAT_TOOLBAR = document.getElementById('float-toolbar');
  const BTN_ANALYZE = document.getElementById('btn-analyze');
  const BTN_CLOSE = document.getElementById('btn-close-toolbar');

  let selectedText = '';
  let onAnalyzeCallback = null;
  let startHandle = null;
  let endHandle = null;

  function setupTextLayers() {
    document.querySelectorAll('.textLayer').forEach(layer => {
      layer.style.pointerEvents = 'auto';
      layer.style.userSelect = 'text';
      layer.style.webkitUserSelect = 'text';
    });
  }

  // --- Create iOS-style selection handles ---
  function ensureHandles() {
    if (!startHandle) {
      startHandle = document.createElement('div');
      startHandle.className = 'selection-handle';
      startHandle.id = 'sel-handle-start';
      document.body.appendChild(startHandle);
    }
    if (!endHandle) {
      endHandle = document.createElement('div');
      endHandle.className = 'selection-handle';
      endHandle.id = 'sel-handle-end';
      document.body.appendChild(endHandle);
    }
  }

  function updateHandles() {
    const sel = window.getSelection();
    if (!sel || sel.isCollapsed || !sel.toString().trim()) {
      hideHandles();
      return;
    }

    ensureHandles();

    const range = sel.getRangeAt(0);
    const startRect = range.getClientRects()[0];
    const rects = range.getClientRects();
    const endRect = rects[rects.length - 1];

    if (startRect) {
      startHandle.style.display = '';
      startHandle.style.top = `${startRect.top - 14}px`;
      startHandle.style.left = `${startRect.left - 5}px`;
    }
    if (endRect) {
      endHandle.style.display = '';
      endHandle.style.top = `${endRect.bottom + 4}px`;
      endHandle.style.left = `${endRect.right - 5}px`;
    }
  }

  function hideHandles() {
    if (startHandle) startHandle.style.display = 'none';
    if (endHandle) endHandle.style.display = 'none';
  }

  // --- Double-click: select whole word ---
  function handleDblClick(e) {
    const target = e.target;
    if (!target.closest || !target.closest('.textLayer')) return;

    const sel = window.getSelection();
    if (!sel.isCollapsed) return;

    // Find the text node under cursor
    const range = document.caretRangeFromPoint(e.clientX, e.clientY);
    if (!range) return;

    const textNode = range.startContainer;
    if (textNode.nodeType !== Node.TEXT_NODE) return;

    const text = textNode.textContent;
    const offset = range.startOffset;

    // Expand to word boundaries
    let start = offset;
    let end = offset;
    const wordRe = /[\w'-]/;

    while (start > 0 && wordRe.test(text[start - 1])) start--;
    while (end < text.length && wordRe.test(text[end])) end++;

    if (start === end) {
      // Not on a word character, select the nearest non-space chunk
      while (start > 0 && text[start - 1] !== ' ') start--;
      while (end < text.length && text[end] !== ' ') end++;
    }

    if (start < end) {
      const wordRange = document.createRange();
      wordRange.setStart(textNode, start);
      wordRange.setEnd(textNode, end);
      sel.removeAllRanges();
      sel.addRange(wordRange);

      selectedText = sel.toString().trim();
      const rect = wordRange.getBoundingClientRect();
      updateHandles();
      setTimeout(() => showToolbar(rect), 50);
    }
  }

  // --- Mouseup: show toolbar for existing selection ---
  function handleMouseUp(e) {
    setTimeout(() => {
      const sel = window.getSelection();
      if (!sel || sel.isCollapsed || !sel.toString().trim()) {
        hideToolbar();
        hideHandles();
        return;
      }

      const text = sel.toString().trim();
      if (!text) {
        hideToolbar();
        hideHandles();
        return;
      }

      selectedText = text;

      const range = sel.getRangeAt(0);
      const rect = range.getBoundingClientRect();

      const container = range.commonAncestorContainer;
      const isInTextLayer = container.nodeType === Node.TEXT_NODE
        ? container.parentElement?.closest('.textLayer')
        : container.closest?.('.textLayer');

      if (!isInTextLayer) {
        hideToolbar();
        hideHandles();
        return;
      }

      updateHandles();
      showToolbar(rect);
    }, 30);
  }

  // --- Selection change: update handles ---
  function handleSelectionChange() {
    const sel = window.getSelection();
    if (!sel || sel.isCollapsed || !sel.toString().trim()) {
      hideHandles();
      return;
    }
    if (sel.toString().trim() !== selectedText) {
      selectedText = sel.toString().trim();
    }
    updateHandles();
  }

  // --- Toolbar ---
  function showToolbar(rect) {
    const toolbarWidth = FLOAT_TOOLBAR.offsetWidth || 150;
    let top = rect.top - 44;
    let left = rect.left + rect.width / 2 - toolbarWidth / 2;

    if (top < 10) top = rect.bottom + 8;
    if (left < 10) left = 10;
    if (left + toolbarWidth > window.innerWidth - 10) {
      left = window.innerWidth - toolbarWidth - 10;
    }

    FLOAT_TOOLBAR.style.top = `${top}px`;
    FLOAT_TOOLBAR.style.left = `${left}px`;
    FLOAT_TOOLBAR.classList.remove('hidden');
  }

  function hideToolbar() {
    FLOAT_TOOLBAR.classList.add('hidden');
  }

  function onAnalyze(callback) {
    onAnalyzeCallback = callback;
  }

  function getSelectedText() {
    return selectedText;
  }

  function init() {
    document.addEventListener('mouseup', handleMouseUp);
    document.addEventListener('dblclick', handleDblClick);
    document.addEventListener('selectionchange', handleSelectionChange);

    BTN_ANALYZE.addEventListener('click', (e) => {
      e.stopPropagation();
      if (onAnalyzeCallback && selectedText) {
        onAnalyzeCallback(selectedText);
      }
      hideToolbar();
      hideHandles();
    });

    BTN_CLOSE.addEventListener('click', (e) => {
      e.stopPropagation();
      hideToolbar();
      hideHandles();
    });

    document.addEventListener('mousedown', (e) => {
      if (!FLOAT_TOOLBAR.contains(e.target)) {
        hideToolbar();
      }
    });
  }

  return {
    init,
    setupTextLayers,
    onAnalyze,
    getSelectedText,
    hideToolbar
  };
})();
