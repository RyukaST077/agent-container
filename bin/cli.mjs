#!/usr/bin/env node
// @ts-check
/**
 * agent-container installer
 *
 * Claude Code の「ナレッジループ」一式（skills + hooks +
 * knowledge/ 雛形 + .devcontainer）を、実行したカレントディレクトリ
 * （プロジェクト）に展開する。
 *
 * 使い方:
 *   npx github:RyukaST077/agent-container            # 導入
 *   npx github:RyukaST077/agent-container --dry-run  # 差分だけ確認
 *
 * 依存ゼロ（Node 標準モジュールのみ）。
 */

import { fileURLToPath } from "node:url";
import path from "node:path";
import fs from "node:fs";

const SCRIPT_DIR = path.dirname(fileURLToPath(import.meta.url));
const PKG_ROOT = path.resolve(SCRIPT_DIR, "..");
const CWD = process.cwd();

const COPY_TARGETS = [".claude", "knowledge", ".devcontainer"];

// 生成する agent ガイド（ナレッジループの起動導線）
const DOC_START = "<!-- agent-container:knowledge-loop:start -->";
const DOC_END = "<!-- agent-container:knowledge-loop:end -->";
const DOC_TARGETS = ["CLAUDE.md"];

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

// ---- colors ---------------------------------------------------------------
const useColor = process.stdout.isTTY && !process.env.NO_COLOR;
const c = (code, s) => (useColor ? `\x1b[${code}m${s}\x1b[0m` : s);
const dim = (s) => c("2", s);
const green = (s) => c("32", s);
const yellow = (s) => c("33", s);
const cyan = (s) => c("36", s);
const bold = (s) => c("1", s);

// ---- args -----------------------------------------------------------------
const argv = process.argv.slice(2);

if (argv.includes("--help") || argv.includes("-h")) {
  printHelp();
  process.exit(0);
}

const FORCE = argv.includes("--force") || argv.includes("-f");
const DRY = argv.includes("--dry-run") || argv.includes("-n");
const QUIET = argv.includes("--quiet") || argv.includes("-q");
const NO_DOCS = argv.includes("--no-docs");
// フックを動かすシェル。Windows は既定で PowerShell、その他は bash。
const SHELL = resolveShell(argv);

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
log(dim(`  shell:  ${SHELL === "powershell" ? "PowerShell (.ps1)" : "bash (.sh)"}`));
if (DRY) log(yellow("  (dry-run: 実際の書き込みは行いません)"));
log("");

for (const top of COPY_TARGETS) {
  const src = path.join(PKG_ROOT, top);
  if (!fs.existsSync(src)) continue;
  walkCopy(src, path.join(CWD, top));
}

if (!NO_DOCS) generateAgentDocs();

printSummary();

// ---- functions ------------------------------------------------------------

/**
 * src（ファイル or ディレクトリ）を dst に再帰コピー。
 */
