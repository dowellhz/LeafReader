# AI Chat

The AI panel handles selected text explanations, summaries, translations, follow-up questions, and document-aware prompts.

## Flow

```text
Selection
  -> AIChatPanel
     -> Actions and context
     -> Request lifecycle
        -> AIClient
        -> Streaming deltas
     -> Bubble rendering
     -> Conversation store
```

## Files

- `AIChatPanel.swift`: core panel state and selection entry points.
- `AIChatPanel+UI.swift`: panel layout and controls.
- `AIChatPanel+Actions.swift`: user actions, selected text questions, summary/translation, follow-up context.
- `AIChatPanel+Requests.swift`: request lifecycle, retry/cancel, translation, busy state, error mapping.
- `AIChatPanel+Selection.swift`: mouse interaction monitor and bubble text selection.
- `AIChatPanel+Bubbles.swift`: bubble creation, rendering, layout debounce, scrolling.
- `AIChatPanel+Conversation.swift`: saved conversation restore.
- `AIChatPanel+LinkedWords.swift`: linked vocabulary bubble behavior.
- `AIClient.swift`: HTTP request and streaming client.
- `AIPromptStore.swift` and `mac-app/AIPrompts.json`: built-in prompt templates.

## Performance Notes

- Streaming updates are throttled before re-rendering bubbles.
- Transcript layout is debounced so long conversations do not force layout on every update.
- Recent conversations are trimmed to keep startup and bubble restore work bounded.
