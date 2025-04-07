#!/bin/bash

# Enhanced recovery script for sorting recovered files by language type
# Advanced version with superior language detection, progress tracking, and optimization

# Error handling
set -o pipefail  # Make pipe failures exit with failure
trap cleanup EXIT INT TERM  # Ensure cleanup on exit

# Cleanup function
cleanup() {
    # Kill any background processes
    if [ -n "$PROGRESS_PID" ]; then
        kill $PROGRESS_PID 2>/dev/null || true
        wait $PROGRESS_PID 2>/dev/null || true
    fi
    
    # Clean up temp directory if it exists
    if [ -n "$TEMP_DIR" ] && [ -d "$TEMP_DIR" ]; then
        rm -rf "$TEMP_DIR" || true
    fi
    
    # Reset terminal
    echo -e "\033[?25h"  # Show cursor
    echo -e "\033[0m"    # Reset terminal colors
}

# Default options
SOURCE_DIR=""
TARGET_DIR=""
PROJECT_NAMES=""
PARALLEL_JOBS=4
SKIP_EXTENSIONS="jpg,jpeg,png,gif,bmp,tiff,mp3,mp4,avi,mov,mkv,flv,wmv,webm,pdf,dll,exe,so,zip,rar,7z,tar,gz,bz2,xz"
SKIP_SIZE="10M"  # Default max size in human-readable format
RENAME_FILES=true   # Enable file renaming by default
MERGE_FRAGMENTS=false  # Disable fragment merging by default 
INTELLIGENT_NAMING=true  # Enable intelligent naming by default
PRE_PROCESS=false   # Disable pre-processing by default
OPEN_REPORT=false   # Don't open report automatically by default
MOVE_FILES=false      # Copy files by default instead of moving
AUTO_PREPROCESS=false # Don't auto-preprocess by default

# Parse command line options
while [[ $# -gt 0 ]]; do
  case $1 in
    -s|--source)
      SOURCE_DIR="$2"
      shift 2
      ;;
    -t|--target)
      TARGET_DIR="$2"
      shift 2
      ;;
    -p|--projects)
      PROJECT_NAMES="$2"
      shift 2
      ;;
    -j|--jobs)
      PARALLEL_JOBS="$2"
      shift 2
      ;;
    -e|--skip-extensions)
      SKIP_EXTENSIONS="$2"
      shift 2
      ;;
    -m|--max-size)
      # Store the provided size - we'll parse it later
      SKIP_SIZE="$2"
      shift 2
      ;;
    --pre-process)
      PRE_PROCESS=true
      shift
      ;;
    --rename|--no-rename)
      if [[ "$1" == "--rename" ]]; then
        RENAME_FILES=true
      else
        RENAME_FILES=false
      fi
      shift
      ;;
    --merge-fragments|--no-merge-fragments)
      if [[ "$1" == "--merge-fragments" ]]; then
        MERGE_FRAGMENTS=true
      else
        MERGE_FRAGMENTS=false
      fi
      shift
      ;;
    --intelligent-naming|--no-intelligent-naming)
      if [[ "$1" == "--intelligent-naming" ]]; then
        INTELLIGENT_NAMING=true
      else
        INTELLIGENT_NAMING=false
      fi
      shift
      ;;
    --move)
      MOVE_FILES=true
      shift
      ;;
    --auto-preprocess)
      AUTO_PREPROCESS=true
      shift
      ;;
    --open-report)
      OPEN_REPORT=true
      shift
      ;;
    --help)
      echo "Usage: $0 -s|--source <source_directory> -t|--target <target_directory> [OPTIONS]"
      echo ""
      echo "Options:"
      echo "  -s, --source            Directory containing recovered files"
      echo "  -t, --target            Target directory for sorted files"
      echo "  -p, --projects          Comma-separated list of project names to prioritize" 
      echo "  -j, --jobs              Number of parallel jobs (default: 4)"
      echo "  -e, --skip-extensions   Comma-separated list of extensions to skip"
      echo "  -m, --max-size          Skip files larger than this size (e.g., 10M, 1G, 500K) (default: 10MB)"
      echo "  --rename, --no-rename   Enable/disable renaming with proper extensions (default: enabled)"
      echo "  --intelligent-naming, --no-intelligent-naming"
      echo "                          Enable/disable intelligent file naming (default: enabled)"
      echo "  --merge-fragments, --no-merge-fragments"
      echo "                          Enable/disable merging file fragments (default: disabled)"
      echo "  --move                  Move files instead of copying (faster, modifies source directory)"
      echo "  --auto-preprocess       Automatically pre-process files before detailed sorting"
      echo "  --pre-process           Only pre-process Photorec directories (faster initial sorting)"
      echo "  --open-report           Open the HTML report when completed"
      echo "  --help                  Show this help message"
      exit 0
      ;;
    *)
      echo "Unknown option: $1"
      exit 1
      ;;
  esac
done

# Check required parameters
if [ -z "$SOURCE_DIR" ] || [ -z "$TARGET_DIR" ]; then
    echo "Usage: $0 -s|--source <source_directory> -t|--target <target_directory> [-p|--projects 'project1,project2'] [-j|--jobs <num>] [-e|--skip-extensions 'ext1,ext2'] [-m|--max-size <bytes>]"
    echo ""
    echo "Options:"
    echo "  -s, --source            Directory containing recovered files"
    echo "  -t, --target            Target directory for sorted files"
    echo "  -p, --projects          Comma-separated list of project names to prioritize"
    echo "  -j, --jobs              Number of parallel jobs (default: 4)"
    echo "  -e, --skip-extensions   Comma-separated list of extensions to skip"
    echo "  -m, --max-size          Skip files larger than this size (e.g., 10M, 1G, 500K) (default: 10MB)"
    exit 1
fi

# Check if source directory exists
if [ ! -d "$SOURCE_DIR" ]; then
    echo "Source directory does not exist!"
    exit 1
fi

# Create base target directory
mkdir -p "$TARGET_DIR"

# Create language-specific directories
declare -A LANG_DIRS=(
    # Web development
    ["vue"]="Vue components"
    ["vue-ts"]="Vue TypeScript components"
    ["vue-js"]="Vue JavaScript components" 
    ["react"]="React components"
    ["angular"]="Angular components"
    ["svelte"]="Svelte components"
    ["js"]="JavaScript files"
    ["ts"]="TypeScript files"
    ["jsx"]="React JSX files"
    ["tsx"]="React TSX files"
    ["html"]="HTML files"
    ["css"]="CSS files"
    ["scss"]="SCSS files"
    ["less"]="LESS files"
    ["sass"]="Sass files"
    
    # Server-side languages
    ["php"]="PHP files"
    ["java"]="Java files"
    ["kotlin"]="Kotlin files"
    ["scala"]="Scala files"
    ["groovy"]="Groovy files"
    ["python"]="Python files"
    ["ruby"]="Ruby files"
    ["go"]="Go files"
    ["rust"]="Rust files"
    ["csharp"]="C# files"
    ["fsharp"]="F# files"
    ["perl"]="Perl files"
    
    # Systems programming
    ["c"]="C files"
    ["cpp"]="C++ files"
    ["swift"]="Swift files"
    ["objective-c"]="Objective-C files"
    
    # Shell/scripting
    ["bash"]="Bash scripts"
    ["shell"]="Shell scripts"
    ["powershell"]="PowerShell scripts"
    ["batch"]="Windows Batch files"
    
    # Configuration/Data
    ["json"]="JSON files"
    ["yaml"]="YAML files"
    ["toml"]="TOML files"
    ["xml"]="XML files"
    ["ini"]="INI files"
    ["env"]="Environment files"
    ["properties"]="Properties files"
    ["csv"]="CSV files"
    
    # Documentation
    ["md"]="Markdown files"
    ["txt"]="Text files"
    ["rst"]="reStructuredText files"
    ["latex"]="LaTeX files"
    
    # Frameworks/Libraries
    ["nuxt"]="Nuxt.js files"
    ["next"]="Next.js files"
    ["gatsby"]="Gatsby files"
    ["supabase"]="Supabase files"
    ["firebase"]="Firebase files"
    ["node"]="Node.js files"
    ["django"]="Django files"
    ["rails"]="Ruby on Rails files"
    ["laravel"]="Laravel files"
    ["spring"]="Spring framework files"
    ["express"]="Express.js files"
    
    # Database
    ["sql"]="SQL files"
    ["graphql"]="GraphQL files"
    ["mongo"]="MongoDB queries"
    
    # Other
    ["src"]="Other source files"
    ["config"]="Configuration files"
    ["binary"]="Binary files"
    ["unknown"]="Unknown file types"
)

