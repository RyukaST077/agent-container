#!/usr/bin/env node
// @ts-check
/**
 * agent-container installer
 *
 * Claude Code の「ナレッジループ」一式（skills + hooks + knowledge/ 雛形 +
 * .devcontainer）を、実行したカレントディレクトリ（プロジェクト）に展開する。
 *
 * 使い方:
 *   npx github:RyukaST077/agent-container          # 現在のディレクトリに導入
 *   npx github:RyukaST077/agent-container --force   # 既存ファイルも上書き
 *   npx github:RyukaST077/agent-container --dry-run # 変更内容を表示のみ
 *
 * 依存ゼロ（Node 標準モジュールのみ）。
 */

import { fileURLToPath } from "node:url";
import path from "node:path";
import fs from "node:fs";

const SCRIPT_DIR = path.dirname(fileURLToPath(import.meta.url));
const PKG_ROOT = path.resolve(SCRIPT_DIR, "..");
const CWD = process.cwd();

// CWD にコピーするトップレベル項目
const COPY_TARGETS = [".claude", "knowledge", ".devcontainer"];

// インストーラ自身の成果物（誤コピー防止）
const SELF_FILES = new Set([
  "bin",
  "package.json",
  "package-lock.json",
  "node_modules",
  ".git",
  ".gitignore",
  ".npmignore",
  "README.md",
  "LICENSE",
]);

// ---- args -----------------------------------------------------------------
const argv = process.argv.slice(2);
const FORCE = argv.includes("--force") || argv.includes("-f");
const DRY = argv.includes("--dry-run") || argv.includes("-n");
const QUIET = argv.includes("--quiet") || argv.includes("-q");

if (argv.includes("--help") || argv.includes("-h")) {
  printHelp();
  process.exit(0);
}

// ---- colors ---------------------------------------------------------------
const useColor = process.stdout.isTTY && !process.env.NO_COLOR;
const c = (code, s) => (useColor ? `\x1b[${code}m${s}\x1b[0m` : s);
const dim = (s) => c("2", s);
const green = (s) => c("32", s);
const yellow = (s) => c("33", s);
const cyan = (s) => c("36", s);
const bold = (s) => c("1", s);

// ---- guards ---------------------------------------------------------------
if (path.resolve(PKG_ROOT) === path.resolve(CWD)) {
  console.error(
    yellow(
      "⚠ このコマンドは配布元リポジトリ自体の中で実行されています。\n" +
        "  導入したいプロジェクトのルートで実行してください。"
    )
  );
  if (!DRY) process.exit(1);
}

const stats = { created: [], merged: [], skipped: [], chmod: [] };

// ---- main -----------------------------------------------------------------
log(bold(cyan("\n  agent-container — Claude Code ナレッジループ導入\n")));
log(dim(`  source: ${PKG_ROOT}`));
log(dim(`  target: ${CWD}`));
if (DRY) log(yellow("  (dry-run: 実際の書き込みは行いません)"));
log("");

for (const top of COPY_TARGETS) {
  const src = path.join(PKG_ROOT, top);
  if (!fs.existsSync(src)) continue;
  walkCopy(src, path.join(CWD, top));
}

printSummary();

// ---- functions ------------------------------------------------------------

/**
 * src（ファイル or ディレクトリ）を dst に再帰コピー。
 */
function walkCopy(src, dst) {
  const st = fs.statSync(src);
  if (st.isDirectory()) {
    if (SELF_FILES.has(path.basename(src)) && path.dirname(src) === PKG_ROOT) {
      return;
    }
    if (!DRY) fs.mkdirSync(dst, { recursive: true });
    for (const entry of fs.readdirSync(src)) {
      walkCopy(path.join(src, entry), path.join(dst, entry));
    }
    return;
  }

  // ファイル
  const rel = path.relative(CWD, dst);
  const isSettings = rel === path.join(".claude", "settings.json");

  if (isSettings && fs.existsSync(dst)) {
    mergeSettingsFile(src, dst, rel);
    return;
  }

  if (fs.existsSync(dst) && !FORCE) {
    stats.skipped.push(rel);
    log(`  ${dim("skip ")} ${rel} ${dim("(既存 — --force で上書き)")}`);
    return;
  }

  const existed = fs.existsSync(dst);
  if (!DRY) {
    fs.mkdirSync(path.dirname(dst), { recursive: true });
    fs.copyFileSync(src, dst);
    maybeChmod(dst, rel);
  } else {
    maybeChmod(dst, rel, /*dryOnly*/ true);
  }
  stats.created.push(rel);
  const verb = existed ? yellow("force") : green("write");
  log(`  ${verb} ${rel}`);
}

/**
 * 実行ビットが必要なファイル（*.sh）に 755 を付与。
 */
function maybeChmod(dst, rel, dryOnly = false) {
  if (!dst.endsWith(".sh")) return;
  if (!dryOnly) fs.chmodSync(dst, 0o755);
  stats.chmod.push(rel);
}

/**
 * .claude/settings.json を安全マージ。
 */
