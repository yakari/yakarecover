#!/bin/bash

# =====================
# RECOVER-CODE SCRIPT
# =====================
# Scans recovered files and sorts them by programming language or tech
# Usage: ./recover-code.sh [options]

# ---- Config ----
PROJECT_KEYWORDS=()
FILTER_TYPES=()
ENABLE_ZIP=false
OPEN_VSCODE=false
SOURCE_DIR="./recup_dir.*"
DEST_DIR="./recovered_code"
MAX_SIZE_BYTES=0  # 0 = no size filter
LOG_FILE=""
SUMMARY_FILE=""
LINES_TO_READ=40
ENABLE_FALLBACK=true

# ---- Colors ----
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[1;34m'
RED='\033[1;31m'
NC='\033[0m' # No Color

# ---- Args ----
show_help() {
  echo -e "\nUsage: $0 [OPTIONS]"
  echo -e "\nOptions:"
  echo -e "  --project, -p LIST         Comma-separated keywords to prioritize"
  echo -e "  --filter, -f TYPES         Comma-separated types to detect"
  echo -e "  --output-dir, -o DIR       Output directory"
  echo -e "  --lines, -l NUM            Lines to read from each file"
  echo -e "  --size, -s SIZE            Max file size to scan (e.g. 100k, 10m)"
  echo -e "  --zip                      Compress the result"
  echo -e "  --open-vscode              Open in VS Code"
  echo -e "  --no-fallback              Disable fallback scoring"
  echo -e "  --help, -h                 Show help"
  exit 0
}

parse_size() {
  local input="$1"
  local multiplier=1
  case "$input" in
    *k|*K) multiplier=1024; input="${input%k}"; input="${input%K}" ;;
    *m|*M) multiplier=1048576; input="${input%m}"; input="${input%M}" ;;
  esac
  MAX_SIZE_BYTES=$((input * multiplier))
}

parse_args() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --project|-p) IFS=',' read -ra PROJECT_KEYWORDS <<< "$2"; shift 2 ;;
      --filter|-f) IFS=',' read -ra FILTER_TYPES <<< "$2"; shift 2 ;;
      --output-dir|-o) DEST_DIR="$2"; shift 2 ;;
      --lines|-l) LINES_TO_READ="$2"; shift 2 ;;
      --size|-s) parse_size "$2"; shift 2 ;;
      --zip) ENABLE_ZIP=true; shift ;;
      --open-vscode) OPEN_VSCODE=true; shift ;;
      --no-fallback) ENABLE_FALLBACK=false; shift ;;
      --help|-h) show_help ;;
      *) echo -e "${RED}Unknown option: $1${NC}" >&2; exit 1 ;;
    esac
  done
  LOG_FILE="$DEST_DIR/sorting_log.txt"
  SUMMARY_FILE="$DEST_DIR/sorting_summary.csv"
}

