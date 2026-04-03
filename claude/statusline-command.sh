#!/usr/bin/env bash
# Claude Code status line - 2-line layout
# Reads JSON from stdin and outputs a formatted 2-line status line
#
# Line 1: 📁 dir 🌿 branch | 🤖 Model | 🧠 effort | ⏰ time
# Line 2: 📊 [bar] used% | 🔄 Context Remaining: X% (~Yk) | 💰 cost | 💬 commits 📁 files

input=$(cat)

# ANSI colors (dimmed-friendly)
RESET='\033[0m'
BOLD='\033[1m'
DIM='\033[2m'
CYAN='\033[36m'
GREEN='\033[32m'
YELLOW='\033[33m'
RED='\033[31m'
BLUE='\033[34m'
MAGENTA='\033[35m'
WHITE='\033[37m'

# --- Data extraction ---
user=$(whoami)
host=$(hostname -s)
dir=$(echo "$input" | jq -r '.workspace.current_dir // .cwd // empty')
[ -z "$dir" ] && dir=$(pwd)
short_dir=$(basename "$dir")

model=$(echo "$input" | jq -r '.model.display_name // empty')
model_id=$(echo "$input" | jq -r '.model.id // empty')
used=$(echo "$input" | jq -r '.context_window.used_percentage // empty')
remaining=$(echo "$input" | jq -r '.context_window.remaining_percentage // empty')
ctx_size=$(echo "$input" | jq -r '.context_window.context_window_size // empty')
session_name=$(echo "$input" | jq -r '.session_name // empty')
vim_mode=$(echo "$input" | jq -r '.vim.mode // empty')
transcript_path=$(echo "$input" | jq -r '.transcript_path // empty')

# Git branch (skip optional locks)
git_branch=""
if git -C "$dir" rev-parse --git-dir > /dev/null 2>&1; then
  git_branch=$(git -C "$dir" -c gc.auto=0 symbolic-ref --short HEAD 2>/dev/null || git -C "$dir" -c gc.auto=0 rev-parse --short HEAD 2>/dev/null)
fi

# Current time
now=$(date +%H:%M)

# --- Today's git activity (skip optional locks) ---
today=$(date +%Y-%m-%d)
git_commits_today=""
git_files_today=""
if git -C "$dir" rev-parse --git-dir > /dev/null 2>&1; then
  git_commits_today=$(git -C "$dir" -c gc.auto=0 log --oneline --after="${today} 00:00" --before="${today} 23:59:59" 2>/dev/null | wc -l | tr -d ' ')
  git_files_today=$(git -C "$dir" -c gc.auto=0 log --name-only --pretty=format: --after="${today} 00:00" --before="${today} 23:59:59" 2>/dev/null | sort -u | grep -c . 2>/dev/null || echo "0")
fi

# --- Context bar builder ---
# Produces a visual bar like [=====     ] 10 chars wide
make_bar() {
  local pct="$1"
  local filled=$(( pct * 10 / 100 ))
  [ $filled -gt 10 ] && filled=10
  local empty=$(( 10 - filled ))
  local bar="["
  for ((i=0; i<filled; i++)); do bar="${bar}="; done
  for ((i=0; i<empty; i++)); do bar="${bar} "; done
  bar="${bar}]"
  printf '%s' "$bar"
}

# --- Context color (based on used%) ---
ctx_color() {
  local pct="$1"
  if [ -z "$pct" ]; then printf '%s' "$WHITE"; return; fi
  local p=$(printf '%.0f' "$pct")
  if [ "$p" -ge 90 ]; then printf '%s' "$RED"
  elif [ "$p" -ge 70 ]; then printf '%s' "$YELLOW"
  else printf '%s' "$GREEN"
  fi
}

# --- Remaining context color (based on remaining%) ---
remaining_color() {
  local pct="$1"
  if [ -z "$pct" ]; then printf '%s' "$WHITE"; return; fi
  local p=$(printf '%.0f' "$pct")
  if [ "$p" -le 10 ]; then printf '%s' "$RED"
  elif [ "$p" -le 30 ]; then printf '%s' "$YELLOW"
  else printf '%s' "$GREEN"
  fi
}

