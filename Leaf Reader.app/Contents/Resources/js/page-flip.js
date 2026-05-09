const PageFlip = (() => {
  let totalPages = 0;
  let currentSpread = 0;
  let isAnimating = false;

  const BOOK = document.getElementById('book');
  const PAGE_RIGHT = document.getElementById('page-right');
  const PAGE_LEFT = document.getElementById('page-left');
  const BTN_PREV = document.getElementById('btn-prev');
  const BTN_NEXT = document.getElementById('btn-next');

  function getPageSize(el) {
    const content = el.querySelector('.page-content');
    return {
      w: content ? content.offsetWidth : el.offsetWidth,
      h: content ? content.offsetHeight : el.offsetHeight
    };
  }

  function onPDFLoaded(_totalPages, _currentSpread) {
    totalPages = _totalPages;
    currentSpread = _currentSpread;
    updateNavButtons();
  }

  function updateNavButtons() {
    BTN_PREV.disabled = currentSpread <= 0 || !PDFLoader.canGoPrev();
    BTN_NEXT.disabled = !PDFLoader.canGoNext();
  }

  function cleanup(overlay) {
    if (overlay) overlay.remove();
    BOOK.classList.remove('flipping-forward', 'flipping-backward');
    isAnimating = false;
  }

  async function quickFlipForward() {
    if (isAnimating || !PDFLoader.canGoNext()) return;
    isAnimating = true;

    const { w, h } = getPageSize(PAGE_RIGHT);
    if (w === 0 || h === 0) { isAnimating = false; return; }

    const nextSpread = currentSpread + 1;
    const { leftNum } = PDFLoader.getSpreadPages(nextSpread);

    const overlay = document.createElement('div');
    overlay.className = 'page-flip forward';
    overlay.style.width = `${w}px`;
    overlay.style.height = `${h}px`;

    const front = document.createElement('div');
    front.className = 'page-flip-front';
    const back = document.createElement('div');
    back.className = 'page-flip-back';
    const edge = document.createElement('div');
    edge.className = 'page-edge';

    overlay.appendChild(front);
    overlay.appendChild(back);
    overlay.appendChild(edge);

    // Copy current right page onto front
    const rightCanvas = document.getElementById('canvas-right');
    const copyCanvas = document.createElement('canvas');
    copyCanvas.width = rightCanvas.width;
    copyCanvas.height = rightCanvas.height;
    copyCanvas.style.width = `${w}px`;
    copyCanvas.style.height = `${h}px`;
    copyCanvas.getContext('2d').drawImage(rightCanvas, 0, 0);
    front.appendChild(copyCanvas);

    // Render next page onto back
    await PDFLoader.renderPageToContainer(leftNum, back);

    PAGE_RIGHT.querySelector('.page-content').appendChild(overlay);
    BOOK.classList.add('flipping-forward');

    overlay.addEventListener('animationend', async () => {
      currentSpread = nextSpread;
      await PDFLoader.renderSpread(currentSpread);
      cleanup(overlay);
      updateNavButtons();
    }, { once: true });
  }

  async function quickFlipBackward() {
    if (isAnimating || !PDFLoader.canGoPrev()) return;
    isAnimating = true;

    const { w, h } = getPageSize(PAGE_LEFT);
    if (w === 0 || h === 0) { isAnimating = false; return; }

    const prevSpread = currentSpread - 1;
    const { rightNum } = PDFLoader.getSpreadPages(prevSpread);
    const { leftNum } = PDFLoader.getSpreadPages(currentSpread);

    const overlay = document.createElement('div');
    overlay.className = 'page-flip backward';
    overlay.style.width = `${w}px`;
    overlay.style.height = `${h}px`;

    const front = document.createElement('div');
    front.className = 'page-flip-front';
    const back = document.createElement('div');
    back.className = 'page-flip-back';
    const edge = document.createElement('div');
    edge.className = 'page-edge';
    edge.style.right = 'auto';
    edge.style.left = '0';

    overlay.appendChild(front);
    overlay.appendChild(back);
    overlay.appendChild(edge);

    await PDFLoader.renderPageToContainer(leftNum, front);
    await PDFLoader.renderPageToContainer(rightNum, back);

    PAGE_LEFT.querySelector('.page-content').appendChild(overlay);
    BOOK.classList.add('flipping-backward');

    overlay.addEventListener('animationend', async () => {
      currentSpread = prevSpread;
      await PDFLoader.renderSpread(currentSpread);
      cleanup(overlay);
      updateNavButtons();
    }, { once: true });
  }

  function setupNavigation() {
    BTN_NEXT.addEventListener('click', (e) => { e.stopPropagation(); quickFlipForward(); });
    BTN_PREV.addEventListener('click', (e) => { e.stopPropagation(); quickFlipBackward(); });

    document.addEventListener('keydown', (e) => {
      if (e.target.tagName === 'INPUT' || e.target.tagName === 'TEXTAREA') return;
      if (e.key === 'ArrowRight') { e.preventDefault(); quickFlipForward(); }
      if (e.key === 'ArrowLeft') { e.preventDefault(); quickFlipBackward(); }
    });
  }

  function init() {
    setupNavigation();
    updateNavButtons();
  }

  return { init, onPDFLoaded, quickFlipForward, quickFlipBackward };
})();
