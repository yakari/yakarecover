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
    tput cnorm     # Show cursor 
    tput sgr0      # Reset all attributes
    echo -e "\033[?25h"  # Show cursor (alternative method)
    echo -e "\033[0m"    # Reset terminal colors
    
    # Move to bottom of screen to ensure prompt is at a clean position
    tput cup $(tput lines) 0
    tput el
    tput cuu1
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
    
    # Calculate percentage
    local percentage=0
    if [ "$TOTAL_FILES" -gt 0 ]; then
        percentage=$(( current * 100 / TOTAL_FILES ))
    fi
    
    # Save current percentage
    echo "$percentage" > "$PROGRESS_FILE"
    
    # Save cursor position, move to bottom line, clear line, display progress
    tput sc                # Save cursor position
    tput cup $(tput lines) 0  # Move cursor to bottom of screen
    tput el                # Clear line
    
    # Display progress with consistent formatting
    printf "[Progress] %d%% (%d/%d files)" "$percentage" "$current" "$TOTAL_FILES"
    
    # Return to original cursor position
    tput rc                # Restore cursor position
    
    # If complete, move to bottom, clear line, show final message and move back up
    if [ "$percentage" -eq 100 ]; then
        tput cup $(tput lines) 0  # Move to bottom
        tput el                # Clear line
        printf "[Progress] 100%% Complete!   "
        tput cuu1              # Move up one line
        echo -ne "\033[?25h"   # Show cursor
    fi
}

# Function to check if file matches project names
check_project_match() {
    local file="$1"
    
    # Skip if file doesn't exist
    if [ ! -f "$file" ]; then
        return 1
    }
    
    if [ -z "$PROJECT_NAMES" ]; then
        return 1  # No project names specified
    fi
    
    IFS=',' read -ra PROJECTS <<< "$PROJECT_NAMES"
    for project in "${PROJECTS[@]}"; do
        if grep_check "$file" "$project"; then
            # Create project directory if it doesn't exist
            mkdir -p "$TARGET_DIR/$project"
            
            if ! is_duplicate "$file" "$project"; then
                if [ "$MOVE_FILES" = true ]; then
                    mv "$file" "$TARGET_DIR/$project/$(basename "$file")" 2>/dev/null || 
                        cp "$file" "$TARGET_DIR/$project/$(basename "$file")" 2>/dev/null || 
                        echo "Warning: Could not move file $file to project $project" >&2
                else
                    cp "$file" "$TARGET_DIR/$project/$(basename "$file")" 2>/dev/null || 
                        echo "Warning: Could not copy file $file to project $project" >&2
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
    local extension=$(get_extension "$file")
    local file_type=""
    
    # First check existing extension for known types (prioritize standard extensions)
    case "$extension" in
        js|jsx|ts|tsx|vue|java|py|c|cpp|h|hpp|cs|rb|php|go|rs|swift|kt|scala)
            # If it has a known extension, verify it with content analysis
            file_type="$extension"
            ;;
        *)
            # If no known extension, examine content
            file_type="unknown"
            ;;
    esac
    
    # For extensions that don't match known types or are unknown, examine content
    if [ "$file_type" = "unknown" ]; then
        # Get a sample of file content
        local content_sample=$(head -n 50 "$file" 2>/dev/null)
        
        # Check for specific file signatures in content, from most specific to most general
        
        # Python detection
        if grep -q "^import \|^from .* import \|def \|class \|if __name__ == ['\"]__main__['\"]:" <<< "$content_sample"; then
            file_type="python"
            
        # Java detection
        elif grep -q "public class\|class .* extends\|interface .* \|@Override\|import java\." <<< "$content_sample"; then
            file_type="java"
            
        # C/C++ detection
        elif grep -q "#include <\|^int main(\|void main(\|struct \|typedef \|#ifndef\|#define\|#pragma once" <<< "$content_sample"; then
            if grep -q "std::\|namespace\|template <\|class .* {\|vector<" <<< "$content_sample"; then
                file_type="cpp"
            else
                file_type="c"
            fi
            
        # Vue component (must check before generic JS because Vue files contain JS)
        elif grep -q "<template>\|export default {" <<< "$content_sample" && grep -q "<script>\|<style>" <<< "$content_sample"; then
            # Detect if Vue component uses TypeScript
            if grep -q "<script lang=\"ts\">\|<script lang='ts'>" <<< "$content_sample"; then
                file_type="vue-ts"
            else
                file_type="vue-js"
            fi
            
        # React JSX/TSX detection (enhanced)
        elif grep -q "import React\|React\." <<< "$content_sample" || grep -q "from ['\"]react['\"]" <<< "$content_sample" || grep -q "React\.Component" <<< "$content_sample" || grep -q "useState\|useEffect\|useContext" <<< "$content_sample"; then
            if grep -q ":\s*\(string\|number\|boolean\|any\|React\.\)\|interface\s\|type\s" <<< "$content_sample" || grep -q "<.*>\(" <<< "$content_sample"; then
                file_type="tsx"
            else
                file_type="jsx"
            fi
            
        # TypeScript detection
        elif grep -q "interface \|type \|:\s*\(string\|number\|boolean\|any\)\|class .* implements" <<< "$content_sample"; then
            file_type="ts"
            
        # JavaScript detection
        elif grep -q "function\|const\|let\|var\|import\|export\|=>\|module\.exports\|require(" <<< "$content_sample"; then
            file_type="js"
            
        # HTML detection
        elif grep -q "<!DOCTYPE html>\|<html>\|<head>\|<body>\|<div>\|<script>" <<< "$content_sample"; then
            file_type="html"
            
        # CSS detection
        elif grep -q "{\s*\(color\|background\|font-size\|margin\|padding\)" <<< "$content_sample"; then
            file_type="css"
            
        # Default to text if we couldn't determine
        else
            file_type="text"
        fi
    else
        # Additional verification for files with known extensions
        
        # For Vue files, verify they're actually Vue components
        if [ "$file_type" = "vue" ]; then
            if ! grep -q "<template>\|<script>\|<style>" "$file"; then
                # This isn't a Vue component, reclassify
                local new_type=$(identify_file_type_without_extension "$file")
                if [ -n "$new_type" ]; then
                    file_type="$new_type"
                fi
            fi
        fi
        
        # Verify TypeScript files
        if [ "$file_type" = "ts" ] || [ "$file_type" = "tsx" ]; then
            if ! grep -q ":\s*\(string\|number\|boolean\|any\)\|interface\s\|type\s" "$file"; then
                # This might not be TypeScript, reclassify
                if [ "$file_type" = "tsx" ]; then
                    file_type="jsx"
                else
                    file_type="js"
                fi
            fi
        fi
    fi
    
    echo "$file_type"
}

