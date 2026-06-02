#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
SOURCE_DIR="$ROOT_DIR/docs/wiki"
WIKI_REMOTE="${WIKI_REMOTE:-git@github.com:dowellhz/LeafReader.wiki.git}"
WIKI_WORKTREE="${WIKI_WORKTREE:-/private/tmp/leafreader-wiki-sync}"
PUSH=0
WIKI_PAGES=(
  Home.md
  Chinese.md
  English.md
  Getting-Started.md
  Architecture.md
  Feature-Map.md
  Development-Tasks.md
  Document-Loading.md
  Reading-Notes.md
  Shortcuts.md
  AI-Chat.md
  AI-Analysis-Cache.md
  Word-Highlights.md
  TTS-And-Read-Aloud.md
  Release-Process.md
  Release-Checklist.md
  Release-Runbook.md
  Security.md
  Troubleshooting.md
  Code-Map.md
  Type-Index.md
  _Sidebar.md
  _Footer.md
)

usage() {
  cat <<'EOF'
Usage: ./scripts/sync_github_wiki.sh [--push]

Sync docs/wiki into the GitHub Wiki repository.

Default mode:
  - clones or updates the local wiki worktree
  - writes converted wiki pages
  - shows the wiki diff
  - does not commit or push

With --push:
  - commits the wiki changes when there is a diff
  - pushes to the wiki remote

Environment:
  WIKI_REMOTE     GitHub Wiki git remote
  WIKI_WORKTREE   local wiki checkout path
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --push)
      PUSH=1
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      usage >&2
      exit 1
      ;;
  esac
done

if [[ ! -d "$SOURCE_DIR" ]]; then
  echo "Missing source wiki directory: $SOURCE_DIR" >&2
  exit 1
fi

if [[ ! -d "$WIKI_WORKTREE/.git" ]]; then
  rm -rf "$WIKI_WORKTREE"
  git clone "$WIKI_REMOTE" "$WIKI_WORKTREE"
else
  git -C "$WIKI_WORKTREE" fetch origin
  git -C "$WIKI_WORKTREE" checkout master
  if [[ -z "$(git -C "$WIKI_WORKTREE" status --porcelain)" ]]; then
    git -C "$WIKI_WORKTREE" pull --ff-only origin master
  fi
fi

unexpected_dirty_files() {
  git -C "$WIKI_WORKTREE" status --porcelain | while read -r _ path; do
    local allowed=0
    for page in "${WIKI_PAGES[@]}"; do
      if [[ "$path" == "$page" ]]; then
        allowed=1
        break
      fi
    done
    if [[ "$allowed" -ne 1 ]]; then
      echo "$path"
    fi
  done
}

if [[ -n "$(unexpected_dirty_files)" ]]; then
  echo "Wiki worktree has uncommitted changes: $WIKI_WORKTREE" >&2
  git -C "$WIKI_WORKTREE" status --short >&2
  exit 1
fi

copy_page() {
  local source="$1"
  local target="$2"
  cp "$SOURCE_DIR/$source" "$WIKI_WORKTREE/$target"
}

copy_page "getting-started.md" "Getting-Started.md"
copy_page "zh.md" "Chinese.md"
copy_page "en.md" "English.md"
copy_page "architecture.md" "Architecture.md"
copy_page "feature-map.md" "Feature-Map.md"
copy_page "development-tasks.md" "Development-Tasks.md"
copy_page "document-loading.md" "Document-Loading.md"
copy_page "reading-notes.md" "Reading-Notes.md"
copy_page "shortcuts.md" "Shortcuts.md"
copy_page "ai-chat.md" "AI-Chat.md"
copy_page "ai-analysis-cache.md" "AI-Analysis-Cache.md"
copy_page "word-highlights.md" "Word-Highlights.md"
copy_page "tts.md" "TTS-And-Read-Aloud.md"
copy_page "release-process.md" "Release-Process.md"
copy_page "release-checklist.md" "Release-Checklist.md"
copy_page "release-runbook.md" "Release-Runbook.md"
copy_page "security.md" "Security.md"
copy_page "troubleshooting.md" "Troubleshooting.md"
copy_page "code-map.md" "Code-Map.md"
copy_page "type-index.md" "Type-Index.md"

CURRENT_VERSION="$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$ROOT_DIR/mac-app/Info.plist")"

cat > "$WIKI_WORKTREE/Home.md" <<EOF
# Leaf Reader Wiki

Leaf Reader Wiki keeps Chinese user documentation and English/engineering documentation as separate entry points.

## 文档状态 / Current Version