# Create all target directories
for dir in "${!LANG_DIRS[@]}"; do
    mkdir -p "$TARGET_DIR/$dir"
done

# Create project directories if project names are specified
if [ ! -z "$PROJECT_NAMES" ]; then
    IFS=',' read -ra PROJECTS <<< "$PROJECT_NAMES"
    for project in "${PROJECTS[@]}"; do
        mkdir -p "$TARGET_DIR/$project"
    done
fi

echo "Created directories for ${#LANG_DIRS[@]} file types"

# Create temporary directory for tracking
TEMP_DIR=$(mktemp -d)
HASH_DIR="$TEMP_DIR/hashes"
COUNTER_FILE="$TEMP_DIR/counter"
PROGRESS_FILE="$TEMP_DIR/progress"
mkdir -p "$HASH_DIR"

# Initialize counter
echo "0" > "$COUNTER_FILE"
echo "0" > "$PROGRESS_FILE"

# Function to get file extension
get_extension() {
    filename=$(basename "$1")
    extension="${filename##*.}"
    if [ "$filename" = "$extension" ]; then
        echo ""
    else
        echo "$extension" | tr '[:upper:]' '[:lower:]'
    fi
}

# Function to check if file should be skipped based on extension
should_skip_extension() {
    local file="$1"
    local ext=$(get_extension "$file")
    
    if [ -z "$ext" ]; then
        return 1  # Don't skip files without extension
    fi
    
    IFS=',' read -ra SKIP_EXTS <<< "$SKIP_EXTENSIONS"
    for skip_ext in "${SKIP_EXTS[@]}"; do
        if [ "$ext" = "$skip_ext" ]; then
            return 0  # Skip this extension
        fi
    done
    
    return 1  # Don't skip
}

# Function to check if file should be skipped based on size
should_skip_size() {
    local file="$1"
    local size=$(stat -c%s "$file")
    
    if [ "$size" -gt "$SKIP_SIZE" ]; then
        return 0  # Skip large files
    fi
    
    return 1  # Don't skip
}

# Function to safely check if file contains pattern
grep_check() {
    local file="$1"
    local pattern="$2"
    grep -l -m 1 "$pattern" "$file" 2>/dev/null >/dev/null
    return $?
}

# Function to check if file is a duplicate using hash
is_duplicate() {
    local file="$1"
    local hash=$(md5sum "$file" 2>/dev/null | cut -d ' ' -f 1)
    
    if [ -z "$hash" ]; then
        return 1  # Not a duplicate (couldn't calculate hash)
    fi
    
    local hash_path="${hash:0:2}"
    local hash_file="$HASH_DIR/$hash_path/$hash"
    
    mkdir -p "$HASH_DIR/$hash_path"
    
    if [ -f "$hash_file" ]; then
        # File is a duplicate, add target directory to hash file
        echo "$2" >> "$hash_file"
        return 0  # Is duplicate
    else
        echo "$2" > "$hash_file"
        return 1  # Not duplicate
    fi
}

# Function to update counter for progress bar
update_counter() {
    local current=$(cat "$COUNTER_FILE")
    echo $((current + 1)) > "$COUNTER_FILE"
}

# Function to display progress bar
display_progress() {
    local current=$(cat "$COUNTER_FILE" 2>/dev/null || echo "0")
    current=$(( current + 0 ))  # Force to integer
    
    # Only update progress display if percentage changed
    local percentage=0
    if [ "$TOTAL_FILES" -gt 0 ]; then
        percentage=$(( current * 100 / TOTAL_FILES ))
    fi
    
    local last_percentage=$(cat "$PROGRESS_FILE" 2>/dev/null || echo "0")
    last_percentage=$(( last_percentage + 0 ))  # Force to integer
    
    if [ "$percentage" -ne "$last_percentage" ]; then
        echo "$percentage" > "$PROGRESS_FILE"
        
        # Hide cursor during progress display
        echo -ne "\033[?25l"
        
        # Clear current line and move to beginning
        printf "\033[1K\r"
        
        # Print progress bar
        local bar_size=50
        local filled=$(( percentage * bar_size / 100 ))
        local empty=$(( bar_size - filled ))
        
        printf "Progress: ["
        printf "%${filled}s" | tr ' ' '#'
        printf "%${empty}s" | tr ' ' ' '
        printf "] %d%% (%d/%d files)" "$percentage" "$current" "$TOTAL_FILES"
    fi
    
    # Show cursor again if progress is complete
    if [ "$percentage" -eq 100 ]; then
        echo -ne "\033[?25h"
    fi
}

# Function to check if file matches project names
check_project_match() {
    local file="$1"
    
    if [ -z "$PROJECT_NAMES" ]; then
        return 1  # No project names specified
    fi
    
    IFS=',' read -ra PROJECTS <<< "$PROJECT_NAMES"
    for project in "${PROJECTS[@]}"; do
        if grep_check "$file" "$project"; then
            if ! is_duplicate "$file" "$project"; then
                if [ "$MOVE_FILES" = true ]; then
                    mv "$file" "$TARGET_DIR/$project/$(basename "$file")"
                else
                    cp "$file" "$TARGET_DIR/$project/$(basename "$file")"
                fi
            fi
            return 0  # Matched a project
        fi
    done
    
    return 1  # No match
}

