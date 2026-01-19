# Scripts

<div align="center">
    <strong>English</strong> | <a href="./README.zh-Hans.md"><strong>简体中文</strong></a>
</div>
<br/>

This directory contains build and development scripts for the project.

## build-docc.sh

Script for building DocC documentation with multi-language support.

### Quick Start

```bash
# Build all languages
./scripts/build-docc.sh --all

# Start local preview server
python3 -m http.server 8000 --directory .build/docs

# Open in browser: http://localhost:8000/documentation/service/
```

### Available Options

| Option | Description |
|--------|-------------|
| `--all` | Build all languages and combine output |
| `--lang <lang>` | Build a single language (e.g., `en`, `zh-Hans`) |
| `--output <path>` | Custom output directory |
| `--skip-build` | Skip compilation, reuse existing symbol graphs |
| `-h, --help` | Show help message |

### Examples

```bash
# Quick iteration: regenerate docs without recompiling
./scripts/build-docc.sh --all --skip-build

# Build single language
./scripts/build-docc.sh --lang zh-Hans

# Custom output directory
./scripts/build-docc.sh --all --output ./docs
```
