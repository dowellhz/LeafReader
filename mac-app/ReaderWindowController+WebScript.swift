import Foundation

extension ReaderWindowController {
    static let webDocumentUserScriptSource = """
            (() => {
              var lastScrollSent = 0;
              var preservedHighlightRange = null;
              var documentMouseDown = false;
              const installSelectionHighlightStyle = () => {
                if (document.getElementById('leaf-reader-selection-highlight-style')) return;
                const style = document.createElement('style');
                style.id = 'leaf-reader-selection-highlight-style';
                style.textContent = `
                  ::highlight(leaf-reader-selection) { background: rgba(255, 221, 87, .62); color: inherit; }
                  ::highlight(leaf-reader-ai-source) { text-decoration-line: underline; text-decoration-color: rgba(0, 122, 255, .72); text-decoration-thickness: 1.5px; text-underline-offset: .16em; }
                  .leaf-reader-selection-highlight { background: rgba(255, 221, 87, .62); color: inherit; }
                  .leaf-reader-ai-source-underline { text-decoration-line: underline; text-decoration-color: rgba(0, 122, 255, .72); text-decoration-thickness: 1.5px; text-underline-offset: .16em; }
                  .leaf-reader-linked-word { background: rgba(255, 221, 87, .62); border-radius: 3px; cursor: pointer; }
                  ::highlight(leaf-reader-search) { background: rgba(255, 221, 87, .52); color: inherit; }
                  ::highlight(leaf-reader-search-current) { background: rgba(255, 149, 0, .72); color: inherit; }
                `;
                document.head.appendChild(style);
              };
              const normalizedText = (value) => String(value || '').replace(/\\s+/g, ' ').trim().toLowerCase();
              const occurrenceIndexInText = (source, selected, before) => {
                const normalizedSelected = normalizedText(selected);
                const normalizedBefore = normalizedText(before);
                if (!normalizedSelected || !normalizedBefore) return 0;
                let count = 0;
                let index = normalizedBefore.indexOf(normalizedSelected);
                while (index >= 0) {
                  count += 1;
                  index = normalizedBefore.indexOf(normalizedSelected, index + Math.max(1, normalizedSelected.length));
                }
                return count;
              };
              let leafReaderSearchQuery = '';
              let leafReaderSearchIndex = -1;
              let leafReaderSearchRanges = [];
              const unwrapSpans = (selector) => {
                document.querySelectorAll(selector).forEach((span) => {
                  const parent = span.parentNode;
                  if (!parent) return;
                  while (span.firstChild) parent.insertBefore(span.firstChild, span);
                  parent.removeChild(span);
                  parent.normalize();
                });
              };
              window.leafReaderClearSearchHighlights = () => {
                leafReaderSearchRanges = [];
                if (window.CSS && CSS.highlights) {
                  CSS.highlights.delete('leaf-reader-search');
                  CSS.highlights.delete('leaf-reader-search-current');
                }
                leafReaderSearchQuery = '';
                leafReaderSearchIndex = -1;
              };
              const leafReaderFindSearchRanges = (query) => {
                const needle = String(query || '').toLowerCase();
                if (!needle) return [];
                const walker = document.createTreeWalker(document.body, NodeFilter.SHOW_TEXT, {
                  acceptNode(node) {
                    const parent = node.parentElement;
                    if (!parent || parent.closest('script,style,noscript')) return NodeFilter.FILTER_REJECT;
                    if (!(node.nodeValue || '').toLowerCase().includes(needle)) return NodeFilter.FILTER_SKIP;
                    return NodeFilter.FILTER_ACCEPT;
                  }
                });
                const matches = [];
                let node;
                while ((node = walker.nextNode())) {
                  const value = node.nodeValue || '';
                  const lower = value.toLowerCase();
                  let index = lower.indexOf(needle);
                  while (index >= 0) {
                    matches.push({ node, start: index, end: index + needle.length });
                    index = lower.indexOf(needle, index + Math.max(1, needle.length));
                  }
                }
                return matches.map((match) => {
                  const range = document.createRange();
                  range.setStart(match.node, match.start);
                  range.setEnd(match.node, match.end);
                  return range;
                });
              };
              const leafReaderApplySearchHighlights = () => {
                if (!(window.CSS && CSS.highlights && window.Highlight)) return false;
                if (leafReaderSearchRanges.length > 0) {
                  CSS.highlights.set('leaf-reader-search', new Highlight(...leafReaderSearchRanges));
                } else {
                  CSS.highlights.delete('leaf-reader-search');
                }
                const current = leafReaderSearchRanges[leafReaderSearchIndex];
                if (current) {
                  CSS.highlights.set('leaf-reader-search-current', new Highlight(current));
                } else {
                  CSS.highlights.delete('leaf-reader-search-current');
                }
                return true;
              };
              window.leafReaderSearch = (query, direction, reset) => {
                installSelectionHighlightStyle();
                if (!(window.CSS && CSS.highlights && window.Highlight)) {
                  const found = window.find(String(query || ''), false, direction < 0, true, false, true, false);
                  return { index: found ? 1 : 0, total: found ? 1 : 0 };
                }
                const normalizedQuery = String(query || '').trim();
                if (!normalizedQuery) {
                  window.leafReaderClearSearchHighlights();
                  return { index: 0, total: 0 };
                }
                if (reset || normalizedQuery !== leafReaderSearchQuery) {
                  leafReaderSearchQuery = normalizedQuery;
                  leafReaderSearchIndex = -1;
                  leafReaderSearchRanges = leafReaderFindSearchRanges(normalizedQuery);
                }
                const total = leafReaderSearchRanges.length;
                if (!total) return { index: 0, total: 0 };
                leafReaderSearchIndex = (leafReaderSearchIndex + (direction < 0 ? -1 : 1) + total) % total;
                leafReaderApplySearchHighlights();
                const current = leafReaderSearchRanges[leafReaderSearchIndex];
                const rect = current.getBoundingClientRect();
                window.scrollBy({ top: rect.top - (window.innerHeight * 0.35), behavior: 'smooth' });
                return { index: leafReaderSearchIndex + 1, total };
              };
              const normalizedIndexForRoot = (root) => {
                const walker = document.createTreeWalker(root, NodeFilter.SHOW_TEXT);
                const positions = [];
                let normalized = '';
                let previousWasSpace = true;
                let node;
                while ((node = walker.nextNode())) {
                  const raw = node.nodeValue || '';
                  for (let i = 0; i < raw.length; i++) {
                    const char = raw[i];
                    if (/\\s/.test(char)) {
                      if (!previousWasSpace) {
                        normalized += ' ';
                        positions.push({ node, offset: i });
                        previousWasSpace = true;
                      }
                    } else {
                      normalized += char.toLowerCase();
                      positions.push({ node, offset: i });
                      previousWasSpace = false;
                    }
                  }
                }
                const leadingSpaces = normalized.length - normalized.trimStart().length;
                return { text: normalized.trim(), positions, leadingSpaces };
              };
              const rangeFromNormalizedSpan = (index, startIndex, length) => {
                const start = index.positions[index.leadingSpaces + startIndex];
                const end = index.positions[index.leadingSpaces + startIndex + length - 1];
                if (!start || !end) return null;
                const range = document.createRange();
                range.setStart(start.node, start.offset);
                range.setEnd(end.node, end.offset + 1);
                return range;
              };
              const rangeForNormalizedText = (root, target, occurrenceIndex = 0) => {
                const normalizedTarget = normalizedText(target);
                if (!root || !normalizedTarget) return null;
                const index = normalizedIndexForRoot(root);
                const trimmed = index.text;
                let matchIndex = -1;
                let searchFrom = 0;
                const targetOccurrence = Math.max(0, Number(occurrenceIndex || 0));
                for (let seen = 0; seen <= targetOccurrence; seen++) {
                  matchIndex = trimmed.indexOf(normalizedTarget, searchFrom);
                  if (matchIndex < 0) break;
                  searchFrom = matchIndex + Math.max(1, normalizedTarget.length);
                }
                if (matchIndex < 0) return null;
                return rangeFromNormalizedSpan(index, matchIndex, normalizedTarget.length);
              };
              const rangeForWordInContext = (root, word, context, occurrenceIndex = 0) => {
                const normalizedWord = normalizedText(word);
                const normalizedContext = normalizedText(context);
                if (!root || !normalizedWord || !normalizedContext) return null;
                const index = normalizedIndexForRoot(root);
                const source = index.text;
                const contextNeedle = normalizedContext.slice(0, Math.min(160, normalizedContext.length));
                const contextIndex = source.indexOf(contextNeedle);
                if (contextIndex < 0) return null;
                const contextEnd = Math.min(source.length, contextIndex + normalizedContext.length);
                const contextSource = source.slice(contextIndex, contextEnd);
                let wordIndexInContext = contextSource.indexOf(normalizedWord);
                if (wordIndexInContext < 0) {
                  wordIndexInContext = source.indexOf(normalizedWord, contextIndex);
                  if (wordIndexInContext < 0 || wordIndexInContext >= contextEnd) return null;
                  return rangeFromNormalizedSpan(index, wordIndexInContext, normalizedWord.length);
                }
                return rangeFromNormalizedSpan(index, contextIndex + wordIndexInContext, normalizedWord.length);
              };
              window.leafReaderFindTextRange = (word, context, occurrenceIndex = 0) => {
                const normalizedWord = normalizedText(word);
                const normalizedContext = normalizedText(context);
                if (!normalizedWord) return null;
                const blocks = Array.from(document.body.querySelectorAll('p,li,blockquote,pre,td,th,h1,h2,h3,h4,h5,h6,div'));
                for (const block of blocks) {
                  const source = normalizedText(block.innerText || block.textContent || '');
                  if (normalizedContext && !source.includes(normalizedContext.slice(0, Math.min(120, normalizedContext.length)))) continue;
                  if (!source.includes(normalizedWord)) continue;
                  const range = normalizedContext
                    ? (rangeForWordInContext(block, normalizedWord, normalizedContext, occurrenceIndex) || rangeForNormalizedText(block, normalizedWord, occurrenceIndex))
                    : rangeForNormalizedText(block, normalizedWord, occurrenceIndex);
                  if (range) return range;
                }
                const walker = document.createTreeWalker(document.body, NodeFilter.SHOW_TEXT);
                let node;
                while ((node = walker.nextNode())) {
                  const value = node.nodeValue || '';
                  const lower = value.toLowerCase();
                  let index = lower.indexOf(normalizedWord);
                  while (index >= 0) {
                    const block = node.parentElement?.closest('p,li,blockquote,pre,td,th,h1,h2,h3,h4,h5,h6,div');
                    const source = (block ? (block.innerText || block.textContent || '') : value).replace(/\\s+/g, ' ').trim().toLowerCase();
                    if (!normalizedContext || source.includes(normalizedContext.slice(0, Math.min(80, normalizedContext.length)))) {
                      if (occurrenceIndex > 0) {
                        occurrenceIndex -= 1;
                        index = lower.indexOf(normalizedWord, index + normalizedWord.length);
                        continue;
                      }
                      const range = document.createRange();
                      range.setStart(node, index);
                      range.setEnd(node, index + normalizedWord.length);
                      return range;
                    }
                    index = lower.indexOf(normalizedWord, index + normalizedWord.length);
                  }
                }
                return null;
              };
              const wrapRangeTextNodes = (range, className, configureSpan = null) => {
                const walker = document.createTreeWalker(range.commonAncestorContainer, NodeFilter.SHOW_TEXT);
                const targets = [];
                let node;
                while ((node = walker.nextNode())) {
                  if (!range.intersectsNode(node)) continue;
                  let start = node === range.startContainer ? range.startOffset : 0;
                  let end = node === range.endContainer ? range.endOffset : (node.nodeValue || '').length;
                  if (end <= start) continue;
                  if (!(node.nodeValue || '').slice(start, end).trim()) continue;
                  targets.push({ node, start, end });
                }
                if (range.startContainer.nodeType === Node.TEXT_NODE && !targets.some((target) => target.node === range.startContainer)) {
                  const node = range.startContainer;
                  const end = node === range.endContainer ? range.endOffset : (node.nodeValue || '').length;
                  if (end > range.startOffset) targets.push({ node, start: range.startOffset, end });
                }
                for (const target of targets.reverse()) {
                  const textNode = target.node;
                  let middle = textNode;
                  if (target.end < middle.nodeValue.length) middle.splitText(target.end);
                  if (target.start > 0) middle = middle.splitText(target.start);
                  const span = document.createElement('span');
                  span.className = className;
                  if (configureSpan) configureSpan(span);
                  middle.parentNode.insertBefore(span, middle);
                  span.appendChild(middle);
                }
                return targets.length > 0;
              };
              window.leafReaderClearAISourceUnderlines = () => {
                if (window.CSS && CSS.highlights) CSS.highlights.delete('leaf-reader-ai-source');
                document.querySelectorAll('span.leaf-reader-ai-source-underline').forEach((span) => {
                  const parent = span.parentNode;
                  if (!parent) return;
                  while (span.firstChild) parent.insertBefore(span.firstChild, span);
                  parent.removeChild(span);
                  parent.normalize();
                });
              };
              window.leafReaderAddAISourceUnderlineForSelection = (key) => {
                const selection = window.getSelection();
                const text = String(selection || '').trim();
                if (!selection || selection.rangeCount === 0 || text.length === 0) return false;
                installSelectionHighlightStyle();
                const range = selection.getRangeAt(0).cloneRange();
                return wrapRangeTextNodes(range, 'leaf-reader-ai-source-underline', (span) => {
                  span.dataset.leafAiSourceKey = String(key || '');
                });
              };
              window.leafReaderRestoreAISourceUnderlines = (sources) => {
                window.leafReaderClearAISourceUnderlines();
                installSelectionHighlightStyle();
                for (const source of sources || []) {
                  const text = normalizedText(source.selectedText || '');
                  if (!text) continue;
                  const range = window.leafReaderFindTextRange(text, source.context || '', source.occurrenceIndex || 0);
                  if (!range) continue;
                  wrapRangeTextNodes(range, 'leaf-reader-ai-source-underline', (span) => {
                    span.dataset.leafAiSourceKey = String(source.key || '');
                  });
                }
              };
              window.leafReaderRestoreWordHighlights = (records) => {
                installSelectionHighlightStyle();
                document.querySelectorAll('span.leaf-reader-linked-word').forEach((span) => {
                  const parent = span.parentNode;
                  if (!parent) return;
                  while (span.firstChild) parent.insertBefore(span.firstChild, span);
                  parent.removeChild(span);
                  parent.normalize();
                });
                for (const record of records || []) {
                  try {
                    const range = window.leafReaderFindTextRange(record.word, record.context, record.occurrenceIndex || 0);
                    if (!range) continue;
                    wrapRangeTextNodes(range, 'leaf-reader-linked-word', (span) => {
                      span.dataset.leafWordId = record.id;
                    });
                  } catch (_) {}
                }
              };
              window.leafReaderMarkSelectionAsWord = (id) => {
                const selection = window.getSelection();
                const text = String(selection || '').trim();
                if (!selection || selection.rangeCount === 0 || !text || !id) return false;
                installSelectionHighlightStyle();
                const range = selection.getRangeAt(0).cloneRange();
                const didWrap = wrapRangeTextNodes(range, 'leaf-reader-linked-word', (span) => {
                  span.dataset.leafWordId = String(id);
                });
                selection.removeAllRanges();
                return didWrap;
              };
              window.leafReaderRemoveWordHighlight = (id) => {
                const selector = `span.leaf-reader-linked-word[data-leaf-word-id="${CSS.escape(String(id || ''))}"]`;
                document.querySelectorAll(selector).forEach((span) => {
                  const parent = span.parentNode;
                  if (!parent) return;
                  while (span.firstChild) parent.insertBefore(span.firstChild, span);
                  parent.removeChild(span);
                  parent.normalize();
                });
              };
              window.leafReaderScrollToWord = (id, fallbackProgress) => {
                const target = document.querySelector(`span.leaf-reader-linked-word[data-leaf-word-id="${CSS.escape(String(id || ''))}"]`);
                if (target) {
                  target.scrollIntoView({ behavior: 'smooth', block: 'center' });
                  return true;
                }
                const height = Math.max(1, document.documentElement.scrollHeight - window.innerHeight);
                window.scrollTo({ top: height * Math.max(0, Math.min(1, Number(fallbackProgress || 0))), behavior: 'smooth' });
                return false;
              };
              const clearSpanHighlights = () => {
                document.querySelectorAll('span.leaf-reader-selection-highlight').forEach((span) => {
                  const parent = span.parentNode;
                  if (!parent) return;
                  while (span.firstChild) parent.insertBefore(span.firstChild, span);
                  parent.removeChild(span);
                  parent.normalize();
                });
              };
              const clearPreservedSelectionHighlight = () => {
                preservedHighlightRange = null;
                if (window.CSS && CSS.highlights) CSS.highlights.delete('leaf-reader-selection');
                clearSpanHighlights();
              };
              window.leafReaderClearSelection = () => {
                clearPreservedSelectionHighlight();
                const selection = window.getSelection();
                if (selection) selection.removeAllRanges();
                window.webkit.messageHandlers.selectionChanged.postMessage({ text: "", context: "" });
              };
              window.leafReaderClearSelectionVisualOnly = () => {
                clearPreservedSelectionHighlight();
                const selection = window.getSelection();
                if (selection) selection.removeAllRanges();
              };
              const preserveSelectionHighlight = (selection) => {
                if (!selection || selection.rangeCount === 0 || String(selection || "").trim().length === 0) return;
                installSelectionHighlightStyle();
                clearPreservedSelectionHighlight();
                const range = selection.getRangeAt(0).cloneRange();
                preservedHighlightRange = range;
                if (window.CSS && CSS.highlights && window.Highlight) {
                  CSS.highlights.set('leaf-reader-selection', new Highlight(range));
                  return;
                }
                try {
                  const span = document.createElement('span');
                  span.className = 'leaf-reader-selection-highlight';
                  range.surroundContents(span);
                } catch (_) {
                  // Complex cross-node EPUB selections still keep their text context in native selection.
                }
              };
              const sendSelection = () => {
                const selection = window.getSelection();
                const text = String(selection || "").trim();
                let context = "";
                if (selection && selection.rangeCount > 0 && text.length > 0) {
                  preserveSelectionHighlight(selection);
                  const container = selection.getRangeAt(0).commonAncestorContainer;
                  const element = container.nodeType === Node.ELEMENT_NODE ? container : container.parentElement;
                  const block = element ? element.closest('p,li,blockquote,pre,td,th,h1,h2,h3,h4,h5,h6,div') : null;
                  const source = block ? (block.innerText || block.textContent || "") : text;
                  context = source.replace(/\\s+/g, " ").trim().slice(0, 360);
                  let occurrenceIndex = 0;
                  if (block) {
                    try {
                      const beforeRange = document.createRange();
                      beforeRange.selectNodeContents(block);
                      beforeRange.setEnd(selection.getRangeAt(0).startContainer, selection.getRangeAt(0).startOffset);
                      occurrenceIndex = occurrenceIndexInText(source, text, beforeRange.toString());
                    } catch (_) {}
                  }
                  window.webkit.messageHandlers.selectionChanged.postMessage({ text, context, occurrenceIndex });
                  documentMouseDown = false;
                  return;
                } else if (documentMouseDown) {
                  clearPreservedSelectionHighlight();
                }
                window.webkit.messageHandlers.selectionChanged.postMessage({ text, context, occurrenceIndex: null });
                documentMouseDown = false;
              };
              const sendScroll = (force = false) => {
                const now = Date.now();
                if (!force && now - lastScrollSent < 200) return;
                lastScrollSent = now;
                const height = Math.max(1, document.documentElement.scrollHeight - window.innerHeight);
                const progress = Math.max(0, Math.min(1, window.scrollY / height));
                window.webkit.messageHandlers.scrollChanged.postMessage(progress);
              };
              window.leafReaderJumpToHref = (href) => {
                href = String(href || '');
                const fragment = href.includes('#') ? href.split('#').pop() : (href.startsWith('#') ? href.slice(1) : '');
                const path = href.split('#')[0];
                const sections = Array.from(document.querySelectorAll('section.reader-section[data-leaf-href]'));
                const matchingSection = path ? sections.find((section) => {
                  const value = section.dataset.leafHref || '';
                  return value === path || value.endsWith('/' + path) || path.endsWith('/' + value);
                }) : null;
                if (fragment) {
                  const target = matchingSection
                    ? (window.CSS && CSS.escape
                      ? matchingSection.querySelector(`#${CSS.escape(fragment)}`)
                      : Array.from(matchingSection.querySelectorAll('[id]')).find(el => el.id === fragment))
                    : document.getElementById(fragment);
                  if (target) {
                    target.scrollIntoView({ behavior: 'smooth', block: 'start' });
                    return true;
                  }
                }
                if (matchingSection) {
                  matchingSection.scrollIntoView({ behavior: 'smooth', block: 'start' });
                  return true;
                }
                return false;
              };
              document.addEventListener("mousedown", () => {
                documentMouseDown = true;
                clearPreservedSelectionHighlight();
                const selection = window.getSelection();
                if (selection) selection.removeAllRanges();
                window.webkit.messageHandlers.selectionChanged.postMessage({ text: "", context: "" });
              });
              document.addEventListener("click", (event) => {
                const aiSource = event.target?.closest?.('span.leaf-reader-ai-source-underline');
                if (aiSource) {
                  event.preventDefault();
                  event.stopPropagation();
                  window.webkit.messageHandlers.webAISourceClicked.postMessage(String(aiSource.dataset.leafAiSourceKey || ''));
                  return;
                }
                const link = event.target?.closest?.('a[data-leaf-href]');
                if (link) {
                  event.preventDefault();
                  event.stopPropagation();
                  window.leafReaderJumpToHref(link.dataset.leafHref || '');
                  return;
                }
                const target = event.target?.closest?.('span.leaf-reader-linked-word');
                if (!target) return;
                event.preventDefault();
                event.stopPropagation();
                window.webkit.messageHandlers.webWordClicked.postMessage(String(target.dataset.leafWordId || ''));
              }, true);
              document.addEventListener("selectionchange", () => setTimeout(sendSelection, 0));
              document.addEventListener("mouseup", () => {
                sendSelection();
              });
              document.addEventListener("keyup", sendSelection);
              window.addEventListener("scroll", () => sendScroll(false), { passive: true });
              window.addEventListener("load", () => sendScroll(true));
              setTimeout(() => sendScroll(true), 250);
            })();
            """
}
