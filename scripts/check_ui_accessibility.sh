#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
failures=0

require_text() {
  local file="$1"
  local text="$2"
  local message="$3"
  if ! grep -Fq "$text" "$ROOT_DIR/$file"; then
    echo "FAIL accessibility: $message" >&2
    failures=$((failures + 1))
  fi
}

reject_text() {
  local file="$1"
  local text="$2"
  local message="$3"
  if grep -Fq "$text" "$ROOT_DIR/$file"; then
    echo "FAIL accessibility: $message" >&2
    failures=$((failures + 1))
  fi
}

reject_text \
  "mac-app/SearchOverlayView.swift" \
  "configureIconButton(_ button: NSButton, symbol: String, action: Selector)" \
  "search icon buttons must require an accessibility label"
require_text \
  "mac-app/SearchOverlayView.swift" \
  "button.setAccessibilityLabel(label)" \
  "search icon buttons must expose their label to accessibility clients"

reject_text \
  "mac-app/ReadingNotePanelController+Build.swift" \
  "iconButton(symbol: String, action: Selector, pointSize:" \
  "reading-note icon buttons must require an accessibility label"
require_text \
  "mac-app/ReadingNotePanelController+Build.swift" \
  "button.setAccessibilityLabel(label)" \
  "reading-note icon buttons must expose their label to accessibility clients"

reject_text \
  "mac-app/ReaderWindowController+ChromeUI.swift" \
  "iconButton(symbol: String, action: Selector)" \
  "reader chrome icon buttons must require an accessibility description"
require_text \
  "mac-app/ReaderWindowController+ChromeUI.swift" \
  "button.setAccessibilityLabel(accessibilityDescription)" \
  "reader chrome icon buttons must expose their label to accessibility clients"
require_text \
  "mac-app/AISettingsPanelController+BuildCache.swift" \
  "cacheDisclosureButton.setAccessibilityLabel(disclosureLabel)" \
  "the cache disclosure button must have an accessibility label"
require_text \
  "mac-app/ReaderWindowController+ToolbarUI.swift" \
  "relatedFormsButton.setAccessibilityLabel(title)" \
  "stateful reader controls must update their accessibility label"
require_text \
  "mac-app/AIChatPanel+UI.swift" \
  "cancelRequestButton.setAccessibilityLabel(AppText.cancel)" \
  "AI chat cancel must have an accessibility label"
require_text \
  "mac-app/AIChatPanel+UI.swift" \
  "sendButton.setAccessibilityLabel(AppText.send)" \
  "AI chat send must have an accessibility label"
require_text \
  "mac-app/ReadAloudFloatingControlView.swift" \
  "button.setAccessibilityLabel(label)" \
  "stateful floating read-aloud buttons must update their accessibility label"
require_text \
  "mac-app/ReadingNotePanelController+Build.swift" \
  "titleIconView.setAccessibilityElement(false)" \
  "decorative reading-note images must be ignored by accessibility"

if (( failures > 0 )); then
  echo "UI accessibility checks failed: $failures issue(s)." >&2
  exit 1
fi

echo "UI accessibility checks passed."
