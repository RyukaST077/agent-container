#!/usr/bin/env node
// @ts-check
/**
 * agent-container installer
 *
 * Claude Code / Codex の「ナレッジループ」一式（skills + hooks +
 * knowledge/ 雛形 + .devcontainer）を、実行したカレントディレクトリ
 * （プロジェクト）に展開する。
 *
 * 使い方:
 *   npx github:RyukaST077/agent-container                 # 対話選択して導入
 *   npx github:RyukaST077/agent-container --agent codex   # Codex 用を導入
 *   npx github:RyukaST077/agent-container --agent both    # 両方を導入
 *
 * 依存ゼロ（Node 標準モジュールのみ）。
 */

import { fileURLToPath } from "node:url";
import path from "node:path";
import fs from "node:fs";
import readline from "node:readline";

const SCRIPT_DIR = path.dirname(fileURLToPath(import.meta.url));
const PKG_ROOT = path.resolve(SCRIPT_DIR, "..");
const CWD = process.cwd();

const AGENT_CHOICES = new Set(["claude", "codex", "both"]);
const COMMON_TARGETS = ["knowledge", ".devcontainer"];
const AGENT_TARGETS = {
  claude: [".claude"],
  codex: [".agents", ".codex"],
  both: [".claude", ".agents", ".codex"],
};