# Helper function to identify without using extension
identify_file_type_without_extension() {
    local file="$1"
    local file_type="unknown"
    
    # Get a sample of file content
    local content_sample=$(head -n 50 "$file" 2>/dev/null)
    
    # Python detection (strongest indicators first)
    if grep -q "^import \|^from .* import \|def \|class \|if __name__ == ['\"]__main__['\"]:" <<< "$content_sample"; then
        file_type="python"
        
    # Java detection
    elif grep -q "public class\|class .* extends\|interface .* \|@Override\|import java\." <<< "$content_sample"; then
        file_type="java"
        
    # C/C++ detection
    elif grep -q "#include <\|^int main(\|void main(\|struct \|typedef \|#ifndef\|#define\|#pragma once" <<< "$content_sample"; then
        if grep -q "std::\|namespace\|template <\|class .* {\|vector<" <<< "$content_sample"; then
            file_type="cpp"
        else
            file_type="c"
        fi
        
    # Vue component (must check before generic JS because Vue files contain JS)
    elif grep -q "<template>\|export default {" <<< "$content_sample" && grep -q "<script>\|<style>" <<< "$content_sample"; then
        # Detect if Vue component uses TypeScript
        if grep -q "<script lang=\"ts\">\|<script lang='ts'>" <<< "$content_sample"; then
            file_type="vue-ts"
        else
            file_type="vue-js"
        fi
        
    # React JSX/TSX detection
    elif grep -q "import React\|React\." <<< "$content_sample" || grep -q "from ['\"]react['\"]" <<< "$content_sample" || grep -q "React\.Component" <<< "$content_sample"; then
        if grep -q ":\s*\(string\|number\|boolean\|any\|React\.\)\|interface\s\|type\s" <<< "$content_sample"; then
            file_type="tsx"
        else
            file_type="jsx"
        fi
        
    # TypeScript detection
    elif grep -q "interface \|type \|:\s*\(string\|number\|boolean\|any\)\|class .* implements" <<< "$content_sample"; then
        file_type="ts"
        
    # JavaScript detection
    elif grep -q "function\|const\|let\|var\|import\|export\|=>\|module\.exports\|require(" <<< "$content_sample"; then
        file_type="js"
        
    # HTML detection
    elif grep -q "<!DOCTYPE html>\|<html>\|<head>\|<body>\|<div>\|<script>" <<< "$content_sample"; then
        file_type="html"
        
    # CSS detection
    elif grep -q "{\s*\(color\|background\|font-size\|margin\|padding\)" <<< "$content_sample"; then
        file_type="css"
        
    # Default to text if we couldn't determine
    else
        file_type="text"
    fi
    
    echo "$file_type"
}

