#!/usr/bin/env node
'use strict';

const c = {
  reset: '\x1b[0m',
  bold: '\x1b[1m',
  dim: '\x1b[2m',
  green: '\x1b[32m',
  yellow: '\x1b[33m',
  cyan: '\x1b[36m',
  bgGreen: '\x1b[42m',
  black: '\x1b[30m',
};

const stripAnsi = (value) => String(value).replace(/\x1b\[[0-9;]*m/g, '');

const START_COMMAND = 'npm run dev:app';
const INSTALL_COMMAND = 'npm run start';
const SETUP_COMMAND = 'npm run setup';

const paint = {
  cmd: (text) => `${c.green}${text}${c.reset}`,
  phase: (text) => `${c.yellow}${text}${c.reset}`,
  dim: (text) => `${c.dim}${text}${c.reset}`,
  path: (text) => `${c.cyan}${text}${c.reset}`,
  guide: (text) => `${c.bold}${text}${c.reset}`,
  highlight: (text) => `${c.bold}${c.bgGreen}${c.black}${text}${c.reset}`,
  highlightCmd: (text) => `${c.bold}${c.green}${text}${c.reset}`,
};

const commands = [
  ['Start here', START_COMMAND, '★ Build, test, build app, launch on macOS'],
  ['Install', INSTALL_COMMAND, '★ Build release app + DMG → drag to Applications'],
  ['Setup', SETUP_COMMAND, '★ generate-env + GCP login + git hooks (website deploy)'],
  ['Setup', 'npm run setup:xcodegen', 'Install XcodeGen (once)'],
  ['Setup', 'npm run setup:xcode', 'Xcode first-launch (if build fails)'],
  ['Website', 'npm run dev:website', 'Local Next.js site at http://127.0.0.1:3000'],
  ['Website', 'npm run deploy:website', 'Deploy site to Cloud Run'],
  ['Website', 'npm run ci', 'Live deploy status dashboard'],
  ['Development', 'npm run build', 'Build Swift packages'],
  ['Development', 'npm run test', 'Run package tests'],
  ['Development', 'npm run build:app', 'Debug .app build'],
  ['Development', 'npm run run:app', 'Launch DiskWise.app on macOS'],
  ['Development', 'npm run app', 'Build app + launch on macOS'],
  ['Debug', 'npm run xcode', 'Build app + open Xcode (⌘R to debug)'],
  ['Debug', 'npm run open:xcode', 'Open DiskWise.xcodeproj only'],
  ['Debug', 'swift test --filter …', 'Filter package tests from terminal'],
  ['Release', 'npm run release', 'Huge Shop sign + notarize + DMG (see .env.release.example)'],
  ['Release', 'npm run build:app:release', 'Release .app build only'],
  ['Release', 'npm run sign', 'Developer ID sign (requires .env.release)'],
  ['Release', 'npm run package', 'DMG + notarize (requires signed .app)'],
  ['Help', 'npm run info', 'Show this guide'],
  ['Help', 'npm run init', 'Alias for info'],
];

const guides = [
  [
    'Test',
    `${START_COMMAND}   (packages + unit tests + launch DiskWise.app)`,
  ],
  [
    'Development',
    `${START_COMMAND} → edit Sources/ · Tests/ → repeat`,
  ],
  [
    'Debug',
    'npm run xcode → scheme DiskWise → ⌘R · breakpoints · Instruments',
  ],
  [
    'Operate app',
    'Scan /Volumes/… → Overview → Duplicates → AI → Preview cleanup → Trash',
  ],
  [
    'Install',
    `${INSTALL_COMMAND} → open DiskWise.dmg → drag DiskWise.app to Applications`,
  ],
];

const envVars = [
  ['MACOS_CODESIGN_IDENTITY', 'Developer ID Application: Huge Shop Pty Ltd (Q3TXW887NM)', 'npm run release'],
  ['APPLE_TEAM_ID', 'Q3TXW887NM', 'npm run release'],
  ['APPLE_NOTARIZE_KEYCHAIN_PROFILE', 'AC_NOTARY (shared with officeless kit)', 'npm run release'],
  ['MACOS_NOTARIZE', '1', 'npm run release'],
];

const paths = [
  ['Debug app', '.build/DerivedData/Build/Products/Debug/DiskWise.app'],
  ['Release app', '.build/DerivedData/Build/Products/Release/DiskWise.app'],
  ['Installer', 'DiskWise.dmg'],
  ['Database', '~/Library/Application Support/DiskWise/diskwise.sqlite'],
  ['Docs', 'README.md · docs/architecture.md · docs/local-development.md'],
];

function renderTable(title, headers, rows, styleRow, subtitle) {
  const plainRows = rows.map((row) => row.map((cell) => stripAnsi(cell)));
  const widths = headers.map((header, index) =>
    Math.max(header.length, ...plainRows.map((row) => (row[index] || '').length))
  );

  const border = `┌${widths.map((w) => '─'.repeat(w + 2)).join('┬')}┐`;
  const divider = `├${widths.map((w) => '─'.repeat(w + 2)).join('┼')}┤`;
  const bottom = `└${widths.map((w) => '─'.repeat(w + 2)).join('┴')}┘`;

  const formatRow = (cells) =>
    `│ ${cells.map((cell, index) => {
      const padding = Math.max(0, widths[index] - stripAnsi(cell).length);
      return `${cell}${' '.repeat(padding)}`;
    }).join(' │ ')} │`;

  const lines = [
    '',
    subtitle
      ? `${c.bold}${c.cyan}${title}${c.reset} ${paint.dim(subtitle)}`
      : `${c.bold}${c.cyan}${title}${c.reset}`,
    border,
    formatRow(headers.map((h) => `${c.bold}${h}${c.reset}`)),
    divider,
  ];

  for (const row of rows) {
    lines.push(formatRow(styleRow ? styleRow(row) : row));
  }

  lines.push(bottom, '');
  return lines;
}

function styleCommandRow([phase, command, description]) {
  if (command === START_COMMAND) {
    return [
      paint.highlight(phase),
      paint.highlightCmd(command),
      `${c.bold}${description}${c.reset}`,
    ];
  }

  if (command === INSTALL_COMMAND) {
    return [
      paint.phase(phase),
      paint.highlightCmd(command),
      `${c.bold}${description}${c.reset}`,
    ];
  }

  if (command === SETUP_COMMAND) {
    return [
      paint.highlight(phase),
      paint.highlightCmd(command),
      `${c.bold}${description}${c.reset}`,
    ];
  }

  return [paint.phase(phase), paint.cmd(command), paint.dim(description)];
}

function styleGuideRow([guide, flow]) {
  if (flow.includes(START_COMMAND)) {
    const suffix = flow.slice(flow.indexOf(START_COMMAND) + START_COMMAND.length);
    const highlightedFlow = `${paint.highlightCmd(START_COMMAND)}${paint.dim(suffix)}`;
    return [paint.guide(guide), highlightedFlow];
  }

  return [paint.guide(guide), paint.dim(flow)];
}

const startBanner = [
  '',
  paint.highlight(`Start here → ${START_COMMAND}`),
  paint.dim('Build + test packages, build DiskWise.app, launch on macOS.'),
  '',
];

const setupBanner = [
  paint.highlight(`Website / GCP setup → ${SETUP_COMMAND}`),
  paint.dim('Runs generate-env, login, and install-hooks. Do this once after npm install.'),
  '',
];

const commandTable = renderTable(
  'Commands',
  ['Phase', 'Command', 'Description'],
  commands,
  styleCommandRow,
  'DiskWise macOS · SwiftUI · GRDB · local AI'
);

const guideTable = renderTable(
  'Compact guides',
  ['Guide', 'Flow'],
  guides,
  styleGuideRow
);

const envTable = renderTable(
  'Release environment',
  ['Variable', 'Example', 'Used by'],
  envVars,
  ([variable, example, usedBy]) => [
    paint.cmd(variable),
    paint.dim(example),
    paint.cmd(usedBy),
  ]
);

const pathTable = renderTable(
  'Paths & references',
  ['Item', 'Location'],
  paths,
  ([item, location]) => [paint.dim(item), paint.path(location)]
);

const footer = [
  paint.dim('Requires: macOS 14+ · Xcode 15+ · Node.js · optional: brew install xcodegen create-dmg'),
  '',
];

process.stdout.write(
  [...startBanner, ...setupBanner, ...commandTable, ...guideTable, ...envTable, ...pathTable, ...footer].join('\n')
);
