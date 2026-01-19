#!/bin/bash
#
# Build DocC documentation for one or all languages.
# Used by both local development and GitHub Actions.
#
# Usage:
#   ./scripts/build-docc.sh [options]
#
# Options:
#   --all                   Build all languages and combine into single output
#   --lang <lang>           Build single language (e.g., en, zh-Hans)
#   --output <path>         Output directory (default: .build/docs or .build/docs-<lang>)
#   --skip-build            Skip swift build (reuse existing symbol graphs)
#   -h, --help              Show this help message
#
# Environment:
#   Automatically detects CI (GitHub Actions) vs local environment.
#   - Local: builds for direct preview (no base path)
#   - CI: builds for GitHub Pages (with repository base path)
#
# Examples:
#   ./scripts/build-docc.sh --all                  # Build all languages
#   ./scripts/build-docc.sh --lang en              # Build English only
#   ./scripts/build-docc.sh --all --skip-build     # Rebuild without recompiling
#

set -euo pipefail

# Default values
LANG=""
BUILD_ALL=false
DEFAULT_LANG="en"
LANGS_JSON='["en","zh-Hans"]'
TARGET="Service"
DOCC_CATALOG="Sources/Service/Documentation.docc"
HOSTING_BASE_PATH="swift-service"
OUTPUT=""
GA_ID=""
SKIP_BUILD=false

# Auto-detect environment: local mode if not in CI
if [[ -z "${GITHUB_ACTIONS:-}" ]]; then
  HOSTING_BASE_PATH=""
fi

# Parse arguments
while [[ $# -gt 0 ]]; do
  case $1 in
    --lang)
      LANG="$2"
      shift 2
      ;;
    --all)
      BUILD_ALL=true
      shift
      ;;
    --default-lang)
      DEFAULT_LANG="$2"
      shift 2
      ;;
    --langs)
      LANGS_JSON="$2"
      shift 2
      ;;
    --target)
      TARGET="$2"
      shift 2
      ;;
    --docc-catalog)
      DOCC_CATALOG="$2"
      shift 2
      ;;
    --hosting-base-path)
      HOSTING_BASE_PATH="$2"
      shift 2
      ;;
    --output)
      OUTPUT="$2"
      shift 2
      ;;
    --ga-id)
      GA_ID="$2"
      shift 2
      ;;
    --skip-build)
      SKIP_BUILD=true
      shift
      ;;
    -h|--help)
      head -27 "$0" | tail -26
      exit 0
      ;;
    *)
      echo "Unknown option: $1" >&2
      exit 1
      ;;
  esac
done

# Parse languages from JSON
LANG_LIST=$(echo "$LANGS_JSON" | tr -d '[]"' | tr ',' ' ')

# Validate arguments
if [[ "$BUILD_ALL" == "false" && -z "$LANG" ]]; then
  echo "Error: Must specify --lang <lang> or --all" >&2
  exit 1
fi

if [[ "$BUILD_ALL" == "true" && -n "$LANG" ]]; then
  echo "Error: Cannot use both --lang and --all" >&2
  exit 1
fi

if [[ -n "$LANG" ]]; then
  valid_lang=false
  for l in $LANG_LIST; do
    if [[ "$l" == "$LANG" ]]; then
      valid_lang=true
      break
    fi
  done
  if [[ "$valid_lang" != "true" ]]; then
    echo "Error: Invalid language '$LANG'. Supported: $LANG_LIST" >&2
    exit 1
  fi
fi

# Find docc command
find_docc() {
  if command -v docc &>/dev/null; then
    echo "docc"
  elif xcrun --find docc &>/dev/null 2>&1; then
    xcrun --find docc
  else
    local swift_bin_dir
    swift_bin_dir="$(dirname "$(which swift)")"
    if [[ -x "$swift_bin_dir/docc" ]]; then
      echo "$swift_bin_dir/docc"
    else
      echo "Error: docc not found" >&2
      exit 1
    fi
  fi
}

DOCC_CMD=$(find_docc)
echo "Using docc: $DOCC_CMD"