function mergeSettingsFile(src, dst, rel) {
  let incoming, existing;
  try {
    incoming = JSON.parse(fs.readFileSync(src, "utf8"));
  } catch (e) {
    log(`  ${yellow("warn ")} ${rel} 配布元の JSON 解析に失敗: ${e.message}`);
    return;
  }
  try {
    existing = JSON.parse(fs.readFileSync(dst, "utf8"));
  } catch (e) {
    log(
      `  ${yellow("warn ")} ${rel} 既存ファイルが不正な JSON のためマージをスキップ: ${e.message}`
    );
    stats.skipped.push(rel);
    return;
  }

  const merged = mergeSettings(existing, incoming);

  if (JSON.stringify(merged) === JSON.stringify(existing)) {
    stats.skipped.push(rel);
    log(`  ${dim("skip ")} ${rel} ${dim("(マージ差分なし)")}`);
    return;
  }

  if (!DRY) {
    fs.writeFileSync(dst, JSON.stringify(merged, null, 2) + "\n");
  }
  stats.merged.push(rel);
  log(`  ${cyan("merge")} ${rel} ${dim("(hooks / permissions / env を追記)")}`);
}

/**
 * settings オブジェクトの安全マージ。既存値を尊重し、欠けているものだけ補う。
 */
function mergeSettings(existing, incoming) {
  const out = { ...existing };
  for (const [k, v] of Object.entries(incoming)) {
    if (!(k in out)) {
      out[k] = v;
      continue;
    }
    if (k === "hooks") out[k] = mergeHooks(out[k], v);
    else if (k === "permissions") out[k] = mergePermissions(out[k], v);
    else if (k === "env") out[k] = { ...v, ...out[k] }; // 既存値を優先
    // それ以外のスカラー（effortLevel 等）は既存値を保持
  }
  return out;
}

/**
 * hooks をイベント単位でマージ。エントリ単位で重複排除（同一 command の連発を防ぐ）。
 */
function mergeHooks(existing = {}, incoming = {}) {
  const out = { ...existing };
  for (const [event, inEntries] of Object.entries(incoming)) {
    const cur = Array.isArray(out[event]) ? out[event].slice() : [];
    const seen = new Set(cur.map(entrySignature));
    for (const entry of inEntries) {
      const sig = entrySignature(entry);
      if (!seen.has(sig)) {
        cur.push(entry);
        seen.add(sig);
      }
    }
    out[event] = cur;
  }
  return out;
}

function entrySignature(entry) {
  // matcher + 各 hook の command で同一性を判定
  const cmds = (entry.hooks || []).map((h) => `${h.type}:${h.command}`);
  return JSON.stringify({ matcher: entry.matcher || "", cmds });
}

/**
 * permissions をマージ。deny/allow/ask は和集合、defaultMode は既存優先。
 */
function mergePermissions(existing = {}, incoming = {}) {
  const out = { ...existing };
  for (const key of ["deny", "allow", "ask"]) {
    if (!incoming[key]) continue;
    const base = Array.isArray(out[key]) ? out[key] : [];
    const set = new Set(base);
    out[key] = base.concat(incoming[key].filter((x) => !set.has(x)));
  }
  if (!("defaultMode" in out) && "defaultMode" in incoming) {
    out.defaultMode = incoming.defaultMode;
  }
  return out;
}

// ---- output ---------------------------------------------------------------
function printSummary() {
  log("");
  log(bold("  完了:"));
  log(`    ${green("write")} ${stats.created.length} 件`);
  log(`    ${cyan("merge")} ${stats.merged.length} 件`);
  log(`    ${dim("skip ")} ${stats.skipped.length} 件`);
  if (stats.chmod.length) log(`    ${dim("chmod 755")} ${stats.chmod.length} 件`);
  log("");
  if (stats.skipped.length && !FORCE) {
    log(dim("  既存ファイルは保持しました。上書きするには --force を付けて再実行。"));
  }
  log(dim("  次の一歩: Claude Code を起動し、トラブル時に consult-knowledge が"));
  log(dim("            効くか試してください。設定は .claude/settings.json。"));
  log("");
}

function log(s) {
  if (!QUIET) console.log(s);
}

function printHelp() {
  console.log(`
agent-container — Claude Code ナレッジループ導入インストーラ

USAGE
  npx github:RyukaST077/agent-container [options]

何をするか
  カレントディレクトリに以下を展開します（既存ファイルは保持）:
    .claude/skills/   consult-knowledge / save-knowledge / update-skill
    .claude/hooks/    consult/save を後押しする3つのフック
    .claude/settings.json  既存があれば hooks/permissions/env を安全マージ
    knowledge/        トラブル知見の蓄積フォルダ（README / INDEX / 雛形）
    .devcontainer/    開発コンテナ定義

OPTIONS
  -f, --force     既存ファイルも上書きする
  -n, --dry-run   実際には書き込まず、変更内容だけ表示
  -q, --quiet     ログを抑制
  -h, --help      このヘルプを表示
`);
}