# Function to analyze a file's content to determine its type
identify_file_type() {
    local file="$1"
    local first_lines=$(head -n 20 "$file" 2>/dev/null || echo "")
    local content_sample=$(cat "$file" 2>/dev/null | head -c 16384 || echo "")  # Examine up to 16KB
    local ext=$(get_extension "$file")
    local file_type=""
    
    # Try to identify based on shebang line first
    if grep -q "^#!" <<< "$first_lines"; then
        if grep -q "^#!/usr/bin/env node" <<< "$first_lines" || grep -q "^#!/usr/bin/node" <<< "$first_lines"; then
            file_type="node"
        elif grep -q "^#!/usr/bin/env python" <<< "$first_lines" || grep -q "^#!/usr/bin/python" <<< "$first_lines"; then
            file_type="python"
        elif grep -q "^#!/usr/bin/env ruby" <<< "$first_lines" || grep -q "^#!/usr/bin/ruby" <<< "$first_lines"; then
            file_type="ruby"
        elif grep -q "^#!/usr/bin/perl" <<< "$first_lines" || grep -q "^#!/usr/bin/env perl" <<< "$first_lines"; then
            file_type="perl"
        elif grep -q "^#!/bin/bash" <<< "$first_lines"; then
            file_type="bash"
        elif grep -q "^#!/bin/sh" <<< "$first_lines"; then
            file_type="shell"
        elif grep -q "^#!/usr/bin/php" <<< "$first_lines"; then
            file_type="php"
        fi
    fi
    
    # If no match from shebang, try content patterns
    if [ -z "$file_type" ]; then
        # Vue files detection (enhanced for various Vue syntax variants)
        if grep -q "<template" <<< "$content_sample"; then
            # Match Vue with TypeScript syntax variants
            if grep -q "<script.*lang=['\"]ts['\"]" <<< "$content_sample" || 
               grep -q "<script.*setup.*lang=['\"]ts['\"]" <<< "$content_sample" || 
               grep -q "defineProps<{" <<< "$content_sample" ||
               grep -q "interface Props" <<< "$content_sample" && grep -q "defineProps<Props>" <<< "$content_sample"; then
                file_type="vue-ts"
            # Match Vue with setup syntax
            elif grep -q "<script.*setup" <<< "$content_sample" || grep -q "defineProps" <<< "$content_sample" || grep -q "defineEmits" <<< "$content_sample"; then
                file_type="vue-js" 
            # Standard Vue component
            elif grep -q "<script" <<< "$content_sample"; then
                file_type="vue-js"
            else
                file_type="vue"
            fi
        
        # React JSX/TSX detection (enhanced)
        elif grep -q "import React\|React\." <<< "$content_sample" || grep -q "from ['\"]react['\"]" <<< "$content_sample" || grep -q "React\.Component" <<< "$content_sample" || grep -q "useState\|useEffect\|useContext" <<< "$content_sample"; then
            if grep -q ":\s*\(string\|number\|boolean\|any\|React\.\)\|interface\s\|type\s" <<< "$content_sample" || grep -q "<.*>(\{.*\})" <<< "$content_sample"; then
                file_type="tsx"
            else
                file_type="jsx"
            fi
            
        # Angular detection
        elif grep -q "@Component" <<< "$content_sample" && grep -q "selector:" <<< "$content_sample"; then
            file_type="angular"
            
        # Svelte detection
        elif grep -q "<script" <<< "$content_sample" && grep -q "<style" <<< "$content_sample" && ! grep -q "<template" <<< "$content_sample"; then
            file_type="svelte"
            
        # Framework-specific detection
        elif grep -q "defineNuxtConfig\|useNuxtApp\|useRuntimeConfig" <<< "$content_sample"; then
            file_type="nuxt"
        elif grep -q "getStaticProps\|getServerSideProps\|NextPage\|NextApiRequest" <<< "$content_sample"; then
            file_type="next"
        elif grep -q "createClient\|supabase\|from('profiles')\|from('auth')" <<< "$content_sample"; then
            file_type="supabase"
        elif grep -q "firebase\|initializeApp\|getFirestore\|getAuth" <<< "$content_sample"; then
            file_type="firebase"
        elif grep -q "express\|app.get\|app.use\|app.post\|app.listen" <<< "$content_sample"; then
            file_type="express"
        elif grep -q "@SpringBootApplication\|@Controller\|@Repository\|@Service" <<< "$content_sample"; then
            file_type="spring"
        elif grep -q "class.*extends.*Model\|Schema::\|Route::\|namespace App\\" <<< "$content_sample"; then
            file_type="laravel"
        elif grep -q "from django\|@admin.register\|class.*Model\|class.*Form" <<< "$content_sample"; then
            file_type="django"
        elif grep -q "class.*ActiveRecord::\|class.*ApplicationController\|Rails.application" <<< "$content_sample"; then
            file_type="rails"
        
        # Programming languages detection
        elif grep -q "<?php" <<< "$content_sample" || grep -q "namespace\s\+[A-Z]" <<< "$content_sample" && grep -q "use\s\+[A-Z]" <<< "$content_sample"; then
            file_type="php"
        elif grep -q "package\s\+[a-z]" <<< "$content_sample" && grep -q "import\s\+[a-z]" <<< "$content_sample" && grep -q "public\s\+class" <<< "$content_sample"; then
            file_type="java" 
        elif grep -q "fun\s\+[a-z]" <<< "$content_sample" && grep -q "val\s\+[a-z]" <<< "$content_sample"; then
            file_type="kotlin"
        elif grep -q "object\s\+[A-Z]" <<< "$content_sample" && grep -q "def\s\+[a-z]" <<< "$content_sample" && grep -q "case\s\+class" <<< "$content_sample"; then
            file_type="scala"
        elif grep -q "def\s\+[a-z]" <<< "$content_sample" && grep -q "import\s\+[a-z]" <<< "$content_sample" && ! grep -q "func\s\+[a-z]" <<< "$content_sample"; then
            if grep -q "@" <<< "$content_sample" && grep -q "class\s\+[A-Z]" <<< "$content_sample"; then
                file_type="groovy"
            else
                file_type="python"
            fi
        elif grep -q "func\s\+[a-z]" <<< "$content_sample" && grep -q "package\s\+[a-z]" <<< "$content_sample"; then
            file_type="go"
        elif grep -q "fn\s\+[a-z]" <<< "$content_sample" && grep -q "use\s\+[a-z]" <<< "$content_sample" && grep -q "pub\s\+struct" <<< "$content_sample"; then
            file_type="rust"
        elif grep -q "namespace\s\+[A-Z]" <<< "$content_sample" && grep -q "using\s\+[A-Z]" <<< "$content_sample" && grep -q "public\s\+class" <<< "$content_sample"; then
            file_type="csharp"
        elif grep -q "module\s\+[A-Z]" <<< "$content_sample" && grep -q "open\s\+[A-Z]" <<< "$content_sample" && grep -q "let\s\+[a-z]" <<< "$content_sample"; then
            file_type="fsharp"
        elif grep -q "my\s\+\$[a-z]" <<< "$content_sample" || grep -q "sub\s\+[a-z]" <<< "$content_sample" && grep -q "\$[a-z]" <<< "$content_sample"; then
            file_type="perl"
        elif grep -q "#include\s\+<[a-z]" <<< "$content_sample" || grep -q "int\s\+main" <<< "$content_sample"; then
            if grep -q "class\s\+[A-Z]" <<< "$content_sample" || grep -q "template\s\+<" <<< "$content_sample" || grep -q "std::" <<< "$content_sample"; then
                file_type="cpp"
            else
                file_type="c"
            fi
        elif grep -q "import\s\+[A-Z]" <<< "$content_sample" && grep -q "@interface" <<< "$content_sample" || grep -q "@implementation" <<< "$content_sample"; then
            file_type="objective-c"
        elif grep -q "import\s\+[A-Z]" <<< "$content_sample" && grep -q "class\s\+[A-Z]" <<< "$content_sample" && grep -q "func\s\+[a-z]" <<< "$content_sample"; then
            file_type="swift"
        
        # Web language detection (enhanced TypeScript detection)
        elif grep -q "interface\s\+[A-Z][A-Za-z]*\s*{\|type\s\+[A-Z][A-Za-z]*\s*=\|class\s.*implements\s\+[A-Z]" <<< "$content_sample" || 
             grep -q "export\s\+type\s\+" <<< "$content_sample" ||
             grep -q ":\s*\(string\|number\|boolean\|any\|unknown\|void\|never\)\(\[\]\)*" <<< "$content_sample" ||
             grep -q "<.*>\(" <<< "$content_sample" ||
             grep -q "as\s\+const" <<< "$content_sample" ||
             grep -q "import\s\+{.*}\s\+from" <<< "$content_sample" && grep -q ":[^=]" <<< "$content_sample"; then
            file_type="ts"
        elif grep -q "function\s\+[a-z]" <<< "$content_sample" || grep -q "const\s\+[a-z]" <<< "$content_sample" || grep -q "let\s\+[a-z]" <<< "$content_sample" || grep -q "var\s\+[a-z]" <<< "$content_sample" || grep -q "=>" <<< "$content_sample"; then
            if grep -q "require(" <<< "$content_sample" || grep -q "module.exports" <<< "$content_sample" || grep -q "process.env" <<< "$content_sample"; then
                file_type="node"
            else
                file_type="js"
            fi
        elif grep -q "<!DOCTYPE\|<html\|<head\|<body" <<< "$content_sample"; then
            file_type="html"
        elif grep -q "@import\|@mixin\|@include\|\$" <<< "$content_sample" && grep -q "{" <<< "$content_sample"; then
            file_type="scss"
        elif grep -q "@import" <<< "$content_sample" && grep -q "{" <<< "$content_sample" && grep -q "&" <<< "$content_sample"; then
            file_type="less"
        elif grep -q "\$" <<< "$content_sample" && ! grep -q "{" <<< "$content_sample"; then
            file_type="sass"
        elif grep -q "{" <<< "$content_sample" && grep -q ";" <<< "$content_sample" && grep -q ":" <<< "$content_sample"; then
            file_type="css"
            
        # Data/Config detection
        elif grep -q "^\s*{" <<< "$content_sample" && grep -q ":" <<< "$content_sample" && ! grep -q ";" <<< "$content_sample"; then
            file_type="json"
        elif grep -q "^\s*-" <<< "$content_sample" || grep -q ":\s*$" <<< "$content_sample"; then
            file_type="yaml"
        elif grep -q "^\s*\[[a-zA-Z]" <<< "$content_sample" && grep -q "=" <<< "$content_sample"; then
            file_type="toml"
        elif grep -q "^<\?xml" <<< "$content_sample" || (grep -q "<[a-zA-Z]" <<< "$content_sample" && grep -q "</[a-zA-Z]" <<< "$content_sample"); then
            file_type="xml"
        elif grep -q "^\s*\[[a-zA-Z]" <<< "$content_sample" && grep -q "=" <<< "$content_sample" && ! grep -q ":" <<< "$content_sample"; then
            file_type="ini"
        elif grep -q "^[A-Z_]+=." <<< "$content_sample"; then
            file_type="env"
        elif grep -q "^[a-zA-Z]\+\.[a-zA-Z]\+=" <<< "$content_sample"; then
            file_type="properties"
        elif grep -q "^\"" <<< "$content_sample" && grep -q "\"," <<< "$content_sample"; then
            file_type="csv"
            
        # Database files detection
        elif grep -q "SELECT\|INSERT\|UPDATE\|DELETE\|CREATE TABLE" <<< "$content_sample"; then
            file_type="sql"
        elif grep -q "type\s\+Query\|type\s\+Mutation\|input\s\+[A-Z]" <<< "$content_sample"; then
            file_type="graphql"
        elif grep -q "db\.[a-zA-Z]\+\.find\|db\.[a-zA-Z]\+\.aggregate" <<< "$content_sample"; then
            file_type="mongo"
            
        # Documentation detection
        elif grep -q "^#\s\|^##\s" <<< "$content_sample" && ! grep -q "import\s\+[a-z]" <<< "$content_sample"; then
            file_type="md"
        elif grep -q "^[A-Za-z]" <<< "$content_sample" && ! grep -q "[<>{};]" <<< "$content_sample"; then
            file_type="txt"
        elif grep -q "^\.\.\s\+" <<< "$content_sample" || grep -q "^===\+$" <<< "$content_sample"; then
            file_type="rst"
        elif grep -q "\\\\begin{\|\\\\section{\|\\\\documentclass" <<< "$content_sample"; then
            file_type="latex"
            
        # Scripting detection
        elif grep -q "^@echo\|^set\s\+[a-zA-Z]=" <<< "$content_sample"; then
            file_type="batch"
        elif grep -q "param(\|function\s\+[A-Z]" <<< "$content_sample" && grep -q "\$" <<< "$content_sample"; then
            file_type="powershell"
            
        # Configuration detection
        elif grep -q "config\." <<< "$content_sample" || grep -q "^\s*module.exports\s*=" <<< "$content_sample" || grep -q "webpack\|babel\|eslint\|tsconfig" <<< "$first_lines"; then
            file_type="config"
            
        # Default to source file if it has code-like content but couldn't be classified
        elif grep -q "function\|class\|import\|export\|var\|const\|let\|if\|for\|while" <<< "$content_sample"; then
            file_type="src"
        else
            # Try to identify binary files
            if file "$file" | grep -q "executable\|binary\|data"; then
                file_type="binary"
            else
                file_type="unknown"
            fi
        fi
    fi
    
    # Fall back to extension-based detection if we couldn't determine type
    if [ -z "$file_type" ] && [ ! -z "$ext" ]; then
        case "$ext" in
            js)  file_type="js" ;;
            ts)  file_type="ts" ;;
            jsx) file_type="jsx" ;;
            tsx) file_type="tsx" ;;
            vue) file_type="vue" ;;
            php) file_type="php" ;;
            py)  file_type="python" ;;
            rb)  file_type="ruby" ;;
            java) file_type="java" ;;
            kt) file_type="kotlin" ;;
            scala) file_type="scala" ;;
            groovy) file_type="groovy" ;;
            go) file_type="go" ;;
            rs) file_type="rust" ;;
            cs) file_type="csharp" ;;
            fs) file_type="fsharp" ;;
            pl) file_type="perl" ;;
            c) file_type="c" ;;
            cpp|cc|cxx|h|hpp) file_type="cpp" ;;
            swift) file_type="swift" ;;
            m) file_type="objective-c" ;;
            html|htm) file_type="html" ;;
            css) file_type="css" ;;
            scss) file_type="scss" ;;
            less) file_type="less" ;;
            sass) file_type="sass" ;;
            json) file_type="json" ;;
            yml|yaml) file_type="yaml" ;;
            toml) file_type="toml" ;;
            xml) file_type="xml" ;;
            ini) file_type="ini" ;;
            env) file_type="env" ;;
            properties) file_type="properties" ;;
            csv) file_type="csv" ;;
            md|markdown) file_type="md" ;;
            txt) file_type="txt" ;;
            rst) file_type="rst" ;;
            tex) file_type="latex" ;;
            sh) file_type="shell" ;;
            bash) file_type="bash" ;;
            bat|cmd) file_type="batch" ;;
            ps1) file_type="powershell" ;;
            sql) file_type="sql" ;;
            graphql|gql) file_type="graphql" ;;
            *) file_type="unknown" ;;
        esac
    fi
    
    echo "$file_type"
}

