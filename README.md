# dotfiles

Personal dotfiles — Claude Code statusline and configuration.

## Quick Install

```bash
curl -s https://raw.githubusercontent.com/playkang/dotfiles/main/install.sh | bash
```

Or clone and run:

```bash
git clone https://github.com/playkang/dotfiles.git ~/dotfiles
bash ~/dotfiles/install.sh
```

## What's included

### Claude Code Statusline (`claude/statusline-command.sh`)

2-line status bar for Claude Code:

```
📁 myproject 🌿 develop | 🤖 Claude Sonnet 4.6 | 🧠 medium | ⏰ 14:32
📊 [======    ] 63% used (~73k left) | ⚡ 5h:12% 7d:8% | 💰 $0.042 | 💬 3 commits 📁 12 files
```

**Features:**
- Git branch display
- Model name + effort level (🌱/🧠/🔥)
- Context usage bar with color warnings (green → yellow → red)
- Context remaining tokens
- Rate limit usage (5h / 7d)
- Session cost estimate (API equivalent)
- Today's git activity (commits + files)
- Compression detection (🗜️ compressed)
- Current time

## Requirements

- `jq` — for JSON parsing (`brew install jq`)
- `bash` — already on macOS/Linux