# --- /effort level ---
# Priority: stdin JSON > CLAUDE_EFFORT env var > settings.json > default "medium"
effort_level=$(echo "$input" | jq -r '.session.effort // .effort // empty' 2>/dev/null)
if [ -z "$effort_level" ]; then
  effort_level="${CLAUDE_EFFORT:-}"
fi
if [ -z "$effort_level" ]; then
  settings_file="$HOME/.claude/settings.json"
  if [ -f "$settings_file" ]; then
    effort_level=$(jq -r '.effortLevel // .effort // empty' "$settings_file" 2>/dev/null)
  fi
fi
[ -z "$effort_level" ] && effort_level="medium"

# Effort icon and color
effort_icon() {
  case "$1" in
    low)    printf '🌱' ;;
    medium) printf '🧠' ;;
    high)   printf '🔥' ;;
    *)      printf '🧠' ;;
  esac
}
effort_color() {
  case "$1" in
    low)    printf '%s' "$GREEN" ;;
    medium) printf '%s' "$YELLOW" ;;
    high)   printf '%s' "$RED" ;;
    *)      printf '%s' "$WHITE" ;;
  esac
}

# --- Compression detection ---
# Strategy 1: Parse JSONL transcript for type=="summary" entries
# Strategy 2: Compare used% with previous value (drop >= 20% = compressed)
CACHE_DIR="${TMPDIR:-/tmp}/claude_statusline"
mkdir -p "$CACHE_DIR" 2>/dev/null

detect_compression() {
  local tpath="$1"
  local cur_used="$2"
  local session_id="$3"

  # Derive a stable cache key from session_id, fallback to transcript path hash
  local cache_key=""
  if [ -n "$session_id" ]; then
    cache_key=$(printf '%s' "$session_id" | md5 2>/dev/null || printf '%s' "$session_id" | md5sum 2>/dev/null | cut -d' ' -f1)
  elif [ -n "$tpath" ]; then
    cache_key=$(printf '%s' "$tpath" | md5 2>/dev/null || printf '%s' "$tpath" | md5sum 2>/dev/null | cut -d' ' -f1)
  fi

  local compressed=0

  # Strategy 1: Check JSONL for summary entries
  if [ -n "$tpath" ] && [ -f "$tpath" ]; then
    if jq -e 'select(.type == "summary" or (.role == "system" and (.content | type == "string") and (.content | test("summary|compress|summariz"; "i"))))' "$tpath" > /dev/null 2>&1; then
      compressed=1
    fi
  fi

  # Strategy 2: Track used% drop >= 20pp between calls
  if [ -n "$cache_key" ] && [ -n "$cur_used" ]; then
    local prev_file="$CACHE_DIR/${cache_key}.prev_used"
    local prev_used=""
    [ -f "$prev_file" ] && prev_used=$(cat "$prev_file" 2>/dev/null)

    if [ -n "$prev_used" ] && [ "$prev_used" != "$cur_used" ]; then
      local prev_int cur_int
      prev_int=$(printf '%.0f' "$prev_used" 2>/dev/null)
      cur_int=$(printf '%.0f' "$cur_used" 2>/dev/null)
      if [ -n "$prev_int" ] && [ -n "$cur_int" ]; then
        local drop=$(( prev_int - cur_int ))
        if [ "$drop" -ge 20 ]; then
          compressed=1
          # Record this as the first call after compression; store compressed flag
          printf '%s' "1" > "$CACHE_DIR/${cache_key}.was_compressed" 2>/dev/null
        fi
      fi
    fi

    # Persist current used% for next comparison
    printf '%s' "$cur_used" > "$prev_file" 2>/dev/null
  fi

  # Also check persisted compression flag (so indicator stays visible for a few calls)
  if [ -n "$cache_key" ]; then
    local comp_file="$CACHE_DIR/${cache_key}.was_compressed"
    if [ -f "$comp_file" ]; then
      compressed=1
      # Auto-clear the flag after the current context grows past 10% again
      # (meaning a new conversation turn has happened post-compression)
      local cur_int=""
      [ -n "$cur_used" ] && cur_int=$(printf '%.0f' "$cur_used" 2>/dev/null)
      if [ -n "$cur_int" ] && [ "$cur_int" -gt 15 ]; then
        rm -f "$comp_file" 2>/dev/null
      fi
    fi
  fi

  printf '%d' "$compressed"
}

