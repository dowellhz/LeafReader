'use strict';

const assert = require('assert');
const { makeSearchAPI } = require('../mac-app/Resources/reader-web-search.js');

class TestHighlight {
  constructor(...ranges) {
    this.ranges = ranges;
  }

  add(range) {
    this.ranges.push(range);
  }
}

const scheduledTasks = [];
global.setTimeout = (task) => {
  scheduledTasks.push(task);
  return scheduledTasks.length;
};
global.NodeFilter = {
  SHOW_TEXT: 4,
  FILTER_ACCEPT: 1,
  FILTER_REJECT: 2,
  FILTER_SKIP: 3
};

const textNodes = Array.from({ length: 130 }, (_, index) => ({
  nodeValue: `Needle ${index}`,
  parentElement: { closest: () => null }
}));

global.document = {
  body: {},
  createTreeWalker(_body, _kind, filter) {
    const accepted = textNodes.filter((node) => filter.acceptNode(node) === NodeFilter.FILTER_ACCEPT);
    let index = 0;
    return { nextNode: () => accepted[index++] || null };
  },
  createRange() {
    return {
      setStart(node, offset) {
        this.startNode = node;
        this.startOffset = offset;
      },
      setEnd(node, offset) {
        this.endNode = node;
        this.endOffset = offset;
      },
      getBoundingClientRect() {
        return { top: 100 };
      }
    };
  }
};

const highlights = new Map();
global.CSS = { highlights };
global.window = {
  CSS: global.CSS,
  Highlight: TestHighlight,
  innerHeight: 800,
  scrollBy() {},
  find() { return false; }
};
global.Highlight = TestHighlight;

const api = makeSearchAPI({
  installReaderOverlayStyle() {},
  leafReaderFindSearchSpans(value, needle) {
    const start = value.toLowerCase().indexOf(needle);
    return start < 0 ? [] : [{ start, end: start + needle.length }];
  }
});

const firstResult = api.search('Needle', 1, true);
assert.deepStrictEqual(firstResult, { index: 1, total: 130 });
assert.strictEqual(highlights.get('leaf-reader-search').ranges.length, 0, 'all-match highlight should start empty');
assert.strictEqual(highlights.get('leaf-reader-search-current').ranges.length, 1, 'current match should be highlighted immediately');

scheduledTasks.shift()();
assert.strictEqual(highlights.get('leaf-reader-search').ranges.length, 64, 'first batch should contain 64 ranges');
while (scheduledTasks.length) scheduledTasks.shift()();
assert.strictEqual(highlights.get('leaf-reader-search').ranges.length, 130, 'all matches should be highlighted after every batch runs');

api.search('Needle', 1, true);
api.clearSearchHighlights();
while (scheduledTasks.length) scheduledTasks.shift()();
assert.strictEqual(highlights.has('leaf-reader-search'), false, 'clearing should cancel stale highlight batches');
assert.strictEqual(highlights.has('leaf-reader-search-current'), false, 'clearing should remove the current highlight');

console.log('Reader web search tests passed');
