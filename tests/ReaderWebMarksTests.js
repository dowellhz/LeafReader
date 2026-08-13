'use strict';

const assert = require('assert');
const { makeMarksAPI } = require('../mac-app/Resources/reader-web-marks.js');

class HighlightStub {
  constructor(...ranges) {
    this.ranges = ranges;
  }
}

const highlights = new Map();
global.CSS = { highlights, escape: (value) => String(value) };
global.Highlight = HighlightStub;
global.window = { CSS: global.CSS, Highlight: HighlightStub };

const blocks = Array.from({ length: 80 }, (_, blockIndex) => {
  const records = Array.from({ length: 5 }, (_, itemIndex) => {
    const recordIndex = (blockIndex * 5) + itemIndex;
    return `context ${recordIndex} contains word${recordIndex}`;
  });
  return { innerText: records.join(' ') };
});

global.document = {
  body: { querySelectorAll: () => blocks },
  querySelectorAll: () => []
};

let normalizationCount = 0;
let legacyFallbackCount = 0;
const normalizedText = (value) => {
  normalizationCount += 1;
  return String(value || '').toLowerCase().replace(/\s+/g, ' ').trim();
};
const rangeForWordInContext = (block, word, context) => {
  const source = String(block.innerText || '').toLowerCase();
  return source.includes(String(word).toLowerCase()) && source.includes(String(context).toLowerCase())
    ? { block, word, context }
    : null;
};

const marks = makeMarksAPI({
  installReaderOverlayStyle() {},
  normalizedText,
  wrapRangeTextNodes() { return false; },
  findTextRange() {
    legacyFallbackCount += 1;
    return null;
  },
  rangeForWordInContext,
  rangeForNormalizedText() { return null; },
  unwrapSpans() { return 0; },
  invalidateTextIndex() {}
});

const records = Array.from({ length: 400 }, (_, index) => ({
  id: `record-${index}`,
  word: `word${index}`,
  context: `context ${index} contains word${index}`,
  occurrenceIndex: 0
}));

const result = marks.restoreWordHighlights(records);
assert.strictEqual(result.strategy, 'batch-custom-highlight');
assert.strictEqual(result.records, 400);
assert.strictEqual(result.ranges, 400);
assert.strictEqual(result.blocks, 80);
assert.strictEqual(result.fallbacks, 0);
assert.strictEqual(legacyFallbackCount, 0);
assert(normalizationCount <= blocks.length + (records.length * 2) + 5);
assert.strictEqual(highlights.get('leaf-reader-linked-word').ranges.length, 400);

normalizationCount = 0;
const noteResult = marks.restoreNoteHighlights(records.map((record) => ({
  id: `note-${record.id}`,
  selectedText: record.word,
  context: record.context,
  occurrenceIndex: record.occurrenceIndex
})));
assert.strictEqual(noteResult.ranges, 400);
assert(normalizationCount <= (records.length * 2) + 5);

normalizationCount = 0;
const aiResult = marks.restoreAISourceUnderlines(records.map((record) => ({
  key: `ai-${record.id}`,
  selectedText: record.word,
  context: record.context,
  occurrenceIndex: record.occurrenceIndex
})));
assert.strictEqual(aiResult.ranges, 400);
assert(normalizationCount <= (records.length * 2) + 5);

const customHighlightWindow = global.window;
global.window = {};
let wrappedLegacyRanges = 0;
const legacyMarks = makeMarksAPI({
  installReaderOverlayStyle() {},
  normalizedText,
  wrapRangeTextNodes() {
    wrappedLegacyRanges += 1;
    return true;
  },
  findTextRange() { return {}; },
  rangeForWordInContext,
  rangeForNormalizedText() { return null; },
  unwrapSpans() { return 0; },
  invalidateTextIndex() {}
});
const legacyResult = legacyMarks.restoreWordHighlights([records[0]]);
assert.strictEqual(legacyResult.strategy, 'legacy-dom');
assert.strictEqual(legacyResult.ranges, 1);
assert.strictEqual(wrappedLegacyRanges, 1);
global.window = customHighlightWindow;

console.log('Reader web marks tests passed');