session_id_val=$(echo "$input" | jq -r '.session_id // empty')
compression_detected=$(detect_compression "$transcript_path" "$used" "$session_id_val")

# --- Autocompact threshold calculation ---
# Read CLAUDE_AUTOCOMPACT_PCT_OVERRIDE from settings.json env block, fallback to 95
autocompact_threshold=""
settings_file_env="$HOME/.claude/settings.json"
if [ -f "$settings_file_env" ]; then
  autocompact_threshold=$(jq -r '.env.CLAUDE_AUTOCOMPACT_PCT_OVERRIDE // empty' "$settings_file_env" 2>/dev/null)
fi
[ -z "$autocompact_threshold" ] && autocompact_threshold="95"

# Calculate gap between current used% and autocompact threshold
compact_threshold_suffix=""
if [ -n "$used" ] && [ "${compression_detected:-0}" != "1" ]; then
  used_int_for_compact=$(printf '%.0f' "$used")
  gap=$(( autocompact_threshold - used_int_for_compact ))
  if [ "$gap" -le 0 ]; then
    # Already past threshold (compress imminent or in progress)
    compact_threshold_suffix=$(printf " ${RED}🗜️ !압축임박${RESET}")
  elif [ "$gap" -le 5 ]; then
    compact_threshold_suffix=$(printf " ${RED}🗜️ -%d%%${RESET}" "$gap")
  elif [ "$gap" -le 10 ]; then
    compact_threshold_suffix=$(printf " ${YELLOW}🗜️ -%d%%${RESET}" "$gap")
  else
    compact_threshold_suffix=$(printf " ${DIM}🗜️ -%d%%${RESET}" "$gap")
  fi
fi

