#!/usr/bin/env python3
"""
generate_overview.py – Generate a static Git Size Reports overview page.

Usage:
    python generate_overview.py <results_dir> [output_file]

Arguments:
    results_dir   Directory to scan for per-repo result folders.
                  Each subfolder must contain git_sizes_tree.html to be included.
                  If it also contains git_sizes.txt, the key=value pairs are read.
    output_file   Path for the generated HTML file.
                  Defaults to <results_dir>/overview.html

Example:
    python generate_overview.py ../results
    python generate_overview.py ../results /tmp/my_overview.html
"""

import argparse
import html
import os
import re
import sys
from datetime import datetime


# ---------------------------------------------------------------------------
# WSL / path helpers
# ---------------------------------------------------------------------------

_WSL_MOUNT_RE = re.compile(r"^/mnt/([a-zA-Z])(/.*)?$")


def _is_wsl() -> bool:
    try:
        with open("/proc/version", encoding="utf-8") as fh:
            return "microsoft" in fh.read().lower()
    except OSError:
        return False


_ON_WSL: bool = _is_wsl()


def _wsl_to_win(path: str) -> str | None:
    """Return a Windows-style absolute path if *path* is a WSL Windows-drive mount, else None."""
    m = _WSL_MOUNT_RE.match(path)
    if m:
        drive = m.group(1).upper()
        rest = (m.group(2) or "").replace("/", "/")  # keep forward slashes
        return f"{drive}:{rest}"
    return None


def make_href(abs_target: str, out_dir: str) -> str:
    """Return a browser-usable href for *abs_target* from an HTML file in *out_dir*.

    On WSL, if the target is on a Windows drive mount (/mnt/x/…) but the
    output directory is not (or vice-versa), the relative path would resolve
    to an unusable wsl.localhost UNC URL in the browser.  In that case we
    emit a 'file:///X:/…' absolute URL instead.
    """
    if _ON_WSL:
        win_target = _wsl_to_win(abs_target)
        win_out_dir = _wsl_to_win(out_dir)
        # Cross-boundary: one side is on a Windows mount, the other is not.
        if (win_target is None) != (win_out_dir is None):
            if win_target:
                # Target is on Windows drive – use absolute file:/// URL.
                return "file:///" + win_target.replace("\\", "/")
            # Target is in WSL, output is on Windows drive – rare, use absolute WSL path.
            return abs_target
    rel = os.path.relpath(abs_target, out_dir)
    return rel.replace(os.sep, "/")


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

def read_git_sizes(path: str) -> dict[str, str]:
    """Parse a key=value file and return a dict.  Missing or blank values → 'n/a'."""
    values: dict[str, str] = {}
    try:
        with open(path, encoding="utf-8") as fh:
            for raw in fh:
                line = raw.strip()
                if not line or line.startswith("#"):
                    continue
                eq = line.find("=")
                if eq <= 0:
                    continue
                key = line[:eq].strip()
                value = line[eq + 1:].strip()
                if key:
                    values[key] = value if value else "n/a"
    except OSError:
        pass
    return values


def scan_repos(base_dir: str) -> list[dict]:
    """Return a sorted list of repo dicts for every subfolder that has git_sizes_tree.html."""
    repos = []
    try:
        entries = sorted(os.scandir(base_dir), key=lambda e: e.name.lower())
    except OSError as exc:
        sys.exit(f"Error reading directory '{base_dir}': {exc}")

    for entry in entries:
        if not entry.is_dir():
            continue
        tree_path = os.path.join(entry.path, "git_sizes_tree.html")
        if not os.path.isfile(tree_path):
            tree_path = "n/a"
        sizes_path = os.path.join(entry.path, "git_sizes.txt")
        values = read_git_sizes(sizes_path) if os.path.isfile(sizes_path) else {}
        repos.append(
            {
                "repo": entry.name,
                "repo_dir_abs": entry.path,
                "tree_abs": tree_path,
                "sizes_abs": sizes_path,
                "values": values,
            }
        )
    return repos


def get_dynamic_keys(repos: list[dict]) -> list[str]:
    """Collect and order all unique keys found across all repos.
    'git_verdict' is sorted to the front if present."""
    keys: set[str] = set()
    for r in repos:
        keys.update(r["values"].keys())
    ordered = sorted(keys)
    if "git_size_pack" in ordered:
        ordered.remove("git_size_pack")
    if "git_verdict" in ordered:
        ordered.remove("git_verdict")
        ordered.insert(0, "git_verdict")
    return ordered


def verdict_cell(value: str) -> str:
    val_lower = value.lower()
    if val_lower == "n/a" or val_lower == "":
        cls = "na"
    elif "must lfs" in val_lower:
        cls = "must-lfs"
    elif "could lfs" in val_lower:
        cls = "could-lfs"
    elif "no issues" in val_lower:
        cls = "ok"
    else:
        cls = "na"
    return f'<span class="verdict {cls}">{html.escape(value)}</span>'


