#!/bin/bash
# Claude Code StatusLine v2.3.0 — Catppuccin Mocha 双行布局
#
# 环境变量（均有默认值，无需配置即可使用）：
#   CC_SL_LINES=1|2          单行/双行（默认 2）
#   CC_SL_SHOW_PACE=0        关闭 pace delta 指示器
#   CC_SL_SHOW_RESET=0       不显示重置倒计时
#   CC_SL_SHOW_VIM=0         不显示 Vim 模式徽章
#   CC_SL_SHOW_AGENT=0       不显示 Agent 徽章
#   CC_SL_SHOW_EFFORT=0      不显示 Effort 徽章
#   CC_SL_SHOW_CTX_TOKENS=1  显示上下文 token 用量（如 106k/200k）
#   CC_SL_RL_WARN_PCT=60     速率限制/上下文黄色阈值
#   CC_SL_RL_DANGER_PCT=85   速率限制/上下文红色阈值
#   CC_SL_PACE_THRESHOLD=5   Pace delta 最小显示幅度（百分点）
#   CC_SL_PATH_DEPTH=1       保留路径末尾几段完整显示（默认 1）
#   CC_SL_DEBUG=1            将原始 JSON payload 写入 /tmp/statusline-debug.json

VERSION="2.3.0"
[ "${1:-}" = "--version" ] && echo "statusline v${VERSION}" && exit 0

input=$(cat)
[ "${CC_SL_DEBUG:-0}" = "1" ] && echo "$input" > /tmp/statusline-debug.json

# ── Truecolor 自动检测 ──
# 默认开启 truecolor（Claude Code 内置 Electron renderer 始终支持）。
# 仅在明确检测到不支持的环境时降级为 256 色，避免错误降级破坏体验。
_use_truecolor() {
  # 显式声明 truecolor 的终端
  case "${COLORTERM:-}" in
    truecolor|24bit) return 0 ;;
  esac
  # 已知支持 truecolor 的 TERM_PROGRAM
  case "${TERM_PROGRAM:-}" in
    iTerm.app|vscode|WezTerm|Hyper|Cursor) return 0 ;;
  esac
  # Apple Terminal（macOS Sonoma 之前）明确不支持 truecolor
  [ "${TERM_PROGRAM:-}" = "Apple_Terminal" ] && return 1
  # 默认：假设支持 truecolor（Claude Code 内置渲染器）
  return 0
}

if _use_truecolor; then
  # ── Catppuccin Mocha 配色（24 位 Truecolor ANSI）──
  Mauve='\033[38;2;203;166;247m'    # 模型名
  Blue='\033[38;2;137;180;250m'     # 项目名
  Yellow='\033[38;2;249;226;175m'   # Git 分支 / 警告
  Green='\033[38;2;166;227;161m'    # 正常 / 新增行
  Red='\033[38;2;243;139;168m'      # 危险 / 删除行
  Lavender='\033[38;2;180;190;254m' # 时长
  Teal='\033[38;2;148;226;213m'     # 费用
  Sapphire='\033[38;2;116;199;236m' # 上下文 %
  Peach='\033[38;2;250;179;135m'    # 速率限制（正常区间）
  Pink='\033[38;2;245;194;231m'     # Vim VISUAL 模式
  Surface2='\033[38;2;88;91;112m'   # 分隔符 / 次要文字
else
  # ── Catppuccin Mocha 配色（256 色降级，最接近近似值）──
  # 降级映射：每个颜色通过 xterm-256 6×6×6 色块计算最近邻
  Mauve='\033[38;5;183m'    # #d7afd7 ≈ Mauve
  Blue='\033[38;5;111m'     # #87afff ≈ Blue
  Yellow='\033[38;5;223m'   # #ffd7af ≈ Yellow
  Green='\033[38;5;151m'    # #afd7af ≈ Green
  Red='\033[38;5;211m'      # #ff87af ≈ Red
  Lavender='\033[38;5;147m' # #afafff ≈ Lavender
  Teal='\033[38;5;116m'     # #87d7d7 ≈ Teal
  Sapphire='\033[38;5;117m' # #87d7ff ≈ Sapphire
  Peach='\033[38;5;216m'    # #ffaf87 ≈ Peach
  Pink='\033[38;5;218m'     # #ffafd7 ≈ Pink
  Surface2='\033[38;5;60m'  # #5f5f87 ≈ Surface2
