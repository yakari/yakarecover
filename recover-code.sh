#!/bin/bash

# =====================
# RECOVER-CODE SCRIPT
# =====================
# Scans recovered files and sorts them by programming language or tech
# Usage: ./recover-code.sh [options]

# ---- Config ----
PROJECT_NAME=""
FILTER_TYPES=()
ENABLE_ZIP=false
OPEN_VSCODE=false
SOURCE_DIR="./recup_dir.*"
DEST_DIR="./recovered_code"
MAX_SIZE_BYTES=0  # 0 = no size filter
LOG_FILE=""
SUMMARY_FILE=""
LINES_TO_READ=40

# ---- Colors ----
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[1;34m'
RED='\033[1;31m'
NC='\033[0m' # No Color

# ---- Functions ----
show_help() {
  echo -e "\nUsage: $0 [OPTIONS]"
  echo -e "\nOptions:"
  echo -e "  --project, -p NAME         Prioritize files containing NAME (case-insensitive)"
  echo -e "  --filter, -f TYPES         Comma-separated list of types to detect (e.g. ts,vue,py,c,cpp)"
  echo -e "  --output-dir, -o DIR       Output directory (default: ./recovered_code)"
  echo -e "  --lines, -l NUM            Number of lines to read from each file (default: 40)"
  echo -e "  --size, -s SIZE            Maximum file size to scan (e.g. 100000, 100k, 10m)"
  echo -e "  --zip                      Compress the result into a zip archive"
  echo -e "  --open-vscode              Open the destination folder in VS Code"
  echo -e "  --help, -h                 Show this help message\n"
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
      --project|-p)
        PROJECT_NAME="$2"
        shift 2
        ;;
      --filter|-f)
        IFS=',' read -ra FILTER_TYPES <<< "$2"
        shift 2
        ;;
      --output-dir|-o)
        DEST_DIR="$2"
        shift 2
        ;;
      --lines|-l)
        LINES_TO_READ="$2"
        shift 2
        ;;
      --size|-s)
        parse_size "$2"
        shift 2
        ;;
      --zip)
        ENABLE_ZIP=true
        shift
        ;;
      --open-vscode)
        OPEN_VSCODE=true
        shift
        ;;
      --help|-h)
        show_help
        ;;
      *)
        echo -e "${RED}Unknown option: $1${NC}" >&2
        exit 1
        ;;
    esac
  done
  LOG_FILE="$DEST_DIR/sorting_log.txt"
  SUMMARY_FILE="$DEST_DIR/sorting_summary.csv"
}

should_include_type() {
  local type="$1"
  if [ ${#FILTER_TYPES[@]} -eq 0 ]; then return 0; fi
  for t in "${FILTER_TYPES[@]}"; do
    [[ "$t" == "$type" ]] && return 0
  done
  return 1
}

# ---- Type definitions ----
declare -A TYPE_PATTERNS

# Web/Frontend
TYPE_PATTERNS[vue]="<template>|<script setup"
TYPE_PATTERNS[ts]="import type|export const|defineComponent"
TYPE_PATTERNS[js]="import .* from|export default"
TYPE_PATTERNS[html]="<html>|<!DOCTYPE html>"
TYPE_PATTERNS[css]="@import|:root|--.*:"

# Config/Markdown
TYPE_PATTERNS[json]='"name":|"scripts":'
TYPE_PATTERNS[md]="#|---|\* "
TYPE_PATTERNS[yml]='version:|services:'
TYPE_PATTERNS[env]='^[A-Z_]+=.*'

# Backend/General
TYPE_PATTERNS[py]='^def |import .*'
TYPE_PATTERNS[sh]="^#!/bin/(ba|z)sh|set -[eux]"
TYPE_PATTERNS[perl]="^#!/usr/bin/perl|use strict"
TYPE_PATTERNS[sql]='create table|select .* from'

# Mobile/JVM
TYPE_PATTERNS[kt]='fun main|val |var |suspend fun'
TYPE_PATTERNS[java]='public class|import java'
TYPE_PATTERNS[gradle]='plugins \{|apply plugin'
TYPE_PATTERNS[maven]='<project xmlns|<dependencies>'
TYPE_PATTERNS[ant]='<project name=.* default='

# Systems
TYPE_PATTERNS[c]='#include <.*>|int main\(.*\)'
TYPE_PATTERNS[cpp]='#include <.*>|std::cout'
TYPE_PATTERNS[make]='^all:|^[a-zA-Z0-9_-]+:.*'

# Others / Exotic
TYPE_PATTERNS[rust]='fn main|use std'
TYPE_PATTERNS[go]='package main|func main'
TYPE_PATTERNS[elixir]='defmodule|IO.puts'
TYPE_PATTERNS[dart]='void main|import .*dart'
TYPE_PATTERNS[swift]='import Swift|func .*\(.*\)' 

# ---- Main ----
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
    if [[ $MAX_SIZE_BYTES -gt 0 && $filesize -gt $MAX_SIZE_BYTES ]]; then
      continue
    fi

    content=$(head -n "$LINES_TO_READ" "$file")
    full_content=$(cat "$file")
    filename=$(basename "$file")

    best_type="unknown"
    best_score=0
    found_keywords=""

    if [[ -n "$PROJECT_NAME" ]] && echo "$full_content" | grep -qi "$PROJECT_NAME"; then
      best_type="project"
      best_score=999
      found_keywords="$PROJECT_NAME"
      echo -e "${RED}🔥 Project match ($PROJECT_NAME): $filename${NC}"
    else
      for type in "${!TYPE_PATTERNS[@]}"; do
        should_include_type "$type" || continue
        pattern="${TYPE_PATTERNS[$type]}"
        match_count=$(echo "$content" | grep -Eo "$pattern" | wc -l)
        if (( match_count > best_score )); then
          best_type=$type
          best_score=$match_count
          found_keywords=$(echo "$content" | grep -Eo "$pattern" | sort | uniq | paste -sd "," -)
        fi
      done
    fi

    mkdir -p "$DEST_DIR/$best_type"
    dest_path="$DEST_DIR/$best_type/${filename}_$counter.$best_type"
    cp -p "$file" "$dest_path"
    echo "$file -> $best_type (score: $best_score, keywords: $found_keywords)" >> "$LOG_FILE"
    echo "$filename,$best_type,$best_score,\"$found_keywords\"" >> "$SUMMARY_FILE"
    ((counter++))

    # Progress bar
    percent=$(( 100 * counter / nbTotalFiles ))
    echo -ne "\r${BLUE}Progress:${NC} $counter / $nbTotalFiles ["
    for ((i = 0; i < percent / 2; i++)); do echo -n "#"; done
    for ((i = percent / 2; i < 50; i++)); do echo -n "."; done
    echo -ne "] ${BLUE}($percent%)${NC}"
  fi
done

# Final newline
echo -e "\n${GREEN}✅ Recovered and sorted $counter files into $DEST_DIR/${NC}"
echo -e "${BLUE}📊 Summary written to $SUMMARY_FILE${NC}"
echo -e "${BLUE}📄 Log written to $LOG_FILE${NC}"

# Optional: Zip and/or open in VS Code
if [ "$ENABLE_ZIP" = true ]; then
  zip -rq "$DEST_DIR.zip" "$DEST_DIR"
  echo -e "${YELLOW}📦 Zipped result: $DEST_DIR.zip${NC}"
fi

if [ "$OPEN_VSCODE" = true ]; then
  code "$DEST_DIR"
fi
