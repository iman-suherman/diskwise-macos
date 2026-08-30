#!/usr/bin/env node
/**
 * Track local DiskWise website deploy progress with live log tail preview.
 *
 * Usage:
 *   npm run ci
 *   npm run ci -- --once
 */

const path = require("node:path");
const { spawnSync } = require("node:child_process");
const { DEPLOY_TARGETS, REPO_ROOT } = require("./deploy-config.cjs");
const { readState, STATE_FILE, findDeployment } = require("./deploy-store.cjs");
const { lastLogLine, tailLogLines, sanitizeTerminal } = require("./deploy-log-utils.cjs");
const {
  getGcpBillingSummary,
  allocateTargetCosts,
  formatSummaryForDashboard,
  formatTargetCost,
} = require("./gcp-billing-ci.cjs");

const useColor = process.stdout.isTTY && !process.env.NO_COLOR;
const wrap =
  (open) =>
  (t) =>
    useColor ? `${open}${t}\x1b[0m` : t;
const green = wrap("\x1b[32m");
const red = wrap("\x1b[31m");
const yellow = wrap("\x1b[33m");
const cyan = wrap("\x1b[36m");
const magenta = wrap("\x1b[35m");
const blue = wrap("\x1b[34m");
const dim = wrap("\x1b[2m");
const bold = wrap("\x1b[1m");
const boldGreen = (t) => bold(green(t));
const boldRed = (t) => bold(red(t));
const boldYellow = (t) => bold(yellow(t));
const boldCyan = (t) => bold(cyan(t));
const boldWhite = (t) => (useColor ? `\x1b[1m${t}\x1b[0m` : t);

const LOG_TAIL_LINES = Number.parseInt(process.env.DISKWise_CI_LOG_LINES || "12", 10);
const ACTIVITY_LINES = Number.parseInt(process.env.DISKWise_CI_ACTIVITY_LINES || "8", 10);

const TABLE = {
  service: 28,
  url: 34,
  status: 10,
  head: 9,
  deployed: 9,
  cost: 10,
  lastRun: 16,
};

function parseArgs(argv) {
  let once = false;
  let intervalMs = Number.parseInt(process.env.DISKWise_CI_INTERVAL || "2", 10) * 1000;
  for (let i = 0; i < argv.length; i += 1) {
    if (argv[i] === "--once") once = true;
    else if (argv[i] === "--interval" && argv[i + 1]) {
      intervalMs = Math.max(1, Number.parseInt(argv[++i], 10) || 2) * 1000;
    } else if (argv[i] === "-h" || argv[i] === "--help") {
      console.log(`Usage: npm run ci [-- --once] [--interval <sec>]

  npm run ci                         live dashboard (keeps watching; Ctrl+C to stop)
  npm run ci -- --once               snapshot and exit
  npm run deploy:stop -- --repo <n>  interrupt a running deploy
  npm run deploy:retry               retry failed/pending targets

  DISKWise_CI_LOG_LINES=12             log tail lines (default 12)
  DISKWise_CI_INTERVAL=2               refresh interval in seconds (default 2)
`);
      process.exit(0);
    }
  }
  return { once, intervalMs };
}

function sleep(ms) {
  return new Promise((r) => setTimeout(r, ms));
}

function gitHead() {
  const r = spawnSync("git", ["rev-parse", "HEAD"], { cwd: REPO_ROOT, encoding: "utf8" });
  return r.status === 0 ? r.stdout.trim() : null;
}

function boxWidth() {
  const cols = process.stdout.columns || 80;
  const tableInner =
    TABLE.service +
    TABLE.url +
    TABLE.status +
    TABLE.head +
    TABLE.deployed +
    TABLE.cost +
    TABLE.lastRun +
    20;
  return Math.max(tableInner + 4, Math.min(cols - 1, 140));
}