- 当前版本 / Current version: \`$CURRENT_VERSION\`
- Git tag: \`v$CURRENT_VERSION\`
- Website: [leafreader.space](https://leafreader.space)
- Appcast: [docs/appcast.xml](https://dowellhz.github.io/LeafReader/appcast.xml)
- Latest installer: [LeafReader-$CURRENT_VERSION.pkg](https://github.com/dowellhz/LeafReader/releases/download/v$CURRENT_VERSION/LeafReader-$CURRENT_VERSION.pkg)

## 中文文档

- [中文入口](Chinese)
- [安装与入门](Getting-Started)
- [阅读笔记](Reading-Notes)
- [快捷键](Shortcuts)
- [AI 使用](AI-Chat)
- [背单词与单词高亮](Word-Highlights)
- [TTS 与朗读](TTS-And-Read-Aloud)
- [故障排查](Troubleshooting)
- [架构](Architecture)
- [功能地图](Feature-Map)
- [开发任务](Development-Tasks)
- [文档加载](Document-Loading)
- [AI 分析缓存](AI-Analysis-Cache)
- [发布流程](Release-Process)
- [发布检查清单](Release-Checklist)
- [发布运行手册](Release-Runbook)
- [安全](Security)
- [代码地图](Code-Map)
- [类型索引](Type-Index)

## English & Engineering

- [English Index](English)
- [Architecture](Architecture)
- [Feature Map](Feature-Map)
- [Development Tasks](Development-Tasks)
- [Document Loading](Document-Loading)
- [AI Analysis Cache](AI-Analysis-Cache)
- [Release Process](Release-Process)
- [Release Checklist](Release-Checklist)
- [Release Runbook](Release-Runbook)
- [Security](Security)
- [Troubleshooting](Troubleshooting)
- [Code Map](Code-Map)
- [Type Index](Type-Index)

## Common Commands

~~~sh
./scripts/check.sh
./scripts/release_pkg.sh <version>
./scripts/publish_release.sh <version>
./scripts/update_wiki.sh --push
~~~

## Maintenance

- Keep durable architecture notes in these pages.
- Regenerate [Code Map](Code-Map) after large refactors:

~~~sh
./scripts/update_wiki.sh
~~~

- Prefer short flow descriptions and source file links over copied code.
EOF

cat > "$WIKI_WORKTREE/_Sidebar.md" <<'EOF'
## 中文文档

- [首页](Home)
- [中文入口](Chinese)
- [安装与入门](Getting-Started)
- [阅读笔记](Reading-Notes)
- [快捷键](Shortcuts)
- [AI 使用](AI-Chat)
- [背单词](Word-Highlights)
- [TTS 与朗读](TTS-And-Read-Aloud)
- [故障排查](Troubleshooting)
- [架构](Architecture)
- [功能地图](Feature-Map)
- [开发任务](Development-Tasks)
- [文档加载](Document-Loading)
- [AI 分析缓存](AI-Analysis-Cache)
- [发布流程](Release-Process)
- [发布检查清单](Release-Checklist)
- [发布运行手册](Release-Runbook)
- [安全](Security)
- [代码地图](Code-Map)
- [类型索引](Type-Index)

## English & Engineering

- [English Index](English)
- [Architecture](Architecture)
- [Feature Map](Feature-Map)
- [Development Tasks](Development-Tasks)
- [Document Loading](Document-Loading)
- [AI Analysis Cache](AI-Analysis-Cache)
- [Release Process](Release-Process)
- [Release Checklist](Release-Checklist)
- [Release Runbook](Release-Runbook)
- [Security](Security)
- [Troubleshooting](Troubleshooting)
- [Code Map](Code-Map)
- [Type Index](Type-Index)
EOF

cat > "$WIKI_WORKTREE/_Footer.md" <<'EOF'
---

Related: [Home](Home) · [Feature Map](Feature-Map) · [Development Tasks](Development-Tasks) · [Code Map](Code-Map) · [Type Index](Type-Index)

Maintained by `./scripts/update_wiki.sh`.
EOF

echo "Wiki worktree: $WIKI_WORKTREE"
git -C "$WIKI_WORKTREE" status --short

if [[ -z "$(git -C "$WIKI_WORKTREE" status --porcelain)" ]]; then
  echo "GitHub Wiki is already up to date."
  exit 0
fi

git -C "$WIKI_WORKTREE" diff --stat

if [[ "$PUSH" -ne 1 ]]; then
  echo "Dry run complete. Re-run with --push to commit and push wiki changes."
  exit 0
fi

git -C "$WIKI_WORKTREE" add "${WIKI_PAGES[@]}"
git -C "$WIKI_WORKTREE" commit -m "Sync code wiki"
git -C "$WIKI_WORKTREE" push origin master