# Function to process a single file
process_file() {
    local file="$1"
    
    # First check if file exists
    if [ ! -f "$file" ]; then
        # Silently skip missing files and update counter
        { flock "$COUNTER_FILE" sh -c "current=\$(cat \"$COUNTER_FILE\" 2>/dev/null || echo 0); echo \$((current + 1)) > \"$COUNTER_FILE\""; } 2>/dev/null
        return
    }
    
    # Skip based on extension or size
    if should_skip_extension "$file" || should_skip_size "$file"; then
        # Update counter with safer approach
        { flock "$COUNTER_FILE" sh -c "current=\$(cat \"$COUNTER_FILE\" 2>/dev/null || echo 0); echo \$((current + 1)) > \"$COUNTER_FILE\""; } 2>/dev/null
        return
    fi
    
    # Check for project name matches first (high priority)
    if check_project_match "$file"; then
        # Update counter with safer approach
        { flock "$COUNTER_FILE" sh -c "current=\$(cat \"$COUNTER_FILE\" 2>/dev/null || echo 0); echo \$((current + 1)) > \"$COUNTER_FILE\""; } 2>/dev/null
        return
    fi
    
    # Identify file type
    local file_type=$(identify_file_type "$file")
    
    # Make sure target directory exists
    mkdir -p "$TARGET_DIR/$file_type"
    
    # Copy/move file to appropriate directory if not a duplicate
    if ! is_duplicate "$file" "$file_type"; then
        if [ "$MOVE_FILES" = true ]; then
            mv "$file" "$TARGET_DIR/$file_type/$(basename "$file")" 2>/dev/null || 
                cp "$file" "$TARGET_DIR/$file_type/$(basename "$file")" 2>/dev/null || 
                echo "Warning: Could not process file $file" >&2
        else
            cp "$file" "$TARGET_DIR/$file_type/$(basename "$file")" 2>/dev/null || 
                echo "Warning: Could not copy file $file" >&2
        fi
    fi
    
    # Update counter with safer approach
    { flock "$COUNTER_FILE" sh -c "current=\$(cat \"$COUNTER_FILE\" 2>/dev/null || echo 0); echo \$((current + 1)) > \"$COUNTER_FILE\""; } 2>/dev/null
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
    
    # Set up a counter file for progress
    echo "0" > "$COUNTER_FILE"
    
    # Start progress display with persistent positioning
    (
        while true; do
            # Calculate progress manually with safe integer handling
            local current=$(cat "$COUNTER_FILE" 2>/dev/null || echo "0")
            current=$(( current + 0 ))  # Force to integer
            
            # Avoid division by zero
            if [ "$preprocess_total" -gt 0 ]; then
                local percentage=$(( current * 100 / preprocess_total ))
                
                # Position at bottom of screen for persistent display
                tput sc                # Save cursor position
                tput cup $(tput lines) 0  # Move cursor to bottom of screen
                tput el                # Clear line
                
                # Display progress
                printf "[Pre-processing] %d%% (%d/%d files)" \
                    "$percentage" "$current" "$preprocess_total"
                
                # Return to original position
                tput rc                # Restore cursor position
            fi
            
            if [ "$current" -ge "$preprocess_total" ]; then
                # Final progress display
                tput sc
                tput cup $(tput lines) 0
                tput el
                printf "[Pre-processing] 100%% Complete!"
                tput rc
                break
            fi
            
            sleep 0.5
        done
    ) &
    local preprocess_pid=$!
    
    # Process files in parallel with quick classification and size limit
    # Using a more robust approach without backreferences in grep
    find "$source_dir" -type f -size -${SKIP_SIZE}c -print | xargs -P "$PARALLEL_JOBS" -I{} bash -c '
        file="$1"
        
        # Quick file command check without complex regex
        file_info=$(file -b "$file")
        
        # Basic categorization with safer pattern matching
        if echo "$file_info" | grep -q "text\|script\|source"; then
            # Probably code or text
            '"$FILE_OP"' "$file" "'"$target_dir"'/code/$(basename "$file")"
        elif echo "$file_info" | grep -q "image\|video\|audio"; then
            # Media file
            '"$FILE_OP"' "$file" "'"$target_dir"'/media/$(basename "$file")"
        elif echo "$file_info" | grep -q "document\|PDF"; then
            # Document
            '"$FILE_OP"' "$file" "'"$target_dir"'/docs/$(basename "$file")"
        elif echo "$file_info" | grep -q "archive\|compressed"; then
            # Archive
            '"$FILE_OP"' "$file" "'"$target_dir"'/archives/$(basename "$file")"
        else
            # Unknown
            '"$FILE_OP"' "$file" "'"$target_dir"'/unknown/$(basename "$file")"
        fi
        
        # Atomic counter update with proper error redirection
        { flock "$COUNTER_FILE" sh -c "current=\$(cat \"$COUNTER_FILE\" 2>/dev/null || echo 0); echo \$((current + 1)) > \"$COUNTER_FILE\""; } 2>/dev/null
    ' -- {}
    
    # Kill progress process
    kill $preprocess_pid 2>/dev/null
    wait $preprocess_pid 2>/dev/null
    
    # Move cursor to bottom and back up one line for clean output
    tput cup $(tput lines) 0
    tput el
    tput cuu1
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

