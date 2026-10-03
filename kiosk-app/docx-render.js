// Browser-side .docx rendering shared by docview.html (one document as a
// site) and slideshow.html (documents mixed into a folder slideshow).
// Needs node_modules/jszip and node_modules/docx-preview loaded first.
//
// Each render gets its own class prefix and keeps its generated styles
// inside its own container, so two documents on screen at once (a
// slideshow crossfade) can't restyle each other, and removing the
// container removes its styles.
(() => {
  let counter = 0;

  // Word draws most bullets with private-use characters from the Symbol
  // and Wingdings fonts (U+F0B7 etc.), which a kiosk doesn't have - they
  // render as blanks. docx-preview passes them through into its generated
  // list CSS; swap the common ones for real Unicode equivalents.
  const SYMBOL_BULLETS = {
    '': '•', // Symbol bullet          -> •
    '': '▪', // Wingdings square        -> ▪
    '': '➢', // Wingdings arrowhead     -> ➢
    '': '❖', // Wingdings diamond       -> ❖
    '': '✓', // Wingdings check         -> ✓
    '': '■', // Wingdings black square  -> ■
    '': '❏', // Wingdings box           -> ❏
  };

  function fixSymbolBullets(container) {
    container.querySelectorAll('style').forEach((st) => {
      let css = st.textContent;
      const before = css;
      for (const [from, to] of Object.entries(SYMBOL_BULLETS)) {
        css = css.split(from).join(to);
        // Also the CSS-escaped form ("\f0b7" / "\00f0b7 ").
        const hex = from.charCodeAt(0).toString(16);
        css = css.replace(new RegExp('\\\\0*' + hex + '\\s?', 'gi'), to);
      }
      if (css !== before) st.textContent = css;
    });
  }

  window.KioskDocx = {
    available() {
      return !!(window.docx && window.JSZip);
    },

    base64ToBytes(b64) {
      return Uint8Array.from(atob(b64), (c) => c.charCodeAt(0));
    },

    // Render into `container` (emptied first). Returns the class prefix
    // used, for fit().
    async render(bytes, container) {
      const cls = `kdocx${++counter}`;
      container.innerHTML = '';
      await window.docx.renderAsync(bytes, container, container, {
        className: cls,
        inWrapper: true,
        ignoreLastRenderedPageBreak: true,
        experimental: true,
        useBase64URL: true,
      });
      const wrapper = container.querySelector(`.${cls}-wrapper`);
      if (wrapper) {
        wrapper.style.background = 'transparent';
        wrapper.style.padding = '16px 0';
      }
      container.querySelectorAll(`section.${cls}`).forEach((s) => {
        s.style.marginBottom = '16px';
        s.style.boxShadow = '0 2px 8px rgba(0,0,0,.4)';
      });
      fixSymbolBullets(container);
      return cls;
    },

    // Scale `zoomEl` so the first page fills `width` (capped at maxZoom),
    // so a portrait page is readable on a landscape screen without
    // sideways scrolling. CSS zoom keeps scrolling and touch coordinates
    // consistent.
    fit(zoomEl, cls, width, maxZoom = 1.6) {
      const page = zoomEl.querySelector(`section.${cls}`);
      if (!page) return;
      zoomEl.style.zoom = 1;
      const pageWidth = page.getBoundingClientRect().width + 32;
      zoomEl.style.zoom = Math.min(width / pageWidth, maxZoom);
    },

    // Scale `zoomEl` so the whole first page fits in width x height
    // (letterboxed, like an image) - for one-page documents in a slideshow,
    // where scrolling through the page's empty bottom would be pointless.
    fitPage(zoomEl, cls, width, height) {
      const page = zoomEl.querySelector(`section.${cls}`);
      if (!page) return;
      zoomEl.style.zoom = 1;
      const r = page.getBoundingClientRect();
      zoomEl.style.zoom = Math.min(width / (r.width + 32), height / (r.height + 32));
    },

    // True when the whole document fits on one physical page. Not just
    // "one <section>": docx-preview doesn't paginate by itself - it only
    // starts a new section at an explicit page break - so a long document
    // without breaks is one very tall section. Each section's min-height
    // is the paper height, so content that fits leaves it at that height.
    isSinglePage(zoomEl, cls) {
      const pages = zoomEl.querySelectorAll(`section.${cls}`);
      if (pages.length !== 1) return false;
      const paper = parseFloat(getComputedStyle(pages[0]).minHeight);
      if (!paper) return false;
      return pages[0].getBoundingClientRect().height <= paper * 1.02;
    },
  };
})();