function stripAnsi(text) {
  return String(text).replace(/\x1b\[[0-9;]*m/g, "");
}

function truncatePlain(text, max) {
  const plain = stripAnsi(text);
  if (plain.length <= max) return plain;
  const suffix = "…";
  const cut = Math.max(1, max - suffix.length);
  return `${plain.slice(0, cut)}${suffix}`;
}

function padPlain(text, width) {
  const plain = truncatePlain(text, width);
  return plain + " ".repeat(Math.max(0, width - plain.length));
}

function padCol(text, width, colorFn) {
  const plain = truncatePlain(text, width);
  const pad = " ".repeat(Math.max(0, width - plain.length));
  const colored = colorFn ? colorFn(plain) : plain;
  return colored + pad;
}

function clipBoxLine(line, inner) {
  const safe = sanitizeTerminal(line);
  const plain = stripAnsi(safe);
  const clipped = truncatePlain(plain, inner);
  const pad = " ".repeat(Math.max(0, inner - clipped.length));
  if (plain.length <= inner) return { text: safe, pad };
  const open = safe.match(/^(\x1b\[[0-9;]*m)+/)?.[0] || "";
  const close = safe.includes("\x1b[0m") ? "\x1b[0m" : "";
  return { text: `${open}${clipped}${close}`, pad };
}

function clearScreen() {
  if (process.stdout.isTTY) {
    process.stdout.write("\x1b[2J\x1b[H");
  }
}

function renderBox(title, lines, options = {}) {
  const width = options.width || boxWidth();
  const inner = width - 4;
  const bar = "─".repeat(Math.max(1, width - 2));
  const titlePad = Math.max(0, width - stripAnsi(title).length - 5);
  console.log(`┌─ ${bold(title)} ${"─".repeat(titlePad)}┐`);
  for (const line of lines) {
    const { text, pad } = clipBoxLine(line, inner);
    console.log(`│ ${text}${pad} │`);
  }
  console.log(`└${bar}┘`);
}

function formatRelativeTime(iso) {
  if (!iso) return "—";
  const seconds = Math.max(0, Math.floor((Date.now() - new Date(iso).getTime()) / 1000));
  if (seconds < 60) return `${seconds}s ago`;
  const minutes = Math.floor(seconds / 60);
  if (minutes < 60) return `${minutes}m ago`;
  const hours = Math.floor(minutes / 60);
  if (hours < 24) return `${hours}h ago`;
  return `${Math.floor(hours / 24)}d ago`;
}

function formatDuration(ms) {
  if (ms == null) return "";
  const sec = Math.round(ms / 1000);
  if (sec < 60) return `${sec}s`;
  const min = Math.floor(sec / 60);
  return `${min}m ${sec % 60}s`;
}

/** True only when a deploy process is actually running (not stuck queued). */
function isActiveDeploy(rs) {
  if (!rs) return false;
  if (rs.status === "in_progress") return true;
  if (rs.status === "queued" && (rs.pid || rs.currentDeploymentId)) return true;
  return false;
}

function activityLabel(type) {
  switch (type) {
    case "success":
      return green("✓");
    case "failure":
    case "spawn_failed":
      return red("✗");
    case "cancelled":
      return magenta("⊘");
    case "started":
      return yellow("⟳");
    case "triggered":
    case "spawned":
      return cyan("→");
    case "stale_recovered":
      return yellow("↻");
    case "trigger_skipped":
      return dim("·");
    default:
      return dim("·");
  }
}

function statusLabel(status) {
  switch (status) {
    case "in_progress":
      return { text: "⟳ running", color: boldYellow };
    case "queued":
      return { text: "◷ queued", color: boldCyan };
    case "success":
      return { text: "✓ success", color: boldGreen };
    case "failure":
      return { text: "✗ failure", color: boldRed };
    case "cancelled":
      return { text: "⊘ cancelled", color: magenta };
    case "idle":
    default:
      return { text: "– idle", color: dim };
  }
}

function isUpToDate(row) {
  if (row.headSha === "—" || row.headSha !== row.deployedSha) return false;
  if (row.syncOnly) return true;
  // HEAD matches lastDeployedSha — treat as current even if a later cancel
  // overwrote lastDeploymentId (race after deploy:stop).
  return true;
}

function shaColor(headSha, deployedSha, pendingDeploy, active, lastOutcome) {
  if (headSha === "—") return dim;
  if (active) return boldCyan;
  if (lastOutcome === "success") {
    if (headSha === deployedSha && deployedSha !== "—") return boldGreen;
    return green;
  }
  if (headSha === deployedSha && deployedSha !== "—") return boldGreen;
  if (deployedSha === "—") return pendingDeploy ? yellow : dim;
  return yellow;
}

function lastRunColor(row) {
  if (row.status === "in_progress" || row.status === "queued") return boldYellow;
  if (row.lastOutcome === "success") return boldGreen;
  if (row.lastOutcome === "failure") return boldRed;
  if (row.lastOutcome === "cancelled") return magenta;
  return dim;
}

function componentNameColor(row) {
  if (row.status === "in_progress" || row.status === "queued") return boldCyan;
  if (row.lastOutcome === "success") {
    return isUpToDate(row) ? boldGreen : green;
  }
  if (row.pendingDeploy) return yellow;
  if (row.lastOutcome === "failure") return boldRed;
  return (t) => t;
}

function displayStatus(row) {
  if (row.status === "in_progress" || row.status === "queued") {
    return statusLabel(row.status);
  }
  // Checkpoint already at HEAD — don't keep showing a superseded cancel/failure.
  if (row.headSha !== "—" && row.headSha === row.deployedSha) {
    return statusLabel("success");
  }
  if (row.lastOutcome) {
    return statusLabel(row.lastOutcome);
  }
  return statusLabel("idle");
}

function isPendingDeploy(rs, lastDeploy, target) {
  if (target?.syncOnly || target?.infraDeploy) {
    if (!rs.headSha) return false;
    if (!rs.lastDeployedSha) return Boolean(rs.headSha);
    return rs.headSha !== rs.lastDeployedSha;
  }
  if (!rs.headSha || rs.headSha === rs.lastDeployedSha) return false;
  if (!rs.lastDeployedSha) {
    return lastDeploy?.sha === rs.headSha && lastDeploy?.status !== "success";
  }
  return true;
}

function shortenUrl(url) {
  if (!url) return "—";
  return url.replace(/^https?:\/\//, "").replace(/\/$/, "");
}

function summarize(state, billing = null) {
  const head = gitHead();
  const costs = allocateTargetCosts(billing || {}, DEPLOY_TARGETS);
  const rows = [];
  let active = 0;
  let failed = 0;
  let pending = 0;
  let everDeployed = false;
  const pendingRepos = [];
  const failedRepos = [];

  for (const target of DEPLOY_TARGETS) {
    const rs = state.repos[target.repo] || {};
    if (head) rs.headSha = head;

    const activeStatus = isActiveDeploy(rs) ? rs.status : null;
    let lastDeploy = rs.lastDeploymentId
      ? findDeployment(state, rs.lastDeploymentId)
      : null;
    if (!lastDeploy) {
      lastDeploy = (state.deployments || []).find((d) => d.repo === target.repo) || null;
    }
    // Prefer the success that matches lastDeployedSha over a later cancel/failure
    // (deploy:stop can finish after deploy:sync and overwrite lastDeploymentId).
    if (
      rs.lastDeployedSha &&
      lastDeploy &&
      lastDeploy.status !== "success" &&
      lastDeploy.sha !== rs.lastDeployedSha
    ) {
      const matchingSuccess = (state.deployments || []).find(
        (d) =>
          d.repo === target.repo &&
          d.status === "success" &&
          d.sha === rs.lastDeployedSha,
      );
      if (matchingSuccess) lastDeploy = matchingSuccess;
    }
    const lastOutcome = lastDeploy?.status || null;
    const rowStatus = activeStatus || "idle";
    const pendingDeploy = isPendingDeploy(rs, lastDeploy, target);
    const tracked = Boolean(target.npmScript || target.syncOnly || target.infraDeploy);

    if (lastDeploy || rs.lastDeployedSha) everDeployed = true;
    if (activeStatus) active += 1;
    if (!activeStatus && lastOutcome === "failure" && !target.syncOnly) {
      failed += 1;
      failedRepos.push({ repo: target.repo, label: target.label });
    }
    if (!activeStatus && pendingDeploy) {
      pending += 1;
      pendingRepos.push({ repo: target.repo, label: target.label, headSha: rs.headSha });
    }

    const current = rs.currentDeploymentId
      ? findDeployment(state, rs.currentDeploymentId)
      : null;
    const logRef = activeStatus
      ? current?.logFile || lastDeploy?.logFile
      : lastDeploy?.logFile || null;

    const costAmount = Object.prototype.hasOwnProperty.call(costs, target.repo)
      ? costs[target.repo]
      : null;

    rows.push({
      repo: target.repo,
      label: target.label,
      url: target.url || "",
      deployable: Boolean(target.npmScript && !target.syncOnly),
      tracked,
      syncOnly: Boolean(target.syncOnly || target.infraDeploy),
      note: target.note,
      details: target.details,
      status: rowStatus,
      lastOutcome,
      pendingDeploy,
      branch: rs.branch || target.branch || "main",
      headSha: rs.headSha ? rs.headSha.slice(0, 7) : "—",
      deployedSha: rs.lastDeployedSha ? rs.lastDeployedSha.slice(0, 7) : "—",
      costPlain: formatTargetCost(costAmount, billing?.currency),
      costAmount,
      lastRun:
        current?.startedAt || lastDeploy?.finishedAt || lastDeploy?.startedAt || null,
      duration: lastDeploy?.durationMs,
      logFile: logRef,
      lastLine: logRef ? lastLogLine(logRef) : null,
      logTail: logRef ? tailLogLines(logRef, LOG_TAIL_LINES) : [],
      logLive: Boolean(activeStatus),
      pid: rs.pid,
      error: rs.lastError,
    });
  }

  return { rows, active, failed, pending, pendingRepos, failedRepos, everDeployed, billing };
}

const TABLE_SEP = dim(" │ ");

function tableSep() {
  return dim(
    [
      "─".repeat(TABLE.service),
      "─".repeat(TABLE.url),
      "─".repeat(TABLE.status),
      "─".repeat(TABLE.head),
      "─".repeat(TABLE.deployed),
      "─".repeat(TABLE.cost),
      "─".repeat(TABLE.lastRun),
    ].join("─┼─"),
  );
}

function tableRow(cells) {
  return cells.join(TABLE_SEP);
}

function tableHeader() {
  return tableRow([
    bold(padPlain("Service", TABLE.service)),
    bold(padPlain("URL", TABLE.url)),
    bold(padPlain("Status", TABLE.status)),
    bold(padPlain("HEAD", TABLE.head)),
    bold(padPlain("Deployed", TABLE.deployed)),
    bold(padPlain("Cost", TABLE.cost)),
    bold(padPlain("Last run", TABLE.lastRun)),
  ]);
}

function buildStatusBoxLines(
  state,
  rows,
  active,
  failed,
  pending,
  pendingRepos,
  failedRepos,
  everDeployed,
  billing,
) {
  const relState = path.relative(process.cwd(), STATE_FILE) || STATE_FILE;
  const billingLine = formatSummaryForDashboard(billing || { ok: false, line: "GCP billing…" }, {
    green,
    yellow,
    dim,
    bold: boldWhite,
  });
  const lines = [
    dim(`State: ${relState}`),
    dim(`Updated: ${state.updatedAt || "—"}  ·  Ctrl+C to stop watching`),
    "",
    billingLine,
    dim("Cost = allocated GCP MTD (Cloud Run / Storage / …); Cloudflare & App Store = —"),
    "",
    tableHeader(),
    tableSep(),
  ];

  for (const row of rows) {
    const st = row.syncOnly && !row.deployable
      ? row.pendingDeploy
        ? { text: "pending", color: yellow }
        : row.lastOutcome === "success" || (row.deployedSha !== "—" && !row.pendingDeploy)
          ? { text: "synced", color: green }
          : displayStatus(row)
      : displayStatus(row);

    const when = row.lastRun ? formatRelativeTime(row.lastRun) : "—";
    const dur =
      row.status === "in_progress" || row.status === "queued"
        ? ""
        : row.duration != null
          ? ` (${formatDuration(row.duration)})`
          : "";
    const lastRunText = truncatePlain(`${when}${dur}`, TABLE.lastRun);
    const urlPlain = truncatePlain(shortenUrl(row.url), TABLE.url);

    const headColor = shaColor(
      row.headSha,
      row.deployedSha,
      row.pendingDeploy,
      row.status === "in_progress" || row.status === "queued",
      row.lastOutcome,
    );
    const deployedColor = shaColor(
      row.deployedSha,
      row.headSha,
      row.pendingDeploy,
      false,
      row.lastOutcome,
    );

    lines.push(
      tableRow([
        padCol(truncatePlain(row.label, TABLE.service), TABLE.service, componentNameColor(row)),
        padCol(urlPlain, TABLE.url, dim),
        padCol(st.text, TABLE.status, st.color),
        padCol(row.headSha, TABLE.head, headColor),
        padCol(row.deployedSha, TABLE.deployed, deployedColor),
        padCol(row.costPlain || "—", TABLE.cost, row.costAmount ? green : dim),
        padCol(lastRunText, TABLE.lastRun, lastRunColor(row)),
      ]),
    );

    if (row.pid) {
      lines.push(dim(`  pid ${row.pid}`));
    }
    if (row.status === "idle" && isUpToDate(row)) {
      lines.push(green(`  ↳ deployed and up to date`));
    } else if (row.status === "idle" && row.syncOnly && !row.pendingDeploy && row.deployedSha !== "—") {
      lines.push(green(`  ↳ checkpoint synced at HEAD`));
    } else if (row.status === "idle" && row.error && !row.lastOutcome) {
      lines.push(yellow(`  ↳ ${row.error}`));
    } else if (row.status === "idle" && row.pendingDeploy) {
      const hint = row.syncOnly
        ? `  ↳ new commit ${row.headSha} — npm run deploy:sync -- --repo ${row.repo}`
        : `  ↳ new commit ${row.headSha} — npm run deploy:retry -- --repo ${row.repo}`;
      lines.push(row.lastOutcome === "success" ? dim(hint) : yellow(hint));
    } else if (
      row.status === "idle" &&
      !isUpToDate(row) &&
      (row.lastOutcome === "failure" || row.lastOutcome === "cancelled")
    ) {
      lines.push(yellow(`  ↳ retry: npm run deploy:retry -- --repo ${row.repo}`));
    }
    if (row.error && row.lastOutcome === "failure") {
      lines.push(red(`  ↳ ${row.error}`));
    }
  }

  lines.push("");
  if (active > 0) {
    lines.push(yellow(`${active} deployment(s) running — refreshing…`));
    lines.push(dim("Interrupt: npm run deploy:stop -- --repo diskwise-website"));
  } else if (pending > 0 || failed > 0) {
    if (pending > 0) {
      lines.push(yellow(`${pending} target(s) have undeployed commits`));
      for (const target of pendingRepos) {
        const head = target.headSha ? target.headSha.slice(0, 7) : "—";
        lines.push(yellow(`  ↳ ${target.repo} (${target.label}) — HEAD ${head}`));
      }
    }
    if (failed > 0) {
      lines.push(red(`${failed} target(s) last deploy failed`));
      for (const target of failedRepos) {
        lines.push(red(`  ↳ ${target.repo} (${target.label})`));
      }
    }
    lines.push(dim("Sync/retry:  npm run deploy:sync   ·   npm run deploy:retry"));
  } else if (!everDeployed) {
    lines.push(yellow("No deployments yet."));
    lines.push(dim("Push website changes or run: npm run deploy:retry -- --repo diskwise-website"));
  } else {
    lines.push(green("All tracked targets idle and up to date."));
    lines.push(dim("Watching for new commits and deploys — Ctrl+C to stop"));
  }

  return lines;
}

function printLogSection(title, rows, options = {}) {
  const { liveOnly = false } = options;

  const logRows = rows
    .filter((row) => {
      if (!row.deployable || !row.logFile) return false;
      if (liveOnly && !row.logLive) return false;
      if (!liveOnly && row.logLive) return false;
      return row.logTail.length > 0 || row.logLive;
    })
    .sort((a, b) => {
      const ta = a.lastRun ? new Date(a.lastRun).getTime() : 0;
      const tb = b.lastRun ? new Date(b.lastRun).getTime() : 0;
      return tb - ta;
    });

  if (logRows.length === 0) return;

  const allSuccess = logRows.every(
    (row) => row.lastOutcome === "success" && !row.logLive,
  );
  console.log("");
  console.log(allSuccess ? boldGreen(title) : bold(title));

  for (let i = 0; i < logRows.length; i += 1) {
    const row = logRows[i];
    if (i > 0) console.log("");

    const st = row.logLive ? statusLabel(row.status) : displayStatus(row);
    const mode = row.logLive
      ? boldYellow("live")
      : row.lastOutcome === "success"
        ? green("last deploy")
        : row.lastOutcome === "failure"
          ? red("last deploy")
          : blue("last deploy");
    const dur =
      !row.logLive && row.duration != null
        ? dim(` · ${formatDuration(row.duration)}`)
        : "";
    const when = row.lastRun ? dim(` · ${formatRelativeTime(row.lastRun)}`) : "";
    const shaHint =
      row.deployedSha !== "—" && !row.logLive
        ? dim(` · ${row.deployedSha}`)
        : "";

    const labelColor =
      row.lastOutcome === "success" && !row.logLive
        ? boldGreen
        : row.logLive
          ? boldCyan
          : row.lastOutcome === "failure"
            ? boldRed
            : boldCyan;
    const logLineColor =
      row.lastOutcome === "success" && !row.logLive ? green : row.logLive ? cyan : cyan;
    const logPathColor =
      row.lastOutcome === "success" && !row.logLive ? (t) => dim(green(t)) : dim;

    console.log(
      `${labelColor(row.label)}  ${mode}  ${st.color(st.text)}${when}${dur}${shaHint}`,
    );
    if (row.error && row.lastOutcome === "failure") {
      console.log(red(`  ↳ ${row.error}`));
    }
    console.log(logPathColor(`  ${row.logFile}`));

    const tail = row.logLive
      ? row.logTail.length > 0
        ? row.logTail
        : ["(waiting for log output…)"]
      : row.logTail;
    for (const line of tail) {
      console.log(logLineColor(`  ${sanitizeTerminal(line)}`));
    }
  }
}

function printActivitySection(state) {
  const items = (state.activities || []).slice(0, ACTIVITY_LINES);
  if (items.length === 0) return;

  console.log("");
  console.log(bold("Recent activity"));

  for (const item of items) {
    const when = formatRelativeTime(item.at);
    const repo = item.repo ? dim(`${item.repo} `) : "";
    const sha = item.shortSha ? dim(`${item.shortSha} `) : "";
    const msg = item.message || item.type || "";
    console.log(
      `${activityLabel(item.type)} ${repo}${sha}${dim(when)}  ${sanitizeTerminal(msg)}`,
    );
    if (item.logFile && (item.type === "success" || item.type === "failure")) {
      console.log(dim(`    log: ${item.logFile}`));
    }
  }
}

function printDashboard(state) {
  const billing = getGcpBillingSummary({ repoRoot: REPO_ROOT });
  const { rows, active, failed, pending, pendingRepos, failedRepos, everDeployed } =
    summarize(state, billing);

  clearScreen();
  renderBox(
    "suherman.net local deployment",
    buildStatusBoxLines(
      state,
      rows,
      active,
      failed,
      pending,
      pendingRepos,
      failedRepos,
      everDeployed,
      billing,
    ),
  );

  if (active > 0) {
    printLogSection("Deploy logs (live)", rows, { liveOnly: true });
  }
  printLogSection("Last deployment results", rows, { liveOnly: false });
  printActivitySection(state);
}

async function main() {
  const { once, intervalMs } = parseArgs(process.argv.slice(2));

  process.on("SIGINT", () => {
    console.log(dim("\nStopped watching. Deployments still run in the background — npm run ci"));
    process.exit(0);
  });

  while (true) {
    const state = readState();
    if (process.stdout.isTTY) {
      printDashboard(state);
    } else {
      const billing = getGcpBillingSummary({ repoRoot: REPO_ROOT });
      const summary = summarize(state, billing);
      console.log(billing.line || "GCP billing unavailable");
      for (const row of summary.rows) {
        console.log(
          [
            row.repo,
            row.status,
            row.lastOutcome || "",
            row.headSha,
            row.deployedSha,
            row.costPlain || "—",
            row.lastLine || "",
          ].join("\t"),
        );
      }
      if (once) {
        process.exit(summary.failed > 0 || summary.pending > 0 ? 1 : 0);
      }
    }

    const billing = getGcpBillingSummary({ repoRoot: REPO_ROOT });
    const { active, failed, pending } = summarize(state, billing);
    if (process.stdout.isTTY) {
      if (once) {
        process.exit(failed > 0 || pending > 0 ? 1 : 0);
      }
    } else if (once || active === 0) {
      process.exit(failed > 0 || pending > 0 ? 1 : 0);
    }

    await sleep(intervalMs);
  }
}

main().catch((err) => {
  console.error(red(`ci-deploy-status: ${err.message || err}`));
  process.exit(1);
});
