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

    def unquote(value: str) -> str:
        # Remove a single layer of matching wrapper quotes around whole values.
        if len(value) >= 2 and value[0] == value[-1] and value[0] in ("'", '"'):
            return value[1:-1].strip()
        return value

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
                value = unquote(line[eq + 1:].strip())
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
    special_keys = [key for key in ("git_lfs_files_count", "git_submodules") if key in keys]
    for key in special_keys:
        ordered.remove(key)
    if "git_size_total" in ordered:
        ordered.remove("git_size_total")
    if "git_size_pack" in ordered:
        ordered.remove("git_size_pack")
    if "git_verdict" in ordered:
        ordered.remove("git_verdict")
        ordered.insert(0, "git_verdict")
    ordered.extend(special_keys)
    return ordered


def verdict_class(value: str) -> str:
    val_lower = (value or "").strip().lower()
    if (
        "too-big" in val_lower
        or "must lfs" in val_lower
        or "must-lfs" in val_lower
    ):
        cls = "red"
    elif (
        "ok" in val_lower
        or "no issue detected" in val_lower
        or "no issues" in val_lower
    ):
        cls = "green"
    else:
        cls = "yellow"
    return cls


def verdict_group(value: str) -> str:
    """Return the filter-panel group for a verdict."""
    if (value or "").strip().lower() == "n/a":
        return "unknown"
    return verdict_class(value)


def verdict_cell(value: str) -> str:
    cls = verdict_class(value)
    return f'<span class="verdict {cls}">{html.escape(value)}</span>'