# Function to process a single file
process_file() {
    local file="$1"
    
    # Skip based on extension or size
    if should_skip_extension "$file" || should_skip_size "$file"; then
        # Update counter with lock to prevent race conditions
        flock "$COUNTER_FILE" bash -c "current=\$(cat \"$COUNTER_FILE\" 2>/dev/null || echo 0); echo \$((current + 1)) > \"$COUNTER_FILE\""
        return
    fi
    
    # Check for project name matches first (high priority)
    if check_project_match "$file"; then
        # Update counter with lock to prevent race conditions
        flock "$COUNTER_FILE" bash -c "current=\$(cat \"$COUNTER_FILE\" 2>/dev/null || echo 0); echo \$((current + 1)) > \"$COUNTER_FILE\""
        return
    fi
    
    # Identify file type
    local file_type=$(identify_file_type "$file")
    
    # Copy/move file to appropriate directory if not a duplicate
    if ! is_duplicate "$file" "$file_type"; then
        if [ "$MOVE_FILES" = true ]; then
            mv "$file" "$TARGET_DIR/$file_type/$(basename "$file")"
        else
            cp "$file" "$TARGET_DIR/$file_type/$(basename "$file")"
        fi
    fi
    
    # Update counter with lock to prevent race conditions
    flock "$COUNTER_FILE" bash -c "current=\$(cat \"$COUNTER_FILE\" 2>/dev/null || echo 0); echo \$((current + 1)) > \"$COUNTER_FILE\""
}

