// Browser-side PDF rendering for slideshow.html, via pdf.js (pdfjs-dist,
// an npm dependency of this app). A module because pdf.js only ships as
// one; it sets window.KioskPdf for slideshow.html's classic script.
//
// Pages are drawn to canvases (no viewer toolbar, and the slideshow can
// scroll them like a Word document). pdf.js >= 4.2.67 is required - older
// versions could run JavaScript embedded in a crafted PDF (CVE-2024-4367);
// isEvalSupported:false is set as well, belt and braces.
import * as pdfjs from './node_modules/pdfjs-dist/build/pdf.min.mjs';

const base = new URL('./node_modules/pdfjs-dist/', import.meta.url).href;
pdfjs.GlobalWorkerOptions.workerSrc = base + 'build/pdf.worker.min.mjs';

// Rendering every page of a huge PDF would take a long time and a lot of
// memory for something shown for seconds - stop after this many.
const MAX_PAGES = 30;

window.KioskPdf = {
  // Render `bytes` into `container` (emptied first), sized for a screen of
  // width x height: a one-page PDF fits entirely (like an image); a longer
  // one fits the width, pages stacked, for the slideshow to scroll.
  async render(bytes, container, width, height) {
    container.innerHTML = '';
    const task = pdfjs.getDocument({
      // A copy: pdf.js transfers (empties) the buffer it's given, and the
      // slideshow caches these bytes to show the PDF again next round.
      data: bytes.slice(),
      isEvalSupported: false,
      cMapUrl: base + 'cmaps/',
      cMapPacked: true,
      standardFontDataUrl: base + 'standard_fonts/',
    });
    try {
      const doc = await task.promise;
      const count = Math.min(doc.numPages, MAX_PAGES);
      const single = doc.numPages === 1;
      const gap = 16;
      container.style.display = 'flex';
      container.style.flexDirection = 'column';
      container.style.alignItems = 'center';
      container.style.gap = gap + 'px';
      container.style.padding = (single ? 0 : gap) + 'px 0';
      container.style.minHeight = single ? '100%' : '';
      container.style.justifyContent = single ? 'center' : '';
      const dpr = window.devicePixelRatio || 1;
      for (let n = 1; n <= count; n++) {
        const page = await doc.getPage(n);
        const natural = page.getViewport({ scale: 1 });
        const scale = single
          ? Math.min(width / natural.width, height / natural.height)
          : Math.min((width - 2 * gap) / natural.width, 1.6 * (96 / 72));
        const vp = page.getViewport({ scale: scale * dpr });
        const canvas = document.createElement('canvas');
        canvas.width = Math.floor(vp.width);
        canvas.height = Math.floor(vp.height);
        canvas.style.width = Math.floor(vp.width / dpr) + 'px';
        canvas.style.height = Math.floor(vp.height / dpr) + 'px';
        canvas.style.background = '#fff';
        canvas.style.boxShadow = single ? '' : '0 2px 8px rgba(0,0,0,.4)';
        container.appendChild(canvas);
        await page.render({ canvasContext: canvas.getContext('2d'), viewport: vp }).promise;
        page.cleanup();
      }
      return { pages: doc.numPages, rendered: count };
    } finally {
      // Frees the document and its worker-side data (pdf.js 6 has this on
      // the loading task, not the document).
      task.destroy();
    }
  },
};
