#!/bin/bash
# Codex CLI 会话横幅 — 展示真实用量（Catppuccin Mocha 配色）
# 用量数据通过缓存读取，后台异步刷新（codexbar codex 查询需 2+ 分钟）

Mauve='\033[38;2;203;166;247m'    # 工具名
Blue='\033[38;2;137;180;250m'     # 模型
Sapphire='\033[38;2;116;199;236m' # 目录
Green='\033[38;2;166;227;161m'    # 时间戳
Yellow='\033[38;2;249;226;175m'   # 用量警告
Red='\033[38;2;243;139;168m'      # 用量危险
Peach='\033[38;2;250;179;135m'    # 用量正常
Teal='\033[38;2;148;226;213m'     # Credits
Surface2='\033[38;2;88;91;112m'   # 分隔符
RESET='\033[0m'
SEP="${Surface2}│${RESET}"

CODEXBAR="/Users/wenbin/Downloads/CodexBar.app/Contents/Helpers/CodexBarCLI"
CACHE_FILE="/tmp/codexbar-codex-usage.json"
CACHE_MAX_AGE=3600  # 1小时刷新一次

MODEL=$(grep -m1 '^model ' ~/.codex/config.toml 2>/dev/null | cut -d'"' -f2)
[ -z "$MODEL" ] && MODEL="unknown"

DIR_FULL="${PWD##*/}"
if [ ${#DIR_FULL} -gt 24 ]; then DIR="${DIR_FULL:0:21}…"; else DIR="$DIR_FULL"; fi

TIMESTAMP=$(date '+%Y-%m-%d %H:%M')

# ── 读取缓存（stale-while-revalidate 策略） ──
USAGE_JSON=""
[ -f "$CACHE_FILE" ] && USAGE_JSON=$(cat "$CACHE_FILE" 2>/dev/null)

# 缓存过期则后台静默刷新（不阻塞横幅显示）
CACHE_AGE=0
[ -f "$CACHE_FILE" ] && CACHE_AGE=$(( $(date +%s) - $(stat -f %m "$CACHE_FILE" 2>/dev/null || echo 0) ))
if [ ! -f "$CACHE_FILE" ] || [ "$CACHE_AGE" -gt "$CACHE_MAX_AGE" ]; then
  ( perl -e 'alarm(180); exec @ARGV' -- "$CODEXBAR" usage --provider codex --json --no-color \
    > "$CACHE_FILE" 2>/dev/null ) &
fi

# ── 解析用量 ──
USAGE_DISPLAY=""
CREDITS_DISPLAY=""
if [ -n "$USAGE_JSON" ]; then
  SEC_INT=$(echo "$USAGE_JSON" | jq -r '.[0].usage.secondary.usedPercent // ""' | cut -d. -f1)
  if [ -n "$SEC_INT" ] && [ "$SEC_INT" != "" ] && [ "$SEC_INT" != "null" ]; then
    if [ "$SEC_INT" -ge 85 ] 2>/dev/null; then RL_COLOR="$Red"
    elif [ "$SEC_INT" -ge 60 ] 2>/dev/null; then RL_COLOR="$Yellow"
    else RL_COLOR="$Peach"; fi
    USAGE_DISPLAY=" ${SEP} ${RL_COLOR}↑${SEC_INT}%${RESET}"
  fi

  CREDITS=$(echo "$USAGE_JSON" | jq -r '.[0].credits.remaining // ""')
  if [ -n "$CREDITS" ] && [ "$CREDITS" != "null" ] && [ "$CREDITS" != "" ]; then
    CREDITS_DISPLAY=" ${SEP} ${Teal}cr \$${CREDITS}${RESET}"
  fi
fi

echo -e "${Mauve}✦ Codex CLI${RESET} ${SEP} ${Blue}${MODEL}${RESET}${USAGE_DISPLAY}${CREDITS_DISPLAY} ${SEP} ${Sapphire}${DIR}${RESET} ${SEP} ${Green}${TIMESTAMP}${RESET}"