def strip_prefix(col: str) -> str:
    """Strip 'git_' prefix from column name for display."""
    if col.startswith("git_"):
        return col[4:]
    return col


def truncate_with_ellipsis(value: str, max_len: int) -> str:
    """Truncate *value* to *max_len* chars and append '...' when truncated."""
    if len(value) <= max_len:
        return value
    return value[:max_len] + "..."


# ---------------------------------------------------------------------------
# HTML generation
# ---------------------------------------------------------------------------

STYLE = """
    :root { --bg:#0d1324; --panel:#151e37; --line:#2a355e; --text:#e8ecff; --muted:#a7b4df; --accent:#8ab4ff; --ok:#34d399; --na:#94a3b8; }
    * { box-sizing: border-box; }
    body { margin: 0; font-family: Segoe UI, Arial, sans-serif; background: radial-gradient(circle at top left, #1a2850 0%, var(--bg) 60%); color: var(--text); }
    main { padding: 24px; }
    .card { background: var(--panel); border: 1px solid var(--line); border-radius: 12px; padding: 16px; overflow-x: auto; }
    h1 { margin: 0 0 8px; }
    .meta { color: var(--muted); margin: 0 0 16px; }
    table { width: 100%; border-collapse: collapse; }
    th, td { padding: 10px 12px; border-bottom: 1px solid var(--line); text-align: left; vertical-align: top; }
    th { background: #111a32; color: #cfe0ff; cursor: pointer; user-select: none; }
    th:hover { background: #1a2440; }
    th.sortable::after { content: ' ⇅'; font-size: 0.85em; opacity: 0.6; }
    th.sorted-asc::after { content: ' ↑'; opacity: 1; }
    th.sorted-desc::after { content: ' ↓'; opacity: 1; }
    .num { text-align: right; font-variant-numeric: tabular-nums; }
    tr:last-child td { border-bottom: none; }
    a { color: var(--accent); text-decoration: none; }
    a:hover { text-decoration: underline; }
    .verdict { padding: 3px 8px; border-radius: 999px; border: 1px solid currentColor; font-size: 0.85rem; white-space: nowrap; }
    .verdict.ok { color: var(--ok); background: rgba(52, 211, 153, 0.12); }
    .verdict.na { color: #e8e8e8; background: rgba(232, 232, 232, 0.12); }
    .verdict.could-lfs { color: #fbbf24; background: rgba(251, 191, 36, 0.12); }
    .verdict.must-lfs { color: #ef4444; background: rgba(239, 68, 68, 0.12); }
    td { white-space: nowrap; }
"""

STATIC_COLS = ["#", "Repository"]
LINK_COLS = ["Tree Report", "Details"]