# Function to check if a file seems corrupted or incomplete
is_valid_file() {
    local file="$1"
    local file_type="$2"
    local file_size=$(stat -c%s "$file")
    
    # Skip tiny files that likely just have fragments
    if [ "$file_size" -lt 50 ]; then
        return 1
    fi
    
    # Check for specific file types if they have expected structure
    case "$file_type" in
        vue|vue-js|vue-ts)
            # Vue file should have at least template, script or style sections
            if ! grep -q "<template\|<script\|<style" "$file"; then
                return 1
            fi
            ;;
        js|ts)
            # JS/TS files should have sensible content, not just random text
            if ! grep -q "function\|const\|let\|var\|import\|export\|class" "$file"; then
                return 1
            fi
            ;;
        java|kotlin|cpp|csharp)
            # These files should have class definitions or imports
            if ! grep -q "class\|import\|package\|namespace\|using" "$file"; then
                return 1
            fi
            ;;
        html)
            # HTML files should have basic structure
            if ! grep -q "<html\|<body\|<head\|<!DOCTYPE" "$file"; then
                return 1
            fi
            ;;
    esac
    
    return 0
}

# Function to detect file signatures and improve naming based on content
detect_file_signature() {
    local file="$1"
    local file_type="$2"
    local filename=$(basename "$file")
    local new_filename=""
    
    # Try to extract name from package/import statements
    case "$file_type" in
        js|ts)
            # Try to extract component name or main export
            local component_name=$(grep -o -m 1 "export\s\+default\s\+class\s\+\([A-Za-z0-9_]\+\)" "$file" | sed 's/.*class\s\+\([A-Za-z0-9_]\+\).*/\1/')
            if [ -z "$component_name" ]; then
                component_name=$(grep -o -m 1 "export\s\+default\s\+function\s\+\([A-Za-z0-9_]\+\)" "$file" | sed 's/.*function\s\+\([A-Za-z0-9_]\+\).*/\1/')
            fi
            if [ -z "$component_name" ]; then
                component_name=$(grep -o -m 1 "class\s\+\([A-Za-z0-9_]\+\)" "$file" | sed 's/.*class\s\+\([A-Za-z0-9_]\+\).*/\1/')
            fi
            if [ -n "$component_name" ]; then
                new_filename="${component_name}.$file_type"
            fi
            ;;
        vue|vue-js|vue-ts)
            # Try to extract component name from script section
            local component_name=$(grep -o -m 1 "name:\s*['\"]\\([A-Za-z0-9_-]\\+\\)['\"]" "$file" | sed "s/.*name:\s*['\"]\\([A-Za-z0-9_-]\\+\\)['\"].*/\\1/")
            if [ -n "$component_name" ]; then
                new_filename="${component_name}.vue"
            fi
            ;;
        java|kotlin)
            # Extract class name
            local class_name=$(grep -o -m 1 "class\s\+\([A-Za-z0-9_]\+\)" "$file" | sed 's/.*class\s\+\([A-Za-z0-9_]\+\).*/\1/')
            if [ -n "$class_name" ]; then
                new_filename="${class_name}.$file_type"
            fi
            ;;
        python)
            # Try to get module name from imports or class definitions
            local class_name=$(grep -o -m 1 "class\s\+\([A-Za-z0-9_]\+\)" "$file" | sed 's/.*class\s\+\([A-Za-z0-9_]\+\).*/\1/')
            if [ -n "$class_name" ]; then
                new_filename="${class_name}.py"
            fi
            ;;
    esac
    
    echo "$new_filename"
}

