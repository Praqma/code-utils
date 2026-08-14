#!/usr/bin/env python3
import concurrent.futures
import json
import os
import re
import subprocess
import sys

RE_HB = re.compile(r'^(\d+)\s+([HB])\s+(\d+)\s+(.+)$')
RE_HIST = re.compile(r'^(\d+)\s+(\d+)\s+(.+)$')
MIN_LOG_SIZE_BYTES = 1 * 1024 * 1024


def to_list(node):
    children = sorted(node['children'].values(), key=lambda x: -x['size'])
    return {
        'n': node['name'],
        's': node['size'],
        'p': node['prefix'],
        'c': node['count'],
        'd': node['is_dir'],
        'ch': [to_list(c) for c in children],
    }


def build_tree(input_file):
    root = {
        'name': '(root)',
        'size': 0,
        'children': {},
        'prefix': '',
        'count': 0,
        'is_dir': True,
    }

    with open(input_file) as f:
        for line in f:
            line = line.rstrip('\n')
            if not line.strip():
                continue

            m = RE_HB.match(line)
            if m:
                size, prefix, count, path = int(m.group(1)), m.group(2), int(m.group(3)), m.group(4)
            else:
                m = RE_HIST.match(line)
                if not m:
                    continue
                size, prefix, count, path = int(m.group(1)), '', int(m.group(2)), m.group(3)

            if not path:
                continue

            components = path.split('/')
            node = root
            for comp in components[:-1]:
                if comp not in node['children']:
                    node['children'][comp] = {
                        'name': comp,
                        'size': 0,
                        'children': {},
                        'prefix': '',
                        'count': 0,
                        'is_dir': True,
                    }
                node['children'][comp]['size'] += size
                node = node['children'][comp]

            fname = components[-1]
            if fname not in node['children']:
                node['children'][fname] = {
                    'name': fname,
                    'size': size,
                    'children': {},
                    'prefix': prefix,
                    'count': count,
                    'is_dir': False,
                }
            else:
                node['children'][fname]['size'] += size
                node['children'][fname]['prefix'] = prefix
            root['size'] += size

    return root


def strip_pack_tag(path):
    return re.sub(r'\s+\(\s*[IP]\s*\)\s*$', '', path).strip()


def collect_unique_paths(input_file, min_size_bytes=0):
    path_sizes = {}
    with open(input_file) as f:
      for line in f:
        line = line.rstrip('\n')
        if not line.strip():
          continue

        m = RE_HIST.match(line)
        if not m:
          continue
        size = int(m.group(1))
        path = m.group(3)

        clean = strip_pack_tag(path)
        if not clean:
          continue

        # Keep the largest observed historical size for each path.
        prev = path_sizes.get(clean)
        if prev is None or size > prev:
          path_sizes[clean] = size

    if min_size_bytes > 0:
      return sorted([p for p, s in path_sizes.items() if s >= min_size_bytes])
    return sorted(path_sizes.keys())


def collect_git_logs(repo_path, paths):
    if os.environ.get('GIT_ANALYST_SKIP_LOGS', '').lower() in ('1', 'true', 'yes'):
        return {}

    # Parallelize independent git-log calls to reduce total wall-clock time.
    cpu_count = os.cpu_count() or 4
    workers = min(max(cpu_count, 1), 8)
    env_workers = os.environ.get('GIT_ANALYST_LOG_WORKERS', '').strip()
    if env_workers.isdigit():
        workers = max(1, int(env_workers))

    def run_one(rel_path):
        cmd = [
            'git', '-C', repo_path,
            'log', '--all', '--full-history', '--summary', '--oneline', '--', rel_path
        ]
        try:
            completed = subprocess.run(
                cmd,
                stdout=subprocess.PIPE,
                stderr=subprocess.STDOUT,
                text=True,
                check=False,
            )
            output = completed.stdout.strip()
            if not output:
                output = '(no history found for path)'
        except Exception as exc:
            output = 'Failed to run git log: ' + str(exc)

        return rel_path, {
            'cmd': 'git log --all --full-history --summary --oneline -- ' + rel_path,
            'out': output,
        }

    logs = {}
    with concurrent.futures.ThreadPoolExecutor(max_workers=workers) as executor:
        for rel_path, entry in executor.map(run_one, paths):
            logs[rel_path] = entry
    return logs


def load_extension_verdicts(input_file):
    ext_file = os.path.join(os.path.dirname(os.path.abspath(input_file)), 'git_size_extensions.txt')
    verdicts = {}
    if not os.path.isfile(ext_file):
        return verdicts

    # Expected line format: "ext=size (count) verdict"
    line_re = re.compile(r'^(.*?)=.*\(\s*\d+\s*\)\s+(\S+)\s*$')
    with open(ext_file) as f:
        for raw in f:
            line = raw.strip()
            if not line:
                continue
            m = line_re.match(line)
            if not m:
                continue
            ext = m.group(1).strip().lower()
            verdict = m.group(2).strip()
            if ext == '[no-ext]':
                ext = '[no_ext]'
            verdicts[ext] = verdict
    return verdicts