# Generate symbol graph (unless skipped)
generate_symbol_graph() {
  if [[ "$SKIP_BUILD" != "true" ]]; then
    echo ""
    echo "Swift version: $(swift --version | head -1)"
    echo "Generating symbol graph..."

    if ! swift package dump-symbol-graph --minimum-access-level public 2>&1; then
      echo "Error: Failed to generate symbol graph" >&2
      exit 1
    fi

    # Find the symbol graph directory
    SYMBOL_GRAPH_DIR=$(find .build -type d \( -name "symbol-graph" -o -name "symbolgraph" \) 2>/dev/null | head -1)

    if [[ -z "$SYMBOL_GRAPH_DIR" || ! -d "$SYMBOL_GRAPH_DIR" ]]; then
      echo "Error: Could not find symbol graph directory" >&2
      echo "Searching in .build for symbol graph directories..." >&2
      find .build -type d -name "*symbol*" 2>/dev/null || true
      exit 1
    fi
  else
    SYMBOL_GRAPH_DIR=$(find .build -type d \( -name "symbol-graph" -o -name "symbolgraph" \) 2>/dev/null | head -1)
    if [[ -z "$SYMBOL_GRAPH_DIR" ]]; then
      echo "Error: No symbol graph found. Run without --skip-build first." >&2
      exit 1
    fi
  fi
  echo "Symbol graphs: $SYMBOL_GRAPH_DIR"
}

# Build documentation for a single language
build_single_lang() {
  local lang="$1"
  local out_dir="$2"

  echo ""
  echo "=========================================="
  echo "Building DocC for language: $lang"
  echo "  Output: $out_dir"
  echo "=========================================="

  rm -rf "$out_dir"
  mkdir -p "$out_dir"

  # Prepare documentation files (hide other languages)
  echo "Preparing documentation files..."

  if [[ "$lang" == "$DEFAULT_LANG" ]]; then
    for lang_suffix in $LANG_LIST; do
      if [[ "$lang_suffix" != "$DEFAULT_LANG" ]]; then
        find "$DOCC_CATALOG" -name "*.$lang_suffix.md" -type f -exec mv {} {}.hidden \; 2>/dev/null || true
      fi
    done
  else
    find "$DOCC_CATALOG" -name "*.md" ! -name "*.$lang.md" -type f -exec mv {} {}.hidden \; 2>/dev/null || true

    for f in $(find "$DOCC_CATALOG" -name "*.$lang.md" -type f 2>/dev/null || true); do
      base="${f%.$lang.md}.md"
      cp "$f" "$f.original"
      mv "$f" "$base"
    done
  fi

  # Determine hosting base path
  local hosting_path
  if [[ -z "$HOSTING_BASE_PATH" ]]; then
    # Local mode: no base path or just language
    if [[ "$lang" == "$DEFAULT_LANG" ]]; then
      hosting_path=""
    else
      hosting_path="$lang"
    fi
  else
    # Deployment mode: include repo name
    if [[ "$lang" == "$DEFAULT_LANG" ]]; then
      hosting_path="$HOSTING_BASE_PATH"
    else
      hosting_path="$HOSTING_BASE_PATH/$lang"
    fi
  fi

  # Generate documentation
  echo "Generating DocC documentation..."
  local docc_args=(
    "$DOCC_CMD" convert "$DOCC_CATALOG"
    --fallback-display-name "$TARGET"
    --fallback-bundle-identifier "com.github.swift-service.$TARGET"
    --fallback-bundle-version 1.0.0
    --additional-symbol-graph-dir "$SYMBOL_GRAPH_DIR"
    --transform-for-static-hosting
    --output-path "$out_dir"
  )

  if [[ -n "$hosting_path" ]]; then
    docc_args+=(--hosting-base-path "$hosting_path")
  fi

  "${docc_args[@]}"

  touch "$out_dir/.nojekyll"

  # Restore documentation files
  echo "Restoring documentation files..."
  find "$DOCC_CATALOG" -name "*.md.hidden" -type f -exec sh -c 'mv "$1" "${1%.hidden}"' _ {} \; 2>/dev/null || true
  for f in $(find "$DOCC_CATALOG" -name "*.md.original" -type f 2>/dev/null || true); do
    original="${f%.original}"
    mv "$f" "$original"
  done

  echo "Done building $lang"
}

