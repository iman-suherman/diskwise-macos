/**
 * GCP billing helpers for `npm run ci` (MTD project spend + per-GCP-service totals).
 * Uses the same BigQuery billing export as suherman-net-infra.
 */
const { spawnSync } = require("node:child_process");
const path = require("node:path");
const { resolveGcpProjectId, buildGcpCliEnv } = require("./gcp-config.cjs");
const { applyGcpEnv } = require("./apply-gcp-env.cjs");

const DEFAULT_CACHE_MS =
  Number.parseInt(process.env.DISKWise_CI_BILLING_CACHE_SEC || "300", 10) * 1000;
const DEFAULT_DATASET = process.env.GCP_BILLING_BQ_DATASET || "billing_export";

/** @type {{ fetchedAt: number, summary: object | null } | null} */
let cache = null;

function currencySymbol(currency) {
  switch (currency) {
    case "AUD":
      return "A$";
    case "USD":
      return "$";
    case "EUR":
      return "€";
    case "GBP":
      return "£";
    default:
      return currency ? `${currency} ` : "";
  }
}

function formatMoney(amount, currency) {
  if (amount == null || Number.isNaN(Number(amount))) return null;
  const sym = currencySymbol(currency);
  const rounded = Math.round(Number(amount) * 100) / 100;
  return `${sym}${rounded.toFixed(2)}`;
}

function monthLabel(date = new Date()) {
  return date.toLocaleString("en-AU", { month: "short", year: "numeric", timeZone: "UTC" });
}

function runCli(command, args, repoRoot) {
  const r = spawnSync(command, args, {
    encoding: "utf8",
    stdio: ["ignore", "pipe", "pipe"],
    env: buildGcpCliEnv(repoRoot),
  });
  if (r.error) throw r.error;
  if (r.status !== 0) {
    throw new Error((r.stderr || r.stdout || "").trim() || `${command} failed`);
  }
  return (r.stdout || "").trim();
}

function billingExportTableName(billingAccount) {
  return `gcp_billing_export_v1_${billingAccount.replace(/-/g, "_")}`;
}

function resolveBillingTable(projectId, billingAccount) {
  if (process.env.GCP_BILLING_BQ_TABLE) return process.env.GCP_BILLING_BQ_TABLE;
  return `${projectId}.${DEFAULT_DATASET}.${billingExportTableName(billingAccount)}`;
}

function toBqTableRef(qualifiedTable) {
  if (qualifiedTable.includes(":")) return qualifiedTable;
  const dot = qualifiedTable.indexOf(".");
  if (dot === -1) return qualifiedTable;
  return `${qualifiedTable.slice(0, dot)}:${qualifiedTable.slice(dot + 1)}`;
}

function emptySummary(overrides = {}) {
  return {
    ok: false,
    skipped: false,
    error: null,
    projectId: null,
    currency: null,
    monthLabel: monthLabel(),
    mtdSpend: null,
    byGcpService: {},
    line: "",
    ...overrides,
  };
}

function buildSummaryLine(summary) {
  if (!summary.ok) {
    return summary.error ? `GCP billing: ${summary.error}` : "GCP billing unavailable";
  }
  if (summary.mtdSpend == null) {
    return `GCP billing · ${summary.monthLabel} · export not ready`;
  }
  const spend = formatMoney(summary.mtdSpend, summary.currency) || `${summary.mtdSpend}`;
  return `GCP billing · ${summary.monthLabel} · ${spend} MTD · ${summary.projectId}`;
}

/**
 * @param {{ repoRoot?: string, force?: boolean }} [options]
 */