def load_report_metadata(input_file):
    metadata_file = os.path.join(os.path.dirname(os.path.abspath(input_file)), 'git_sizes.txt')
    metadata = {}
    if not os.path.isfile(metadata_file):
      return metadata

    key_re = re.compile(r"^(git_size_total|git_size_modules|git_size_lfs|git_size_lfs_files_count|git_size_modules_url_count)='([^']*)'$")
    with open(metadata_file) as f:
        for raw in f:
            match = key_re.match(raw.strip())
            if match:
                metadata[match.group(1)] = match.group(2)
    return metadata


def render_html(repo_name, repo_link, tree_json, logs_json, ext_verdicts_json, metadata_json):
    html_template = r'''<!DOCTYPE html>
<html lang="en">
<head><meta charset="UTF-8"><title>Git Object Sizes - __REPO__</title>
<style>
*{box-sizing:border-box;margin:0;padding:0}
body{font-family:'Segoe UI',Consolas,monospace;background:radial-gradient(circle at top left,#161a2d 0%,#0f1220 50%);color:#e5e9ff;margin:0;height:100vh;overflow:hidden;display:grid;grid-template-rows:auto auto minmax(0,1fr)}
#main-top{display:grid;gap:6px;width:100%;padding:16px 16px 10px}
#layout{display:grid;grid-template-columns:minmax(0,1fr) minmax(0,3fr);gap:10px;padding:0 16px 16px;min-height:0;height:100%}
#sidebar,#main,#controls{display:contents}
h1{font-size:1.8em;color:#e5e9ff;margin-bottom:6px}
h1 a{color:#8ab4ff;text-decoration:none}
#summary-hint{font-size:.84em;color:#8e97bc;background:#1f243b;border:1px solid #39415f;border-radius:8px;padding:6px 10px;display:block;width:100%}
#sidebar-title{font-size:1.3em;margin-bottom:6px}
#sidebar-subtitle{font-size:.9em;color:#aab2d8;margin-bottom:12px}
#controls{display:grid;grid-template-rows:auto minmax(0,1fr) auto;gap:10px;height:100%;min-height:0}
#action-row{display:grid;grid-template-columns:minmax(0,1fr) minmax(0,1.5fr) minmax(0,1.5fr);gap:10px;align-items:stretch;padding:0 16px 10px}
#level-controls{display:grid;grid-template-columns:1fr 1fr;gap:8px;border:1px solid #39415f;background:#1f243b;border-radius:10px;padding:10px}
#level-controls #filter-row{grid-column:1 / -1}
#filter-row{display:grid;grid-template-columns:auto minmax(0,1fr) auto;align-items:center;gap:6px;background:#232944;border:1px solid #39415f;border-radius:8px;padding:6px 8px}
#filter-row label{font-size:.85em;color:#aab2d8;white-space:nowrap}
#path-filter{background:#232944;color:#e5e9ff;border:1px solid #39415f;padding:8px 10px;border-radius:8px;font-size:.95em;width:100%}
#path-filter::placeholder{color:#8e97bc}
#type-filter-row{display:grid;gap:6px;font-size:.95em;border:1px solid #39415f;background:#1f243b;border-radius:10px;padding:10px}
#type-filter-row label{display:flex;align-items:center;gap:7px;cursor:pointer;line-height:1.2}
#type-filter-row input[type="checkbox"]{margin:0;transform:translateY(0)}
#type-filter-reset{margin-top:2px}
.section-title{font-size:.95em;color:#c9cedf;margin-top:4px}
.type-legend-line{display:flex;align-items:center;gap:7px;color:#aab2d8;font-size:.92em;padding-left:23px;line-height:1.2}
.type-inline-dot{width:10px;height:10px;border-radius:50%;display:inline-block;flex-shrink:0;position:relative;top:1px}
.type-inline-dot-h{background:#89b4fa}
.type-inline-dot-b{background:#fab387}
.type-inline-dot-hist{background:#ef4444}
.type-inline-dot-mixed{background:#c9cedf}
#ext-panel{border:1px solid #39415f;background:#1f243b;border-radius:10px;padding:10px;display:grid;grid-template-rows:auto minmax(0,1fr) auto;gap:8px;height:100%;min-height:0;overflow:hidden}
#repo-stats{display:grid;grid-template-columns:minmax(0,1fr);gap:6px;border:1px solid #39415f;background:#1f243b;border-radius:10px;padding:10px;height:100%;min-height:0}
.repo-stat{display:flex;justify-content:space-between;gap:10px;min-width:0;color:#aab2d8;font-size:.84em;white-space:nowrap;overflow:hidden;text-overflow:ellipsis}
.repo-stat strong{color:#e5e9ff;font-weight:600}
#ext-table-head-wrap{position:sticky;top:0;z-index:2;background:#232944;border:1px solid #39415f;border-radius:8px 8px 0 0;overflow:hidden}
#ext-table-wrap{min-height:0;overflow-y:auto;overflow-x:hidden;border:1px solid #39415f;border-top:none;border-radius:0 0 8px 8px;scrollbar-gutter:stable}
.ext-table{width:100%;border-collapse:collapse;font-size:.84em;table-layout:auto}
.ext-table th,.ext-table td{min-width:0;overflow:hidden;text-overflow:ellipsis;padding:6px 8px}
.ext-table th{background:#232944;color:#c9cedf;text-align:left;border-bottom:1px solid #39415f;white-space:normal;line-height:1.15}
.ext-table td{border-bottom:1px solid #2a2f48;color:#dfe4ff;white-space:nowrap}
.ext-table td:nth-child(2),.ext-table td:nth-child(3){text-align:right;color:#aab2d8}
.ext-table td:nth-child(4){font-weight:600;color:#c9cedf}
.ext-table tbody tr{cursor:pointer}
.ext-table tbody tr:hover td{background:#2a2a3e}
.ext-table tr:last-child td{border-bottom:none}
#ext-empty{font-size:.84em;color:#8e97bc;padding:2px 0}
.ext-legend{font-size:.8em;color:#9aa4cd;line-height:1.3}
.ctx-hint{font-size:.82em;color:#8e97bc}
button{background:#232944;color:#e5e9ff;border:1px solid #39415f;padding:8px 10px;border-radius:8px;cursor:pointer;font-size:.95em}
button:hover{background:#45475a}
#tree-panel{display:grid;grid-template-rows:auto 1fr;min-height:0;border:1px solid #39415f;border-radius:10px;overflow-y:auto;overflow-x:hidden;background:#151a2d}
#tree{font-size:.94em;overflow-x:hidden;overflow-y:visible;min-height:0}
.hdr,.row{display:grid;grid-template-columns:minmax(0,1fr) 40px minmax(24px,.8fr) minmax(13px,.225fr) minmax(16px,.25fr);column-gap:5px;align-items:center}
.hdr{position:sticky;top:0;z-index:3;padding:6px 8px;font-size:.9em;color:#aab2d8;border-bottom:1px solid #39415f;background:#1a1f33;user-select:none}
.hdr .h-name{min-width:0}
.hdr .h-tag{text-align:right}
.hdr .h-bar{text-align:center}
.hdr .h-sz{text-align:right}
.hdr .h-cnt{text-align:right}
.hdr>div,.row>div{min-width:0}
.node{margin:1px 0;content-visibility:auto;contain-intrinsic-block-size:26px}
.row{padding:2px 6px;border-radius:4px;cursor:default}
.row.clickable{cursor:pointer}
.row:hover{background:#2a2a3e}
.lead{display:grid;grid-template-columns:14px 16px minmax(0,1fr);column-gap:4px;align-items:center;min-width:0;padding-left:calc(var(--depth, 0) * 10px)}
.tog{width:14px;font-size:.8em;color:#585b70;text-align:center}
.ico{font-size:.95em;width:16px;text-align:center}
.nm{min-width:0;white-space:nowrap;overflow:hidden;text-overflow:ellipsis}
.tag{text-align:right;color:#aab2d8;font-size:.82em}
.bar-w{width:100%;background:#40476b;border-radius:3px;height:9px;overflow:hidden}
.bar{height:9px;border-radius:3px;min-width:1px}
.sz{text-align:right;color:#a6adc8;font-size:.92em}
.cnt{text-align:right;color:#585b70;font-size:.88em}
.tag,.sz,.cnt{white-space:nowrap;overflow:hidden;text-overflow:ellipsis}
.sz-dir{color:#c9cedf}
.sz-H{color:#89b4fa}
.sz-B{color:#fab387}
.sz-hist{color:#ef4444}
.cnt-dir{color:#c9cedf}
.cnt-H{color:#89b4fa}
.cnt-B{color:#fab387}
.cnt-hist{color:#ef4444}
.tag,.sz,.cnt{color:#e5e9ff!important}
.sz-hist,.cnt-hist{color:#ff9f9f!important}
.children{display:block}
.collapsed>.children{display:none}
.bar-dir{background:#c9cedf}
.bar-H{background:#89b4fa}
.bar-B{background:#fab387}
.bar-hist{background:#ef4444}
.ico-dir{color:#c9cedf}
.ico-H{color:#89b4fa}
.ico-B{color:#fab387}
.ico-hist{color:#ef4444}
#log-modal{position:fixed;inset:0;background:rgba(6,9,18,.75);display:none;align-items:center;justify-content:center;z-index:50;padding:16px}
#log-modal.show{display:flex}
#log-panel{width:min(1100px,96vw);height:min(78vh,760px);background:#11172b;border:1px solid #39415f;border-radius:12px;display:grid;grid-template-rows:auto auto 1fr;overflow:hidden}
#log-head{display:flex;align-items:center;justify-content:space-between;gap:10px;padding:10px 12px;border-bottom:1px solid #39415f;background:#1a1f33}
#log-title{font-size:.95em;color:#dfe4ff;min-width:0;white-space:nowrap;overflow:hidden;text-overflow:ellipsis}
#log-close{padding:6px 9px;font-size:.85em}
#log-cmd{font-size:.84em;color:#aab2d8;padding:8px 12px;border-bottom:1px solid #2a2f48;white-space:nowrap;overflow:auto;background:#161c31}
#log-out{margin:0;padding:12px;overflow:auto;font-size:.84em;line-height:1.35;color:#e5e9ff;white-space:pre-wrap}
@media (max-width:980px){
  body{height:auto;overflow:auto}
  #layout{grid-template-columns:1fr}
  #sidebar{position:static;height:auto;border-right:none;border-bottom:1px solid #39415f}
  #controls{height:auto}
  #main{height:auto;overflow:visible}
  #action-row{grid-template-columns:1fr}
  #tree-panel{min-height:420px}
}
@media (max-width:1280px){
  .hdr,.row{grid-template-columns:minmax(0,1fr) 34px minmax(18px,.9fr) minmax(10px,.2fr) minmax(12px,.2fr)}
  .lead{padding-left:calc(var(--depth, 0) * 7px)}
}
</style>
</head>
<body>
<div id="main-top">
  <h1>Git Object Sizes &mdash; <a href="__REPO_LINK__" title="Raw data and more details">__REPO__</a></h1>
</div>
<div id="action-row">
  <div id="repo-stats">
    <div class="repo-stat">Total size across all revisions: <strong id="stat-total"></strong></div>
    <div class="repo-stat">Unique files tracked: <strong id="stat-files"></strong></div>
    <div class="repo-stat">Submodules(urls in HEAD): <strong id="stat-modules"></strong></div>
    <div class="repo-stat">LFS: <strong id="stat-lfs"></strong></div>
    <div class="repo-stat">Extensions (incl [no_ext]): <strong id="stat-extensions"></strong></div>
  </div>
  <div id="level-controls">
    <button onclick="expandAll()">Expand All</button>
    <button onclick="collapseAll()">Collapse All</button>
    <button onclick="changeDepth(1)" title="Show one more folder level">+ Level</button>
    <button onclick="changeDepth(-1)" title="Show one fewer folder level">- Level</button>
    <div id="filter-row">
          <label for="path-filter">Regex</label>
      <input id="path-filter" type="text" placeholder="e.g. installer|\\.jar$ or click an extension" spellcheck="false" />
      <button id="path-filter-clear" type="button" title="Clear path regex">Clear</button>
    </div>
  </div>
  <div id="type-filter-row">
    <label><input id="type-h" type="checkbox" checked /><span class="type-inline-dot type-inline-dot-h"></span>H (HEAD/default branch)</label>
    <label><input id="type-b" type="checkbox" checked /><span class="type-inline-dot type-inline-dot-b"></span>B (branch only)</label>
    <label><input id="type-hist" type="checkbox" checked /><span class="type-inline-dot type-inline-dot-hist"></span>historical (not in active branches)</label>
    <div class="type-legend-line"><span class="type-inline-dot type-inline-dot-mixed"></span>mixed directories</div>
    <button id="type-filter-reset" type="button" title="Select H, B, and historical files">Reset Types</button>
  </div>
</div>
<div id="layout">
  <aside id="sidebar">
    <div id="controls">
      <div id="ext-panel">
        <div id="ext-table-head-wrap">
          <table class="ext-table" aria-hidden="true">
            <thead>
              <tr>
                <th>Extension</th>
                <th>Total Size</th>
                <th>Count</th>
                <th title="nA/nB = 8kb NUL char detection for binary&#10;gA/gB = git diff says text/binary&#10;fA/fB/fE = file says text/binary/empty">Verdict *</th>
              </tr>
            </thead>
          </table>
        </div>
        <div id="ext-table-wrap">
          <table class="ext-table" id="ext-table">
            <tbody id="ext-table-body"></tbody>
          </table>
        </div>
        <div id="ext-empty" style="display:none">No matching files.</div>
      </div>
    </div>
  </aside>
  <main id="main">
    <div id="tree-panel">
      <div class="hdr">
        <div class="h-name">Name</div>
        <div class="h-tag" title="I = direct-packed object total&#10;P = revision/delta-packed object total">P/I *</div>
        <div class="h-bar">Relative Size</div>
        <div class="h-sz">Total Size</div>
        <div class="h-cnt" title="Empty means the file has only one revision">Revisions *</div>
      </div>
      <div id="tree"></div>
    </div>
  </main>
 </div>
<div id="log-modal" role="dialog" aria-modal="true" aria-label="Git log output">
  <div id="log-panel">
    <div id="log-head">
      <div id="log-title">History Output</div>
      <button id="log-close" type="button">Close</button>
    </div>
    <div id="log-cmd"></div>
    <pre id="log-out"></pre>
  </div>
</div>
<script>
const DATA = __DATA__;
const FILE_LOGS = __LOGS__;
const EXT_VERDICTS = __EXT_VERDICTS__;
const REPORT_META = __META__;
const total = DATA.s;
let pathRegexText = '';
let pathRegex = null;
let showH = true;
let showB = true;
let showHist = true;
let treeDepth = 0;
let totalFiles = 0;
let renderTimer = null;
let renderToken = 0;

function normalizeLeafPath(path) {
  return (path || '').replace(/\s+\(\s*[IP]\s*\)\s*$/i, '').trim();
}

function isHistoricalLeaf(node) {
  return !node.d && normalizePrefix(node.p) === 'hist';
}

function pathMatches(path) {
  const matchPath = normalizeLeafPath(path);
  if (pathRegex) {
    pathRegex.lastIndex = 0;
    if (!pathRegex.test(matchPath)) return false;
  }
  return true;
}

function typeMatches(prefix) {
  if (prefix === 'H') return showH;
  if (prefix === 'B') return showB;
  return showHist;
}

function normalizePrefix(prefix) {
  if (prefix === 'H' || prefix === 'B') return prefix;
  return 'hist';
}

function folderPrefixFromChildren(children) {
  let folderPrefix = null;
  for (const child of children) {
    const childPrefix = child.d ? (child.dp || '') : normalizePrefix(child.p);
    if (!childPrefix) continue;
    if (folderPrefix === null) {
      folderPrefix = childPrefix;
      continue;
    }
    if (folderPrefix !== childPrefix) return '';
  }
  return folderPrefix || '';
}

function filterTree(node, parentPath) {
  const fullPath = parentPath ? (parentPath + '/' + node.n) : node.n;
  const isDir = !!node.d;
  const copy = { ...node, fp: fullPath };

  if (!isDir) return (pathMatches(fullPath) && typeMatches(node.p)) ? copy : null;

  const children = (node.ch || []).map(c => filterTree(c, fullPath)).filter(Boolean);
  if (children.length > 0) {
    copy.ch = children;
    copy.dp = folderPrefixFromChildren(children);
    return copy;
  }
  return null;
}

function countVisibleFiles(node) {
  if (!node) return 0;
  if (!node.d) return 1;
  let sum = 0;
  for (const c of (node.ch || [])) sum += countVisibleFiles(c);
  return sum;
}

function sumVisibleFileSize(node) {
  if (!node) return 0;
  if (!node.d) return node.s || 0;
  let sum = 0;
  for (const c of (node.ch || [])) sum += sumVisibleFileSize(c);
  return sum;
}

function updateFilteredStats(totalVisible, totalVisibleSize) {
  document.getElementById('stat-total').textContent = fmtSz(totalVisibleSize) + ' / ' + fmtSz(total);
  document.getElementById('stat-files').textContent = totalVisible + ' / ' + totalFiles;
}

function fileExtFromPath(path) {
  const rawName = (path || '').split('/').pop() || '';
  const name = rawName.replace(/\s+\(\s*[IP]\s*\)\s*$/i, '');
  const dot = name.lastIndexOf('.');
  if (dot <= 0 || dot === name.length - 1) return '[no_ext]';
  return name.slice(dot + 1).toLowerCase();
}

function normalizeExtKey(ext) {
  const key = (ext || '').toLowerCase();
  if (key === '[no-ext]') return '[no_ext]';
  return key;
}

function collectExtensionStats(node, stats) {
  if (!node) return;
  if (!node.d) {
    const ext = normalizeExtKey(fileExtFromPath(node.fp || node.n));
    if (!stats[ext]) stats[ext] = { size: 0, count: 0 };
    stats[ext].size += (node.s || 0);
    stats[ext].count += 1;
    return;
  }
  for (const c of (node.ch || [])) collectExtensionStats(c, stats);
}

function renderExtensionTable(filteredChildren) {
  const stats = {};
  for (const c of filteredChildren) collectExtensionStats(c, stats);

  const rows = Object.entries(stats).map(([ext, values]) => ({
    ext,
    size: values.size,
    count: values.count,
    verdict: EXT_VERDICTS[normalizeExtKey(ext)] || 'n/a'
  })).sort((a, b) => b.size - a.size);
  document.getElementById('stat-extensions').textContent = String(rows.length);
  const body = document.getElementById('ext-table-body');
  const empty = document.getElementById('ext-empty');
  const wrap = document.getElementById('ext-table-wrap');

  body.innerHTML = '';
  if (rows.length === 0) {
    empty.style.display = 'block';
    wrap.style.display = 'none';
    return;
  }

  empty.style.display = 'none';
  wrap.style.display = 'block';

  for (const item of rows) {
    const tr = document.createElement('tr');
    const tdExt = document.createElement('td');
    const tdSize = document.createElement('td');
    const tdCount = document.createElement('td');
    const tdVerdict = document.createElement('td');
    tdExt.textContent = item.ext;
    tdSize.textContent = fmtSz(item.size);
    tdCount.textContent = String(item.count);
    tdVerdict.textContent = item.verdict;
    tdVerdict.title = 'nA/nB = 8kb NUL char detection for binary\ngA/gB = git diff says text/binary\nfA/fB/fE = file says text/binary/empty';
    tr.appendChild(tdExt);
    tr.appendChild(tdSize);
    tr.appendChild(tdCount);
    tr.appendChild(tdVerdict);
    tr.title = 'Filter tree by .' + item.ext + ' files; click again to clear';
    tr.addEventListener('click', () => {
      const input = document.getElementById('path-filter');
      const filter = item.ext === '[no_ext]'
        ? '(^|/)[^/]*$'
        : '\\.' + item.ext.replace(/[.*+?^${}()|[\\]\\]/g, '\\$&') + '$';
      input.value = input.value === filter ? '' : filter;
      input.dispatchEvent(new Event('input', { bubbles: true }));
      input.focus();
    });
    body.appendChild(tr);
  }
}

function fmtSz(s) {
  const u = ['B','KB','MB','GB','TB'];
  let i = 0;
  while (s >= 1024 && i < u.length - 1) { s /= 1024; i++; }
  return s.toFixed(i === 0 ? 0 : 1) + '\u00a0' + u[i];
}

function fileIcon(name) {
  const e = (name.split('.').pop() || '').toLowerCase();
  const m = {
    jar:'&#9749;', zip:'&#128230;', gz:'&#128230;', tar:'&#128230;',
    exe:'&#9881;', bat:'&#128220;', sh:'&#128220;', java:'&#9749;',
    groovy:'&#128220;', xml:'&#128203;', yml:'&#128203;', yaml:'&#128203;',
    json:'&#128203;', md:'&#128221;', txt:'&#128196;', png:'&#128444;',
    jpg:'&#128444;', jpeg:'&#128444;', ico:'&#128444;', pdf:'&#128196;',
    class:'&#9749;', xsl:'&#128203;', cnf:'&#9881;', ini:'&#9881;',
    iml:'&#128203;', service:'&#9881;', sql:'&#128451;', log:'&#128196;'
  };
  return m[e] || '&#128196;';
}

function splitNameAndTag(name) {
  const m = name.match(/^(.*)\s+\(\s+([IP])\s+\)$/);
  if (!m) return { displayName: name, packIdx: '' };
  return { displayName: m[1], packIdx: m[2] };
}

function ensureChildrenRendered(chEl) {
  if (!chEl._lazyChildren) return;
  const frag = document.createDocumentFragment();
  for (const c of chEl._lazyChildren) frag.appendChild(buildNode(c, chEl._lazyDepth + 1));
  chEl.appendChild(frag);
  delete chEl._lazyChildren;
  delete chEl._lazyDepth;
}

function buildNode(node, depth) {
  const isDir = node.d;
  const parsed = splitNameAndTag(node.n);
  const cleanPath = normalizeLeafPath(node.fp || node.n);
  const hasKids = isDir && node.ch && node.ch.length > 0;
  const pct = total > 0 ? (node.s / total * 100) : 0;
  const tone = isDir ? (node.dp || 'dir') : normalizePrefix(node.p);
  const barCls = isDir
    ? (node.dp ? ('bar-' + node.dp) : 'bar-dir')
    : (node.p === 'H' ? 'bar-H' : node.p === 'B' ? 'bar-B' : 'bar-hist');
  const icoCls = isDir
    ? (node.dp ? ('ico-' + node.dp) : 'ico-dir')
    : (node.p === 'H' ? 'ico-H' : node.p === 'B' ? 'ico-B' : 'ico-hist');

  const div = document.createElement('div');
  div.className = 'node';

  const row = document.createElement('div');
  row.className = 'row' + (hasKids ? ' clickable' : '');
  row.title = 'Right-click a file row to view git history output';
  row.style.setProperty('--depth', depth);
  const historicalLeaf = isHistoricalLeaf(node);

  const lead = document.createElement('div');
  lead.className = 'lead';

  const tog = document.createElement('div');
  tog.className = 'tog';
  if (hasKids) tog.innerHTML = depth < 1 ? '&#9660;' : '&#9654;';

  const ico = document.createElement('div');
  ico.className = 'ico ' + icoCls;
  ico.innerHTML = isDir ? (depth < 1 ? '&#128194;' : '&#128193;') : fileIcon(parsed.displayName);

  const nm = document.createElement('div');
  nm.className = 'nm';
  nm.textContent = parsed.displayName;
  nm.title = parsed.displayName + ' \u2014 ' + fmtSz(node.s) + (node.c > 1 ? ' (' + node.c + ' revisions)' : '') + '\nRight-click a file row to view git history output';

  const tag = document.createElement('div');
  tag.className = 'tag';
  tag.textContent = isDir ? '' : parsed.packIdx;

  const barW = document.createElement('div');
  barW.className = 'bar-w';
  const bar = document.createElement('div');
  bar.className = 'bar ' + barCls;
  bar.style.width = Math.max(pct > 0 ? 0.3 : 0, Math.min(100, pct)) + '%';
  barW.appendChild(bar);

  const sz = document.createElement('div');
  sz.className = 'sz sz-' + tone;
  sz.textContent = fmtSz(node.s);

  const cnt = document.createElement('div');
  cnt.className = 'cnt cnt-' + tone;
  cnt.textContent = !isDir && node.c > 1 ? String(node.c) : '';

  lead.appendChild(tog);
  lead.appendChild(ico);
  lead.appendChild(nm);
  row.appendChild(lead);
  row.appendChild(tag);
  row.appendChild(barW);
  row.appendChild(sz);
  row.appendChild(cnt);
  div.appendChild(row);

  if (hasKids) {
    const ch = document.createElement('div');
    ch.className = 'children';

    const startCollapsed = depth >= 1;
    if (startCollapsed) {
      // Lazy: store child data, don't build DOM until first expand
      div.classList.add('collapsed');
      tog.innerHTML = '&#9654;';
      ico.innerHTML = '&#128193;';
      ch._lazyChildren = node.ch;
      ch._lazyDepth = depth;
    } else {
      for (const c of node.ch) ch.appendChild(buildNode(c, depth + 1));
    }
    div.appendChild(ch);

    row.onclick = () => {
      const collapsed = div.classList.toggle('collapsed');
      tog.innerHTML = collapsed ? '&#9654;' : '&#9660;';
      ico.innerHTML = collapsed ? '&#128193;' : '&#128194;';
      if (!collapsed) ensureChildrenRendered(ch);
    };
  } else if (historicalLeaf) {
    row.addEventListener('contextmenu', (ev) => {
      ev.preventDefault();
      showLogModal(cleanPath, parsed.displayName);
    });
  }
  return div;
}

function showLogModal(path, displayName) {
  const modal = document.getElementById('log-modal');
  const title = document.getElementById('log-title');
  const cmd = document.getElementById('log-cmd');
  const out = document.getElementById('log-out');
  const entry = FILE_LOGS[path];

  title.textContent = 'History: ' + displayName;
  if (entry) {
    cmd.textContent = entry.cmd;
    out.textContent = entry.out;
  } else {
    cmd.textContent = 'git log --all --full-history --summary --oneline -- ' + path;
    out.textContent = '(no precomputed output found for this path)';
  }

  modal.classList.add('show');
}

function closeLogModal() {
  document.getElementById('log-modal').classList.remove('show');
}

function expandAll() {
  function expandNode(el) {
    const ch = Array.from(el.children).find(child => child.classList.contains('children'));
    if (!ch) return;
    ensureChildrenRendered(ch);
    el.classList.remove('collapsed');
    const row = Array.from(el.children).find(child => child.classList.contains('row'));
    const t = row && row.querySelector('.tog'); if (t) t.innerHTML = '&#9660;';
    const i = row && row.querySelector('.ico'); if (i && i.classList.contains('ico-dir')) i.innerHTML = '&#128194;';
    Array.from(ch.children).filter(child => child.classList.contains('node')).forEach(expandNode);
  }
  document.querySelectorAll('#tree>.node').forEach(expandNode);
  document.querySelectorAll('#tree .node').forEach(el => {
    const ch = Array.from(el.children).find(child => child.classList.contains('children'));
    if (!ch) return;
    const row = Array.from(el.children).find(child => child.classList.contains('row'));
    const t = row && row.querySelector('.tog'); if (t) t.innerHTML = '&#9660;';
  });
}

function collapseAll() {
  document.querySelectorAll('#tree .node').forEach(n => {
    const ch = Array.from(n.children).find(child => child.classList.contains('children'));
    if (!ch) return;
    n.classList.add('collapsed');
    const row = Array.from(n.children).find(child => child.classList.contains('row'));
    const t = row && row.querySelector('.tog'); if (t) t.innerHTML = '&#9654;';
    const i = row && row.querySelector('.ico'); if (i && i.classList.contains('ico-dir')) i.innerHTML = '&#128193;';
  });
}

function setDepth(max) {
  treeDepth = Math.max(0, max);
  collapseAll();
  function openTo(el, d) {
    if (d >= max) return;
    const ch = el.querySelector(':scope>.children');
    if (ch) {
      ensureChildrenRendered(ch);
      el.classList.remove('collapsed');
      const t = el.querySelector(':scope>.row>.tog'); if (t) t.innerHTML = '&#9660;';
      const i = el.querySelector(':scope>.row>.ico'); if (i && i.classList.contains('ico-dir')) i.innerHTML = '&#128194;';
    }
    el.querySelectorAll(':scope>.children>.node').forEach(c => openTo(c, d + 1));
  }
  document.querySelectorAll('#tree>.node').forEach(n => openTo(n, 0));
}

function changeDepth(delta) {
  setDepth(treeDepth + delta);
}

function renderTree() {
  const tree = document.getElementById('tree');
  tree.innerHTML = '';

  const filteredRoot = {
    ...DATA,
    ch: (DATA.ch || []).map(c => filterTree(c, '')).filter(Boolean)
  };
  renderExtensionTable(filteredRoot.ch);
  for (const c of filteredRoot.ch) tree.appendChild(buildNode(c, 0));
  if (pathRegexText) {
    expandAll();
  } else {
    collapseAll();
  }

  const totalVisible = filteredRoot.ch.reduce((sum, c) => sum + countVisibleFiles(c), 0);
  const totalVisibleSize = filteredRoot.ch.reduce((sum, c) => sum + sumVisibleFileSize(c), 0);
  updateFilteredStats(totalVisible, totalVisibleSize);
}

function renderTreeAsync(token) {
  const tree = document.getElementById('tree');
  if (token !== renderToken) return;

  const filteredRoot = {
    ...DATA,
    ch: (DATA.ch || []).map(c => filterTree(c, '')).filter(Boolean)
  };

  if (token !== renderToken) return;

  renderExtensionTable(filteredRoot.ch);
  tree.innerHTML = '';

  const topNodes = filteredRoot.ch || [];
  let idx = 0;
  const chunkSize = 24;

  function appendChunk() {
    if (token !== renderToken) return;

    const frag = document.createDocumentFragment();
    let n = 0;
    while (idx < topNodes.length && n < chunkSize) {
      frag.appendChild(buildNode(topNodes[idx], 0));
      idx++;
      n++;
    }
    tree.appendChild(frag);

    if (idx < topNodes.length) {
      requestAnimationFrame(appendChunk);
      return;
    }

    if (pathRegexText) {
      expandAll();
    } else {
      collapseAll();
    }

    const totalVisible = filteredRoot.ch.reduce((sum, c) => sum + countVisibleFiles(c), 0);
    const totalVisibleSize = filteredRoot.ch.reduce((sum, c) => sum + sumVisibleFileSize(c), 0);
    updateFilteredStats(totalVisible, totalVisibleSize);
  }

  requestAnimationFrame(appendChunk);
}

function scheduleRender(debounceMs) {
  if (renderTimer) {
    clearTimeout(renderTimer);
    renderTimer = null;
  }

  const token = ++renderToken;
  renderTimer = setTimeout(() => {
    renderTimer = null;
    renderTreeAsync(token);
  }, debounceMs);
}

(function () {
  function countFiles(n) { if (!n.d) totalFiles++; if (n.ch) n.ch.forEach(countFiles); }
  countFiles(DATA);
  document.getElementById('stat-total').textContent = fmtSz(total);
  document.getElementById('stat-modules').textContent =
    (REPORT_META.git_size_modules_url_count || '0') + ' ( ' + (REPORT_META.git_size_modules || '0M') + ' )';
  document.getElementById('stat-lfs').textContent =
    (REPORT_META.git_size_lfs || '0M') + ' (' + (REPORT_META.git_size_lfs_files_count || '0') + ' files)';
  document.getElementById('stat-files').textContent = totalFiles + ' / ' + totalFiles;
  const input = document.getElementById('path-filter');
  const clearFilter = document.getElementById('path-filter-clear');
  const typeH = document.getElementById('type-h');
  const typeB = document.getElementById('type-b');
  const typeHist = document.getElementById('type-hist');
  const typeReset = document.getElementById('type-filter-reset');
  const modal = document.getElementById('log-modal');
  const closeBtn = document.getElementById('log-close');

  function syncTypeFilters() {
    showH = !!typeH.checked;
    showB = !!typeB.checked;
    showHist = !!typeHist.checked;
  }

  typeH.addEventListener('change', () => {
    syncTypeFilters();
    scheduleRender(0);
  });
  typeB.addEventListener('change', () => {
    syncTypeFilters();
    scheduleRender(0);
  });
  typeHist.addEventListener('change', () => {
    syncTypeFilters();
    scheduleRender(0);
  });

  typeReset.addEventListener('click', () => {
    typeH.checked = true;
    typeB.checked = true;
    typeHist.checked = true;
    syncTypeFilters();
    scheduleRender(0);
  });

  syncTypeFilters();

  input.addEventListener('input', () => {
    pathRegexText = input.value.trim();
    if (!pathRegexText) {
      pathRegex = null;
      scheduleRender(0);
      return;
    }
    try {
      pathRegex = new RegExp(pathRegexText, 'i');
      scheduleRender(140);
    } catch (e) {
      renderToken += 1;
      if (renderTimer) {
        clearTimeout(renderTimer);
        renderTimer = null;
      }
      pathRegex = null;
    }
  });

  clearFilter.addEventListener('click', () => {
    input.value = '';
    input.dispatchEvent(new Event('input', { bubbles: true }));
    input.focus();
  });

  closeBtn.addEventListener('click', closeLogModal);
  modal.addEventListener('click', (ev) => {
    if (ev.target === modal) closeLogModal();
  });
  document.addEventListener('keydown', (ev) => {
    if (ev.key === 'Escape') closeLogModal();
  });

  scheduleRender(0);
})();
</script>
</body>
</html>'''

    return html_template.replace('__REPO__', repo_name).replace('__REPO_LINK__', repo_link).replace('__DATA__', tree_json).replace('__LOGS__', logs_json).replace('__EXT_VERDICTS__', ext_verdicts_json).replace('__META__', metadata_json)


