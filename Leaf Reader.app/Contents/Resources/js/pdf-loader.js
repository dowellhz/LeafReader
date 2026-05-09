/* global pdfjsLib */

const PDFLoader = (() => {
  let pdfDoc = null;
  let totalPages = 0;
  let currentSpread = 0;

  const CANVAS_LEFT = document.getElementById('canvas-left');
  const CANVAS_RIGHT = document.getElementById('canvas-right');
  const TEXT_LAYER_LEFT = document.getElementById('text-layer-left');
  const TEXT_LAYER_RIGHT = document.getElementById('text-layer-right');
  const PAGE_LEFT_EL = document.getElementById('page-left');
  const PAGE_RIGHT_EL = document.getElementById('page-right');
  const UPLOAD_ZONE = document.getElementById('upload-zone');
  const BOOK_WRAPPER = document.getElementById('book-wrapper');
  const PAGE_INDICATOR = document.getElementById('page-indicator');
  const TOP_TOOLBAR = document.getElementById('top-toolbar');
  const BOTTOM_NAV = document.getElementById('bottom-nav');

  const RENDER_SCALE = 2.0;
  const PADDING_X = 40;
  const PADDING_Y = 40;

  let pageWidth = 0;   // natural page width (at scale 1.0)
  let pageHeight = 0;  // natural page height (at scale 1.0)
  let displayScale = 1;
  let displayW = 0;
  let displayH = 0;
  let zoomMultiplier = 1.0;

  function getTotalSpreads() {
    return Math.ceil(totalPages / 2);
  }

  function getSpreadPages(spreadIndex) {
    const leftPage = spreadIndex * 2 + 1;
    const rightPage = leftPage + 1;
    return {
      leftPage,
      rightPage: rightPage <= totalPages ? rightPage : null,
      hasRight: rightPage <= totalPages,
      leftNum: leftPage,
      rightNum: rightPage <= totalPages ? rightPage : null
    };
  }

  function calcFitScale(naturalW, naturalH) {
    const toolbarH = TOP_TOOLBAR.offsetHeight || 40;
    const navH = BOTTOM_NAV.offsetHeight || 44;
    const availW = window.innerWidth - PADDING_X * 2;
    const availH = window.innerHeight - toolbarH - navH - PADDING_Y * 2;

    const pageMaxW = availW / 2;
    const pageMaxH = availH;

    const scaleW = pageMaxW / naturalW;
    const scaleH = pageMaxH / naturalH;
    return Math.min(scaleW, scaleH, 1.0);
  }

  async function renderPage(pageNum, canvas, scale) {
    const page = await pdfDoc.getPage(pageNum);
    const viewport = page.getViewport({ scale });

    canvas.width = viewport.width;
    canvas.height = viewport.height;

    const ctx = canvas.getContext('2d');
    await page.render({ canvasContext: ctx, viewport }).promise;

    return { viewport, page };
  }

  async function renderTextLayer(page, viewport, textLayerDiv) {
    textLayerDiv.innerHTML = '';

    const textContent = await page.getTextContent();
    const textItems = textContent.items;

    if (textItems.length === 0) return;

    textLayerDiv.style.width = `${viewport.width}px`;
    textLayerDiv.style.height = `${viewport.height}px`;

    const textLayerFragment = document.createDocumentFragment();

    for (const item of textItems) {
      if (!item.str) continue;

      const tx = pdfjsLib.Util.transform(viewport.transform, item.transform);
      const angle = Math.atan2(tx[1], tx[0]);
      const style = textContent.styles[item.fontName] || {};
      const fontSize = Math.sqrt(tx[2] * tx[2] + tx[3] * tx[3]);
      const scale = viewport.width / page.view[2];

      const div = document.createElement('span');
      div.textContent = item.str;
      div.style.left = `${tx[4]}px`;
      div.style.fontSize = `${fontSize}px`;
      div.style.fontFamily = style.fontFamily || 'sans-serif';

      // Use font metrics to position accurately and prevent line overlap
      if (style.ascent) {
        const ascent = style.ascent * fontSize;
        const descent = style.descent ? style.descent * fontSize : fontSize * 0.2;
        div.style.top = `${tx[5] - ascent}px`;
        div.style.height = `${ascent + descent}px`;
      } else {
        div.style.top = `${tx[5] - fontSize * 0.8}px`;
        div.style.height = `${fontSize}px`;
      }

      div.style.overflow = 'hidden';
      div.style.lineHeight = '1';
      div.style.verticalAlign = 'baseline';

      if (angle !== 0) {
        div.style.transform = `rotate(${angle}rad)`;
      }
      if (item.width > 0) {
        div.style.width = `${item.width * scale}px`;
      }

      textLayerFragment.appendChild(div);
    }

    textLayerDiv.appendChild(textLayerFragment);
  }

  async function renderSpread(spreadIndex) {
    if (!pdfDoc) return;

    const { leftNum, hasRight, rightNum } = getSpreadPages(spreadIndex);

    // Get natural page size (at scale 1.0)
    const firstPage = await pdfDoc.getPage(leftNum);
    const naturalViewport = firstPage.getViewport({ scale: 1.0 });
    pageWidth = naturalViewport.width;
    pageHeight = naturalViewport.height;

    // Calculate display scale to fit viewport (based on natural size), apply zoom
    displayScale = calcFitScale(pageWidth, pageHeight) * zoomMultiplier;
    displayW = Math.floor(pageWidth * displayScale);
    displayH = Math.floor(pageHeight * displayScale);

    // Render canvas at RENDER_SCALE for crisp quality, CSS-size to display
    const { viewport: canvasViewport } = await renderPage(leftNum, CANVAS_LEFT, RENDER_SCALE);
    CANVAS_LEFT.style.width = `${displayW}px`;
    CANVAS_LEFT.style.height = `${displayH}px`;

    // Render text layer at displayScale — text coords match visual layout 1:1
    const textViewport = firstPage.getViewport({ scale: displayScale });
    await renderTextLayer(firstPage, textViewport, TEXT_LAYER_LEFT);
    TEXT_LAYER_LEFT.style.width = `${displayW}px`;
    TEXT_LAYER_LEFT.style.height = `${displayH}px`;

    // Page element at display size
    PAGE_LEFT_EL.style.width = `${displayW}px`;
    PAGE_LEFT_EL.style.height = `${displayH}px`;
    PAGE_LEFT_EL.style.display = '';
    PAGE_LEFT_EL.style.overflow = 'hidden';

    // Page-content at display size (no transform)
    const leftContent = PAGE_LEFT_EL.querySelector('.page-content');
    leftContent.style.width = `${displayW}px`;
    leftContent.style.height = `${displayH}px`;
    leftContent.style.transform = '';
    leftContent.style.transformOrigin = '';

    if (hasRight) {
      const { viewport: rCv } = await renderPage(rightNum, CANVAS_RIGHT, RENDER_SCALE);
      const rDisplayW = Math.floor(pageWidth * displayScale);
      const rDisplayH = Math.floor(pageHeight * displayScale);
      CANVAS_RIGHT.style.width = `${rDisplayW}px`;
      CANVAS_RIGHT.style.height = `${rDisplayH}px`;

      const rPage = await pdfDoc.getPage(rightNum);
      const rTextViewport = rPage.getViewport({ scale: displayScale });
      await renderTextLayer(rPage, rTextViewport, TEXT_LAYER_RIGHT);
      TEXT_LAYER_RIGHT.style.width = `${rDisplayW}px`;
      TEXT_LAYER_RIGHT.style.height = `${rDisplayH}px`;

      PAGE_RIGHT_EL.style.width = `${rDisplayW}px`;
      PAGE_RIGHT_EL.style.height = `${rDisplayH}px`;
      PAGE_RIGHT_EL.style.display = '';

      const rightContent = PAGE_RIGHT_EL.querySelector('.page-content');
      rightContent.style.width = `${rDisplayW}px`;
      rightContent.style.height = `${rDisplayH}px`;
      rightContent.style.transform = '';
      rightContent.style.transformOrigin = '';
    } else {
      PAGE_RIGHT_EL.style.display = 'none';
    }

    currentSpread = spreadIndex;
    updatePageIndicator();
    saveCurrentPosition();
  }

  function saveCurrentPosition() {
    if (typeof Storage !== 'undefined') {
      Storage.savePosition(currentSpread).catch(() => {});
    }
  }

  function updatePageIndicator() {
    const { leftNum, rightNum } = getSpreadPages(currentSpread);
    if (rightNum) {
      PAGE_INDICATOR.textContent = `Page ${leftNum}-${rightNum} / ${totalPages}`;
    } else {
      PAGE_INDICATOR.textContent = `Page ${leftNum} / ${totalPages}`;
    }
  }

  let currentFile = null;

  async function loadPDF(file, startSpread) {
    currentFile = file;
    const arrayBuffer = await file.arrayBuffer();
    pdfDoc = await pdfjsLib.getDocument({ data: arrayBuffer }).promise;
    totalPages = pdfDoc.numPages;
    currentSpread = (startSpread !== undefined) ? Math.min(startSpread, getTotalSpreads() - 1) : 0;

    UPLOAD_ZONE.style.display = 'none';
    BOOK_WRAPPER.style.display = '';

    await renderSpread(currentSpread);

    // Save to IndexedDB
    if (typeof Storage !== 'undefined') {
      Storage.savePDF(file, currentSpread, file.name).catch(() => {});
    }

    if (typeof PageFlip !== 'undefined') PageFlip.onPDFLoaded(totalPages, currentSpread);
    if (typeof TextSelect !== 'undefined') TextSelect.setupTextLayers();
  }

  // Load from stored ArrayBuffer (for restore)
  async function loadPDFFromBuffer(buffer, filename, startSpread) {
    pdfDoc = await pdfjsLib.getDocument({ data: buffer }).promise;
    totalPages = pdfDoc.numPages;
    currentFile = { name: filename };
    currentSpread = (startSpread !== undefined) ? Math.min(startSpread, getTotalSpreads() - 1) : 0;

    UPLOAD_ZONE.style.display = 'none';
    BOOK_WRAPPER.style.display = '';

    await renderSpread(currentSpread);

    if (typeof PageFlip !== 'undefined') PageFlip.onPDFLoaded(totalPages, currentSpread);
    if (typeof TextSelect !== 'undefined') TextSelect.setupTextLayers();
  }

  function getState() {
    return {
      totalPages,
      currentSpread,
      totalSpreads: getTotalSpreads(),
      pageWidth,
      pageHeight,
      displayScale,
      displayW,
      displayH,
      pdfDoc
    };
  }

  function canGoNext() {
    return currentSpread < getTotalSpreads() - 1;
  }

  function canGoPrev() {
    return currentSpread > 0;
  }

  // Render a page into a container at display-scale (used by flip overlay)
  async function renderPageToContainer(pageNum, container) {
    if (!pdfDoc) return;

    const page = await pdfDoc.getPage(pageNum);
    const viewport = page.getViewport({ scale: RENDER_SCALE });

    let canvas = container.querySelector('canvas');
    if (!canvas) {
      canvas = document.createElement('canvas');
      container.appendChild(canvas);
    }

    canvas.width = viewport.width;
    canvas.height = viewport.height;
    canvas.style.width = `${displayW}px`;
    canvas.style.height = `${displayH}px`;

    const ctx = canvas.getContext('2d');
    await page.render({ canvasContext: ctx, viewport }).promise;

    container.style.width = `${displayW}px`;
    container.style.height = `${displayH}px`;

    return { viewport, page, canvas };
  }

  function getCurrentSpread() {
    return currentSpread;
  }

  function onResize() {
    if (pdfDoc) {
      renderSpread(currentSpread);
    }
  }

  function setZoom(level) {
    zoomMultiplier = level;
    if (pdfDoc) renderSpread(currentSpread);
  }

  function reRender() {
    if (pdfDoc) renderSpread(currentSpread);
  }

  let resizeTimer;
  window.addEventListener('resize', () => {
    clearTimeout(resizeTimer);
    resizeTimer = setTimeout(onResize, 200);
  });

  return {
    loadPDF,
    loadPDFFromBuffer,
    renderSpread,
    renderPageToContainer,
    getState,
    canGoNext,
    canGoPrev,
    getCurrentSpread,
    getTotalSpreads,
    getSpreadPages,
    setZoom,
    reRender
  };
})();