def strip_prefix(col: str) -> str:
    """Strip 'git_' prefix from column name for display."""
    if col.startswith("git_"):
        col = col[4:]
    if col.startswith("size_"):
        col = col[5:]
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
    main { height: 100vh; min-height: 0; padding: 24px; display: flex; flex-direction: column; }
    .card { background: var(--panel); border: 1px solid var(--line); border-radius: 12px; padding: 16px; overflow-x: auto; }
    .repo-list { flex: 1 1 auto; min-height: 0; padding: 0; overflow-x: auto; overflow-y: auto; scrollbar-gutter: stable both-edges; scrollbar-width: auto; scrollbar-color: #8ab4ff #111a32; }
    .repo-list::-webkit-scrollbar { width: 12px; height: 12px; }
    .repo-list::-webkit-scrollbar-track { background: #111a32; }
    .repo-list::-webkit-scrollbar-thumb { background: #8ab4ff; border: 3px solid #111a32; border-radius: 6px; }
    .repo-list::-webkit-scrollbar-thumb:hover { background: #cfe0ff; }
    .overview-header { display: grid; grid-template-columns: repeat(2, minmax(0, 1fr)); gap: 16px; margin-bottom: 16px; }
    .overview-header .card { overflow: hidden; }
    h1 { margin: 0 0 8px; }
    .meta { color: var(--muted); margin: 0 0 16px; }
    .status-heading { display: flex; align-items: center; justify-content: space-between; gap: 8px; margin-bottom: 8px; }
    .status-title { margin: 0; font-size: 0.9rem; color: #cfe0ff; }
    .status-actions { display: flex; gap: 6px; }
    .status-actions button { border: 1px solid var(--line); border-radius: 4px; padding: 3px 6px; background: #111a32; color: var(--text); font-size: 0.75rem; cursor: pointer; }
    .status-actions button:hover { background: #1a2440; }
    .status-groups { display: grid; grid-template-columns: repeat(auto-fit, minmax(120px, 1fr)); gap: 8px; }
    .status-group { min-width: 0; }
    .status-group-title { margin: 0 0 4px; padding: 0; border: 0; background: transparent; font: inherit; font-size: 0.7rem; font-weight: 700; text-transform: uppercase; cursor: pointer; }
    .status-group.green .status-group-title { color: var(--ok); }
    .status-group.yellow .status-group-title { color: #fbbf24; }
    .status-group.red .status-group-title { color: #ef4444; }
    .status-group.unknown .status-group-title { color: #fff; }
    .status-grid { display: grid; gap: 4px; }
    .status-item { display: flex; align-items: center; gap: 6px; border-left: 3px solid currentColor; padding: 2px 0 2px 6px; cursor: pointer; }
    .status-item input[type="checkbox"] { margin: 0; accent-color: currentColor; }
    .status-count { min-width: 2ch; font-size: 1rem; font-weight: 700; font-variant-numeric: tabular-nums; }
    .status-label { color: var(--muted); font-size: 0.7rem; overflow-wrap: anywhere; }
    .status-item.green { color: var(--ok); }
    .status-item.yellow { color: #fbbf24; }
    .status-item.red { color: #ef4444; }
    .status-item.unknown { color: #fff; }
    @media (max-width: 720px) { main { padding: 16px; } .overview-header { grid-template-columns: 1fr; } .status-groups { grid-template-columns: 1fr; } }
    table { width: 100%; border-collapse: collapse; }
    #repoTable { min-width: 1100px; }
    th, td { padding: 10px 12px; border-bottom: 1px solid var(--line); text-align: left; vertical-align: top; }
    th { background: #111a32; color: #cfe0ff; cursor: pointer; user-select: none; }
    #repoTable th { position: sticky; top: 0; z-index: 1; }
    th:hover { background: #1a2440; }
    th.sortable::after { content: ' ⇅'; font-size: 0.85em; opacity: 0.6; }
    th.sorted-asc::after { content: ' ↑'; opacity: 1; }
    th.sorted-desc::after { content: ' ↓'; opacity: 1; }
    .num { text-align: right; font-variant-numeric: tabular-nums; }
    tr:last-child td { border-bottom: none; }
    a { color: var(--accent); text-decoration: none; }
    a:hover { text-decoration: underline; }
    .verdict { padding: 3px 8px; border-radius: 999px; border: 1px solid currentColor; font-size: 0.85rem; white-space: nowrap; }
    .verdict.green { color: var(--ok); background: rgba(52, 211, 153, 0.12); }
    .verdict.yellow { color: #fbbf24; background: rgba(251, 191, 36, 0.12); }
    .verdict.red { color: #ff9f9f; background: rgba(239, 68, 68, 0.12); }
    td { white-space: nowrap; }

"""

DISPLAY_COLUMNS = [
    "Repository", "verdict", "extensions", "objects",
    "LFS", "modules", "Tree Report", "Details",
]


def build_html(repos: list[dict], base_dir: str, output: str) -> str:
    verdict_counts: dict[str, int] = {}
    for repo in repos:
        verdict = repo["values"].get("git_verdict", "n/a") or "n/a"
        verdict_counts[verdict] = verdict_counts.get(verdict, 0) + 1

    # --- thead ---
    header_titles = {
        "objects": "Total object size (largest object size)",
        "LFS": "LFS file count (LFS size)",
        "modules": "Module URL count (module size)",
    }
    th_cells = "".join(
        f'<th title="{header_titles[column]}">{column}</th>' if column in header_titles else f"<th>{column}</th>"
        for column in DISPLAY_COLUMNS
    )
    thead = f"<thead><tr>{th_cells}</tr></thead>"

    # --- tbody ---
    out_dir = os.path.dirname(os.path.abspath(output))
    rows = []
    for r in repos:
        tree_rel = make_href(r["tree_abs"], out_dir) if r["tree_abs"] != "n/a" else "n/a"
        repo_dir_rel = make_href(r["repo_dir_abs"], out_dir)
        if not repo_dir_rel.endswith("/"):
            repo_dir_rel += "/"
        
        if tree_rel == "n/a":
            tree_cell = "<td>Not available</td>"
        else:
            tree_cell = f'<td><a href="{html.escape(tree_rel)}">git_sizes_tree.html</a></td>'
        
        cells = [
            f"<td>{html.escape(r['repo'])}</td>",
            f"<td>{verdict_cell(r['values'].get('git_verdict', 'n/a') or 'n/a')}</td>",
        ]
        values = r["values"]
        extensions = values.get("git_size_extensions", "n/a") or "n/a"
        cells.extend([
            f'<td title="{html.escape(extensions)}">{html.escape(truncate_with_ellipsis(extensions, 20))}</td>',
            f'<td class="num" title="Total object size (largest object size)">{html.escape(values.get("git_size_objects", "n/a") or "n/a")} ({html.escape(values.get("git_size_largest", "n/a") or "n/a")})</td>',
            f'<td class="num" title="LFS file count (LFS size)">{html.escape(values.get("git_size_lfs_files_count", "n/a") or "n/a")} ({html.escape(values.get("git_size_lfs", "n/a") or "n/a")})</td>',
            f'<td class="num" title="Module URL count (module size)">{html.escape(values.get("git_size_modules_url_count", "n/a") or "n/a")} ({html.escape(values.get("git_size_modules", "n/a") or "n/a")})</td>',
        ])
        cells.append(tree_cell)
        cells.append(f'<td><a href="{html.escape(repo_dir_rel)}">folder</a></td>')
        verdict = r["values"].get("git_verdict", "n/a") or "n/a"
        rows.append(
            f'<tr data-repo="{html.escape(r["repo"])}" '
            f'data-verdict="{html.escape(verdict, quote=True)}">{"".join(cells)}</tr>'
        )

    tbody = "<tbody>" + "\n        ".join(rows) + "</tbody>" if rows else (
        f'<tbody><tr><td colspan="{len(DISPLAY_COLUMNS)}">No repository result folders with git_sizes_tree.html found.</td></tr></tbody>'
    )

    generated = datetime.now().strftime("%Y-%m-%d %H:%M:%S")
    abs_dir = os.path.abspath(base_dir)
    meta_text = (
        f"Repositories found: {len(repos)}.<br>"
        f"Generated: {generated}<br>"
        f"Path: {html.escape(abs_dir)}"
    )
    verdict_summary_groups = []
    for group, title in (("green", "Green"), ("yellow", "Yellow"), ("red", "Red"), ("unknown", "Unknown")):
        items = "".join(
                f'''<label class="status-item {group}">
                            <input type="checkbox" class="verdict-filter" value="{html.escape(verdict, quote=True)}" checked />
              <span class="status-count">{count}</span>
              <span class="status-label">{html.escape(verdict)}</span>
                        </label>'''
            for verdict, count in sorted(verdict_counts.items(), key=lambda item: (-item[1], item[0].lower()))
            if verdict_group(verdict) == group
        )
        verdict_summary_groups.append(
            f'''<section class="status-group {group}">
                    <button type="button" class="status-group-title" title="Show {title} verdicts only">{title}</button>
                    <div class="status-grid">{items or '<span class="status-label">None</span>'}</div>
                  </section>'''
        )
    verdict_summary = "\n".join(verdict_summary_groups)

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
        <section class="overview-header">
            <div class="card">
                                <h1>Git Size Reports Overview</h1>
                <p class="meta">{meta_text}</p>
            </div>
            <aside class="card" aria-label="Verdict status">
                                <div class="status-heading">
                                    <h2 class="status-title">Verdict status</h2>
                                    <div class="status-actions">
                                        <button type="button" id="selectAllVerdicts">Select all</button>
                                        <button type="button" id="deselectAllVerdicts">Deselect all</button>
                                    </div>
                                </div>
                                <div class="status-groups">{verdict_summary}</div>
            </aside>
        </section>
        <div class="card repo-list">
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
            const verdictFilters = document.querySelectorAll('.verdict-filter');
      let currentSort = {{ col: null, dir: 'asc' }};

            function applyVerdictFilter() {{
                const selectedVerdicts = new Set(
                    Array.from(verdictFilters)
                        .filter(filter => filter.checked)
                        .map(filter => filter.value)
                );
                tbody.querySelectorAll('tr[data-verdict]').forEach(row => {{
                    row.hidden = !selectedVerdicts.has(row.dataset.verdict);
                }});
            }}

            verdictFilters.forEach(filter => {{
                filter.addEventListener('change', applyVerdictFilter);
            }});

                        document.getElementById('selectAllVerdicts').addEventListener('click', () => {{
                            verdictFilters.forEach(filter => {{ filter.checked = true; }});
                            applyVerdictFilter();
                        }});

                        document.getElementById('deselectAllVerdicts').addEventListener('click', () => {{
                            verdictFilters.forEach(filter => {{ filter.checked = false; }});
                            applyVerdictFilter();
                        }});

                        document.querySelectorAll('.status-group-title').forEach(groupTitle => {{
                            groupTitle.addEventListener('click', () => {{
                                const group = groupTitle.closest('.status-group');
                                verdictFilters.forEach(filter => {{ filter.checked = group.contains(filter); }});
                                applyVerdictFilter();
                            }});
                        }});

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
        const match = s.match(/^([0-9.]+)\\s*([KMGT]i?B?)?(?:\\s*\\([^)]*\\))?$/i);
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
