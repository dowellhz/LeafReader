const assert = require('assert');
const web = require('../mac-app/Resources/reader-web.js');
const tts = require('../mac-app/Resources/reader-web-tts.js');
const selection = require('../mac-app/Resources/reader-web-selection.js');

assert.strictEqual(typeof tts.install, 'function');
assert.strictEqual(typeof selection.install, 'function');

global.NodeFilter = { SHOW_TEXT: 4 };
global.document = {
  createTreeWalker(root) {
    const nodes = root.textNodes || [];
    let index = -1;
    return {
      nextNode() {
        index += 1;
        return nodes[index] || null;
      }
    };
  },
  createRange() {
    return {
      startContainer: null,
      startOffset: 0,
      endContainer: null,
      endOffset: 0,
      setStart(node, offset) {
        this.startContainer = node;
        this.startOffset = offset;
      },
      setEnd(node, offset) {
        this.endContainer = node;
        this.endOffset = offset;
      }
    };
  }
};

const textNode = (value) => ({ nodeValue: value });

assert.strictEqual(web.normalizedText('  Hello\nWORLD\t '), 'hello world');
assert.strictEqual(web.normalizedText('I\u2019ve seen high\u2014bouncing lover\u2026'), "i've seen high-bouncing lover...");
assert.strictEqual(web.occurrenceIndexInText('Alpha beta alpha beta', 'alpha', 'Alpha beta '), 1);
assert.deepStrictEqual(web.leafReaderFindSearchSpans('Alpha beta alpha', 'alpha'), [
  { start: 0, end: 5 },
  { start: 11, end: 16 }
]);

const first = textNode('Duke  Paul\n');
const second = textNode('Atreides returns');
const root = { textNodes: [first, second] };
const normalized = web.normalizedIndexForRoot(root);
assert.strictEqual(normalized.text, 'duke paul atreides returns');

const phraseRange = web.rangeForNormalizedText(root, 'Paul Atreides');
assert.strictEqual(phraseRange.startContainer, first);
assert.strictEqual(phraseRange.startOffset, 6);
assert.strictEqual(phraseRange.endContainer, second);
assert.strictEqual(phraseRange.endOffset, 8);

const wordRange = web.rangeForWordInContext(root, 'Atreides', 'Paul Atreides returns');
assert.strictEqual(wordRange.startContainer, second);
assert.strictEqual(wordRange.startOffset, 0);
assert.strictEqual(wordRange.endContainer, second);
assert.strictEqual(wordRange.endOffset, 8);

const quoteNode = textNode('I\u2019ve had advantages that you\u2019ve had.');
const quoteRange = web.rangeForNormalizedText({ textNodes: [quoteNode] }, "you've had");
assert.strictEqual(quoteRange.startContainer, quoteNode);
assert.strictEqual(quoteRange.startOffset, 25);
assert.strictEqual(quoteRange.endContainer, quoteNode);
assert.strictEqual(quoteRange.endOffset, 35);

assert.deepStrictEqual(
  web.leafReaderSentenceSegments('By F. Scott Fitzgerald\n\nThen wear the gold hat, if that will move her;\nIf you can bounce high, bounce for her too,\nTill she cry \u2018Lover, gold-hatted, high-bouncing lover,\nI must have you!\u2019'),
  [
    'By F. Scott Fitzgerald Then wear the gold hat, if that will move her; If you can bounce high, bounce for her too, Till she cry \u2018Lover, gold-hatted, high-bouncing lover, I must have you!\u2019'
  ]
);

const abbreviationSegments = web.leafReaderSentenceSegments('The careful witnesses described the room, hallway, window, clock, table, shelves, door, floor, ceiling, and Dr. Yueh calmly entered with a sealed note. Another sentence follows after the doctor arrives.');
assert(abbreviationSegments.some((segment) => segment.includes('Dr. Yueh')));
assert(!abbreviationSegments.some((segment) => segment.endsWith('Dr.')));

const quotedSegments = web.leafReaderSentenceSegments('He said, "This quoted sentence contains enough words to make the speech segment flush only after the closing quotation mark arrives." Another narrator sentence follows with enough words to stand apart after the quoted line.');
assert(quotedSegments[0].endsWith('"'));
assert(!quotedSegments.slice(1).some((segment) => segment.startsWith('"')));

const chineseSegments = web.leafReaderSentenceSegments('第一句。第二句！第三句？');
assert.deepStrictEqual(chineseSegments, ['第一句。', '第二句！', '第三句？']);

const longChineseSegments = web.leafReaderSentenceSegments('这是一段很长的中文，'.repeat(20));
assert(longChineseSegments.length > 1);
assert(longChineseSegments.every((segment) => segment.length <= 120));

console.log('ReaderWebScriptTests passed');