fi
RESET='\033[0m'
SEP="${Surface2}│${RESET}"

# ── 配置（环境变量覆盖默认值） ──
SL_LINES=${CC_SL_LINES:-2}
SHOW_PACE=${CC_SL_SHOW_PACE:-1}
SHOW_RESET=${CC_SL_SHOW_RESET:-1}
SHOW_VIM=${CC_SL_SHOW_VIM:-1}
SHOW_AGENT=${CC_SL_SHOW_AGENT:-1}
SHOW_EFFORT=${CC_SL_SHOW_EFFORT:-1}
SHOW_CTX_TOKENS=${CC_SL_SHOW_CTX_TOKENS:-1}
RL_WARN=${CC_SL_RL_WARN_PCT:-60}
RL_DANGER=${CC_SL_RL_DANGER_PCT:-85}
PACE_THRESHOLD=${CC_SL_PACE_THRESHOLD:-5}
PATH_DEPTH=${CC_SL_PATH_DEPTH:-1}

# ── 单次 jq 调用提取全部字段（每字段一行，无需分隔符）──
# jq 逗号表达式逐行输出，bash 多个 read 逐行读取。
# 完全避免 IFS/分隔符问题，天然 bash 3.2 兼容。
{
  IFS= read -r MODEL
  IFS= read -r DIR
  IFS= read -r CTX_PCT
  IFS= read -r CTX_SIZE
  IFS= read -r RL5H
  IFS= read -r RL5H_RESET
  IFS= read -r RL7D
  IFS= read -r COST_USD
  IFS= read -r DURATION_MS
  IFS= read -r LINES_ADDED
  IFS= read -r LINES_REMOVED
  IFS= read -r VIM_MODE
  IFS= read -r AGENT_NAME
  IFS= read -r EFFORT_LEVEL
  IFS= read -r IS_WORKTREE
  IFS= read -r WORKTREE_NAME
} < <(echo "$input" | jq -r '
  (.model.display_name // "Unknown"),
  (.workspace.current_dir // ""),
  ((.context_window.used_percentage   // 0) | floor | tostring),
  ((.context_window.context_window_size // 0) | floor | tostring),
  ((.rate_limits.five_hour.used_percentage  // "") | if type == "number" then floor | tostring else . end),
  ((.rate_limits.five_hour.resets_at        // 0)  | floor | tostring),
  ((.rate_limits.seven_day.used_percentage  // "") | if type == "number" then floor | tostring else . end),
  ((.cost.total_cost_usd      // 0) | tostring),
  ((.cost.total_duration_ms   // 0) | floor | tostring),
  ((.cost.total_lines_added   // 0) | floor | tostring),
  ((.cost.total_lines_removed // 0) | floor | tostring),
  (.vim.mode    // ""),
  (.agent.name  // ""),
  (.effort.level // ""),
  (if (.worktree.is_worktree // false) then "1" else "0" end),
  (.worktree.name // "")')

# ── resets_at 时间戳单位自适应（秒 or 毫秒）──
_to_epoch_secs() {
  local ts="${1:-0}"
  [ "${#ts}" -ge 13 ] 2>/dev/null && echo $(( ts / 1000 )) || echo "$ts"
}

# ── Token 数量格式化（k / M 单位）──
_fmt_tokens() {
  local n="${1:-0}"
  if [ "$n" -ge 1000000 ] 2>/dev/null; then
    # M 单位：保留 1 位小数（用 bc 做浮点）
    printf "%.1fM" "$(echo "scale=2; $n/1000000" | bc -l 2>/dev/null || echo 0)"
  elif [ "$n" -ge 1000 ] 2>/dev/null; then
    echo "$(( n / 1000 ))k"
  else
    echo "${n}"
  fi
}

# ── 上下文进度条（阈值变色） ──
CTX_PCT_INT=${CTX_PCT%%.*}
CTX_PCT_INT=${CTX_PCT_INT:-0}
if   [ "$CTX_PCT_INT" -ge "$RL_DANGER" ] 2>/dev/null; then CTX_BAR_COLOR="$Red"
elif [ "$CTX_PCT_INT" -ge "$RL_WARN"   ] 2>/dev/null; then CTX_BAR_COLOR="$Yellow"
else CTX_BAR_COLOR="$Green"
fi
FILLED=$(( (CTX_PCT_INT + 9) / 10 ))
[ "$FILLED" -gt 10 ] && FILLED=10
EMPTY=$((10 - FILLED))
printf -v FILL_STR "%${FILLED}s"; printf -v PAD_STR "%${EMPTY}s"
CTX_BAR="${FILL_STR// /█}${PAD_STR// /░}"

# ── 上下文 Token 数量（可选显示）──
CTX_TOKEN_DETAIL=""
if [ "$SHOW_CTX_TOKENS" = "1" ] && [ "${CTX_SIZE:-0}" -gt 0 ] 2>/dev/null; then
  USED_TOKENS=$(( CTX_SIZE * CTX_PCT_INT / 100 ))
  USED_FMT=$(_fmt_tokens "$USED_TOKENS")
  SIZE_FMT=$(_fmt_tokens "$CTX_SIZE")
  CTX_TOKEN_DETAIL=" ${Surface2}(${USED_FMT}/${SIZE_FMT})${RESET}"
fi

# ── 1M 上下文模型徽章 ──
MODEL_1M=""
[ "${CTX_SIZE:-0}" -ge 1000000 ] 2>/dev/null && MODEL_1M=" ${Surface2}·1M${RESET}"

# ── 速率限制颜色（内联，避免子进程） ──
_rl_color() {
  local pct=$1
  if   [ "$pct" -ge "$RL_DANGER" ] 2>/dev/null; then printf '%s' "$Red"
  elif [ "$pct" -ge "$RL_WARN"   ] 2>/dev/null; then printf '%s' "$Yellow"
  else printf '%s' "$Peach"
  fi
}

# ── 5h 速率限制 + Pace delta + 重置倒计时 ──
RL5H_SECTION=""
if [ -n "$RL5H" ] && [ "$RL5H" != "null" ] && [ "$RL5H" != "" ]; then
  RL5H_INT=${RL5H%%.*}
  RL5H_COLOR=$(_rl_color "$RL5H_INT")

  PACE_DISPLAY=""
  if [ "$SHOW_PACE" = "1" ] && [ -n "$RL5H_RESET" ] && [ "$RL5H_RESET" != "0" ]; then
    NOW=$(date +%s)
    RESET_SECS=$(_to_epoch_secs "$RL5H_RESET")
    ELAPSED=$(( NOW - (RESET_SECS - 18000) ))
    if [ "$ELAPSED" -gt 0 ] && [ "$ELAPSED" -le 18000 ] 2>/dev/null; then
      EXPECTED=$(( ELAPSED * 100 / 18000 ))
      DELTA=$(( RL5H_INT - EXPECTED ))
      ABS_DELTA=${DELTA#-}
      if [ "$ABS_DELTA" -ge "$PACE_THRESHOLD" ] 2>/dev/null; then
        if [ "$DELTA" -gt 0 ]; then
          PACE_DISPLAY=" ${Red}⇡${ABS_DELTA}p%${RESET}"
        else
          PACE_DISPLAY=" ${Green}⇣${ABS_DELTA}p%${RESET}"
        fi
      fi
    fi
  fi

  RESET_COUNTDOWN=""
  if [ "$SHOW_RESET" = "1" ] && [ -n "$RL5H_RESET" ] && [ "$RL5H_RESET" != "0" ]; then
    NOW=$(date +%s)
    RESET_SECS=$(_to_epoch_secs "$RL5H_RESET")
    SECS_LEFT=$(( RESET_SECS - NOW ))
    if [ "$SECS_LEFT" -gt 0 ] 2>/dev/null; then
      HRS_LEFT=$(( SECS_LEFT / 3600 ))
      MINS_LEFT=$(( (SECS_LEFT % 3600) / 60 ))
      if [ "$HRS_LEFT" -gt 0 ]; then
        RESET_COUNTDOWN=" ${Surface2}(重置 ${HRS_LEFT}h${MINS_LEFT}m)${RESET}"
      else
        RESET_COUNTDOWN=" ${Surface2}(重置 ${MINS_LEFT}m)${RESET}"
      fi
    fi
  fi

  RL5H_SECTION=" ${SEP} ${RL5H_COLOR}↑5h:${RL5H_INT}%${RESET}${PACE_DISPLAY}${RESET_COUNTDOWN}"
fi

# ── 7d 速率限制 ──
RL7D_SECTION=""
if [ -n "$RL7D" ] && [ "$RL7D" != "null" ] && [ "$RL7D" != "" ]; then
  RL7D_INT=${RL7D%%.*}
  RL7D_COLOR=$(_rl_color "$RL7D_INT")
  RL7D_SECTION=" ${SEP} ${RL7D_COLOR}↑7d:${RL7D_INT}%${RESET}"
fi

# ── 时长格式化 ──
MINS=$(( DURATION_MS / 60000 ))
SECS=$(( (DURATION_MS % 60000) / 1000 ))

# ── 费用（仅 >0 时显示） ──
COST_SECTION=""
if [ "$(echo "$COST_USD > 0" | bc -l 2>/dev/null)" = "1" ]; then
  COST_SECTION=" ${SEP} ${Teal}\$$(printf '%.2f' "$COST_USD")${RESET}"
fi

# ── Git 信息（5 秒缓存，按项目路径隔离） ──
DIR_HASH=$(printf '%s' "$DIR" | cksum | cut -d' ' -f1)
CACHE_FILE="/tmp/statusline-git-cache-${DIR_HASH}"
CACHE_MAX_AGE=5

cache_is_stale() {
  [ ! -f "$CACHE_FILE" ] || \
  [ $(( $(date +%s) - $(stat -f %m "$CACHE_FILE" 2>/dev/null || stat -c %Y "$CACHE_FILE" 2>/dev/null || echo 0) )) -gt $CACHE_MAX_AGE ]
}

if cache_is_stale; then
  if git -C "$DIR" rev-parse --git-dir > /dev/null 2>&1; then
    BRANCH=$(git -C "$DIR" branch --show-current 2>/dev/null)
    STAGED=$(git -C "$DIR" diff --cached --numstat 2>/dev/null | wc -l | tr -d ' ')
    MODIFIED=$(git -C "$DIR" diff --numstat 2>/dev/null | wc -l | tr -d ' ')
    printf '%s|%s|%s\n' "$BRANCH" "$STAGED" "$MODIFIED" > "$CACHE_FILE"
  else
    printf '||\n' > "$CACHE_FILE"
  fi
fi

IFS='|' read -r BRANCH STAGED MODIFIED < "$CACHE_FILE"

# ── Starship 风格路径缩略 ──
# CC_SL_PATH_DEPTH 控制末尾几段保留完整（默认 1）
# /Users/wenbin/mycode/jupyter/007/project → ~/m/j/0/project (depth=1)
#                                           → ~/m/j/007/project (depth=2)
# 注意：不能用 ${var/#$HOME/~}（bash 分隔符解析 bug），用 ${var#$HOME} 代替
_abbrev_path() {
  local full="$1"
  local depth="${PATH_DEPTH:-1}"
  local stripped="${full#$HOME}"
  local path
  [ "$stripped" != "$full" ] && path="~${stripped}" || path="$full"
  [ -z "$path" ] && { echo "/"; return; }

  if [ ${#path} -le 28 ]; then
    echo "$path"
    return
  fi

  printf '%s' "$path" | awk -v depth="$depth" -F/ '{
    n = NF
    for (i=1; i<=n; i++) {
      seg = $i
      keep = (n - i) < depth
      if      (i==1)   printf "%s",  seg
      else if (keep)   printf "/%s", seg
      else if (seg)    printf "/%s", substr(seg,1,1)
      else             printf "/"
    }
    printf "\n"
  }'
}

ABBREV_PATH=$(_abbrev_path "$DIR")

# ── Git 区段（分支 + staged + modified） ──
GIT_SECTION=""
if [ -n "$BRANCH" ]; then
  BRANCH_DISPLAY="$BRANCH"
  [ ${#BRANCH} -gt 16 ] && BRANCH_DISPLAY="${BRANCH:0:13}…"
  GIT_SECTION=" ${SEP} ${Yellow}${BRANCH_DISPLAY}${RESET}"
  [ "$STAGED"   -gt 0 ] 2>/dev/null && GIT_SECTION="${GIT_SECTION} ${Green}+${STAGED}${RESET}"
  [ "$MODIFIED" -gt 0 ] 2>/dev/null && GIT_SECTION="${GIT_SECTION} ${Yellow}~${MODIFIED}${RESET}"
fi

# ── Worktree 徽章 ──
WORKTREE_BADGE=""
if [ "$IS_WORKTREE" = "1" ] && [ -n "$WORKTREE_NAME" ] && [ "$WORKTREE_NAME" != "null" ]; then
  WT="${WORKTREE_NAME:0:12}"
  [ ${#WORKTREE_NAME} -gt 12 ] && WT="${WT}…"
  WORKTREE_BADGE=" ${Surface2}[wt:${WT}]${RESET}"
fi

# ── Agent 徽章（仅 --agent 模式） ──
AGENT_BADGE=""
if [ "$SHOW_AGENT" = "1" ] && [ -n "$AGENT_NAME" ] && [ "$AGENT_NAME" != "null" ] && [ "$AGENT_NAME" != "" ]; then
  AN="${AGENT_NAME:0:12}"
  [ ${#AGENT_NAME} -gt 12 ] && AN="${AN}…"
  AGENT_BADGE=" ${SEP} ${Peach}⚡${AN}${RESET}"
fi

# ── Vim 模式徽章（颜色区分 INSERT/VISUAL/NORMAL） ──
VIM_BADGE=""
if [ "$SHOW_VIM" = "1" ] && [ -n "$VIM_MODE" ] && [ "$VIM_MODE" != "null" ] && [ "$VIM_MODE" != "" ]; then
  case "$VIM_MODE" in
    INSERT) VIM_COLOR="$Green"  ;;
    VISUAL) VIM_COLOR="$Pink"   ;;
    *)      VIM_COLOR="$Yellow" ;;
  esac
  VIM_BADGE=" ${SEP} ${VIM_COLOR}vim:${VIM_MODE}${RESET}"
fi

# ── Effort 徽章（仅 high/xhigh/max 时显示） ──
EFFORT_BADGE=""
if [ "$SHOW_EFFORT" = "1" ]; then
  case "${EFFORT_LEVEL:-}" in
    high|xhigh|max)
      EFFORT_BADGE=" ${SEP} ${Yellow}effort:${EFFORT_LEVEL}${RESET}"
      ;;
  esac
fi

# ── 代码量统计 ──
CODE_STAT=""
if [ "${LINES_ADDED:-0}" -gt 0 ] 2>/dev/null || [ "${LINES_REMOVED:-0}" -gt 0 ] 2>/dev/null; then
  CODE_STAT=" ${SEP} ${Green}+${LINES_ADDED}${RESET}${Surface2}/${RESET}${Red}-${LINES_REMOVED}${RESET}"
fi

# ── 行组装（字段顺序：模型 → 配额 → 上下文 → 时长 → 费用）──
LINE1="${Mauve}${MODEL}${RESET}${MODEL_1M}${RL5H_SECTION}${RL7D_SECTION} ${SEP} ${CTX_BAR_COLOR}${CTX_BAR}${RESET} ${Sapphire}${CTX_PCT_INT}%${RESET}${CTX_TOKEN_DETAIL} ${SEP} ${Lavender}${MINS}m${SECS}s${RESET}${COST_SECTION}"
LINE2="${Blue}${ABBREV_PATH}${RESET}${GIT_SECTION}${WORKTREE_BADGE}${AGENT_BADGE}${VIM_BADGE}${EFFORT_BADGE}${CODE_STAT}"

if [ "$SL_LINES" = "1" ]; then
  echo -e "${LINE1} ${SEP} ${Blue}${ABBREV_PATH}${RESET}${GIT_SECTION}"
else
  echo -e "$LINE1"
  echo -e "$LINE2"
fi
