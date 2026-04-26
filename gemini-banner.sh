#!/bin/bash
# Gemini CLI 会话横幅 — 展示真实用量（Catppuccin Mocha 配色）

Mauve='\033[38;2;203;166;247m'    # 工具名
Blue='\033[38;2;137;180;250m'     # 模型
Sapphire='\033[38;2;116;199;236m' # 目录
Green='\033[38;2;166;227;161m'    # 时间戳
Yellow='\033[38;2;249;226;175m'   # 用量警告
Red='\033[38;2;243;139;168m'      # 用量危险
Peach='\033[38;2;250;179;135m'    # 用量正常
Surface2='\033[38;2;88;91;112m'   # 分隔符
RESET='\033[0m'
SEP="${Surface2}│${RESET}"

CODEXBAR="/Users/wenbin/Downloads/CodexBar.app/Contents/Helpers/CodexBarCLI"

MODEL=$(jq -r '.model // empty' ~/.gemini/settings.json 2>/dev/null)
[ -z "$MODEL" ] && MODEL="gemini-2.5-pro"

DIR_FULL="${PWD##*/}"
if [ ${#DIR_FULL} -gt 24 ]; then DIR="${DIR_FULL:0:21}…"; else DIR="$DIR_FULL"; fi

TIMESTAMP=$(date '+%Y-%m-%d %H:%M')

# ── 查询用量（最多等 5 秒） ──
USAGE_JSON=$(perl -e 'alarm(5); exec @ARGV' -- "$CODEXBAR" usage --provider gemini --json --no-color 2>/dev/null)

USAGE_DISPLAY=""
if [ -n "$USAGE_JSON" ] && [ "$USAGE_JSON" != "null" ]; then
  # secondary（日配额）通常是最关键的限额
  SEC=$(echo "$USAGE_JSON" | jq -r '.[0].usage.secondary.usedPercent // ""')
  PRI=$(echo "$USAGE_JSON" | jq -r '.[0].usage.primary.usedPercent // ""')
  TERT=$(echo "$USAGE_JSON" | jq -r '.[0].usage.tertiary.usedPercent // ""')

  # 取三个配额中最高的那个用于展示
  MAX_PCT=$(echo "$SEC $PRI $TERT" | tr ' ' '\n' | grep -v '^$' | sort -rn | head -1)
  MAX_INT=$(echo "$MAX_PCT" | cut -d. -f1)

  if [ -n "$MAX_INT" ] && [ "$MAX_INT" != "" ]; then
    if [ "$MAX_INT" -ge 85 ] 2>/dev/null; then RL_COLOR="$Red"
    elif [ "$MAX_INT" -ge 60 ] 2>/dev/null; then RL_COLOR="$Yellow"
    else RL_COLOR="$Peach"; fi
    USAGE_DISPLAY=" ${SEP} ${RL_COLOR}↑${MAX_INT}%${RESET}"
  fi
fi

echo -e "${Mauve}✦ Gemini CLI${RESET} ${SEP} ${Blue}${MODEL}${RESET}${USAGE_DISPLAY} ${SEP} ${Sapphire}${DIR}${RESET} ${SEP} ${Green}${TIMESTAMP}${RESET}"