function getGcpBillingSummary(options = {}) {
  const repoRoot = options.repoRoot || path.join(__dirname, "..");
  const force = Boolean(options.force);

  if (!force && cache && Date.now() - cache.fetchedAt < DEFAULT_CACHE_MS) {
    return cache.summary;
  }

  applyGcpEnv(repoRoot);

  try {
    const projectId = resolveGcpProjectId(repoRoot);
    if (!projectId) throw new Error("GCP_PROJECT_ID is not set");

    const billingAccount = runCli(
      "gcloud",
      [
        "billing",
        "projects",
        "describe",
        projectId,
        "--format=value(billingAccountName)",
      ],
      repoRoot,
    ).replace(/^billingAccounts\//, "");
    if (!billingAccount) throw new Error(`no billing account linked to ${projectId}`);

    const billingTable = resolveBillingTable(projectId, billingAccount);

    const sql = `
SELECT
  service.description AS gcp_service,
  ROUND(
    SUM(cost) + SUM(IFNULL((SELECT SUM(c.amount) FROM UNNEST(credits) c), 0)),
    4
  ) AS mtd_spend,
  ANY_VALUE(currency) AS currency
FROM \`${billingTable}\`
WHERE project.id = '${projectId.replace(/'/g, "\\'")}'
  AND DATE(usage_start_time) >= DATE_TRUNC(CURRENT_DATE(), MONTH)
GROUP BY 1
`.trim();

    const raw = runCli(
      "bq",
      [
        "query",
        "--use_legacy_sql=false",
        "--format=json",
        `--project_id=${projectId}`,
        sql,
      ],
      repoRoot,
    );
    const rows = JSON.parse(raw || "[]");
    const byGcpService = {};
    let mtdSpend = 0;
    let currency = null;
    for (const row of rows) {
      const name = row.gcp_service || "Unknown";
      const amount = row.mtd_spend != null ? Number(row.mtd_spend) : 0;
      byGcpService[name] = amount;
      mtdSpend += amount;
      if (row.currency) currency = row.currency;
    }

    if (!currency) {
      currency = runCli(
        "gcloud",
        [
          "billing",
          "accounts",
          "describe",
          billingAccount,
          "--format=value(currencyCode)",
        ],
        repoRoot,
      );
    }

    const summary = {
      ok: true,
      projectId,
      billingAccount,
      billingTable,
      currency,
      monthLabel: monthLabel(),
      mtdSpend: Math.round(mtdSpend * 100) / 100,
      byGcpService,
      line: "",
    };
    summary.line = buildSummaryLine(summary);
    cache = { fetchedAt: Date.now(), summary };
    return summary;
  } catch (err) {
    const summary = emptySummary({
      error: (err.message || String(err)).split("\n")[0],
      projectId: resolveGcpProjectId(repoRoot),
    });
    summary.line = buildSummaryLine(summary);
    cache = { fetchedAt: Date.now(), summary };
    return summary;
  }
}

/**
 * Allocate MTD spend to deploy targets from gcpServiceWeights on each target.
 * @param {object} summary
 * @param {Array<{ repo: string, gcpServiceWeights?: Record<string, number> }>} targets
 */
function allocateTargetCosts(summary, targets) {
  const out = {};
  if (!summary?.ok) {
    for (const t of targets) out[t.repo] = null;
    return out;
  }

  /** @type {Record<string, Array<{ repo: string, weight: number }>>} */
  const claimants = {};
  for (const t of targets) {
    const weights = t.gcpServiceWeights || {};
    for (const [svc, weight] of Object.entries(weights)) {
      if (!weight) continue;
      if (!claimants[svc]) claimants[svc] = [];
      claimants[svc].push({ repo: t.repo, weight: Number(weight) });
    }
  }

  for (const t of targets) out[t.repo] = 0;

  for (const [svc, rows] of Object.entries(claimants)) {
    const total = summary.byGcpService?.[svc] ?? 0;
    const weightSum = rows.reduce((s, r) => s + r.weight, 0) || 1;
    for (const row of rows) {
      out[row.repo] += (total * row.weight) / weightSum;
    }
  }

  for (const repo of Object.keys(out)) {
    out[repo] = Math.round(out[repo] * 100) / 100;
  }
  return out;
}

function formatSummaryForDashboard(summary, colors = {}) {
  const green = colors.green || ((t) => t);
  const yellow = colors.yellow || ((t) => t);
  const dim = colors.dim || ((t) => t);
  const bold = colors.bold || ((t) => t);

  if (summary.skipped) {
    return dim(summary.line || "GCP billing: skipped");
  }
  if (!summary.ok) {
    return yellow(summary.line || `GCP billing: ${summary.error || "unavailable"}`);
  }
  if (summary.mtdSpend == null) {
    return yellow(summary.line || `GCP billing · ${summary.monthLabel} · export not ready`);
  }
  const spend = formatMoney(summary.mtdSpend, summary.currency) || `${summary.mtdSpend}`;
  return green(`GCP billing · ${summary.monthLabel} · ${bold(`${spend} MTD`)} · ${summary.projectId}`);
}

function formatTargetCost(amount, currency) {
  if (amount == null) return "—";
  if (amount === 0) return formatMoney(0, currency) || "A$0.00";
  return formatMoney(amount, currency) || String(amount);
}

module.exports = {
  getGcpBillingSummary,
  allocateTargetCosts,
  formatSummaryForDashboard,
  formatTargetCost,
  formatMoney,
  currencySymbol,
};
