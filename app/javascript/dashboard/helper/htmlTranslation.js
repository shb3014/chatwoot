const SEGMENT_DELIMITER = '\n<<<SEG>>>\n';

/**
 * Tags whose text content should be skipped during extraction
 * (code, scripts, styles, etc.)
 */
const SKIP_TAGS = new Set([
  'SCRIPT',
  'STYLE',
  'CODE',
  'PRE',
  'SVG',
  'MATH',
  'NOSCRIPT',
]);

/**
 * Parse HTML string into a document body using DOMParser.
 * @param {string} html
 * @returns {Document}
 */
function parseHtml(html) {
  const parser = new DOMParser();
  return parser.parseFromString(html, 'text/html');
}

/**
 * Determine whether a text node should be included in the translation.
 * Skips whitespace-only nodes and nodes inside skip-listed tags.
 * @param {Text} node
 * @returns {boolean}
 */
function isTranslatableTextNode(node) {
  if (!node.textContent.trim()) return false;
  let parent = node.parentElement;
  while (parent) {
    if (SKIP_TAGS.has(parent.tagName)) return false;
    parent = parent.parentElement;
  }
  return true;
}

/**
 * Walk the DOM tree and collect all translatable text segments in document
 * order. The order is deterministic so the same walk can be repeated for
 * replacement.
 *
 * @param {string} html - Raw HTML string
 * @returns {{ segments: string[], joinedText: string }}
 */
export function extractTextSegments(html) {
  const doc = parseHtml(html);
  const walker = doc.createTreeWalker(doc.body, NodeFilter.SHOW_TEXT, {
    acceptNode: node =>
      isTranslatableTextNode(node)
        ? NodeFilter.FILTER_ACCEPT
        : NodeFilter.FILTER_REJECT,
  });

  const segments = [];
  while (walker.nextNode()) {
    segments.push(walker.currentNode.textContent);
  }

  return {
    segments,
    joinedText: segments.join(SEGMENT_DELIMITER),
  };
}

/**
 * Replace text nodes in the original HTML with translated segments.
 *
 * Walks the DOM tree in exactly the same order as `extractTextSegments` and
 * swaps each text node's content with the corresponding translated segment.
 * If the segment count doesn't match, returns `null` so the caller can fall
 * back gracefully.
 *
 * @param {string} html - Original HTML string
 * @param {string[]} translatedSegments - Translated text segments (same order)
 * @returns {string|null} - Translated HTML string, or null on mismatch
 */
export function replaceTextInHtml(html, translatedSegments) {
  const doc = parseHtml(html);
  const walker = doc.createTreeWalker(doc.body, NodeFilter.SHOW_TEXT, {
    acceptNode: node =>
      isTranslatableTextNode(node)
        ? NodeFilter.FILTER_ACCEPT
        : NodeFilter.FILTER_REJECT,
  });

  let idx = 0;
  while (walker.nextNode()) {
    if (idx >= translatedSegments.length) return null;
    walker.currentNode.textContent = translatedSegments[idx];
    idx += 1;
  }

  // Segment count mismatch — graceful degradation
  if (idx !== translatedSegments.length) return null;

  return doc.body.innerHTML;
}

/**
 * Split a translated response back into segments using the delimiter.
 * @param {string} translatedText
 * @returns {string[]}
 */
export function splitTranslatedSegments(translatedText) {
  return translatedText.split(SEGMENT_DELIMITER);
}

export { SEGMENT_DELIMITER };