def build_html(repos: list[dict], base_dir: str, output: str) -> str:
    dyn_keys = get_dynamic_keys(repos)
    all_cols = STATIC_COLS + dyn_keys + LINK_COLS

    # --- thead ---
    th_cells = "".join(f"<th>{html.escape(strip_prefix(c))}</th>" for c in all_cols)
    thead = f"<thead><tr>{th_cells}</tr></thead>"

    # --- tbody ---
    out_dir = os.path.dirname(os.path.abspath(output))
    rows = []
    for idx, r in enumerate(repos, start=1):
        tree_rel = make_href(r["tree_abs"], out_dir) if r["tree_abs"] != "n/a" else "n/a"
        repo_dir_rel = make_href(r["repo_dir_abs"], out_dir)
        if not repo_dir_rel.endswith("/"):
            repo_dir_rel += "/"
        
        if tree_rel == "n/a":
            tree_cell = "<td>Not available</td>"
        else:
            tree_cell = f'<td><a href="{html.escape(tree_rel)}">git_sizes_tree.html</a></td>'
        
        cells = [
            f"<td>{idx}</td>",
            f"<td>{html.escape(r['repo'])}</td>",
        ]
        for key in dyn_keys:
            value = r["values"].get(key, "n/a") or "n/a"
            if key == "git_verdict":
                cells.append(f"<td>{verdict_cell(value)}</td>")
            elif key == "git_size_extensions":
                short_value = truncate_with_ellipsis(value, 20)
                cells.append(
                    f'<td title="{html.escape(value)}">{html.escape(short_value)}</td>'
                )
            elif key.startswith("git_size_"):
                cells.append(f'<td class="num">{html.escape(value)}</td>')
            else:
                cells.append(f"<td>{html.escape(value)}</td>")
        cells.append(tree_cell)
        cells.append(f'<td><a href="{html.escape(repo_dir_rel)}">folder</a></td>')
        rows.append(f'<tr data-repo="{html.escape(r["repo"])}">{"".join(cells)}</tr>')

    tbody = "<tbody>" + "\n        ".join(rows) + "</tbody>" if rows else (
        f'<tbody><tr><td colspan="{len(all_cols)}">No repository result folders with git_sizes_tree.html found.</td></tr></tbody>'
    )

    generated = datetime.now().strftime("%Y-%m-%d %H:%M:%S")
    abs_dir = os.path.abspath(base_dir)
    meta_text = (
        f"Repositories found: {len(repos)}. "
        f"Generated: {generated} from {html.escape(abs_dir)}"
    )

    return f"""<!doctype html>
<html lang="en">
<head>
  <meta charset="utf-8" />
  <meta name="viewport" content="width=device-width, initial-scale=1" />
  <title>Git Size Reports Overview</title>
  <style>{STYLE}  </style>
</head>
<body>
  <main>
    <div class="card">
      <h1>Git Size Reports Overview</h1>
      <p class="meta">{meta_text}</p>
      <table id="repoTable">
        {thead}
        {tbody}
      </table>
    </div>
  </main>
  <script>
    function initSortableTable() {{
      const table = document.getElementById('repoTable');
      const headers = table.querySelectorAll('th');
      const tbody = table.querySelector('tbody');
      let currentSort = {{ col: null, dir: 'asc' }};

      headers.forEach((th, idx) => {{
        th.classList.add('sortable');
        th.addEventListener('click', () => {{
          const isCurrentCol = currentSort.col === idx;
          const newDir = isCurrentCol && currentSort.dir === 'asc' ? 'desc' : 'asc';
          sortTable(idx, newDir);
          currentSort = {{ col: idx, dir: newDir }};
        }});
      }});

      function parseHumanSize(str) {{
        const s = str.trim();
        const match = s.match(/^([0-9.]+)\\s*([KMGT]i?B?)?$/i);
        if (!match) return NaN;
        const num = parseFloat(match[1]);
        let unit = (match[2] || 'B').toUpperCase();
        if (unit === 'K') unit = 'KB';
        if (unit === 'M') unit = 'MB';
        if (unit === 'G') unit = 'GB';
        if (unit === 'T') unit = 'TB';
        const units = {{ B: 1, KB: 1e3, KIB: 1024, MB: 1e6, MIB: 1024**2, GB: 1e9, GIB: 1024**3, TB: 1e12, TIB: 1024**4 }};
        return num * (units[unit] || 1);
      }}

      function sortTable(colIdx, direction) {{
        const rows = Array.from(tbody.querySelectorAll('tr'));
        rows.sort((a, b) => {{
          const aCell = a.cells[colIdx]?.textContent.trim() || '';
          const bCell = b.cells[colIdx]?.textContent.trim() || '';
          
          // Try simple numeric first
          const aNum = parseFloat(aCell);
          const bNum = parseFloat(bCell);
          if (!isNaN(aNum) && !isNaN(bNum)) {{
            const isSimpleNumeric = /^-?[0-9]+(\.[0-9]+)?$/.test(aCell.trim()) && /^-?[0-9]+(\.[0-9]+)?$/.test(bCell.trim());
            if (isSimpleNumeric) {{
              return direction === 'asc' ? aNum - bNum : bNum - aNum;
            }}
          }}
          
          // Try human-readable sizes (with K, M, G, T units)
          const aSize = parseHumanSize(aCell);
          const bSize = parseHumanSize(bCell);
          if (!isNaN(aSize) && !isNaN(bSize)) {{
            return direction === 'asc' ? aSize - bSize : bSize - aSize;
          }}
          
          // Fall back to string comparison
          const cmp = aCell.localeCompare(bCell);
          return direction === 'asc' ? cmp : -cmp;
        }});
        
        headers.forEach((h, i) => {{
          h.classList.remove('sorted-asc', 'sorted-desc');
          if (i === colIdx) {{
            h.classList.add(direction === 'asc' ? 'sorted-asc' : 'sorted-desc');
          }}
        }});
        
        rows.forEach(row => tbody.appendChild(row));
      }}
    }}
    document.addEventListener('DOMContentLoaded', initSortableTable);
  </script>
</body>
</html>
"""


# ---------------------------------------------------------------------------
# Entry point
# ---------------------------------------------------------------------------

def main() -> None:
    parser = argparse.ArgumentParser(
        description="Generate a static Git Size Reports overview HTML page.",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog=__doc__,
    )
    parser.add_argument("results_dir", help="Directory to scan for repo result folders")
    parser.add_argument(
        "output_file",
        nargs="?",
        help="Output HTML file path (default: <results_dir>/overview.html)",
    )
    args = parser.parse_args()

    base_dir = args.results_dir
    if not os.path.isdir(base_dir):
        sys.exit(f"Error: '{base_dir}' is not a directory.")

    output = args.output_file or os.path.join(base_dir, "overview.html")

    repos = scan_repos(base_dir)
    page = build_html(repos, base_dir, output)

    try:
        with open(output, "w", encoding="utf-8") as fh:
            fh.write(page)
    except OSError as exc:
        sys.exit(f"Error writing '{output}': {exc}")

    print(f"Generated {len(repos)} repo(s) → {output}")


if __name__ == "__main__":
    main()