touch "$FILELIST"  # Ensure the file exists even if no files found

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

# Find files and check that they exist before adding to the list
if [ -n "$SKIP_PATTERN" ]; then
    # Use find and grep to exclude known binary extensions and large files
    find "$SOURCE_DIR" -type f -size -${SKIP_SIZE}c 2>/dev/null | grep -v -E "$SKIP_PATTERN" | while read -r f; do
        if [ -f "$f" ]; then echo "$f" >> "$FILELIST"; fi
    done
else
    # Just filter by size if no extensions to skip
    find "$SOURCE_DIR" -type f -size -${SKIP_SIZE}c 2>/dev/null | while read -r f; do
        if [ -f "$f" ]; then echo "$f" >> "$FILELIST"; fi
    done
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
            find "$dir" -type f 2>/dev/null | while read -r file; do
                # Skip if file doesn't exist (it might have been moved)
                if [ ! -f "$file" ]; then
                    continue
                fi
                
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
                    mv "$file" "$dir/$new_name" 2>/dev/null && echo "Renamed: $(basename "$file") -> $new_name"
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

# Move the detect_file_signature function before the EXPORT line
detect_file_signature() {
    local file="$1"
    local file_type="$2"
    local filename=$(basename "$file")
    local new_filename=""
    
    # Skip if file doesn't exist
    if [ ! -f "$file" ]; then
        return
    }
    
    # Try to extract name from package/import statements - using safer grep patterns
    case "$file_type" in
        js|ts)
            # Try to extract component name or main export
            local component_name=$(grep -m 1 "export.*default.*class" "$file" | grep -o "class [A-Za-z0-9_]*" | sed 's/class //')
            if [ -z "$component_name" ]; then
                component_name=$(grep -m 1 "export.*default.*function" "$file" | grep -o "function [A-Za-z0-9_]*" | sed 's/function //')
            fi
            if [ -z "$component_name" ]; then
                component_name=$(grep -m 1 "class [A-Za-z0-9_]" "$file" | grep -o "class [A-Za-z0-9_]*" | sed 's/class //')
            fi
            if [ -n "$component_name" ]; then
                new_filename="${component_name}.$file_type"
            fi
            ;;
        vue|vue-js|vue-ts)
            # Try to extract component name from script section using grep with safer patterns
            local component_name=$(grep -m 1 "name:" "$file" | grep -o "name:.*['\"]\w*['\"]" | sed "s/name:[ ]*['\"]//g" | sed "s/['\"]//g")
            if [ -n "$component_name" ]; then
                new_filename="${component_name}.vue"
            fi
            ;;
        java|kotlin)
            # Extract class name with safer grep patterns
            local class_name=$(grep -m 1 "class " "$file" | grep -o "class [A-Za-z0-9_]*" | sed 's/class //')
            if [ -n "$class_name" ]; then
                new_filename="${class_name}.$file_type"
            fi
            ;;
        python)
            # Try to get module name from imports or class definitions
            local class_name=$(grep -m 1 "class " "$file" | grep -o "class [A-Za-z0-9_]*" | sed 's/class //')
            if [ -n "$class_name" ]; then
                new_filename="${class_name}.py"
            fi
            ;;
    esac
    
    echo "$new_filename"
}

# Update the export line to ensure detect_file_signature is properly exported
export -f process_file get_extension should_skip_extension should_skip_size is_duplicate check_project_match identify_file_type update_counter is_valid_file merge_fragments parse_size detect_file_signature

# Export the additional environment variables
export SOURCE_DIR TARGET_DIR PROJECT_NAMES HASH_DIR COUNTER_FILE SKIP_EXTENSIONS SKIP_SIZE RENAME_FILES INTELLIGENT_NAMING MERGE_FRAGMENTS MOVE_FILES