# Function to attempt to merge file fragments
merge_fragments() {
    local dir="$1"
    local type="$2"
    local output_dir="$dir/merged"
    mkdir -p "$output_dir"
    
    # Only attempt merge for certain file types
    case "$type" in
        vue|vue-js|vue-ts|js|ts|html|css)
            echo "Attempting to merge fragments for $type files..."
            ;;
        *)
            return
            ;;
    esac
    
    case "$type" in
        vue|vue-js|vue-ts)
            # Look for template fragments
            local template_files=$(grep -l "<template" "$dir"/* | sort)
            local script_files=$(grep -l "<script" "$dir"/* | sort)
            local style_files=$(grep -l "<style" "$dir"/* | sort)
            
            # Attempt to reconstruct Vue components from fragments
            if [ -n "$template_files" ] && [ -n "$script_files" ]; then
                local count=1
                for template_file in $template_files; do
                    local template=$(grep -A 1000 "<template" "$template_file" | grep -B 1000 "</template>" | head -n 1000)
                    
                    # Find a matching script section
                    for script_file in $script_files; do
                        local script=$(grep -A 1000 "<script" "$script_file" | grep -B 1000 "</script>" | head -n 1000)
                        
                        # Find a matching style section (optional)
                        local style=""
                        for style_file in $style_files; do
                            style=$(grep -A 1000 "<style" "$style_file" | grep -B 1000 "</style>" | head -n 1000)
                            break  # Just take the first one for now
                        done
                        
                        # Assemble a complete Vue component
                        if [ -n "$template" ] && [ -n "$script" ]; then
                            local merged_file="$output_dir/reconstructed_${count}.vue"
                            cat > "$merged_file" << EOF
$template

$script

${style:-<!-- No style section found -->}
EOF
                            echo "Created merged Vue component: $merged_file"
                            count=$((count + 1))
                            break  # Move to next template
                        fi
                    done
                done
            fi
            ;;
            
        js|ts)
            # Look for files that might be part of the same module
            local files=$(find "$dir" -type f -name "*" | sort)
            local merged=false
            
            # Check for import statements and try to merge related files
            for file in $files; do
                if grep -q "import " "$file"; then
                    local imports=$(grep "import " "$file" | sed -E "s/.*from ['\"](.+)['\"].*/\1/g" | grep -v "^\.\/")
                    
                    if [ -n "$imports" ]; then
                        local merged_file="$output_dir/module_$(basename "$file")"
                        cp "$file" "$merged_file"
                        
                        for imported in $imports; do
                            local imported_files=$(grep -l "$imported" "$dir"/*)
                            if [ -n "$imported_files" ]; then
                                echo "// Imported module: $imported" >> "$merged_file"
                                cat $imported_files >> "$merged_file"
                                echo "// End of imported module: $imported" >> "$merged_file"
                                merged=true
                            fi
                        done
                    fi
                fi
            done
            
            if [ "$merged" = true ]; then
                echo "Created merged JS/TS modules in $output_dir"
            fi
            ;;
            
        html)
            # Try to find HTML fragments that can be combined
            local head_files=$(grep -l "<head" "$dir"/* | sort)
            local body_files=$(grep -l "<body" "$dir"/* | sort)
            
            if [ -n "$head_files" ] && [ -n "$body_files" ]; then
                local count=1
                for head_file in $head_files; do
                    local head=$(grep -A 1000 "<head" "$head_file" | grep -B 1000 "</head>" | head -n 1000)
                    
                    for body_file in $body_files; do
                        local body=$(grep -A 1000 "<body" "$body_file" | grep -B 1000 "</body>" | head -n 1000)
                        
                        if [ -n "$head" ] && [ -n "$body" ]; then
                            local merged_file="$output_dir/reconstructed_${count}.html"
                            cat > "$merged_file" << EOF
<!DOCTYPE html>
<html>
$head
$body
</html>
EOF
                            echo "Created merged HTML file: $merged_file"
                            count=$((count + 1))
                            break
                        fi
                    done
                done
            fi
            ;;
    esac
}

# Add this function for parsing human-readable sizes
parse_size() {
    local input="$1"
    local multiplier=1
    
    # Convert to uppercase for consistency
    input=$(echo "$input" | tr '[:lower:]' '[:upper:]')
    
    # Handle different units (K, M, G, T)
    if [[ "$input" =~ [0-9]+K$ ]]; then
        multiplier=1024
        input="${input%K}"
    elif [[ "$input" =~ [0-9]+M$ ]]; then
        multiplier=$((1024 * 1024))
        input="${input%M}"
    elif [[ "$input" =~ [0-9]+G$ ]]; then
        multiplier=$((1024 * 1024 * 1024))
        input="${input%G}"
    elif [[ "$input" =~ [0-9]+T$ ]]; then
        multiplier=$((1024 * 1024 * 1024 * 1024))
        input="${input%T}"
    fi
    
    # Ensure input is numeric
    if ! [[ "$input" =~ ^[0-9]+$ ]]; then
        echo "Error: Invalid size format. Use a number followed by K, M, G, or T (e.g., 10M)." >&2
        exit 1
    fi
    
    echo $((input * multiplier))
}

# Add auto-preprocessing logic after argument parsing and before main processing
# Do this after the SKIP_SIZE processing
if [[ "$SKIP_SIZE" =~ ^[0-9]+[KMGTkmgt]?$ ]]; then
    SKIP_SIZE=$(parse_size "$SKIP_SIZE")
else
    echo "Error: Invalid size format for --max-size. Use a number followed by K, M, G, or T (e.g., 10M)." >&2
    exit 1
fi

# Function for pre-processing Photorec directories - now accepts a target parameter to support both pre-process and auto-preprocess
preprocess_photorec_dirs() {
    local source_dir="$1"
    local target_dir="$2"
    local exit_after="${3:-true}"  # Default to exit after processing
    
    echo "Pre-processing files for quicker recovery..."
    
    # Create quick classification directories
    mkdir -p "$target_dir/code"
    mkdir -p "$target_dir/media"
    mkdir -p "$target_dir/docs"
    mkdir -p "$target_dir/archives"
    mkdir -p "$target_dir/unknown"
    
    # Count files in source directory for progress tracking
    echo "Counting files in source directory..."
    local preprocess_total=$(find "$source_dir" -type f -size -${SKIP_SIZE}c -print | wc -l)
    preprocess_total=$(( preprocess_total + 0 ))  # Ensure it's a number
    echo "Found $preprocess_total files to pre-process"
    
    # Set up a simple parallel processor with proper integer handling
    echo "0" > "$COUNTER_FILE"
    
    # Start progress display with more robust arithmetic
    (
        while true; do
            # Calculate progress manually with safe integer handling
            local current=$(cat "$COUNTER_FILE" 2>/dev/null || echo "0")
            current=$(( current + 0 ))  # Force to integer
            
            # Avoid division by zero
            if [ "$preprocess_total" -gt 0 ]; then
                local percentage=$(( current * 100 / preprocess_total ))
                local bars=$(( percentage / 2 ))
                
                # Build progress bar safely
                local bar=""
                for ((i=0; i<bars; i++)); do
                    bar="${bar}#"
                done
                
                printf "\r[Pre-processing] [%-50s] %d%% (%d/%d files)" \
                    "$bar" "$percentage" "$current" "$preprocess_total"
            else
                printf "\r[Pre-processing] No files to process"
            fi
            
            if [ "$current" -ge "$preprocess_total" ]; then
                echo ""  # Add final newline
                break
            fi
            
            sleep 0.5
        done
    ) &
    local preprocess_pid=$!
    
    # Get a human-readable size for display
    if [ "$SKIP_SIZE" -ge $((1024*1024*1024)) ]; then
        HR_SIZE="$((SKIP_SIZE / 1024 / 1024 / 1024))G"
    elif [ "$SKIP_SIZE" -ge $((1024*1024)) ]; then
        HR_SIZE="$((SKIP_SIZE / 1024 / 1024))M"
    elif [ "$SKIP_SIZE" -ge 1024 ]; then
        HR_SIZE="$((SKIP_SIZE / 1024))K"
    else
        HR_SIZE="${SKIP_SIZE}B"
    fi
    
    echo "Processing files under ${HR_SIZE} in size..."
    
    # Use file operations based on MOVE_FILES setting
    FILE_OP="cp"
    if [ "$MOVE_FILES" = true ]; then
        FILE_OP="mv"
        echo "Moving files to categorized directories (source will be modified)..."
    else
        echo "Copying files to categorized directories..."
    fi
    
    # Process files in parallel with quick classification and size limit
    # Make sure counter increments are atomic
    find "$source_dir" -type f -size -${SKIP_SIZE}c -print | xargs -P "$PARALLEL_JOBS" -I{} bash -c '
        file="$1"
        
        # Quick file command check
        file_info=$(file -b "$file")
        
        # Basic categorization
        if [[ "$file_info" =~ "text" || "$file_info" =~ "script" || "$file_info" =~ "source" ]]; then
            # Probably code or text
            '"$FILE_OP"' "$file" "'"$target_dir"'/code/$(basename "$file")"
        elif [[ "$file_info" =~ "image" || "$file_info" =~ "video" || "$file_info" =~ "audio" ]]; then
            # Media file
            '"$FILE_OP"' "$file" "'"$target_dir"'/media/$(basename "$file")"
        elif [[ "$file_info" =~ "document" || "$file_info" =~ "PDF" ]]; then
            # Document
            '"$FILE_OP"' "$file" "'"$target_dir"'/docs/$(basename "$file")"
        elif [[ "$file_info" =~ "archive" || "$file_info" =~ "compressed" ]]; then
            # Archive
            '"$FILE_OP"' "$file" "'"$target_dir"'/archives/$(basename "$file")"
        else
            # Unknown
            '"$FILE_OP"' "$file" "'"$target_dir"'/unknown/$(basename "$file")"
        fi
        
        # Update counter with lock to prevent race conditions
        flock "'"$COUNTER_FILE"'" bash -c "current=\$(cat \"'"$COUNTER_FILE"'\" 2>/dev/null || echo 0); echo \$((current + 1)) > \"'"$COUNTER_FILE"'\""
    ' -- {}
    
    # Kill progress process
    kill $preprocess_pid 2>/dev/null
    wait $preprocess_pid 2>/dev/null
    
    echo "Pre-processing complete!"
    
    # Count the categorized files - with safe integer handling
    local code_files=$(find "$target_dir/code" -type f 2>/dev/null | wc -l)
    local media_files=$(find "$target_dir/media" -type f 2>/dev/null | wc -l)
    local doc_files=$(find "$target_dir/docs" -type f 2>/dev/null | wc -l)
    local archive_files=$(find "$target_dir/archives" -type f 2>/dev/null | wc -l)
    local unknown_files=$(find "$target_dir/unknown" -type f 2>/dev/null | wc -l)
    
    # Force to integers
    code_files=$(( code_files + 0 ))
    media_files=$(( media_files + 0 ))
    doc_files=$(( doc_files + 0 ))
    archive_files=$(( archive_files + 0 ))
    unknown_files=$(( unknown_files + 0 ))
    
    echo "Categorized files:"
    echo "- Code files: $code_files"
    echo "- Media files: $media_files"
    echo "- Documents: $doc_files"
    echo "- Archives: $archive_files"
    echo "- Unknown: $unknown_files"
    
    # If we're exiting after preprocessing, show additional info
    if [ "$exit_after" = true ]; then
        echo ""
        echo "You can now run a full analysis on the code files with:"
        echo "$0 -s \"$target_dir/code\" -t \"$TARGET_DIR/sorted_code\" -j $PARALLEL_JOBS"
        exit 0
    else
        # If we're continuing with processing (auto-preprocess), just return
        # to allow the caller to handle next steps
        return 0
    fi
}

# Replace the auto-preprocessing code with a more efficient version that uses the function
if [ "$AUTO_PREPROCESS" = true ] && [ "$PRE_PROCESS" = false ]; then
    echo "Auto-preprocessing enabled, running preliminary categorization..."
    
    # Create temporary target for pre-processing
    PREPROCESS_DIR="$TARGET_DIR/preprocess"
    mkdir -p "$PREPROCESS_DIR"
    
    # Save original source dir and target dir
    ORIGINAL_SOURCE="$SOURCE_DIR"
    ORIGINAL_TARGET="$TARGET_DIR"
    
    # Run pre-processing but don't exit after (false)
    preprocess_photorec_dirs "$ORIGINAL_SOURCE" "$PREPROCESS_DIR" false
    
    # Now process the code directory only
    SOURCE_DIR="$PREPROCESS_DIR/code"
    TARGET_DIR="$ORIGINAL_TARGET"  # Reset to original target for final output
    
    echo "Second phase: Detailed analysis of code files..."
    
    # Count code files to show progress
    CODE_FILE_COUNT=$(find "$SOURCE_DIR" -type f | wc -l)
    echo "Found $CODE_FILE_COUNT code files to analyze in detail."
    
    # Continue with the rest of the script for detailed sorting
fi

# If pre-process flag is set, only do quick categorization (will exit afterwards)
if [ "${PRE_PROCESS:-false}" = true ]; then
    echo "Pre-processing mode activated."
    echo "Will do quick categorization of files instead of full analysis."
    preprocess_photorec_dirs "$SOURCE_DIR" "$TARGET_DIR" true
fi

# Count total files for progress reporting
echo "Counting files in source directory..."
TOTAL_FILES=$(find "$SOURCE_DIR" -type f -print | wc -l)
echo "Total files to process: $TOTAL_FILES"
export TOTAL_FILES

# Process files in parallel with progress tracking
echo "Processing files with $PARALLEL_JOBS parallel jobs..."

# Create a more efficient file list with pre-filtering to improve performance
echo "Preparing file list with pre-filtering..."
FILELIST="$TEMP_DIR/filelist.txt"

# Pre-filter to exclude binary files and files larger than size limit
# Build a list of extension patterns to skip
SKIP_PATTERN=""
IFS=',' read -ra SKIP_EXTS <<< "$SKIP_EXTENSIONS"
for skip_ext in "${SKIP_EXTS[@]}"; do
    if [ -z "$SKIP_PATTERN" ]; then
        SKIP_PATTERN="\.$skip_ext$"
    else
        SKIP_PATTERN="$SKIP_PATTERN|\.$skip_ext$"
    fi
done

if [ -n "$SKIP_PATTERN" ]; then
    # Use find and grep to exclude known binary extensions and large files
    find "$SOURCE_DIR" -type f -size -${SKIP_SIZE}c | grep -v -E "$SKIP_PATTERN" > "$FILELIST"
else
    # Just filter by size if no extensions to skip
    find "$SOURCE_DIR" -type f -size -${SKIP_SIZE}c > "$FILELIST"
fi

# Update the total file count after pre-filtering
TOTAL_FILES=$(wc -l < "$FILELIST")
echo "Pre-filtered file count: $TOTAL_FILES"
echo "0" > "$COUNTER_FILE"  # Reset counter
export TOTAL_FILES

# Start background process to update progress bar
(
    while true; do
        display_progress
        sleep 0.2
        
        # Check if processing is complete
        if [ "$(cat "$COUNTER_FILE")" -ge "$TOTAL_FILES" ]; then
            display_progress
            break
        fi
    done
) &
PROGRESS_PID=$!

# Process files in parallel more efficiently using the pre-filtered list
# Split the file list for better load balancing in multiprocessing
split -n l/$PARALLEL_JOBS "$FILELIST" "$TEMP_DIR/chunk_"

# Process each chunk in parallel
for chunk in "$TEMP_DIR"/chunk_*; do
    (
        while IFS= read -r file; do
            process_file "$file"
        done < "$chunk"
    ) &
done

# Wait for all background jobs to finish
wait

# Kill progress bar process
kill $PROGRESS_PID 2>/dev/null
wait $PROGRESS_PID 2>/dev/null

# Final progress display
display_progress
echo ""

# Process cross-references from hash files
echo "Processing duplicate files to ensure they appear in all relevant directories..."

# Function to process a hash file for cross-references
process_hash_file() {
    local hash_file="$1"
    if [ -f "$hash_file" ]; then
        local file_path=$(head -n 1 "$hash_file")
        local file_name=$(basename "$file_path")
        local types=$(cat "$hash_file" | sort | uniq)
        
        # If this file belongs to multiple types, make sure it's copied to all
        if [ $(wc -l < "$hash_file") -gt 1 ]; then
            for type in $types; do
                if [ -d "$TARGET_DIR/$type" ]; then
                    cp "$SOURCE_DIR/$file_path" "$TARGET_DIR/$type/$file_name" 2>/dev/null
                fi
            done
        fi
    fi
}

export -f process_hash_file
export TARGET_DIR

find "$HASH_DIR" -type f -print | xargs -P "$PARALLEL_JOBS" -I{} bash -c 'process_hash_file "{}"'

# Clean up temporary directory
echo "Cleaning up temporary files..."
rm -rf "$TEMP_DIR"

# Summary of results
echo "File sorting completed!"
echo "Summary of sorted files:"

total_sorted=0
for dir in "$TARGET_DIR"/*; do
    if [ -d "$dir" ]; then
        count=$(find "$dir" -type f | wc -l)
        dir_name=$(basename "$dir")
        if [ "$count" -gt 0 ]; then
            desc="${LANG_DIRS[$dir_name]:-Project files}"
            printf "%-20s: %5d files [%s]\n" "$dir_name" "$count" "$desc"
            total_sorted=$((total_sorted + count))
        fi
    fi
done

echo "--------------------------------------"
echo "Total sorted files: $total_sorted"

# Generate a report file
REPORT_FILE="$TARGET_DIR/recovery_report.html"
echo "Generating report at $REPORT_FILE..."

cat > "$REPORT_FILE" << EOF
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>File Recovery Report</title>
    <style>
        body { font-family: Arial, sans-serif; margin: 20px; line-height: 1.6; }
        h1, h2 { color: #2c3e50; }
        table { border-collapse: collapse; width: 100%; margin-bottom: 20px; }
        th, td { border: 1px solid #ddd; padding: 8px; text-align: left; }
        th { background-color: #f2f2f2; }
        tr:nth-child(even) { background-color: #f9f9f9; }
        .summary { background-color: #e8f4f8; padding: 10px; border-radius: 5px; margin: 20px 0; }
        .highlight { font-weight: bold; color: #3498db; }
        .footer { margin-top: 30px; font-size: 0.8em; color: #7f8c8d; text-align: center; }
    </style>
</head>
<body>
    <h1>Recovered Files Report</h1>
    <div class="summary">
        <p><span class="highlight">Total files processed:</span> $TOTAL_FILES</p>
        <p><span class="highlight">Total files sorted:</span> $total_sorted</p>
        <p><span class="highlight">Recovery completed:</span> $(date)</p>
    </div>
    
    <h2>Files by Type</h2>
    <table>
        <tr>
            <th>Type</th>
            <th>Count</th>
            <th>Description</th>
        </tr>
EOF

# Add rows to the table for each directory
for dir in "$TARGET_DIR"/*; do
    if [ -d "$dir" ]; then
        count=$(find "$dir" -type f | wc -l)
        dir_name=$(basename "$dir")
        if [ "$count" -gt 0 ]; then
            desc="${LANG_DIRS[$dir_name]:-Project files}"
            echo "        <tr>" >> "$REPORT_FILE"
            echo "            <td>$dir_name</td>" >> "$REPORT_FILE"
            echo "            <td>$count</td>" >> "$REPORT_FILE"
            echo "            <td>$desc</td>" >> "$REPORT_FILE"
            echo "        </tr>" >> "$REPORT_FILE"
        fi
    fi
done

# Complete the HTML
cat >> "$REPORT_FILE" << EOF
    </table>
    
    <h2>Recovery Parameters</h2>
    <table>
        <tr><td>Source directory</td><td>$SOURCE_DIR</td></tr>
        <tr><td>Target directory</td><td>$TARGET_DIR</td></tr>
        <tr><td>Parallel jobs</td><td>$PARALLEL_JOBS</td></tr>
        <tr><td>Max file size</td><td>$SKIP_SIZE bytes</td></tr>
    </table>
    
    <div class="footer">
        <p>Generated by enhanced-recover.sh on $(date)</p>
    </div>
</body>
</html>
EOF

echo "Recovery completed! See $REPORT_FILE for details."

# Open the report in a browser if requested
if [ "$OPEN_REPORT" = true ]; then
    if command -v open &> /dev/null; then
        open "$REPORT_FILE"
    elif command -v xdg-open &> /dev/null; then
        xdg-open "$REPORT_FILE"
    else
        echo "Cannot open report automatically. Please open manually: $REPORT_FILE"
    fi
fi

# Replace the interactive file renaming part with non-interactive version
if [ "$RENAME_FILES" = true ]; then
    echo "Renaming files with their proper extensions..."
    
    for dir in "$TARGET_DIR"/*; do
        if [ -d "$dir" ]; then
            dir_name=$(basename "$dir")
            case "$dir_name" in
                js|ts|jsx|tsx|vue|vue-js|vue-ts|html|css|scss|less|sass|php|java|kotlin|scala|groovy|python|ruby|go|rust|csharp|fsharp|perl|c|cpp|swift|objective-c|bash|shell|powershell|batch|json|yaml|toml|xml|ini|env|properties|csv|md|txt|rst|latex|sql|graphql)
                    echo "Renaming files in $dir_name directory..."
                    find "$dir" -type f | while read -r file; do
                        new_name="${file%.*}.$dir_name"
                        mv "$file" "$new_name"
                    done
                    ;;
            esac
        fi
    done
    
    echo "Files renamed successfully!"
fi

# Replace the interactive intelligent naming part with non-interactive version
if [ "$INTELLIGENT_NAMING" = true ]; then
    echo "Analyzing files for intelligent naming..."
    
    for dir in "$TARGET_DIR"/*; do
        if [ -d "$dir" ]; then
            dir_name=$(basename "$dir")
            find "$dir" -type f | while read -r file; do
                # Try to detect a better name based on content
                new_name=$(detect_file_signature "$file" "$dir_name")
                
                if [ -n "$new_name" ]; then
                    # Make sure there are no duplicates by adding a suffix if needed
                    if [ -f "$dir/$new_name" ]; then
                        suffix=1
                        while [ -f "$dir/${new_name%.*}_$suffix.${new_name##*.}" ]; do
                            ((suffix++))
                        done
                        new_name="${new_name%.*}_$suffix.${new_name##*.}"
                    fi
                    
                    # Rename the file with the detected name
                    mv "$file" "$dir/$new_name"
                    echo "Renamed: $(basename "$file") -> $new_name"
                fi
            done
        fi
    done
    
    echo "Intelligent file naming completed!"
fi

# Replace the interactive fragment merging part with non-interactive version
if [ "$MERGE_FRAGMENTS" = true ]; then
    echo "Validating files and attempting to merge fragments..."
    
    for dir in "$TARGET_DIR"/*; do
        if [ -d "$dir" ]; then
            dir_name=$(basename "$dir")
            
            # Create a directory for invalid/corrupted files
            mkdir -p "$dir/fragments"
            
            # Move corrupted/invalid files to fragments directory
            find "$dir" -maxdepth 1 -type f | while read -r file; do
                if ! is_valid_file "$file" "$dir_name"; then
                    mv "$file" "$dir/fragments/$(basename "$file")"
                fi
            done
            
            # Try to merge fragments
            merge_fragments "$dir" "$dir_name"
        fi
    done
    
    echo "File validation and fragment merging completed!"
fi

# Export the additional environment variables
export -f process_file get_extension should_skip_extension should_skip_size is_duplicate check_project_match identify_file_type update_counter detect_file_signature is_valid_file merge_fragments parse_size
export SOURCE_DIR TARGET_DIR PROJECT_NAMES HASH_DIR COUNTER_FILE SKIP_EXTENSIONS SKIP_SIZE RENAME_FILES INTELLIGENT_NAMING MERGE_FRAGMENTS MOVE_FILES