function walkCopy(src, dst) {
  const st = fs.statSync(src);
  if (st.isDirectory()) {
    if (path.basename(src) === ".cache") {
      return;
    }
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
  const isClaudeSettings = rel === path.join(".claude", "settings.json");

  // hooks を含む設定ファイルは、選択シェルに合わせて command を書き換えて反映する。
  if (isClaudeSettings) {
    handleClaudeSettings(src, dst, rel);
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
    writeCopiedFile(src, dst);
    maybeChmod(dst, rel);
  } else {
    maybeChmod(dst, rel, /*dryOnly*/ true);
  }
  stats.created.push(rel);
  const verb = existed ? yellow("force") : green("write");
  log(`  ${verb} ${rel}`);
}

// ---- agent docs (CLAUDE.md) -----------------------------------------------

/**
 * CLAUDE.md を生成（または管理ブロックを更新）。
 */
function generateAgentDocs() {
  for (const filename of DOC_TARGETS) {
    writeManagedDoc(filename);
  }
}

/**
 * 手動検索コマンドのヒントを、選択シェルに合わせて組み立てる。
 */
function manualSearchHint(skillsDir) {
  const base = `${skillsDir}/consult-knowledge/scripts/search-knowledge`;
  if (SHELL === "powershell") {
    return `\`powershell -NoProfile -ExecutionPolicy Bypass -File ${base}.ps1 "<語1>" "<語2>"\``;
  }
  return `\`bash ${base}.sh "<語1>" "<語2>"\``;
}

/**
 * マーカーで囲まれた「ナレッジループ」管理ブロックを組み立てる。
 */
function docBlock() {
  const skillsDir = ".claude/skills";

  return [
    DOC_START,
    "## ナレッジループ（agent-container 自動生成 / このブロックは再実行で更新されます）",
    "",
    "このプロジェクトには開発トラブルを「記録して再利用する」ループが導入されています。",
    "マーカー内は `npx agent-container` の再実行で上書きされます。手書きの追記はマーカーの外で行ってください。",
    "",
    "### スキルの読み込み",
    `スキルは \`${skillsDir}/\` から自動で読み込まれます。下記トリガに該当すると自律的に起動します。`,
    "",
    "### トラブルが起きたら（まず最初に）",
    "ゼロから調査する前に、`knowledge/` に同じトラブルの解決記録がないか確認する。",
    "- スキル: `consult-knowledge`",
    "- 手動検索: " + manualSearchHint(skillsDir),
    "",
    "### トラブルが解決したら",
    "未記録の新しいトラブルは `save-knowledge` で `knowledge/YYYY-MM-DD-<slug>.md` に記録する。",
    "",
    "### その他のスキル",
    "- `implement` … 実装計画書に沿って実装。TaskCreate / TaskUpdate " +
      "でタスク管理し、最後に必ずシステムを起動して Playwright で動作確認する。",
    "- `update-skill` … 既存スキルを安全に更新する。",
    "",
    "運用ルールの詳細は `knowledge/README.md` を参照。",
    DOC_END,
  ].join("\n");
}

/**
 * 管理ブロックをファイルに反映する。
 * - 無ければ見出し付きで新規作成
 * - マーカーがあれば中身を差し替え（冪等）
 * - マーカーが無ければ末尾に追記（既存の手書き内容は保持）
 */
function writeManagedDoc(filename) {
  const dst = path.join(CWD, filename);
  const rel = filename;
  const block = docBlock();

  if (!fs.existsSync(dst)) {
    const content =
      `# ${filename}\n\nClaude Code 向けのプロジェクトガイド。\n\n${block}\n`;
    if (!DRY) fs.writeFileSync(dst, content);
    stats.created.push(rel);
    log(`  ${green("write")} ${rel} ${dim("(ナレッジループ ガイド)")}`);
    return;
  }

  const existing = fs.readFileSync(dst, "utf8");
  const startIdx = existing.indexOf(DOC_START);
  const endIdx = existing.indexOf(DOC_END);

  let next;
  if (startIdx !== -1 && endIdx !== -1 && endIdx > startIdx) {
    next =
      existing.slice(0, startIdx) + block + existing.slice(endIdx + DOC_END.length);
  } else {
    next = existing.replace(/\s*$/, "\n") + "\n" + block + "\n";
  }

  if (next === existing) {
    stats.skipped.push(rel);
    log(`  ${dim("skip ")} ${rel} ${dim("(ブロック差分なし)")}`);
    return;
  }

  if (!DRY) fs.writeFileSync(dst, next);
  stats.merged.push(rel);
  log(`  ${cyan("merge")} ${rel} ${dim("(ナレッジループ ブロックを更新)")}`);
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
  if (incoming && incoming.hooks) {
    incoming = { ...incoming, hooks: platformizeHooks(incoming.hooks) };
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

// ---- shell / hooks platformization ----------------------------------------

/**
 * フックを動かすシェルを解決する。
 * 優先度: --shell/--bash/--powershell > AGENT_CONTAINER_SHELL > プラットフォーム既定。
 * 既定は Windows なら powershell、その他は bash。
 */
function resolveShell(args) {
  let selected = null;
  for (let i = 0; i < args.length; i++) {
    const arg = args[i];
    if (arg === "--shell") {
      selected = args[i + 1] || "";
      i++;
    } else if (arg.startsWith("--shell=")) {
      selected = arg.slice("--shell=".length);
    } else if (arg === "--powershell" || arg === "--pwsh") {
      selected = "powershell";
    } else if (arg === "--bash") {
      selected = "bash";
    }
  }
  if (!selected && process.env.AGENT_CONTAINER_SHELL) {
    selected = process.env.AGENT_CONTAINER_SHELL;
  }

  if (selected) {
    const n = String(selected).trim().toLowerCase();
    if (["powershell", "pwsh", "ps", "windows", "win"].includes(n)) return "powershell";
    if (["bash", "sh", "posix", "unix"].includes(n)) return "bash";
    console.error(yellow(`ERROR: --shell は bash / powershell のいずれかを指定してください: ${selected}`));
    process.exit(2);
  }

  return process.platform === "win32" ? "powershell" : "bash";
}

/**
 * bash 用フックコマンドを、選択シェルに合わせて書き換える。
 * 既知の自前フック（.claude/hooks/*.sh）だけを対象にし、
 * ユーザ独自のコマンドには手を加えない。
 */
function toPowershellCommand(command) {
  if (typeof command !== "string") return command;

  // Claude: bash "$CLAUDE_PROJECT_DIR/.claude/hooks/<name>.sh"
  //   -> Claude Code が $CLAUDE_PROJECT_DIR を実パスに展開する。
  const m = command.match(
    /^bash\s+"\$\{?CLAUDE_PROJECT_DIR\}?\/(.+?)\.sh"\s*$/
  );
  if (m) {
    return `powershell -NoProfile -ExecutionPolicy Bypass -File "$CLAUDE_PROJECT_DIR/${m[1]}.ps1"`;
  }

  return command;
}

/**
 * hooks ツリー（{ event: [ { matcher?, hooks: [ { type, command } ] } ] }）の
 * command を選択シェル向けに書き換える。bash 選択時は無変換。
 */
function platformizeHooks(hooksObj) {
  if (SHELL !== "powershell" || !hooksObj || typeof hooksObj !== "object") {
    return hooksObj;
  }
  const out = {};
  for (const [event, entries] of Object.entries(hooksObj)) {
    const list = Array.isArray(entries) ? entries : [];
    out[event] = list.map((entry) => ({
      ...entry,
      hooks: (Array.isArray(entry.hooks) ? entry.hooks : []).map((h) =>
        h && h.type === "command" && typeof h.command === "string"
          ? { ...h, command: toPowershellCommand(h.command) }
          : h
      ),
    }));
  }
  return out;
}

/**
 * .claude/settings.json を反映する。既存なら安全マージ、無ければ新規作成。
 * いずれも hooks の command を選択シェル向けに書き換える。
 */
function handleClaudeSettings(src, dst, rel) {
  if (fs.existsSync(dst)) {
    mergeSettingsFile(src, dst, rel);
    return;
  }
  let incoming;
  try {
    incoming = JSON.parse(fs.readFileSync(src, "utf8"));
  } catch (e) {
    log(`  ${yellow("warn ")} ${rel} 配布元の JSON 解析に失敗: ${e.message}`);
    return;
  }
  if (incoming && incoming.hooks) {
    incoming = { ...incoming, hooks: platformizeHooks(incoming.hooks) };
  }
  writeFreshJson(dst, rel, incoming);
}

function writeFreshJson(dst, rel, obj) {
  if (!DRY) {
    fs.mkdirSync(path.dirname(dst), { recursive: true });
    fs.writeFileSync(dst, JSON.stringify(obj, null, 2) + "\n");
  }
  stats.created.push(rel);
  const note = SHELL === "powershell" ? dim(" (PowerShell hooks)") : "";
  log(`  ${green("write")} ${rel}${note}`);
}

/**
 * 通常ファイルを書き出す。.ps1 は Windows PowerShell 5.1 が日本語を正しく
 * 読めるよう UTF-8 BOM 付きで書き出す。
 */
function writeCopiedFile(src, dst) {
  if (dst.endsWith(".ps1")) {
    const text = fs.readFileSync(src, "utf8").replace(/^﻿/, "");
    fs.writeFileSync(dst, "﻿" + text);
    return;
  }
  fs.copyFileSync(src, dst);
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
 * hooks をイベント単位でマージ。
 * - 完全一致のエントリは重複排除（同一 command の連発を防ぐ）。
 * - 同じ自前フックの「別シェル版」（bash<->powershell / .sh<->.ps1）が既存にあれば
 *   取り除いてから取り込む。これにより --shell を切り替えて再実行しても二重登録に
 *   ならず、選択したシェルの command に更新される（ユーザのカスタムフックは保持）。
 */
function mergeHooks(existing = {}, incoming = {}) {
  const out = { ...existing };
  for (const [event, inEntries] of Object.entries(incoming)) {
    let cur = Array.isArray(out[event]) ? out[event].slice() : [];

    // 取り込む自前フックの論理 ID（matcher + スクリプト名、シェル非依存）。
    const incomingIds = new Set(inEntries.map(logicalHookId).filter(Boolean));
    // 同じ論理 ID を持つ既存エントリは、完全一致するものだけ残す（別シェル版は除去）。
    cur = cur.filter((entry) => {
      const id = logicalHookId(entry);
      if (!id || !incomingIds.has(id)) return true; // 無関係／ユーザ独自フックは保持
      return inEntries.some((ie) => entrySignature(ie) === entrySignature(entry));
    });

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
 * 自前フックを「matcher + スクリプト名」でシェル非依存に識別する論理 ID。
 * 例: bash/.sh 版も powershell/.ps1 版も同じ ID になる。自前フックでなければ null。
 */
function logicalHookId(entry) {
  const id = (entry.hooks || [])
    .map((h) => h && hookScriptId(h.command))
    .find(Boolean);
  return id ? `${entry.matcher || ""}::${id}` : null;
}

function hookScriptId(command) {
  if (typeof command !== "string") return null;
  const m = command.match(/(\.claude\/hooks\/[A-Za-z0-9_-]+)\.(?:sh|ps1)/);
  return m ? m[1] : null;
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
  log(dim("  次の一歩: VS Code / Cursor で Dev Containers: Reopen in Container を実行し、"));
  log(dim("            DevContainer を起動してください。設定は .devcontainer/devcontainer.json。"));
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
    Claude Code: .claude/skills/ .claude/hooks/ .claude/settings.json
    Common:      knowledge/ .devcontainer/
    フック:      .sh（bash）と .ps1（PowerShell）の両方を展開し、設定ファイルの
                 command は選択シェルに合わせて自動で書き換えます（Windows 既定: PowerShell）
    ガイド:      CLAUDE.md にナレッジループの管理ブロックを生成・更新
                 （既存ファイルはブロックのみ更新）

OPTIONS
  --shell <name>  フックのシェルを bash / powershell から指定
                  （既定: Windows は powershell、その他は bash）
  --powershell    --shell powershell と同じ（Windows 向け）
  --bash          --shell bash と同じ
  -f, --force     既存ファイルも上書きする
  -n, --dry-run   実際には書き込まず、変更内容だけ表示
  -q, --quiet     ログを抑制
  --no-docs       CLAUDE.md の生成・更新を行わない
  -h, --help      このヘルプを表示
`);
}
