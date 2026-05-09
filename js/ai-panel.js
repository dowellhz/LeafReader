const AIPanel = (() => {
  const PANEL = document.getElementById('ai-panel');
  const BTN_OPEN = document.getElementById('btn-ai-panel');
  const BTN_CLOSE = document.getElementById('btn-close-panel');
  const SELECTED_TEXT_EL = document.getElementById('ai-selected-text');
  const VOCABULARY_EL = document.getElementById('ai-vocabulary');
  const USAGE_EL = document.getElementById('ai-usage');
  const CONTEXT_EL = document.getElementById('ai-context');

  const DEEPSEEK_KEY = 'sk-032fd3d2e84243d485227417d7836e31';
  const DEEPSEEK_URL = 'https://api.deepseek.com/chat/completions';

  let isOpen = false;

  function open(text) {
    if (!text || !text.trim()) return;

    isOpen = true;
    PANEL.classList.remove('hidden');
    document.body.classList.add('ai-panel-open');

    analyze(text);
  }

  function close() {
    isOpen = false;
    PANEL.classList.add('hidden');
    document.body.classList.remove('ai-panel-open');
  }

  async function analyze(text) {
    SELECTED_TEXT_EL.textContent = text;
    USAGE_EL.innerHTML = '<div class="loading">AI is analyzing...</div>';
    CONTEXT_EL.innerHTML = '';

    try {
      const response = await fetch(DEEPSEEK_URL, {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          'Authorization': `Bearer ${DEEPSEEK_KEY}`
        },
        body: JSON.stringify({
          model: 'deepseek-chat',
          messages: [
            {
              role: 'system',
              content: '你是一个英语学习软件的AI助手。用户选中了一段英文文本，请你帮助分析。用中文回复，格式清晰易读。'
            },
            {
              role: 'user',
              content: `请分析以下英文文本：

"${text}"

请按以下结构回复：

【整句解释】
先用中文翻译整句，再解释句子的意思、使用的语法结构、语境。

【重点词汇】
只列出句子中的中高级难度词汇（C1/C2级别）和重要短语搭配。跳过基础词汇（如 the, is, have, go, make, good, big 等 A1-B2 级别单词）。每个词汇给出：
- 词性、中文释义
- 1-2个例句（附中文翻译）
- 相关搭配或用法说明`
            }
          ],
          temperature: 0.5,
          max_tokens: 2048
        })
      });

      if (!response.ok) {
        throw new Error(`API error: ${response.status}`);
      }

      const data = await response.json();
      const content = data.choices[0].message.content;

      renderResponse(content);
    } catch (err) {
      console.error('DeepSeek API error:', err);
      CONTEXT_EL.innerHTML = `<div style="color:#e88">API error: ${err.message}</div>`;
      USAGE_EL.innerHTML = '';
    }
  }

  function renderResponse(content) {
    const sentenceMatch = content.match(/【整句解释】([\s\S]*?)(?=【重点词汇】|$)/);
    const vocabMatch = content.match(/【重点词汇】([\s\S]*?)$/);

    if (sentenceMatch) {
      CONTEXT_EL.innerHTML = formatContent(sentenceMatch[1].trim());
    } else {
      CONTEXT_EL.innerHTML = formatContent(content);
    }

    if (vocabMatch) {
      USAGE_EL.innerHTML = formatContent(vocabMatch[1].trim());
    } else {
      USAGE_EL.innerHTML = '';
    }
  }

  function formatContent(text) {
    return text
      .replace(/&/g, '&amp;')
      .replace(/</g, '&lt;')
      .replace(/>/g, '&gt;')
      .replace(/\n/g, '<br>')
      .replace(/\*\*(.+?)\*\*/g, '<strong>$1</strong>')
      .replace(/### (.+)/g, '<h4>$1</h4>');
  }

  function init() {
    BTN_CLOSE.addEventListener('click', close);
    BTN_OPEN.addEventListener('click', () => {
      if (!isOpen) {
        const text = TextSelect ? TextSelect.getSelectedText() : '';
        open(text || 'No text selected. Select text in the PDF and click "AI Analyze".');
      }
    });
  }

  return { init, open, close, analyze };
})();