# Inject redirect script into index.html
inject_redirect() {
  local file="$1"
  local redirect_path="$2"
  local lang_code="${3:-}"

  if [[ ! -f "$file" ]]; then
    return
  fi

  if grep -q "Redirect.*path to documentation" "$file"; then
    return
  fi

  local base_url=""
  if grep -q 'var baseUrl =' "$file"; then
    base_url=$(grep -o 'var baseUrl = "[^"]*"' "$file" | sed 's/var baseUrl = "\([^"]*\)"/\1/')
  fi

  local redirect_script
  if [[ -z "$lang_code" ]]; then
    redirect_script="    <script>
      // Redirect root path to documentation
      (function() {
        const pathname = window.location.pathname;
        const baseUrl = \"${base_url}\";
        let normalizedPath = pathname.endsWith('/') ? pathname.slice(0, -1) : pathname;
        normalizedPath = normalizedPath || '/';
        let normalizedBase = baseUrl.endsWith('/') ? baseUrl.slice(0, -1) : baseUrl;
        normalizedBase = normalizedBase || '';
        if (normalizedPath === normalizedBase || (normalizedBase === '' && normalizedPath === '/')) {
          const redirectPath = \"${redirect_path}\";
          const finalPath = (baseUrl.endsWith('/') && redirectPath.startsWith('/'))
            ? baseUrl + redirectPath.slice(1)
            : baseUrl + redirectPath;
          window.location.href = finalPath;
        }
      })();
    </script>"
  else
    redirect_script="    <script>
      // Redirect language root path to documentation
      (function() {
        const pathname = window.location.pathname;
        const baseUrl = \"${base_url}\";
        let normalizedPath = pathname.endsWith('/') ? pathname.slice(0, -1) : pathname;
        normalizedPath = normalizedPath || '/';
        let normalizedBase = baseUrl.endsWith('/') ? baseUrl.slice(0, -1) : baseUrl;
        normalizedBase = normalizedBase || '';
        if (normalizedPath === normalizedBase) {
          let redirectPath = \"${redirect_path}\";
          const langPrefix = \"/${lang_code}/\";
          if (redirectPath.startsWith(langPrefix)) {
            redirectPath = redirectPath.slice(langPrefix.length - 1);
          }
          const finalPath = (baseUrl.endsWith('/') && redirectPath.startsWith('/'))
            ? baseUrl + redirectPath.slice(1)
            : baseUrl + redirectPath;
          window.location.href = finalPath;
        }
      })();
    </script>"
  fi

  local temp_file
  temp_file=$(mktemp)
  local script_file
  script_file=$(mktemp)
  echo "$redirect_script" > "$script_file"

  sed -E '/<[Hh][Ee][Aa][Dd][^>]*>/r '"$script_file" "$file" > "$temp_file"
  mv "$temp_file" "$file"
  rm -f "$script_file"

  echo "  Added redirect: $file"
}

# Inject Google Analytics into all index.html files
inject_google_analytics() {
  local root="$1"
  local ga_id="$2"

  if [[ -z "$ga_id" ]]; then
    return
  fi

  echo ""
  echo "Injecting Google Analytics..."

  local injected=0
  local skipped=0

  while IFS= read -r -d '' file; do
    if grep -q 'googletagmanager.com/gtag/js' "$file" 2>/dev/null; then
      ((skipped++))
      continue
    fi

    # Inject GA script before </head>
    # Note: sed uses # as delimiter, & escaped as \&
    if [[ "$(uname)" == "Darwin" ]]; then
      sed -i '' "s#</head>#<script async src=\"https://www.googletagmanager.com/gtag/js?id=${ga_id}\"></script><script>window.dataLayer=window.dataLayer||[];function gtag(){dataLayer.push(arguments)}gtag('js',new Date());gtag('config','${ga_id}',{send_page_view:false});function trackPageView(){gtag('event','page_view',{page_title:document.title,page_location:location.href})}trackPageView();(function(){var p=history.pushState,r=history.replaceState;history.pushState=function(){p.apply(this,arguments);trackPageView()};history.replaceState=function(){r.apply(this,arguments);trackPageView()};window.addEventListener('popstate',trackPageView)})();</script></head>#" "$file"
    else
      sed -i "s#</head>#<script async src=\"https://www.googletagmanager.com/gtag/js?id=${ga_id}\"></script><script>window.dataLayer=window.dataLayer||[];function gtag(){dataLayer.push(arguments)}gtag('js',new Date());gtag('config','${ga_id}',{send_page_view:false});function trackPageView(){gtag('event','page_view',{page_title:document.title,page_location:location.href})}trackPageView();(function(){var p=history.pushState,r=history.replaceState;history.pushState=function(){p.apply(this,arguments);trackPageView()};history.replaceState=function(){r.apply(this,arguments);trackPageView()};window.addEventListener('popstate',trackPageView)})();</script></head>#" "$file"
    fi
    ((injected++))
  done < <(find "$root" -name "index.html" -print0)

  echo "  GA injected: $injected files, skipped: $skipped"
}

# Inject redirects for all languages
inject_all_redirects() {
  local root="$1"
  local target_lower
  target_lower=$(echo "$TARGET" | tr '[:upper:]' '[:lower:]')

  echo ""
  echo "Injecting redirects..."

  # Root redirect
  if [[ -f "$root/index.html" ]]; then
    inject_redirect "$root/index.html" "/documentation/$target_lower/" ""
  fi

  # Language-specific redirects
  for lang in $LANG_LIST; do
    if [[ "$lang" != "$DEFAULT_LANG" ]]; then
      local lang_index="$root/$lang/index.html"
      if [[ -f "$lang_index" ]]; then
        inject_redirect "$lang_index" "/$lang/documentation/$target_lower/" "$lang"
      fi
    fi
  done
}

