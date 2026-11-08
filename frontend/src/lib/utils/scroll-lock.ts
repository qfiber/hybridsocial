// Stop the page scrolling behind a modal, sheet or lightbox.
//
// The lock goes on <html>, not <body>: app.css sets `overflow-x: clip` on the
// root, so a body `overflow` is no longer propagated to the viewport and
// `body { overflow: hidden }` leaves the page scrolling underneath on touch.
// Locks are reference-counted so nested overlays (a modal opened from the
// lightbox, say) don't release each other's lock early. On desktop the
// scrollbar's gutter is kept (`scrollbar-gutter: stable`) so hiding it
// doesn't shift the layout sideways; overlay scrollbars on phones have no
// gutter, so nothing changes there.

let count = 0;
let saved: { overflow: string; gutter: string } | null = null;

export function lockScroll(): () => void {
  if (typeof document === 'undefined') return () => {};
  const root = document.documentElement;
  if (count === 0) {
    saved = { overflow: root.style.overflow, gutter: root.style.scrollbarGutter };
    if (window.innerWidth - root.clientWidth > 0) root.style.scrollbarGutter = 'stable';
    root.style.overflow = 'hidden';
  }
  count++;

  let released = false;
  return () => {
    if (released) return;
    released = true;
    count = Math.max(0, count - 1);
    if (count === 0 && saved) {
      root.style.overflow = saved.overflow;
      root.style.scrollbarGutter = saved.gutter;
      saved = null;
    }
  };
}
