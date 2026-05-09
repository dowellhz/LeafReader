/* global pdfjsLib */

const App = (() => {
  const FILE_INPUT = document.getElementById('file-input');
  const UPLOAD_ZONE = document.getElementById('upload-zone');
  const BOOK_WRAPPER = document.getElementById('book-wrapper');

  function init() {
    // Verify PDF.js loaded
    if (typeof pdfjsLib === 'undefined') {
      console.error('PDF.js not loaded');
      return;
    }

    // Initialize sub-modules
    PageFlip.init();
    TextSelect.init();
    AIPanel.init();

    // Wire events: text selection -> AI panel
    TextSelect.onAnalyze((text) => {
      AIPanel.open(text);
    });

    // File input handler
    FILE_INPUT.addEventListener('change', (e) => {
      const file = e.target.files[0];
      if (file && file.type === 'application/pdf') {
        handleFile(file);
      }
    });

    // Drag and drop
    UPLOAD_ZONE.addEventListener('dragover', (e) => {
      e.preventDefault();
      UPLOAD_ZONE.style.borderColor = '#4a6cf7';
    });

    UPLOAD_ZONE.addEventListener('dragleave', () => {
      UPLOAD_ZONE.style.borderColor = '';
    });

    UPLOAD_ZONE.addEventListener('drop', (e) => {
      e.preventDefault();
      UPLOAD_ZONE.style.borderColor = '';

      const file = e.dataTransfer.files[0];
      if (file && file.type === 'application/pdf') {
        handleFile(file);
      }
    });

    // Click upload zone to trigger file input
    UPLOAD_ZONE.addEventListener('click', () => {
      FILE_INPUT.click();
    });

    // Fullscreen toggle
    const btnFullscreen = document.getElementById('btn-fullscreen');
    btnFullscreen.addEventListener('click', () => {
      if (!document.fullscreenElement) {
        document.body.requestFullscreen().catch(() => {});
      } else {
        document.exitFullscreen();
      }
    });

    document.addEventListener('fullscreenchange', () => {
      if (document.fullscreenElement) {
        document.body.classList.add('is-fullscreen');
        btnFullscreen.textContent = 'Exit';
      } else {
        document.body.classList.remove('is-fullscreen');
        btnFullscreen.textContent = 'Full';
      }
      setTimeout(() => {
        if (typeof PDFLoader !== 'undefined') PDFLoader.reRender();
      }, 100);
    });

    // Zoom
    let zoomLevel = 1.0;
    const zoomIndicator = document.getElementById('zoom-indicator');

    function applyZoom(newLevel) {
      zoomLevel = Math.max(0.25, Math.min(4.0, newLevel));
      zoomIndicator.textContent = Math.round(zoomLevel * 100) + '%';
      if (typeof PDFLoader !== 'undefined') PDFLoader.setZoom(zoomLevel);
    }

    document.getElementById('btn-zoom-in').addEventListener('click', () => {
      applyZoom(zoomLevel + 0.25);
    });
    document.getElementById('btn-zoom-out').addEventListener('click', () => {
      applyZoom(zoomLevel - 0.25);
    });

    // Ctrl/Cmd + scroll to zoom
    BOOK_WRAPPER.addEventListener('wheel', (e) => {
      if (e.ctrlKey || e.metaKey) {
        e.preventDefault();
        applyZoom(zoomLevel + (e.deltaY < 0 ? 0.15 : -0.15));
      }
    }, { passive: false });

    // Ctrl/Cmd + 0 to reset zoom
    document.addEventListener('keydown', (e) => {
      if ((e.ctrlKey || e.metaKey) && e.key === '0') {
        e.preventDefault();
        applyZoom(1.0);
      }
    });

    // Auto-restore last PDF and reading position
    restoreLastSession();

    // Initially show upload zone, hide book
    BOOK_WRAPPER.style.display = 'none';
  }

  async function restoreLastSession() {
    try {
      const record = await Storage.loadPDF();
      if (record && record.data) {
        const blob = new Blob([record.data], { type: 'application/pdf' });
        const file = new File([blob], record.filename || 'restored.pdf', { type: 'application/pdf' });
        // Add a fake file reference so storage.js can re-save
        file._restored = true;
        await PDFLoader.loadPDFFromBuffer(record.data, record.filename, record.spread || 0);
      }
    } catch (err) {
      console.log('No saved session to restore');
    }
  }

  async function handleFile(file) {
    try {
      UPLOAD_ZONE.querySelector('.upload-inner').style.opacity = '0.5';
      await PDFLoader.loadPDF(file);
    } catch (err) {
      console.error('Failed to load PDF:', err);
      UPLOAD_ZONE.querySelector('.upload-inner p').textContent =
        'Error loading PDF. Please try another file.';
      UPLOAD_ZONE.querySelector('.upload-inner').style.opacity = '1';
    }
  }

  // Start when DOM is ready
  if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', init);
  } else {
    init();
  }

  return { init };
})();
