# 🛠️ yakarecover: Dev File Recovery & Sorting Tool

## ⚠️ WARNING - FOR POWER USERS ONLY ⚠️

This script is intended for **experienced users** who understand file system operations and command-line tools. It performs potentially destructive operations:

- When using the `--move` option, files are **permanently moved** from their source location
- The script operates on large numbers of files with high parallelism, which can stress your system
- No warranty is provided - use at your own risk
- Always work on a copy of your recovered data, never the original

## Purpose

`recover-code.sh` is an advanced sorting tool designed to help recover and organize code files after using PhotoRec or similar file recovery tools. It automatically identifies, categorizes, and sorts recovered files by type, with special emphasis on modern web development files (JS, TS, Vue, React, etc.).

## Features

- **Intelligent file type detection**: Identifies code files by analyzing content signatures
- **Two-phase processing**: Optional pre-processing to separate code from media/documents
- **High performance**: Parallel processing with configurable job count
- **Move option**: Faster operation with `--move` instead of copying files
- **Project matching**: Prioritize files matching specific project names
- **Intelligent naming**: Attempts to restore proper file names based on content
- **Fragment handling**: Optional merging of file fragments
- **Progress tracking**: Visual progress display during long operations
- **HTML report**: Generates a summary report of recovered files

## Requirements

- Bash shell environment
- Core utilities: `grep`, `find`, `xargs`, `flock` (for atomic operations)
- Developed and tested on macOS and Linux

## Usage

### Basic Usage

```bash
./recover-code.sh -s /path/to/photorec/recup_dir -t /path/to/output/dir
```

### Recommended Usage for Large Sets (2M+ files)

```bash
# Two-phase approach with move instead of copy (faster, but modifies source)
./recover-code.sh -s /path/to/photorec -t /path/to/sorted --auto-preprocess --move -j 16 -m 2M
```

### For Project-Specific Recovery

```bash
# Prioritize files matching specific project names
./recover-code.sh -s /path/to/source -t /path/to/output -p "myproject,otherproject" --move -j 16
```

## Options

| Option | Description |
|--------|-------------|
| `-s, --source` | Directory containing recovered files |
| `-t, --target` | Target directory for sorted files |
| `-p, --projects` | Comma-separated list of project names to prioritize |
| `-j, --jobs` | Number of parallel jobs (default: 4) |
| `-e, --skip-extensions` | Comma-separated list of extensions to skip |
| `-m, --max-size` | Skip files larger than this size (e.g., 10M, 1G, 500K) (default: 10MB) |
| `--rename, --no-rename` | Enable/disable renaming with proper extensions (default: enabled) |
| `--intelligent-naming, --no-intelligent-naming` | Enable/disable intelligent file naming (default: enabled) |
| `--merge-fragments, --no-merge-fragments` | Enable/disable merging file fragments (default: disabled) |
| `--move` | Move files instead of copying (faster, modifies source directory) |
| `--auto-preprocess` | Automatically pre-process files before detailed sorting |
| `--pre-process` | Only pre-process PhotoRec directories (faster initial sorting) |
| `--open-report` | Open the HTML report when completed |
| `--help` | Show this help message |

## Performance Tips

1. **Use SSD storage** for both source and target when possible
2. **Adjust `--jobs`** based on your CPU cores (typically # of cores × 2)
3. **Use `--move`** instead of copying for 2-3× faster operation
4. **Use `--auto-preprocess`** for large file sets to quickly filter non-code files
5. **Set appropriate `--max-size`** to skip large binary files (2-10MB recommended)

## Workflow for Massive Recovery (2M+ files)

1. Run PhotoRec to recover files to a dedicated partition/drive
2. Run the script with `--auto-preprocess` and `--move` options:
   ```bash
   ./recover-code.sh -s /photorec/recup_dir -t /output/dir --auto-preprocess --move -j 16 -m 2M
   ```
3. Review the code files in the sorted directories
4. Use the generated HTML report to see file type distribution

## Interpreting Results

After processing, files will be organized into directories by type:
- Language-specific directories (js, ts, vue, python, java, etc.)
- Project-specific directories (if using the `-p` option)
- Media files (if using `--auto-preprocess`)

## Limitations

- Not intended for binary file recovery (focus is on text/code files)
- May misidentify some file types with ambiguous signatures
- Performance depends on I/O capabilities of your system
- Not suitable for files requiring forensic preservation (uses move operations)

## Support

This is a specialized tool for power users. No formal support is provided.

## License

MIT License - Use at your own risk.

---

## 🔍 Use Case
After accidentally deleting a project, you can use PhotoRec to recover raw data. Then, use `recover-code.sh` to identify and sort the recovered files by language or tech.

---

## 📦 Step 1: Recover with PhotoRec

### 1. Install PhotoRec
```bash
sudo apt install testdisk    # Debian/Ubuntu
sudo pacman -S testdisk      # Arch/Manjaro
brew install testdisk        # macOS with Homebrew
```

### 2. Run PhotoRec
```bash
sudo photorec
```
- Select the correct disk
- Choose the partition
- Opt to recover from free space
- Choose an output location (e.g. a new directory like `recovered_photorec`)
- PhotoRec will create multiple folders named `recup_dir.1`, `recup_dir.2`, etc.
- Optional: Filter file types to only text/code formats

---

## 🧠 Step 2: Run recover-code.sh

### 📥 Quick Two-Phase Recovery
```bash
./recover-code.sh -s /path/to/recup_dirs -t /path/to/output --auto-preprocess --move -j 16
```

This will:
1. Pre-process files to quickly separate code from media/documents
2. Analyze code files in detail to identify specific languages
3. Move files to organized directories by type
4. Use 16 parallel processes for maximum speed

---

## 🧠 Supported File Types

The script detects and categorizes a wide range of file types:

### Web Development:
- JavaScript, TypeScript, JSX, TSX
- Vue (with both JS and TS variants)
- HTML, CSS

### Programming Languages:
- Python
- Java, Kotlin
- C, C++
- And many others detected based on content signatures

### Data & Config:
- JSON, YAML, TOML
- Various config file formats

### Other Categories (with --auto-preprocess):
- Media files (images, audio, video)
- Documents (PDFs, text docs)
- Archives (compressed files)

---

## ✅ Output
- Recovered files sorted into folders by type
- HTML report with statistics (when enabled)
- Automatic deduplication to prevent recovering the same file multiple times

---

## 💡 Tips
- For huge recoveries (millions of files), always use the `--auto-preprocess` and `--move` options
- Set a reasonable `--max-size` limit (2-10MB) to avoid processing large binary files
- Adjust the `-j` parameter based on your CPU's capabilities
- Use `--pre-process` alone for initial quick sorting, then run detailed analysis on just the code files

---

## 🧑‍💻 License
MIT License

