/**
 * One Esc, one thing closed: the most recently opened popover. Each open popover registers its close
 * function; a single document listener calls only the top one (N6).
 */
const stack: (() => void)[] = [];
let bound = false;

function onKey(e: KeyboardEvent) {
  if (e.key !== "Escape" || stack.length === 0) return;
  const close = stack[stack.length - 1];
  e.preventDefault();
  e.stopPropagation();
  close();
}

/** Register `close`; call the returned function when the thing closes by other means. */
export function pushEsc(close: () => void): () => void {
  if (!bound && typeof document !== "undefined") {
    document.addEventListener("keydown", onKey, true);
    bound = true;
  }
  stack.push(close);
  return () => {
    const i = stack.lastIndexOf(close);
    if (i !== -1) stack.splice(i, 1);
  };
}

/** For tests: how many closers are waiting. */
export const escDepth = () => stack.length;
