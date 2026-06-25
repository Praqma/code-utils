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


def render_html(repo_name, tree_json, logs_json):
    html_template = r'''<!DOCTYPE html>
<html lang="en">
<head><meta charset="UTF-8"><title>Git Object Sizes - __REPO__</title>
<style>
*{box-sizing:border-box;margin:0;padding:0}
body{font-family:'Segoe UI',Consolas,monospace;background:radial-gradient(circle at top left,#161a2d 0%,#0f1220 50%);color:#e5e9ff;margin:0;height:100vh;overflow:hidden}
#layout{display:grid;grid-template-columns:330px 1fr;height:100vh}
#sidebar{border-right:1px solid #39415f;background:#1a1f33;padding:16px;position:sticky;top:0;height:100vh;overflow:auto}
#main{padding:16px;display:grid;grid-template-rows:auto 1fr;gap:10px;height:100vh;overflow:hidden}
#main-top{display:grid;gap:6px}
h1{font-size:1.8em;color:#e5e9ff;margin-bottom:6px}
#summary{font-size:1em;color:#aab2d8;margin-bottom:0}
#sidebar-title{font-size:1.3em;margin-bottom:6px}
#sidebar-subtitle{font-size:.9em;color:#aab2d8;margin-bottom:12px}
#controls{display:grid;gap:10px}
#action-row{display:grid;grid-template-columns:1fr 1fr;gap:8px}
#filter-row{display:grid;gap:6px}
#filter-row label{font-size:.85em;color:#aab2d8}
#path-filter{background:#232944;color:#e5e9ff;border:1px solid #39415f;padding:8px 10px;border-radius:8px;font-size:.95em;width:100%}
#path-filter::placeholder{color:#8e97bc}
#filter-status{font-size:.9em;color:#a6adc8;min-height:1.2em}
#filter-status.err{color:#ef4444}
#type-filter-row{display:grid;gap:6px;font-size:.95em;border:1px solid #39415f;background:#1f243b;border-radius:10px;padding:10px}
#type-filter-row label{display:flex;align-items:center;gap:7px;cursor:pointer;line-height:1.2}
#type-filter-row input[type="checkbox"]{margin:0;transform:translateY(0)}
.section-title{font-size:.95em;color:#c9cedf;margin-top:4px}
.type-legend-line{display:flex;align-items:center;gap:7px;color:#aab2d8;font-size:.92em;padding-left:23px;line-height:1.2}
.type-inline-dot{width:10px;height:10px;border-radius:50%;display:inline-block;flex-shrink:0;position:relative;top:1px}
.type-inline-dot-h{background:#89b4fa}
.type-inline-dot-b{background:#fab387}
.type-inline-dot-hist{background:#ef4444}
.type-inline-dot-mixed{background:#c9cedf}
#ext-panel{border:1px solid #39415f;background:#1f243b;border-radius:10px;padding:10px;display:grid;gap:8px}
#ext-summary{font-size:.84em;color:#aab2d8}
#ext-table-wrap{max-height:260px;overflow:auto;border:1px solid #39415f;border-radius:8px}
#ext-table{width:100%;border-collapse:collapse;font-size:.84em}
#ext-table th{position:sticky;top:0;background:#232944;color:#c9cedf;text-align:left;padding:6px 8px;border-bottom:1px solid #39415f}
#ext-table td{padding:6px 8px;border-bottom:1px solid #2a2f48;color:#dfe4ff}
#ext-table td:last-child{text-align:right;color:#aab2d8}
#ext-table tr:last-child td{border-bottom:none}
#ext-empty{font-size:.84em;color:#8e97bc;padding:2px 0}
.ctx-hint{font-size:.82em;color:#8e97bc}
button{background:#232944;color:#e5e9ff;border:1px solid #39415f;padding:8px 10px;border-radius:8px;cursor:pointer;font-size:.95em}
button:hover{background:#45475a}
#tree-panel{display:grid;grid-template-rows:auto 1fr;min-height:0;border:1px solid #39415f;border-radius:10px;overflow:hidden;background:#151a2d}
#tree{font-size:.94em;overflow:auto;min-height:0}
.hdr{display:flex;gap:6px;padding:6px 8px;font-size:.9em;color:#aab2d8;border-bottom:1px solid #39415f;background:#1a1f33;user-select:none}
.hdr .h-tog{width:16px;flex-shrink:0}
.hdr .h-ico{width:18px;flex-shrink:0}
.hdr .h-name{flex:1;min-width:0}
.hdr .h-tag{width:72px;flex-shrink:0;text-align:center}
.hdr .h-bar{width:450px;flex-shrink:0;text-align:center}
.hdr .h-sz{width:82px;flex-shrink:0;text-align:right}
.hdr .h-cnt{width:56px;flex-shrink:0;text-align:right}
.node{margin:1px 0}
.row{display:flex;align-items:center;gap:6px;padding:2px 6px;border-radius:4px;cursor:default}
.row.clickable{cursor:pointer}
.row:hover{background:#2a2a3e}
.tog{width:16px;flex-shrink:0;font-size:.85em;color:#585b70;text-align:center}
.ico{flex-shrink:0;font-size:1em;width:18px;text-align:center}
.nm{flex:1;min-width:0;white-space:nowrap;overflow:hidden;text-overflow:ellipsis}
.tag{width:72px;flex-shrink:0;text-align:center;color:#aab2d8;font-size:.82em}
.bar-w{width:450px;flex-shrink:0;background:#40476b;border-radius:3px;height:9px;overflow:hidden}
.bar{height:9px;border-radius:3px;min-width:1px}
.sz{width:82px;flex-shrink:0;text-align:right;color:#a6adc8;font-size:.92em}
.cnt{width:56px;flex-shrink:0;text-align:right;color:#585b70;font-size:.88em}
.sz-dir{color:#c9cedf}
.sz-H{color:#89b4fa}
.sz-B{color:#fab387}
.sz-hist{color:#ef4444}
.cnt-dir{color:#c9cedf}
.cnt-H{color:#89b4fa}
.cnt-B{color:#fab387}
.cnt-hist{color:#ef4444}
.children{padding-left:18px;border-left:1px solid #2a2a3e;margin-left:14px}
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
  #main{height:auto;overflow:visible}
  #tree-panel{min-height:420px}
}
</style>
</head>
<body>
<div id="layout">
  <aside id="sidebar">
    <div id="sidebar-title">Filters</div>
    <div id="sidebar-subtitle">Path and type filters apply instantly as you type.</div>
    <div id="controls">
      <div id="filter-row">
        <label for="path-filter">Path regex</label>
        <input id="path-filter" type="text" placeholder="e.g. installer|\\.jar$" spellcheck="false" />
      </div>
      <div id="type-filter-row">
        <label><input id="type-h" type="checkbox" checked /><span class="type-inline-dot type-inline-dot-h"></span>H (HEAD/default branch)</label>
        <label><input id="type-b" type="checkbox" checked /><span class="type-inline-dot type-inline-dot-b"></span>B (branch only)</label>
        <label><input id="type-hist" type="checkbox" checked /><span class="type-inline-dot type-inline-dot-hist"></span>historical (not in active branches)</label>
        <div class="type-legend-line"><span class="type-inline-dot type-inline-dot-mixed"></span>mixed directories</div>
      </div>
      <div id="action-row">
        <button onclick="expandAll()">Expand All</button>
        <button onclick="collapseAll()">Collapse All</button>
        <button onclick="setDepth(1)">Top Level</button>
        <button onclick="setDepth(2)">2 Levels</button>
        <button onclick="setDepth(3)">3 Levels</button>
      </div>
      <div id="ext-panel">
        <div class="section-title">Extension Size Breakdown</div>
        <div id="ext-summary"></div>
        <div class="ctx-hint">Right-click a file row to view git history output.</div>
        <div id="ext-table-wrap">
          <table id="ext-table">
            <thead>
              <tr>
                <th>Extension</th>
                <th>Total Size</th>
              </tr>
            </thead>
            <tbody id="ext-table-body"></tbody>
          </table>
        </div>
        <div id="ext-empty" style="display:none">No matching files.</div>
      </div>
      <div id="filter-status"></div>
    </div>
  </aside>
  <main id="main">
    <div id="main-top">
      <h1>Git Object Sizes &mdash; __REPO__</h1>
      <div id="summary"></div>
    </div>
    <div id="tree-panel">
      <div class="hdr">
        <div class="h-tog"></div>
        <div class="h-ico"></div>
        <div class="h-name">Name</div>
        <div class="h-tag">Pack/Idx</div>
        <div class="h-bar">Relative Size</div>
        <div class="h-sz">Total Size</div>
        <div class="h-cnt">Revisions</div>
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
const total = DATA.s;
let pathRegexText = '';
let pathRegex = null;
let showH = true;
let showB = true;
let showHist = true;

function normalizeLeafPath(path) {
  return (path || '').replace(/\s+\(\s*[IP]\s*\)\s*$/i, '').trim();
}

function isHistoricalLeaf(node) {
  return !node.d && normalizePrefix(node.p) === 'hist';
}

function pathMatches(path) {
  if (pathRegex) {
    pathRegex.lastIndex = 0;
    if (!pathRegex.test(path)) return false;
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
  if (children.length > 0 || pathMatches(fullPath)) {
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

function fileExtFromPath(path) {
  const rawName = (path || '').split('/').pop() || '';
  const name = rawName.replace(/\s+\(\s*[IP]\s*\)\s*$/i, '');
  const dot = name.lastIndexOf('.');
  if (dot <= 0 || dot === name.length - 1) return '[no-ext]';
  return name.slice(dot + 1).toLowerCase();
}

function collectExtensionStats(node, stats) {
  if (!node) return;
  if (!node.d) {
    const ext = fileExtFromPath(node.fp || node.n);
    if (!stats[ext]) stats[ext] = 0;
    stats[ext] += (node.s || 0);
    return;
  }
  for (const c of (node.ch || [])) collectExtensionStats(c, stats);
}

function renderExtensionTable(filteredChildren) {
  const stats = {};
  for (const c of filteredChildren) collectExtensionStats(c, stats);

  const rows = Object.entries(stats).sort((a, b) => b[1] - a[1]);
  const body = document.getElementById('ext-table-body');
  const summary = document.getElementById('ext-summary');
  const empty = document.getElementById('ext-empty');
  const wrap = document.getElementById('ext-table-wrap');

  body.innerHTML = '';
  if (rows.length === 0) {
    summary.textContent = '';
    empty.style.display = 'block';
    wrap.style.display = 'none';
    return;
  }

  empty.style.display = 'none';
  wrap.style.display = 'block';

  let total = 0;
  for (const item of rows) total += item[1];
  summary.textContent = rows.length + ' extension(s), total ' + fmtSz(total);

  for (const item of rows) {
    const tr = document.createElement('tr');
    const tdExt = document.createElement('td');
    const tdSize = document.createElement('td');
    tdExt.textContent = item[0];
    tdSize.textContent = fmtSz(item[1]);
    tr.appendChild(tdExt);
    tr.appendChild(tdSize);
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
  const historicalLeaf = isHistoricalLeaf(node);

  const tog = document.createElement('div');
  tog.className = 'tog';
  if (hasKids) tog.innerHTML = depth < 1 ? '&#9660;' : '&#9654;';

  const ico = document.createElement('div');
  ico.className = 'ico ' + icoCls;
  ico.innerHTML = isDir ? (depth < 1 ? '&#128194;' : '&#128193;') : fileIcon(parsed.displayName);

  const nm = document.createElement('div');
  nm.className = 'nm';
  nm.textContent = parsed.displayName;
  nm.title = parsed.displayName + ' \u2014 ' + fmtSz(node.s) + (node.c > 1 ? ' (' + node.c + ' revisions)' : '');

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

  row.appendChild(tog);
  row.appendChild(ico);
  row.appendChild(nm);
  row.appendChild(tag);
  row.appendChild(barW);
  row.appendChild(sz);
  row.appendChild(cnt);
  div.appendChild(row);

  if (hasKids) {
    const ch = document.createElement('div');
    ch.className = 'children';
    for (const c of node.ch) ch.appendChild(buildNode(c, depth + 1));
    div.appendChild(ch);

    const startCollapsed = depth >= 1;
    if (startCollapsed) {
      div.classList.add('collapsed');
      tog.innerHTML = '&#9654;';
      ico.innerHTML = '&#128193;';
    }

    row.onclick = () => {
      const collapsed = div.classList.toggle('collapsed');
      tog.innerHTML = collapsed ? '&#9654;' : '&#9660;';
      ico.innerHTML = collapsed ? '&#128193;' : '&#128194;';
    };
  } else if (historicalLeaf) {
    row.title = 'Right-click to show git log history output';
    row.addEventListener('contextmenu', (ev) => {
      ev.preventDefault();
      showLogModal(cleanPath, parsed.displayName);
    });
  } else {
    row.title = 'History output is available only for historical files';
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
  document.querySelectorAll('.node.collapsed').forEach(n => {
    n.classList.remove('collapsed');
    const t = n.querySelector(':scope>.row>.tog'); if (t) t.innerHTML = '&#9660;';
    const i = n.querySelector(':scope>.row>.ico'); if (i && i.classList.contains('ico-dir')) i.innerHTML = '&#128194;';
  });
}

function collapseAll() {
  document.querySelectorAll('.node:not(.collapsed)').forEach(n => {
    if (n.querySelector(':scope>.children')) {
      n.classList.add('collapsed');
      const t = n.querySelector(':scope>.row>.tog'); if (t) t.innerHTML = '&#9654;';
      const i = n.querySelector(':scope>.row>.ico'); if (i && i.classList.contains('ico-dir')) i.innerHTML = '&#128193;';
    }
  });
}

function setDepth(max) {
  collapseAll();
  function openTo(el, d) {
    if (d >= max) return;
    if (el.querySelector(':scope>.children')) {
      el.classList.remove('collapsed');
      const t = el.querySelector(':scope>.row>.tog'); if (t) t.innerHTML = '&#9660;';
      const i = el.querySelector(':scope>.row>.ico'); if (i && i.classList.contains('ico-dir')) i.innerHTML = '&#128194;';
    }
    el.querySelectorAll(':scope>.children>.node').forEach(c => openTo(c, d + 1));
  }
  document.querySelectorAll('#tree>.node').forEach(n => openTo(n, 0));
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
    setDepth(1);
  }

  const totalVisible = filteredRoot.ch.reduce((sum, c) => sum + countVisibleFiles(c), 0);
  const totalVisibleSize = filteredRoot.ch.reduce((sum, c) => sum + sumVisibleFileSize(c), 0);
  const status = document.getElementById('filter-status');
  if (pathRegexText || !showH || !showB || !showHist) {
    status.classList.remove('err');
    status.textContent = totalVisible + ' matching file(s), total ' + fmtSz(totalVisibleSize);
  } else {
    status.textContent = '';
  }
}

(function () {
  let fc = 0;
  function countFiles(n) { if (!n.d) fc++; if (n.ch) n.ch.forEach(countFiles); }
  countFiles(DATA);
  document.getElementById('summary').textContent =
    'Total git object size across all revisions: ' + fmtSz(total) +
    ' \u2022 Unique files tracked: ' + fc;
  const input = document.getElementById('path-filter');
  const typeH = document.getElementById('type-h');
  const typeB = document.getElementById('type-b');
  const typeHist = document.getElementById('type-hist');
  const status = document.getElementById('filter-status');
  const modal = document.getElementById('log-modal');
  const closeBtn = document.getElementById('log-close');

  function syncTypeFilters() {
    showH = !!typeH.checked;
    showB = !!typeB.checked;
    showHist = !!typeHist.checked;
  }

  typeH.addEventListener('change', () => {
    syncTypeFilters();
    renderTree();
  });
  typeB.addEventListener('change', () => {
    syncTypeFilters();
    renderTree();
  });
  typeHist.addEventListener('change', () => {
    syncTypeFilters();
    renderTree();
  });

  syncTypeFilters();

  input.addEventListener('input', () => {
    pathRegexText = input.value.trim();
    if (!pathRegexText) {
      pathRegex = null;
      status.classList.remove('err');
      renderTree();
      return;
    }
    try {
      pathRegex = new RegExp(pathRegexText, 'i');
      status.classList.remove('err');
      renderTree();
    } catch (e) {
      pathRegex = null;
      status.classList.add('err');
      status.textContent = 'Invalid regex';
    }
  });

  closeBtn.addEventListener('click', closeLogModal);
  modal.addEventListener('click', (ev) => {
    if (ev.target === modal) closeLogModal();
  });
  document.addEventListener('keydown', (ev) => {
    if (ev.key === 'Escape') closeLogModal();
  });

  renderTree();
})();
</script>
</body>
</html>'''

    return html_template.replace('__REPO__', repo_name).replace('__DATA__', tree_json).replace('__LOGS__', logs_json)


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
    repo_name = os.path.basename(os.path.abspath(os.path.dirname(input_file)))
    html = render_html(repo_name, tree_json, logs_json)

    with open(output_file, 'w') as f:
        f.write(html)

    print('Saved: ' + output_file)
    return 0


if __name__ == '__main__':
    sys.exit(main())