# --- Session cost calculation ---
# Uses transcript_path JSONL to sum token usage with per-model pricing
calc_session_cost() {
  local tpath="$1"
  local mid="$2"
  [ -z "$tpath" ] || [ ! -f "$tpath" ] && return

  local input_rate output_rate
  case "$mid" in
    *opus-4*|*opus-4-5*)
      input_rate="15"; output_rate="75" ;;
    *sonnet-4*|*sonnet-4-6*|*sonnet-4-5*)
      input_rate="3"; output_rate="15" ;;
    *haiku-4*|*haiku-4-5*)
      input_rate="0.8"; output_rate="4" ;;
    *opus*)
      input_rate="15"; output_rate="75" ;;
    *sonnet*)
      input_rate="3"; output_rate="15" ;;
    *haiku*)
      input_rate="0.8"; output_rate="4" ;;
    *)
      input_rate="3"; output_rate="15" ;;
  esac

  local cost
  cost=$(jq -s --argjson ir "$input_rate" --argjson or "$output_rate" '
    [.[] |
      (
        (.message.usage.input_tokens // 0) +
        (.message.usage.cache_creation_input_tokens // 0) +
        (.message.usage.cache_read_input_tokens // 0)
      ) as $inp |
      (.message.usage.output_tokens // 0) as $out |
      ($inp * $ir / 1000000) + ($out * $or / 1000000)
    ] | add // 0
  ' "$tpath" 2>/dev/null)

  if [ -n "$cost" ] && [ "$cost" != "0" ] && [ "$cost" != "null" ]; then
    printf '%s' "$cost"
  fi
}

session_cost=$(calc_session_cost "$transcript_path" "$model_id")

# Format cost for display
format_cost() {
  local cost="$1"
  [ -z "$cost" ] && return
  awk -v c="$cost" 'BEGIN {
    if (c+0 >= 1.0) printf "$%.2f", c
    else if (c+0 >= 0.01) printf "$%.3f", c
    else printf "$%.4f", c
  }'
}

# ============================================================
# LINE 1: 프로젝트/환경 정보
# 📁 dir 🌿 branch | 🤖 Model | 🧠 effort | ⏰ time
# ============================================================

line1=""

# Vim mode (if active)
if [ -n "$vim_mode" ]; then
  if [ "$vim_mode" = "INSERT" ]; then
    line1+=$(printf "${GREEN}${BOLD} INSERT ${RESET}")
  else
    line1+=$(printf "${YELLOW}${BOLD} NORMAL ${RESET}")
  fi
  line1+=$(printf "${DIM} | ${RESET}")
fi

# 📁 dir
line1+=$(printf "📁 ${BOLD}${short_dir}${RESET}")

# 🌿 git branch
if [ -n "$git_branch" ]; then
  line1+=$(printf " 🌿 ${MAGENTA}${git_branch}${RESET}")
fi

# Session name
if [ -n "$session_name" ]; then
  line1+=$(printf "${DIM} [${RESET}${WHITE}${session_name}${RESET}${DIM}]${RESET}")
fi

line1+=$(printf "${DIM} | ${RESET}")

# 🤖 Model
if [ -n "$model" ]; then
  line1+=$(printf "🤖 ${BLUE}${model}${RESET}")
  line1+=$(printf "${DIM} | ${RESET}")
fi

# Effort
ecolor=$(effort_color "$effort_level")
eicon=$(effort_icon "$effort_level")
line1+=$(printf "${eicon} ${ecolor}${effort_level}${RESET} ${DIM}/effort /config${RESET}")
line1+=$(printf "${DIM} | ${RESET}")

# ⏰ Time
line1+=$(printf "⏰ ${DIM}${now}${RESET}")

# ============================================================
# LINE 2: 사용량/비용 정보
# 📊 [bar] used% | 🔄 Context Remaining: X% (~Yk) | 💰 cost | 💬 commits 📁 files
# ============================================================

line2=""

# 📊 Context usage bar + used% + remaining tokens (combined)
if [ -n "$used" ]; then
  used_int=$(printf '%.0f' "$used")
  bar=$(make_bar "$used_int")
  color=$(ctx_color "$used_int")
  # Calculate approximate remaining tokens
  rem_suffix=""
  if [ -n "$remaining" ] && [ -n "$ctx_size" ] && [ "$ctx_size" -gt 0 ] 2>/dev/null; then
    rem_int=$(printf '%.0f' "$remaining")
    rem_tokens=$(( ctx_size * rem_int / 100 ))
    if [ "$rem_tokens" -ge 1000 ]; then
      rem_k=$(( rem_tokens / 1000 ))
      rem_suffix="${DIM} (~${rem_k}k left)${RESET}"
    fi
  fi
  # Compression indicator suffix
  compress_suffix=""
  if [ "${compression_detected:-0}" = "1" ]; then
    compress_suffix=$(printf " ${CYAN}🗜️ compressed${RESET}")
  fi
  line2+=$(printf "📊 ${color}${bar} ${used_int}%% used${RESET}${rem_suffix}${compress_suffix}${compact_threshold_suffix}")
  line2+=$(printf "${DIM} | ${RESET}")
else
  # No data yet (conversation not started)
  line2+=$(printf "📊 ${DIM}TBD${RESET}")
  line2+=$(printf "${DIM} | ${RESET}")
fi

# Rate limits (5h and 7d)
five=$(echo "$input" | jq -r '.rate_limits.five_hour.used_percentage // empty')
week=$(echo "$input" | jq -r '.rate_limits.seven_day.used_percentage // empty')
if [ -n "$five" ] || [ -n "$week" ]; then
  line2+=$(printf "⚡ ")
  if [ -n "$five" ]; then
    five_int=$(printf '%.0f' "$five")
    if [ "$five_int" -ge 90 ]; then
      line2+=$(printf "${RED}5h:${five_int}%%${RESET}")
    elif [ "$five_int" -ge 70 ]; then
      line2+=$(printf "${YELLOW}5h:${five_int}%%${RESET}")
    else
      line2+=$(printf "5h:${five_int}%%")
    fi
  fi
  if [ -n "$week" ]; then
    week_int=$(printf '%.0f' "$week")
    [ -n "$five" ] && line2+=$(printf "${DIM} ${RESET}")
    if [ "$week_int" -ge 90 ]; then
      line2+=$(printf "${RED}7d:${week_int}%%${RESET}")
    elif [ "$week_int" -ge 70 ]; then
      line2+=$(printf "${YELLOW}7d:${week_int}%%${RESET}")
    else
      line2+=$(printf "7d:${week_int}%%")
    fi
  fi
  line2+=$(printf "${DIM} | ${RESET}")
fi

# 💰 Session cost
if [ -n "$session_cost" ]; then
  cost_display=$(format_cost "$session_cost")
  if [ -n "$cost_display" ]; then
    cost_color=$(awk -v c="$session_cost" 'BEGIN {
      if (c+0 >= 0.50) print "red"
      else if (c+0 >= 0.10) print "yellow"
      else print "green"
    }')
    STRIKE='\033[9m'
    case "$cost_color" in
      red)    line2+=$(printf "💰 ${STRIKE}${RED}${cost_display}${RESET}") ;;
      yellow) line2+=$(printf "💰 ${STRIKE}${YELLOW}${cost_display}${RESET}") ;;
      *)      line2+=$(printf "💰 ${STRIKE}${GREEN}${cost_display}${RESET}") ;;
    esac
    line2+=$(printf "${DIM} | ${RESET}")
  fi