should_include_type() {
  local type="$1"
  if [ ${#FILTER_TYPES[@]} -eq 0 ]; then return 0; fi
  for t in "${FILTER_TYPES[@]}"; do [[ "$t" == "$type" ]] && return 0; done
  return 1
}

# ---- Hybrid Detection ----
identify_file_type() {
  local file="$1"
  local content=$(head -n "$LINES_TO_READ" "$file" 2>/dev/null)
  local first_bytes=$(head -c 16000 "$file" 2>/dev/null)
  local shebang=$(head -n 1 "$file" | grep "^#!" || echo "")

  # Heuristic detection
  if echo "$shebang" | grep -qE "python"; then echo "py"; return; fi
  if echo "$shebang" | grep -qE "bash|sh"; then echo "sh"; return; fi
  if echo "$shebang" | grep -qE "node"; then echo "js"; return; fi
  if echo "$first_bytes" | grep -qi "<template" && echo "$first_bytes" | grep -qi "<script"; then echo "vue"; return; fi
  if echo "$first_bytes" | grep -qE "import React|from ['\"]react['\"]"; then echo "react"; return; fi
  if echo "$first_bytes" | grep -qE "@NgModule|@Component"; then echo "angular"; return; fi
  if echo "$first_bytes" | grep -qE "createClient\\("; then echo "supabase"; return; fi
  if echo "$first_bytes" | grep -qE "useNuxtApp|defineNuxtConfig"; then echo "nuxt"; return; fi
  if echo "$first_bytes" | grep -qE "defineConfig\\("; then echo "vite"; return; fi
  if echo "$first_bytes" | grep -qE "express\\(|app\\.listen"; then echo "express"; return; fi
  if echo "$first_bytes" | grep -qE "fn main|use std"; then echo "rust"; return; fi
  if echo "$first_bytes" | grep -qE "int main\\(|#include <"; then echo "c"; return; fi
  if echo "$first_bytes" | grep -qE "std::|template <"; then echo "cpp"; return; fi
  if echo "$first_bytes" | grep -qE "package main|func main"; then echo "go"; return; fi
  if echo "$first_bytes" | grep -qE "public class|import java"; then echo "java"; return; fi
  if echo "$first_bytes" | grep -qE "fun main|val |var |suspend fun"; then echo "kt"; return; fi
  if echo "$first_bytes" | grep -qE "def |import .*"; then echo "py"; return; fi

  # Fallback only if enabled
  if [ "$ENABLE_FALLBACK" = false ]; then echo ""; return; fi

  # ---- Fallback detection using TYPE_PATTERNS ----
  local best_type="unknown"
  local best_score=0
  local found_keywords=""
  for type in "${!TYPE_PATTERNS[@]}"; do
    should_include_type "$type" || continue
    local pattern_block="${TYPE_PATTERNS[$type]}"
    local score=0
    local match_summary=""
    IFS='|' read -ra entries <<< "$pattern_block"
    for entry in "${entries[@]}"; do
      keyword=$(echo "$entry" | cut -d':' -f1)
      weight=$(echo "$entry" | cut -d':' -f2)
      [ -z "$weight" ] && weight=1
      hits=$(echo "$content" | grep -Eo "$keyword" | wc -l)
      (( score += hits * weight ))
      [ "$hits" -gt 0 ] && match_summary+="$keyword($hits*$weight),"
    done
    if (( score > best_score )); then
      best_type="$type"
      best_score=$score
      found_keywords="$match_summary"
    fi
  done
  echo "$best_type"
}

# ---- Type Patterns (used only for fallback) ----
declare -A TYPE_PATTERNS
TYPE_PATTERNS[vue]="<template>:5|<script setup.*>:5|defineComponent:4"
TYPE_PATTERNS[ts]="import type:3|export const:2"
TYPE_PATTERNS[js]="import .* from:2|export default:2"
TYPE_PATTERNS[html]="<html>:5|<!DOCTYPE html>:4"
TYPE_PATTERNS[css]="@import:2|:root:2"
TYPE_PATTERNS[json]="\"name\"::2|\"scripts\"::2"
TYPE_PATTERNS[md]="# :2|---:2"
TYPE_PATTERNS[yml]="version::2|services::2"
TYPE_PATTERNS[env]="^[A-Z_]+=.*:2"
TYPE_PATTERNS[py]="^def :3|import .*:2"
TYPE_PATTERNS[sh]="#!/bin/(ba|z)sh:5"
TYPE_PATTERNS[sql]="create table:3|select .* from:2"
TYPE_PATTERNS[kt]="fun main:3|val :2"
TYPE_PATTERNS[java]="public class:3|import java:2"
TYPE_PATTERNS[c]="#include <.*>:3|int main\\(:2"
TYPE_PATTERNS[cpp]="std::cout:2|template <:2"

# ---- Script Execution ----
parse_args "$@"
mkdir -p "$DEST_DIR"
> "$LOG_FILE"
> "$SUMMARY_FILE"
echo "filename,type,score,keywords" >> "$SUMMARY_FILE"

file_list=$(find $SOURCE_DIR -type f)
counter=0
nbTotalFiles=$(echo "$file_list" | wc -l)
clear

for file in $file_list; do
  if file "$file" | grep -qi "text"; then
    filesize=$(stat -c%s "$file")
    if [[ $MAX_SIZE_BYTES -gt 0 && $filesize -gt $MAX_SIZE_BYTES ]]; then continue; fi
    content=$(head -n "$LINES_TO_READ" "$file")
    full_content=$(cat "$file")
    filename=$(basename "$file")

    best_type="unknown"
    matched_project=""

    for keyword in "${PROJECT_KEYWORDS[@]}"; do
      if echo "$full_content" | grep -iq "$keyword"; then
        matched_project="$keyword"
        best_type="projects/$keyword"
        echo -e "${RED}🔥 Project match ($keyword): $filename${NC}"
        break
      fi
    done

    if [[ -z "$matched_project" ]]; then
      best_type=$(identify_file_type "$file")
      [[ -z "$best_type" ]] && best_type="unknown"
    fi

    mkdir -p "$DEST_DIR/$best_type"
    dest_path="$DEST_DIR/$best_type/${filename}_$counter.$(basename "$best_type")"
    cp -p "$file" "$dest_path"
    echo "$file -> $best_type" >> "$LOG_FILE"
    echo "$filename,$best_type,0,\"\"" >> "$SUMMARY_FILE"
    ((counter++))

    percent=$(( 100 * counter / nbTotalFiles ))
    echo -ne "\r${BLUE}Progress:${NC} $counter / $nbTotalFiles ["
    for ((i = 0; i < percent / 2; i++)); do echo -n "#"; done
    for ((i = percent / 2; i < 50; i++)); do echo -n "."; done
    echo -ne "] ${BLUE}($percent%)${NC}"
  fi
done

# ---- Final Steps ----
echo -e "\n${GREEN}✅ Recovered and sorted $counter files into $DEST_DIR/${NC}"
echo -e "${BLUE}📊 Summary written to $SUMMARY_FILE${NC}"
echo -e "${BLUE}📄 Log written to $LOG_FILE${NC}"

if [ "$ENABLE_ZIP" = true ]; then
  zip -rq "$DEST_DIR.zip" "$DEST_DIR"
  echo -e "${YELLOW}📦 Zipped result: $DEST_DIR.zip${NC}"
fi

if [ "$OPEN_VSCODE" = true ]; then
  code "$DEST_DIR"
fi
