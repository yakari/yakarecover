# 🛠️ yakarecover: Dev File Recovery & Sorting Tool

`recover-code.sh` is a script designed to help developers recover and sort source code from data recovery tools like [PhotoRec](https://www.cgsecurity.org/wiki/PhotoRec). It detects a wide range of programming languages, build tools, and config files, and organizes them into a structured folder.

---

## 🔍 Use Case
After accidentally deleting a project, you can use PhotoRec to recover raw data. Then, use `recover-code.sh` to identify and sort the recovered files by language or tech.

---

## 📦 Step 1: Recover with PhotoRec

### 1. Install PhotoRec
```bash
sudo apt install testdisk    # Debian/Ubuntu
sudo pacman -S testdisk      # Arch/Manjaro
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

### 📥 Basic usage
```bash
./recover-code.sh
```
This scans all folders matching `recup_dir.*`, detects language types, and saves results to `./recovered_code/`

---

## ⚙️ Options

### `--project NAME`
Prioritizes files containing the specified keyword (e.g. project name)
> Short form: `-p`

### `--filter TYPES`
Comma-separated list of types to detect (e.g. `ts,vue,py,json`)
> Short form: `-f`

### `--output-dir DIR`
Specify the destination folder (default: `./recovered_code`)
> Short form: `-o`

### `--lines NUM`
Number of lines to scan from each file for improved matching
> Short form: `-l`

### `--size SIZE`
Skip files above a given size (e.g. `100000`, `100k`, `10m`, etc.)
> Short form: `-s`

### `--zip`
Compress the final result into a `.zip` archive

### `--open-vscode`
Open the destination folder in VS Code

### `--help`
Show this help message
> Short form: `-h`

---

## 🧠 Supported File Types

### Languages:
- TypeScript, JavaScript, HTML, CSS, Vue
- Python, Shell, Perl, SQL
- Java, Kotlin, Gradle, Maven, Ant
- C, C++, Makefile
- Rust, Go, Dart, Swift, Elixir

### Formats:
- Markdown, YAML, JSON, .env
- Build tools, Docker, configs

---

## ✅ Output
- Recovered files sorted into folders by type
- `sorting_log.txt` with detailed logs
- `sorting_summary.csv` with stats & keywords

---

## 💡 Tips
- Start small: filter to 2–3 types if you have lots of files
- Use the `--size` filter to exclude large binaries or assets
- Pair with `grep`, `fzf`, or VS Code search to locate files quickly

---

## 🧑‍💻 License & Contributions
Apache 2 licensed. PRs welcome!

### GitHub Repo
https://github.com/yakari/yakarecover