fi

# 💬 Today's git commits + 📁 files
if [ -n "$git_commits_today" ] && [ "$git_commits_today" -gt 0 ] 2>/dev/null; then
  line2+=$(printf "💬 ${GREEN}${git_commits_today} commits${RESET}")
  if [ -n "$git_files_today" ] && [ "$git_files_today" -gt 0 ] 2>/dev/null; then
    line2+=$(printf " 📁 ${WHITE}${git_files_today} files${RESET}")
  fi
  line2+=$(printf "${DIM} | ${RESET}")
fi

# Session token usage: last turn + cumulative total
total_in=$(echo "$input" | jq -r '.context_window.total_input_tokens // empty')
total_out=$(echo "$input" | jq -r '.context_window.total_output_tokens // empty')
last_in=$(echo "$input" | jq -r '.context_window.current_usage.input_tokens // empty')
last_out=$(echo "$input" | jq -r '.context_window.current_usage.output_tokens // empty')

format_tokens() {
  local n="$1"
  if [ "$n" -ge 1000 ] 2>/dev/null; then
    printf '%sk' "$(( n / 1000 ))"
  else
    printf '%s' "$n"
  fi
}

if [ -n "$total_in" ] && [ -n "$total_out" ]; then
  total_tokens=$(( total_in + total_out ))
  if [ "$total_tokens" -gt 0 ]; then
    total_fmt=$(format_tokens "$total_tokens")
    if [ -n "$last_in" ] && [ -n "$last_out" ]; then
      last_tokens=$(( last_in + last_out ))
      last_fmt=$(format_tokens "$last_tokens")
      line2+=$(printf "💬 ${WHITE}${last_fmt} token${RESET} ${DIM}/ ${total_fmt} token 누적${RESET}")
    else
      line2+=$(printf "💬 ${DIM}${total_fmt} token${RESET}")
    fi
  fi
fi

# ============================================================
# OUTPUT: 2 lines separated by newline
# ============================================================
printf '%b\n%b' "$line1" "$line2"