// 生成する agent ガイド（ナレッジループの起動導線）
const DOC_START = "<!-- agent-container:knowledge-loop:start -->";
const DOC_END = "<!-- agent-container:knowledge-loop:end -->";
const DOC_TARGETS = {
  claude: ["CLAUDE.md"],
  codex: ["AGENTS.md"],
  both: ["CLAUDE.md", "AGENTS.md"],
};

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
const AGENT = await resolveAgentChoice(argv);
const COPY_TARGETS = [...AGENT_TARGETS[AGENT], ...COMMON_TARGETS];

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
log(bold(cyan("\n  agent-container — Agent ナレッジループ導入\n")));
log(dim(`  source: ${PKG_ROOT}`));
log(dim(`  target: ${CWD}`));
log(dim(`  agent:  ${agentLabel(AGENT)}`));
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
  const isCodexHooks = rel === path.join(".codex", "hooks.json");
  const isCodexConfig = rel === path.join(".codex", "config.toml");

  // hooks を含む設定ファイルは、選択シェルに合わせて command を書き換えて反映する。
  if (isClaudeSettings) {
    handleClaudeSettings(src, dst, rel);
    return;
  }
  if (isCodexHooks) {
    handleCodexHooks(src, dst, rel);
    return;
  }
  if (isCodexConfig && fs.existsSync(dst)) {
    mergeCodexConfigFile(src, dst, rel);
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

/**
 * --agent / --target を解決。未指定で TTY なら選択、非TTYなら後方互換で claude。
 */
async function resolveAgentChoice(args) {
  let selected = null;

  for (let i = 0; i < args.length; i++) {
    const arg = args[i];
    if (arg === "--agent" || arg === "--target") {
      selected = args[i + 1] || "";
      i++;
    } else if (arg.startsWith("--agent=")) {
      selected = arg.slice("--agent=".length);
    } else if (arg.startsWith("--target=")) {
      selected = arg.slice("--target=".length);
    } else if (arg === "--claude") {
      selected = "claude";
    } else if (arg === "--codex") {
      selected = "codex";
    } else if (arg === "--both") {
      selected = "both";
    }
  }

  if (selected) {
    return normalizeAgentChoice(selected);
  }

  if (!process.stdin.isTTY || !process.stdout.isTTY || QUIET) {
    return "claude";
  }

  const rl = readline.createInterface({
    input: process.stdin,
    output: process.stdout,
  });
  try {
    while (true) {
      const answer = (
        await ask(
          rl,
          [
            "インストール対象を選択してください:",
            "  1) Claude Code",
            "  2) Codex",
            "  3) Both",
            "選択 [1]: ",
          ].join("\n")
        )
      ).trim();

      if (answer === "" || answer === "1") return "claude";
      if (answer === "2") return "codex";
      if (answer === "3") return "both";

      const normalized = normalizeAgentChoice(answer, false);
      if (normalized) return normalized;

      console.log(yellow("  claude / codex / both か 1 / 2 / 3 を入力してください。"));
    }
  } finally {
    rl.close();
  }
}

function ask(rl, question) {
  return new Promise((resolve) => rl.question(question, resolve));
}

function normalizeAgentChoice(value, exitOnError = true) {
  const normalized = String(value || "").trim().toLowerCase();
  if (AGENT_CHOICES.has(normalized)) return normalized;
  if (!exitOnError) return null;

  console.error(yellow(`ERROR: --agent は claude / codex / both のいずれかを指定してください: ${value}`));
  process.exit(2);
}

function agentLabel(agent) {
  if (agent === "claude") return "Claude Code";
  if (agent === "codex") return "Codex";
  return "Claude Code + Codex";
}

// ---- agent docs (CLAUDE.md / AGENTS.md) -----------------------------------

/**
 * 選択した agent に応じて CLAUDE.md / AGENTS.md を生成（または管理ブロックを更新）。
 */
function generateAgentDocs() {
  for (const filename of DOC_TARGETS[AGENT]) {
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
 * AGENTS.md（Codex）はスキルの所在を明示し、起動導線になる。
 */
function docBlock(filename) {
  const isCodex = filename === "AGENTS.md";
  const skillsDir = isCodex ? ".agents/skills" : ".claude/skills";
  const taskTool = isCodex ? "update_plan" : "TaskCreate / TaskUpdate";
  const locationNote = isCodex
    ? `スキル定義は \`${skillsDir}/<name>/SKILL.md\` にあります。下記トリガに該当したら、対応する SKILL.md を読み、その手順に従って実行してください。`
    : `スキルは \`${skillsDir}/\` から自動で読み込まれます。下記トリガに該当すると自律的に起動します。`;

  return [
    DOC_START,
    "## ナレッジループ（agent-container 自動生成 / このブロックは再実行で更新されます）",
    "",
    "このプロジェクトには開発トラブルを「記録して再利用する」ループが導入されています。",
    "マーカー内は `npx agent-container` の再実行で上書きされます。手書きの追記はマーカーの外で行ってください。",
    "",
    "### スキルの読み込み",
    locationNote,
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
    "- `implement` … 実装計画書に沿って実装。" +
      taskTool +
      " でタスク管理し、最後に必ずシステムを起動して Playwright で動作確認する。",
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
  const block = docBlock(filename);

  if (!fs.existsSync(dst)) {
    const content =
      `# ${filename}\n\n${agentLabel(AGENT)} 向けのプロジェクトガイド。\n\n${block}\n`;
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

/**
 * .codex/hooks.json を安全マージ。
 */
function mergeCodexHooksFile(src, dst, rel) {
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

  const merged = { ...existing };
  merged.hooks = mergeHooks(existing.hooks, incoming.hooks);

  if (JSON.stringify(merged) === JSON.stringify(existing)) {
    stats.skipped.push(rel);
    log(`  ${dim("skip ")} ${rel} ${dim("(マージ差分なし)")}`);
    return;
  }

  if (!DRY) {
    fs.writeFileSync(dst, JSON.stringify(merged, null, 2) + "\n");
  }
  stats.merged.push(rel);
  log(`  ${cyan("merge")} ${rel} ${dim("(hooks を追記)")}`);
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
 * 既知の自前フック（.claude/hooks/*.sh, .codex/hooks/*.sh）だけを対象にし、
 * ユーザ独自のコマンドには手を加えない。
 */
function toPowershellCommand(command) {
  if (typeof command !== "string") return command;

  // Claude: bash "$CLAUDE_PROJECT_DIR/.claude/hooks/<name>.sh"
  //   -> Claude Code が $CLAUDE_PROJECT_DIR を実パスに展開する。
  let m = command.match(
    /^bash\s+"\$\{?CLAUDE_PROJECT_DIR\}?\/(.+?)\.sh"\s*$/
  );
  if (m) {
    return `powershell -NoProfile -ExecutionPolicy Bypass -File "$CLAUDE_PROJECT_DIR/${m[1]}.ps1"`;
  }

  // Codex: bash "$(git rev-parse --show-toplevel)/.codex/hooks/<name>.sh"
  //   -> PowerShell の部分式でリポジトリルートを解決する。
  m = command.match(
    /^bash\s+"\$\(git rev-parse --show-toplevel\)\/(.+?)\.sh"\s*$/
  );
  if (m) {
    return `powershell -NoProfile -ExecutionPolicy Bypass -Command "& (Join-Path (git rev-parse --show-toplevel) '${m[1]}.ps1')"`;
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

/**
 * .codex/hooks.json を反映する。既存なら安全マージ、無ければ新規作成。
 */
function handleCodexHooks(src, dst, rel) {
  if (fs.existsSync(dst)) {
    mergeCodexHooksFile(src, dst, rel);
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
 * .codex/config.toml を安全マージ。
 *
 * TOML 全体の意味解析はせず、配布元 config の「section + key」を既存ファイルへ
 * 欠けている分だけ追記する。既存値は常に優先する。
 */
function mergeCodexConfigFile(src, dst, rel) {
  let incoming, existing;
  try {
    incoming = fs.readFileSync(src, "utf8");
  } catch (e) {
    log(`  ${yellow("warn ")} ${rel} 配布元の読み込みに失敗: ${e.message}`);
    return;
  }
  try {
    existing = fs.readFileSync(dst, "utf8");
  } catch (e) {
    log(`  ${yellow("warn ")} ${rel} 既存ファイルの読み込みに失敗: ${e.message}`);
    stats.skipped.push(rel);
    return;
  }

  const merged = mergeTomlBySection(existing, incoming);

  if (merged === existing) {
    stats.skipped.push(rel);
    log(`  ${dim("skip ")} ${rel} ${dim("(マージ差分なし)")}`);
    return;
  }

  if (!DRY) {
    fs.writeFileSync(dst, merged);
  }
  stats.merged.push(rel);
  log(`  ${cyan("merge")} ${rel} ${dim("(Codex config を追記)")}`);
}

function mergeTomlBySection(existingText, incomingText) {
  const existing = parseTomlSections(existingText);
  const incoming = parseTomlSections(incomingText);
  let out = existingText.replace(/\s*$/, "\n");

  for (const [section, inSection] of incoming.sections.entries()) {
    if (!existing.sections.has(section)) {
      out += "\n" + renderTomlSection(section, inSection.bodyLines);
      continue;
    }

    const exSection = existing.sections.get(section);
    const additions = [];
    for (const line of inSection.bodyLines) {
      const key = tomlKey(line);
      if (!key || exSection.keys.has(key)) continue;
      additions.push(line);
    }
    if (!additions.length) continue;
    out = insertTomlLinesAtSectionEnd(out, section, additions);
  }

  return out.replace(/\s*$/, "\n");
}

function parseTomlSections(text) {
  const sections = new Map();
  let current = "";
  sections.set(current, { bodyLines: [], keys: new Set() });

  for (const line of text.split(/\r?\n/)) {
    const section = tomlSection(line);
    if (section !== null) {
      current = section;
      if (!sections.has(current)) {
        sections.set(current, { bodyLines: [], keys: new Set() });
      }
      continue;
    }

    const entry = sections.get(current);
    entry.bodyLines.push(line);
    const key = tomlKey(line);
    if (key) entry.keys.add(key);
  }

  return { sections };
}

function tomlSection(line) {
  const m = line.match(/^\s*\[([^\]]+)\]\s*(?:#.*)?$/);
  return m ? m[1].trim() : null;
}

function tomlKey(line) {
  const trimmed = line.trim();
  if (!trimmed || trimmed.startsWith("#") || trimmed.startsWith("[")) return null;
  const m = trimmed.match(/^("[^"]+"|[A-Za-z0-9_.:-]+)\s*=/);
  return m ? m[1] : null;
}

function renderTomlSection(section, bodyLines) {
  const useful = bodyLines.filter((line) => line.trim() !== "");
  if (section === "") {
    return useful.join("\n") + "\n";
  }
  return `[${section}]\n${useful.join("\n")}\n`;
}

function insertTomlLinesAtSectionEnd(text, section, lines) {
  const split = text.split(/\n/);
  let start = -1;
  let end = split.length;

  if (section === "") {
    start = 0;
    end = split.findIndex((line) => tomlSection(line) !== null);
    if (end === -1) end = split.length;
  } else {
    for (let i = 0; i < split.length; i++) {
      if (tomlSection(split[i]) === section) {
        start = i;
        break;
      }
    }
    if (start === -1) return text;
    for (let i = start + 1; i < split.length; i++) {
      if (tomlSection(split[i]) !== null) {
        end = i;
        break;
      }
    }
  }

  const insertion = lines.filter((line) => line.trim() !== "");
  split.splice(end, 0, ...insertion);
  return split.join("\n");
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
  const m = command.match(/(\.(?:claude|codex)\/hooks\/[A-Za-z0-9_-]+)\.(?:sh|ps1)/);
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
  if (AGENT === "codex") {
    log(dim("  次の一歩: Codex を再起動し、必要に応じて /hooks で project-local hooks を信頼してください。"));
    log(dim("            Skills は .agents/skills/、設定は .codex/config.toml から読み込まれます。"));
  } else if (AGENT === "both") {
    log(dim("  次の一歩: Claude Code / Codex を再起動してください。Codex は必要に応じて /hooks で"));
    log(dim("            project-local hooks を信頼してください。"));
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
agent-container — Claude Code / Codex ナレッジループ導入インストーラ

USAGE
  npx github:RyukaST077/agent-container [options]

何をするか
  カレントディレクトリに以下を展開します（既存ファイルは保持）:
    Claude Code: .claude/skills/ .claude/hooks/ .claude/settings.json
    Codex:       .agents/skills/ .codex/hooks/ .codex/hooks.json .codex/config.toml
    Common:      knowledge/ .devcontainer/
    フック:      .sh（bash）と .ps1（PowerShell）の両方を展開し、設定ファイルの
                 command は選択シェルに合わせて自動で書き換えます（Windows 既定: PowerShell）
    ガイド:      CLAUDE.md（claude）/ AGENTS.md（codex）にナレッジループの
                 管理ブロックを生成・更新（既存ファイルはブロックのみ更新）

OPTIONS
  --agent <name>  claude / codex / both から選択（TTYでは未指定時に質問）
  --claude        --agent claude と同じ
  --codex         --agent codex と同じ
  --both          --agent both と同じ
  --shell <name>  フックのシェルを bash / powershell から指定
                  （既定: Windows は powershell、その他は bash）
  --powershell    --shell powershell と同じ（Windows 向け）
  --bash          --shell bash と同じ
  -f, --force     既存ファイルも上書きする
  -n, --dry-run   実際には書き込まず、変更内容だけ表示
  -q, --quiet     ログを抑制
  --no-docs       CLAUDE.md / AGENTS.md の生成・更新を行わない
  -h, --help      このヘルプを表示
`);
}