# Inject cross-language navigation for local preview
inject_local_navigation() {
  local root="$1"

  # Skip if not local mode
  if [[ -n "$HOSTING_BASE_PATH" ]]; then
    return
  fi

  echo ""
  echo "Injecting local navigation handler..."

  # Inject script that intercepts external links and navigates locally
  # This handles cross-language links without modifying JSON data
  # Note: sed replacement uses # as delimiter, & must be escaped as \&
  local count=0
  while IFS= read -r -d '' file; do
    if ! grep -q 'local-nav-handler' "$file" 2>/dev/null; then
      if [[ "$(uname)" == "Darwin" ]]; then
        sed -i '' 's#</head>#<script data-id="local-nav-handler">document.addEventListener("click",function(e){var a=e.target.closest("a");if(!a)return;var h=a.getAttribute("href");if(!h)return;var prefix="https://nslogmeng.github.io/swift-service";if(h.startsWith(prefix)){e.preventDefault();e.stopPropagation();window.location.href=h.slice(prefix.length)||"/"}},true);</script></head>#' "$file"
      else
        sed -i 's#</head>#<script data-id="local-nav-handler">document.addEventListener("click",function(e){var a=e.target.closest("a");if(!a)return;var h=a.getAttribute("href");if(!h)return;var prefix="https://nslogmeng.github.io/swift-service";if(h.startsWith(prefix)){e.preventDefault();e.stopPropagation();window.location.href=h.slice(prefix.length)||"/"}},true);</script></head>#' "$file"
      fi
      ((count++))
    fi
  done < <(find "$root" -name "*.html" -print0)

  echo "  Navigation handler injected into $count files"
}

# Main execution
generate_symbol_graph

if [[ "$BUILD_ALL" == "true" ]]; then
  # Build all languages
  FINAL_OUTPUT="${OUTPUT:-.build/docs}"

  for lang in $LANG_LIST; do
    if [[ "$lang" == "$DEFAULT_LANG" ]]; then
      build_single_lang "$lang" "$FINAL_OUTPUT"
    else
      build_single_lang "$lang" "$FINAL_OUTPUT/$lang"
    fi
  done

  # Inject redirects
  inject_all_redirects "$FINAL_OUTPUT"

  # Rewrite links for local preview
  inject_local_navigation "$FINAL_OUTPUT"

  # Inject Google Analytics (only if GA_ID provided)
  inject_google_analytics "$FINAL_OUTPUT" "$GA_ID"

  TARGET_LOWER=$(echo "$TARGET" | tr '[:upper:]' '[:lower:]')

  echo ""
  echo "=========================================="
  echo "All languages built successfully!"
  echo "Output: $FINAL_OUTPUT"
  echo "=========================================="
  echo ""
  echo "To preview locally:"
  echo "  python3 -m http.server 8000 --directory $FINAL_OUTPUT"
  echo "  Open: http://localhost:8000/documentation/$TARGET_LOWER/"

else
  # Build single language
  SINGLE_OUTPUT="${OUTPUT:-.build/docs-$LANG}"
  build_single_lang "$LANG" "$SINGLE_OUTPUT"

  # Inject redirect for single language
  TARGET_LOWER=$(echo "$TARGET" | tr '[:upper:]' '[:lower:]')
  if [[ -f "$SINGLE_OUTPUT/index.html" ]]; then
    echo ""
    echo "Injecting redirect..."
    if [[ "$LANG" == "$DEFAULT_LANG" ]]; then
      inject_redirect "$SINGLE_OUTPUT/index.html" "/documentation/$TARGET_LOWER/" ""
    else
      inject_redirect "$SINGLE_OUTPUT/index.html" "/$LANG/documentation/$TARGET_LOWER/" "$LANG"
    fi
  fi

  # Rewrite links for local preview
  inject_local_navigation "$SINGLE_OUTPUT"

  # Inject Google Analytics (only if GA_ID provided)
  inject_google_analytics "$SINGLE_OUTPUT" "$GA_ID"

  echo ""
  echo "=========================================="
  echo "Documentation built successfully!"
  echo "Output: $SINGLE_OUTPUT"
  echo "=========================================="
  echo ""
  echo "To preview locally:"
  echo "  python3 -m http.server 8000 --directory $SINGLE_OUTPUT"
  echo "  Open: http://localhost:8000/documentation/$TARGET_LOWER/"
fi