def main():
    if len(sys.argv) not in (3, 4):
        print('Usage: git-object-sizes-tree-render.py <input_totals_file> <output_html_file> [repo_path]', file=sys.stderr)
        return 2

    input_file = sys.argv[1]
    output_file = sys.argv[2]
    repo_path = sys.argv[3] if len(sys.argv) == 4 else os.path.abspath(os.path.dirname(input_file))

    try:
      root = build_tree(input_file)
    except FileNotFoundError:
      print('Error: file not found: ' + input_file, file=sys.stderr)
      return 1

    tree_json = json.dumps(to_list(root))
    paths = collect_unique_paths(input_file, MIN_LOG_SIZE_BYTES)
    logs = collect_git_logs(repo_path, paths)
    if not isinstance(logs, dict):
      logs = {}
    logs_json = json.dumps(logs)
    ext_verdicts = load_extension_verdicts(input_file)
    ext_verdicts_json = json.dumps(ext_verdicts)
    repo_name = os.path.basename(os.path.abspath(os.path.dirname(input_file)))
    metadata = load_report_metadata(input_file)
    metadata_json = json.dumps(metadata)
    output_dir = os.path.dirname(os.path.abspath(output_file))
    repo_link = './'
    html = render_html(repo_name, repo_link, tree_json, logs_json, ext_verdicts_json, metadata_json)

    with open(output_file, 'w') as f:
        f.write(html)

    print('Saved: ' + output_file)
    return 0


if __name__ == '__main__':
    sys.exit(main())
