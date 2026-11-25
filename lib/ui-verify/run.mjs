// ui-verify runner: drives a pinned Playwright through a lead-written scenario file and judges every
// row itself. Usage and contract: lib/ui-verify/README.md.
//   node run.mjs scenario --scenario <file> --out <dir> [--step-timeout-ms N] [--scenario-timeout-ms N] [--run-budget-ms N]
//   node run.mjs --doctor
// Exit codes: 0 every row PASS, 1 a row FAIL, 2 no FAIL but something unchecked, 3 refused before any
// browser started, 4 internal error. Doctor: 0 ready, 20 no Playwright, 21 version differs, 22 no browser.
import { spawnSync } from 'node:child_process';
import { createHash, randomBytes } from 'node:crypto';
import dns from 'node:dns/promises';
import { existsSync, mkdirSync, readdirSync, readFileSync, realpathSync, statSync, writeFileSync, writeSync } from 'node:fs';
import net from 'node:net';
import path from 'node:path';
import { fileURLToPath, pathToFileURL } from 'node:url';

const MIN_NODE_MAJOR = 22;
if (Number(process.versions.node.split('.')[0]) < MIN_NODE_MAJOR) {
  process.stderr.write(`ui-verify: internal error: node ${process.versions.node} is too old, needs ${MIN_NODE_MAJOR} or newer\n`);
  process.exit(4);
}

const DEFAULT_TIMEOUTS = { stepMs: 10000, scenarioMs: 30000, runBudgetMs: 300000 };
const DEFAULT_VIEWPORTS = [390, 768, 1280];
const MAX_SCENARIOS = 12;
const MAX_STEPS = 20;
const MAX_VIEWPORTS = 4;
const MAX_HOSTS = 8;
const MAX_STRING = 200;
const MAX_READY = 100;
const PIN_WARN_DAYS = 120;
const OBSERVED_MAX = 200;
const DNS_TIMEOUT_MS = 15000;
const LAUNCH_CAP_MS = 60000;
const LEFTOVER_WAIT_MS = 5000;
const VIEWPORT_HEIGHT = 900;
const POLL_MS = 100;
const NO_TEXT_WINDOW_MS = 500;
const WEBRTC_ARG = '--force-webrtc-ip-handling-policy=disable_non_proxied_udp';
const ROLES = ['button', 'link', 'textbox', 'checkbox', 'radio', 'combobox', 'heading', 'tab', 'menuitem', 'dialog', 'alert', 'status'];
const LOOPBACK_NAMES = new Set(['127.0.0.1', 'localhost', '[::1]']);
const EXPECT_VERBS = new Set(['expect_text', 'expect_no_text', 'expect_url']);
const STEP_SHAPES = {
  goto: { required: ['path'], optional: [] },
  click: { required: ['role', 'name'], optional: [] },
  fill: { required: ['role', 'name', 'value'], optional: [] },
  expect_text: { required: ['text'], optional: ['within'] },
  expect_no_text: { required: ['text'], optional: [] },
  expect_url: { required: ['path'], optional: [] },
  screenshot: { required: ['name'], optional: [] },
};

const RUNNER_PATH = realpathSync(fileURLToPath(import.meta.url));
const RUNNER_DIR = path.dirname(RUNNER_PATH);

class Refusal extends Error {}
const refuse = (message) => { throw new Refusal(message); };

const state = { outDir: null, headSha: '', url: '', scenarioSha: '', runId: '', viewports: DEFAULT_VIEWPORTS, startedAt: Date.now() };

function oneLine(text) {
  return String(text).replace(/[\p{Cc}\p{Cf}\p{Zl}\p{Zp}]/gu, ' ').replace(/\s+/g, ' ').trim();
}

// Hostile page text and lead-written strings pass through here before they reach result.json or stdout.
function sanitize(text) {
  const cleaned = String(text)
    .replace(/[\p{Cc}\p{Cf}\p{Zl}\p{Zp}]/gu, ' ')
    .replace(/ {2,}/g, ' ')
    .replace(/`/g, "'")
    .replace(/\|/g, '/')
    .trim();
  return Array.from(cleaned).slice(0, OBSERVED_MAX).join('').trim();
}

function parseArgs(argv) {
  const args = argv.slice(2);
  if (args.length === 1 && args[0] === '--doctor') return { mode: 'doctor' };
  if (args[0] !== 'scenario') refuse('usage: run.mjs scenario --scenario <file> --out <dir> [--step-timeout-ms N] [--scenario-timeout-ms N] [--run-budget-ms N] | run.mjs --doctor');
  const flags = { '--scenario': 'scenario', '--out': 'out', '--step-timeout-ms': 'stepMs', '--scenario-timeout-ms': 'scenarioMs', '--run-budget-ms': 'runBudgetMs' };
  const opts = { mode: 'scenario', timeouts: { ...DEFAULT_TIMEOUTS } };
  const seen = new Set();
  for (let i = 1; i < args.length; i += 2) {
    const key = flags[args[i]];
    if (!key) refuse(`unknown argument ${oneLine(args[i])}`);
    if (seen.has(key)) refuse(`${args[i]} given twice`);
    seen.add(key);
    if (i + 1 >= args.length) refuse(`${args[i]} needs a value`);
    const value = args[i + 1];
    if (key === 'scenario' || key === 'out') { opts[key] = value; continue; }
    if (!/^[1-9][0-9]{0,8}$/.test(value)) refuse(`${args[i]} needs a positive whole number`);
    if (Number(value) > DEFAULT_TIMEOUTS[key]) refuse(`${args[i]} can only lower the default of ${DEFAULT_TIMEOUTS[key]}`);
    opts.timeouts[key] = Number(value);
  }
  if (!opts.scenario) refuse('--scenario is required');
  if (!opts.out) refuse('--out is required');
  return opts;
}

const isObject = (value) => value !== null && typeof value === 'object' && !Array.isArray(value);

function checkKeys(value, where, required, optional) {
  if (!isObject(value)) refuse(`${where} must be an object`);
  for (const key of Object.keys(value)) {
    if (!required.includes(key) && !optional.includes(key)) refuse(`unknown key ${where}.${oneLine(key)}`);
  }
  for (const key of required) {
    if (!(key in value)) refuse(`missing key ${where}.${key}`);
  }
}

function checkString(value, where, min, max) {
  if (typeof value !== 'string') refuse(`${where} must be a string`);
  const length = Array.from(value).length;
  if (length < min) refuse(`${where} must not be shorter than ${min} characters`);
  if (length > max) refuse(`${where} must not be longer than ${max} characters`);
}

function checkLongStrings(value, where) {
  if (typeof value === 'string') {
    if (Array.from(value).length > MAX_STRING) refuse(`${where} is longer than ${MAX_STRING} characters`);
  } else if (Array.isArray(value)) {
    value.forEach((item, index) => checkLongStrings(item, `${where}[${index}]`));
  } else if (isObject(value)) {
    for (const [key, item] of Object.entries(value)) checkLongStrings(item, `${where}.${oneLine(key)}`);
  }
}

function checkPagePath(value, where) {
  checkString(value, where, 1, MAX_STRING);
  if (!/^\/([^/\\\s][^\\\s]*)?$/.test(value)) refuse(`${where} must be a path starting with exactly one /`);
}

function checkRole(value, where) {
  if (!ROLES.includes(value)) refuse(`${where} must be one of the twelve roles`);
}

function checkStep(step, where) {
  if (!isObject(step)) refuse(`${where} must be an object`);
  const shape = STEP_SHAPES[step.do];
  if (typeof step.do !== 'string' || !shape) refuse(`${where}.do is not a known step verb`);
  checkKeys(step, where, ['do', ...shape.required], shape.optional);
  if (step.do === 'goto' || step.do === 'expect_url') checkPagePath(step.path, `${where}.path`);
  if (step.do === 'click' || step.do === 'fill') {
    checkRole(step.role, `${where}.role`);
    checkString(step.name, `${where}.name`, 1, MAX_STRING);
  }
  if (step.do === 'fill') checkString(step.value, `${where}.value`, 0, MAX_STRING);
  if (step.do === 'expect_text' || step.do === 'expect_no_text') checkString(step.text, `${where}.text`, 1, MAX_STRING);
  if (step.do === 'expect_text' && 'within' in step) {
    checkKeys(step.within, `${where}.within`, ['role', 'name'], []);
    checkRole(step.within.role, `${where}.within.role`);
    checkString(step.within.name, `${where}.within.name`, 1, MAX_STRING);
  }
  if (step.do === 'screenshot') {
    checkString(step.name, `${where}.name`, 1, MAX_STRING);
    if (!/^[a-z0-9-]+$/.test(step.name)) refuse(`${where}.name may hold only a-z, 0-9 and -`);
  }
}

function checkScenarioEntry(entry, where, seenPairs) {
  checkKeys(entry, where, ['id', 'kind'], ['title', 'steps', 'skip']);
  if (typeof entry.id !== 'string' || !/^AC-[0-9]+$/.test(entry.id)) refuse(`${where}.id must look like AC-<digits>`);
  if (entry.kind !== 'criterion' && entry.kind !== 'negative') refuse(`${where}.kind must be criterion or negative`);
  const pair = `${entry.id}|${entry.kind}`;
  if (seenPairs.has(pair)) refuse(`${where} repeats the pair ${entry.id} ${entry.kind}`);
  seenPairs.add(pair);
  if ('title' in entry) checkString(entry.title, `${where}.title`, 0, MAX_STRING);
  if ('steps' in entry && 'skip' in entry) refuse(`${where} holds both steps and skip`);
  if (!('steps' in entry) && !('skip' in entry)) refuse(`${where} needs steps or skip`);
  if ('skip' in entry) { checkString(entry.skip, `${where}.skip`, 1, MAX_STRING); return; }
  if (!Array.isArray(entry.steps)) refuse(`${where}.steps must be an array`);
  if (entry.steps.length < 1 || entry.steps.length > MAX_STEPS) refuse(`${where}.steps must hold 1 to ${MAX_STEPS} steps`);
  entry.steps.forEach((step, index) => checkStep(step, `${where}.steps[${index}]`));
}

const HOSTNAME_RE = /^[a-z0-9]([a-z0-9-]*[a-z0-9])?(\.[a-z0-9]([a-z0-9-]*[a-z0-9])?)*$/;

function normalizeHost(host) {
  return String(host).toLowerCase().replace(/\.$/, '');
}

function checkAllowHosts(hosts) {
  if (!Array.isArray(hosts) || hosts.length < 1 || hosts.length > MAX_HOSTS) refuse(`target.allow_hosts must hold 1 to ${MAX_HOSTS} hostnames`);
  const normalized = hosts.map((host, index) => {
    checkString(host, `target.allow_hosts[${index}]`, 1, MAX_STRING);
    const name = normalizeHost(host);
    const bracketed = /^\[[0-9a-f:.]+\]$/.test(name) && net.isIPv6(name.slice(1, -1));
    if (!bracketed && !HOSTNAME_RE.test(name)) refuse(`target.allow_hosts[${index}] must be an exact hostname without wildcards`);
    return name;
  });
  return new Set(normalized);
}

function checkTarget(target) {
  checkKeys(target, 'target', ['url', 'head_sha', 'allow_hosts'], ['allow_loopback']);
  const allowLoopback = target.allow_loopback === undefined ? false : target.allow_loopback;
  if (typeof allowLoopback !== 'boolean') refuse('target.allow_loopback must be true or false');
  checkString(target.url, 'target.url', 1, MAX_STRING);
  if (typeof target.head_sha !== 'string' || !/^[0-9a-f]{40}$/.test(target.head_sha)) refuse('target.head_sha must be 40 lowercase hex characters');
  const allowHosts = checkAllowHosts(target.allow_hosts);
  let url;
  try { url = new URL(target.url); } catch { refuse('target.url is not a valid URL'); }
  if (url.username || url.password) refuse('target.url must not carry credentials');
  if (url.protocol === 'http:') {
    if (!allowLoopback || !LOOPBACK_NAMES.has(url.hostname)) refuse('target.url must be https (http only for a loopback host with allow_loopback)');
  } else if (url.protocol !== 'https:') {
    refuse(`target.url scheme ${oneLine(url.protocol)} is not allowed`);
  }
  if (!allowHosts.has(normalizeHost(url.hostname))) refuse('target.url host is not in target.allow_hosts');
  return { url, allowHosts, allowLoopback, headSha: target.head_sha };
}

function validateScenarioFile(raw) {
  checkKeys(raw, 'scenario file', ['schema', 'target', 'ready', 'scenarios'], ['viewports', 'identity']);
  if (raw.schema !== 1) refuse('schema must be 1');
  checkLongStrings(raw, 'scenario file');
  const target = checkTarget(raw.target);
  checkKeys(raw.ready, 'ready', ['text'], []);
  checkString(raw.ready.text, 'ready.text', 1, MAX_READY);
  let viewports = DEFAULT_VIEWPORTS;
  if ('viewports' in raw) {
    const list = raw.viewports;
    const valid = Array.isArray(list) && list.length >= 1 && list.length <= MAX_VIEWPORTS
      && list.every((width) => Number.isInteger(width) && width >= 200 && width <= 3000);
    if (!valid) refuse(`viewports must hold 1 to ${MAX_VIEWPORTS} integers from 200 to 3000`);
    viewports = list;
  }
  let identity = null;
  if ('identity' in raw) {
    if (!isObject(raw.identity) || Object.keys(raw.identity).length !== 1) refuse('identity must hold exactly one of header or meta');
    checkKeys(raw.identity, 'identity', [], ['header', 'meta']);
    const [kind] = Object.keys(raw.identity);
    checkString(raw.identity[kind], `identity.${kind}`, 1, MAX_STRING);
    identity = { kind, name: raw.identity[kind] };
  }
  if (!Array.isArray(raw.scenarios)) refuse('scenarios must be an array');
  if (raw.scenarios.length > MAX_SCENARIOS) refuse(`more than ${MAX_SCENARIOS} scenarios`);
  const seenPairs = new Set();
  raw.scenarios.forEach((entry, index) => checkScenarioEntry(entry, `scenarios[${index}]`, seenPairs));
  return { ...target, readyText: raw.ready.text, viewports, identity, scenarios: raw.scenarios };
}

function gitRootAbove(start) {
  let dir = start;
  for (;;) {
    if (existsSync(path.join(dir, '.git'))) return dir;
    const parent = path.dirname(dir);
    if (parent === dir) return null;
    dir = parent;
  }
}

function realPathOfPossibleNew(target) {
  let existing = path.resolve(target);
  const rest = [];
  while (!existsSync(existing)) {
    const parent = path.dirname(existing);
    if (parent === existing) break;
    rest.unshift(path.basename(existing));
    existing = parent;
  }
  return path.join(realpathSync(existing), ...rest);
}

const isInside = (child, root) => child === root || child.startsWith(root + path.sep);

function checkRunnerOwnPath() {
  const root = gitRootAbove(realpathSync(process.cwd()));
  if (root && isInside(RUNNER_PATH, root)) refuse('the runner sits inside the git work tree of the current directory; run it from another directory');
}

function readScenarioFile(file) {
  const real = realPathOfPossibleNew(file);
  if (gitRootAbove(path.dirname(real))) refuse('the scenario file sits inside a git work tree');
  let bytes;
  try { bytes = readFileSync(real); } catch { refuse('the scenario file cannot be read'); }
  let parsed;
  try { parsed = JSON.parse(bytes.toString('utf8')); } catch { refuse('the scenario file is not valid JSON'); }
  return { bytes, parsed };
}

function checkOutDir(dir) {
  const real = realPathOfPossibleNew(dir);
  if (gitRootAbove(real)) refuse('--out sits inside a git work tree');
  if (!existsSync(real)) return real;
  if (!statSync(real).isDirectory()) refuse('--out exists and is not a directory');
  if (readdirSync(real).length > 0) refuse('--out exists and is not empty');
  return real;
}

const loopbackList = new net.BlockList();
loopbackList.addSubnet('127.0.0.0', 8, 'ipv4');
loopbackList.addAddress('::1', 'ipv6');
const privateList = new net.BlockList();
for (const [base, bits] of [['0.0.0.0', 8], ['10.0.0.0', 8], ['100.64.0.0', 10], ['169.254.0.0', 16], ['172.16.0.0', 12],
  ['192.0.0.0', 24], ['192.168.0.0', 16], ['198.18.0.0', 15], ['224.0.0.0', 4], ['240.0.0.0', 4]]) privateList.addSubnet(base, bits, 'ipv4');
for (const [base, bits] of [['fc00::', 7], ['fe80::', 10], ['ff00::', 8]]) privateList.addSubnet(base, bits, 'ipv6');
privateList.addAddress('::', 'ipv6');

function classifyAddress(address) {
  const family = net.isIPv6(address) ? 'ipv6' : 'ipv4';
  if (loopbackList.check(address, family)) return 'loopback';
  if (privateList.check(address, family)) return 'private';
  return 'ok';
}

function lookupWithCap(host) {
  const cap = new Promise((resolve) => { setTimeout(() => resolve(null), DNS_TIMEOUT_MS).unref(); });
  const lookup = dns.lookup(host, { all: true }).then((found) => found.map((item) => item.address), () => null);
  return Promise.race([lookup, cap]);
}

async function checkAllowedHostAddresses(allowHosts, allowLoopback) {
  const unresolved = [];
  for (const host of allowHosts) {
    const bare = host.replace(/^\[|\]$/g, '');
    const addresses = net.isIP(bare) ? [bare] : await lookupWithCap(host);
    if (!addresses || addresses.length === 0) { unresolved.push(host); continue; }
    for (const address of addresses) {
      const kind = classifyAddress(address);
      if (kind === 'private') refuse(`allowed host ${oneLine(host)} resolves to a private, link-local or shared address`);
      if (kind === 'loopback' && !allowLoopback) refuse(`allowed host ${oneLine(host)} resolves to a loopback address (allow_loopback is false)`);
    }
  }
  return unresolved;
}

function resolveInstallRoot() {
  const fromEnv = process.env.UI_VERIFY_HOME;
  if (fromEnv && path.isAbsolute(fromEnv)) return { root: fromEnv, source: 'env UI_VERIFY_HOME' };
  const resolver = path.resolve(RUNNER_DIR, '../config/data-path.sh');
  if (!existsSync(resolver)) return { root: '', source: 'the data-path resolver (not found)' };
  const result = spawnSync('bash', [resolver, 'path', 'cache', 'ui-verify'], { encoding: 'utf8', timeout: 15000 });
  const root = result.status === 0 ? result.stdout.trim() : '';
  return { root: path.isAbsolute(root) ? root : '', source: 'the data-path resolver' };
}

function readPin() {
  try {
    const pkg = JSON.parse(readFileSync(path.join(RUNNER_DIR, 'package.json'), 'utf8'));
    return { version: String(pkg.dependencies?.playwright ?? ''), pinnedOn: String(pkg.pinnedOn ?? '') };
  } catch {
    return { version: '', pinnedOn: '' };
  }
}

function hasChromium(browsersDir) {
  try { return readdirSync(browsersDir).some((name) => name.startsWith('chromium')); } catch { return false; }
}

function inspectInstall(root, pinnedVersion) {
  if (!root) return { state: 'absent', installed: '' };
  let installed = '';
  try { installed = String(JSON.parse(readFileSync(path.join(root, 'node_modules', 'playwright', 'package.json'), 'utf8')).version); } catch { return { state: 'absent', installed: '' }; }
  if (installed !== pinnedVersion) return { state: 'drift', installed };
  return { state: hasChromium(path.join(root, 'browsers')) ? 'ready' : 'no-browser', installed };
}

const INSTALL_FAULT_REASONS = {
  absent: 'install absent: playwright is not installed in the install root',
  drift: 'playwright version differs from the pin',
  'no-browser': 'install absent: chromium is not installed in the install root',
};

function pinAgeDays(pinnedOn) {
  const pinned = Date.parse(pinnedOn);
  if (Number.isNaN(pinned)) return null;
  return Math.floor((Date.now() - pinned) / 86400000);
}

function runDoctor() {
  const pin = readPin();
  const { root, source } = resolveInstallRoot();
  const inspected = inspectInstall(root, pin.version);
  const age = pinAgeDays(pin.pinnedOn);
  const quoted = (text) => `"${text}"`;
  const installCommand = [
    `mkdir -p ${quoted(root)}`,
    `cp ${quoted(path.join(RUNNER_DIR, 'package.json'))} ${quoted(path.join(RUNNER_DIR, 'package-lock.json'))} ${quoted(root)}/`,
    `cd ${quoted(root)}`,
    'npm ci --ignore-scripts',
    `PLAYWRIGHT_BROWSERS_PATH=${quoted(path.join(root, 'browsers'))} ./node_modules/.bin/playwright install chromium`,
  ].join(' && ');
  let code = 0;
  let verdict = age !== null && age > PIN_WARN_DAYS ? `READY (pin older than ${PIN_WARN_DAYS} days: bump it)` : 'READY';
  if (inspected.state === 'absent') { code = 20; verdict = 'NOT READY: playwright is not installed in the install root'; }
  if (inspected.state === 'drift') { code = 21; verdict = `NOT READY: installed playwright ${inspected.installed} differs from the pin ${pin.version}`; }
  if (inspected.state === 'no-browser') { code = 22; verdict = 'NOT READY: chromium is missing from the browser cache'; }
  const lines = [
    'ui-verify doctor',
    `pinned:        playwright ${pin.version || 'unknown'}`,
    `installed:     ${inspected.installed ? `playwright ${inspected.installed}` : 'not installed'}`,
    `pin age:       ${age === null ? 'unknown' : `${age} days`} (from "pinnedOn" in lib/ui-verify/package.json)`,
    `node:          v${process.versions.node} (needs ${MIN_NODE_MAJOR} or newer)`,
    `install root:  ${root || 'unresolved'} (from ${source})`,
    `browser cache: ${root ? path.join(root, 'browsers') : 'unresolved'}`,
    `browser:       ${inspected.state === 'ready' ? 'chromium present' : 'missing'}`,
    `install:       ${installCommand}`,
    `state:         ${verdict}`,
  ];
  process.stdout.write(`${lines.join('\n')}\n`);
  return code;
}

function rowKey(entry) { return `${entry.id}|${entry.kind}`; }
function rowLabel(row) { return row.kind === 'negative' ? `${row.id} neg` : row.id; }

function newRow(entry) {
  return { layer: 'scenario', id: entry.id, kind: entry.kind, status: 'NO-CHECK', flaky: false, reason: '', observed: '', viewports: [], evidence: [] };
}

function entryHasExpect(entry) {
  return entry.steps.some((step) => EXPECT_VERBS.has(step.do));
}

// Splits the entries into rows that are settled without a browser (skip, asserts nothing) and the
// entries a browser run must judge.
function planRows(scenarios) {
  const rows = [];
  const runnable = [];
  for (const entry of scenarios) {
    const row = newRow(entry);
    rows.push(row);
    if ('skip' in entry) { row.reason = `skipped by scenario: ${sanitize(entry.skip)}`; continue; }
    if (!entryHasExpect(entry)) { row.reason = 'scenario asserts nothing'; continue; }
    runnable.push({ key: rowKey(entry), entry, row });
  }
  return { rows, runnable };
}

function applyEnvironmentFault(runnable, reason) {
  for (const item of runnable) {
    Object.assign(item.row, { status: 'NO-CHECK', reason, observed: '', flaky: false, viewports: [], evidence: [] });
  }
}

function applyOutcomes(runnable, outcomes) {
  for (const item of runnable) {
    const outcome = outcomes.get(item.key);
    if (!outcome) throw new Error(`the browser driver returned no outcome for ${item.key}`);
    Object.assign(item.row, {
      status: outcome.status,
      reason: sanitize(outcome.reason ?? ''),
      observed: sanitize(outcome.observed ?? ''),
      flaky: outcome.flaky === true,
      viewports: outcome.viewports ?? [],
      evidence: outcome.evidence ?? [],
    });
  }
}

function deriveSummary(rows, environmentReason) {
  const counts = { pass: 0, fail: 0, no_check: 0 };
  for (const row of rows) {
    if (row.status === 'PASS') counts.pass += 1;
    else if (row.status === 'FAIL') counts.fail += 1;
    else counts.no_check += 1;
  }
  let verdict = 'PASS';
  if (rows.length === 0 || counts.no_check > 0) verdict = 'NO-CHECK';
  if (counts.fail > 0) verdict = 'FAIL';
  let reason = environmentReason;
  if (!reason && rows.length === 0) reason = 'no AC';
  return { counts, verdict, reason };
}

const exitCodeFor = (verdict) => (verdict === 'PASS' ? 0 : verdict === 'FAIL' ? 1 : 2);

function emptyBrowserRecord() {
  return { sandbox: false, no_sandbox_seen: false, args: [], launch_attempts: 0, pids: [], leftover_pids: [] };
}

function buildResult(parts) {
  const { rows, environmentReason, identity, blockedRequests, browser, durationMs, playwright } = parts;
  const summary = deriveSummary(rows, environmentReason);
  return {
    schema: 1,
    runner: { path: RUNNER_PATH, playwright },
    head_sha: state.headSha,
    scenario_sha256: state.scenarioSha,
    run_id: state.runId,
    url: state.url,
    identity,
    viewports: state.viewports,
    verdict: summary.verdict,
    reason: summary.reason,
    counts: summary.counts,
    rows,
    blocked_requests: blockedRequests,
    browser,
    duration_ms: durationMs,
  };
}

function renderStdout(result) {
  const lines = [
    `ui-verify: head ${result.head_sha} scenario-sha256 ${result.scenario_sha256.slice(0, 16)} preview-identity ${result.identity.status} playwright ${result.runner.playwright} run ${result.run_id}`,
    `ui-verify: counts PASS ${result.counts.pass} FAIL ${result.counts.fail} NO-CHECK ${result.counts.no_check} runner-verdict ${result.verdict}`,
  ];
  for (const row of result.rows) {
    lines.push(`row ${rowLabel(row)} | ${row.status} | ${row.reason} | ${row.evidence.join(', ')}`.trimEnd());
  }
  for (const row of result.rows) {
    if (row.observed) lines.push(`observed ${rowLabel(row)}: ${row.observed}`);
  }
  return `${lines.join('\n')}\n`;
}

const sleep = (ms) => new Promise((resolve) => { setTimeout(resolve, ms); });
const collapse = (text) => String(text).replace(/\s+/g, ' ').trim();

// Resolves to the promise's value, or to TIMED_OUT after ms. The promise itself keeps running, so its
// late failure is swallowed here and never becomes an unhandled rejection.
const TIMED_OUT = Symbol('timed out');
function raceDeadline(promise, ms) {
  let timer;
  const deadline = new Promise((resolve) => { timer = setTimeout(() => resolve(TIMED_OUT), Math.max(1, ms)); });
  const guarded = Promise.resolve(promise).catch((error) => { if (error?.name === 'TimeoutError') return TIMED_OUT; throw error; });
  return Promise.race([guarded, deadline]).finally(() => clearTimeout(timer));
}

// The run's own browser processes, found by the run id on their command line.
function scanRunProcesses(runId) {
  const marker = `--kit-ui-verify=${runId}`;
  const listed = spawnSync('ps', ['-axww', '-o', 'pid=,command='], { encoding: 'utf8', timeout: 15000, maxBuffer: 64 * 1024 * 1024 });
  if (listed.status !== 0 || typeof listed.stdout !== 'string') return [];
  const found = [];
  for (const line of listed.stdout.split('\n')) {
    const match = /^\s*(\d+)\s+(.*)$/.exec(line);
    if (!match || !match[2].includes(marker) || Number(match[1]) === process.pid) continue;
    found.push({ pid: Number(match[1]), command: match[2] });
  }
  return found;
}

async function loadPlaywright(installRoot) {
  process.env.PLAYWRIGHT_BROWSERS_PATH = path.join(installRoot, 'browsers');
  return import(pathToFileURL(path.join(installRoot, 'node_modules', 'playwright', 'index.mjs')).href);
}

function launchBrowser(playwright, record) {
  record.launch_attempts = 1;
  if (process.env.UI_VERIFY_TEST_FAULT === 'sandbox-unavailable') throw new Error('injected test fault: the sandbox cannot start');
  return playwright.chromium.launch({ headless: true, chromiumSandbox: true, timeout: LAUNCH_CAP_MS, args: record.args });
}

// Reads the processes that carry the run id. A browser with no process found, or one started with
// --no-sandbox, means the sandbox is unverified and the run stops.
function verifySandbox(record, runId) {
  const found = scanRunProcesses(runId);
  record.pids = found.map((item) => item.pid);
  record.no_sandbox_seen = found.some((item) => item.command.includes('--no-sandbox'));
  record.sandbox = found.length > 0 && !record.no_sandbox_seen;
  return record.sandbox ? '' : 'browser sandbox unavailable';
}

async function closeBrowser(browser, record, runId) {
  await raceDeadline(browser.close(), 15000).catch(() => {});
  const until = Date.now() + LEFTOVER_WAIT_MS;
  let left = scanRunProcesses(runId);
  while (left.length > 0 && Date.now() < until) {
    await sleep(250);
    left = scanRunProcesses(runId);
  }
  record.leftover_pids = left.map((item) => item.pid);
}

function hostOfUrl(raw) {
  try { return normalizeHost(new URL(raw).hostname); } catch { return ''; }
}

function noteBlocked(guard, host) {
  const name = host || 'unparsable';
  guard.blocked.set(name, (guard.blocked.get(name) ?? 0) + 1);
}

function isMainFrameNavigation(request) {
  try { return request.isNavigationRequest() && request.frame().parentFrame() === null; } catch { return false; }
}

// Every HTTP request and every WebSocket goes through the host check. Anything off the list is
// aborted (a socket is closed and never connected), counted, and a blocked top-level navigation is
// flagged so a redirect off the allowed hosts gets its own reason.
async function containContext(context, guard) {
  const watch = { navigationBlocked: false };
  await context.route('**/*', async (route) => {
    try {
      const request = route.request();
      const url = request.url();
      if (/^https?:/i.test(url) && guard.allowHosts.has(hostOfUrl(url))) { await route.continue(); return; }
      noteBlocked(guard, hostOfUrl(url));
      if (isMainFrameNavigation(request)) watch.navigationBlocked = true;
      await route.abort('blockedbyclient');
    } catch { /* the page went away while the request was in flight */ }
  });
  await context.routeWebSocket(/.*/, async (socket) => {
    try {
      const url = socket.url();
      if (/^wss?:/i.test(url) && guard.allowHosts.has(hostOfUrl(url))) { socket.connectToServer(); return; }
      noteBlocked(guard, hostOfUrl(url));
      await socket.close();
    } catch { /* the page went away while the socket was opening */ }
  });
  return watch;
}

async function openPage(browser, guard, width) {
  const context = await browser.newContext({ viewport: { width, height: VIEWPORT_HEIGHT }, acceptDownloads: false, serviceWorkers: 'block', permissions: [] });
  const watch = await containContext(context, guard);
  const page = await context.newPage();
  context.on('page', (popup) => { if (popup !== page) popup.close().catch(() => {}); });
  return { context, page, watch };
}

async function closeContext(context) {
  await raceDeadline(context.close(), 10000).catch(() => {});
}

function judgeIdentity(raw, headSha) {
  const value = String(raw ?? '').trim().toLowerCase();
  if (!value) return { status: 'unverified', seen: '' };
  const seen = value.slice(0, 12);
  if (!/^[0-9a-f]{7,40}$/.test(value)) return { status: 'unverified', seen };
  return { status: headSha.startsWith(value) ? 'matched' : 'mismatch', seen };
}

function readMetaContent(name) {
  const meta = Array.from(document.querySelectorAll('meta')).find((item) => item.getAttribute('name') === name);
  return meta ? meta.getAttribute('content') : '';
}

function bodyHasText(text) {
  return Boolean(document.body) && document.body.innerText.replace(/\s+/g, ' ').includes(text);
}

// One look at the preview: status, final host, ready text, identity. Never a FAIL, only a reason.
async function preflightAttempt(env) {
  const { browser, guard, spec, timeouts } = env;
  const opened = await openPage(browser, guard, spec.viewports[0]);
  const started = Date.now();
  try {
    let response;
    try {
      response = await opened.page.goto(spec.url.href, { waitUntil: 'load', timeout: timeouts.stepMs });
    } catch {
      return opened.watch.navigationBlocked ? { reason: 'redirected off an allowed host', final: true } : { reason: 'preview unreachable' };
    }
    if (!response || response.status() >= 400) return { reason: 'preview unreachable' };
    const left = Math.max(1, timeouts.stepMs - (Date.now() - started));
    try {
      await opened.page.waitForFunction(bodyHasText, spec.readyText, { timeout: left });
    } catch {
      return { reason: 'preview not ready' };
    }
    let raw = '';
    if (spec.identity?.kind === 'header') raw = response.headers()[spec.identity.name.toLowerCase()] ?? '';
    if (spec.identity?.kind === 'meta') raw = await raceDeadline(opened.page.evaluate(readMetaContent, spec.identity.name), left) ?? '';
    return { reason: '', raw: raw === TIMED_OUT ? '' : raw };
  } finally {
    await closeContext(opened.context);
  }
}

// Three attempts, with gaps of one fifth and then two fifths of the step timeout.
async function runPreflight(env) {
  const gaps = [env.timeouts.stepMs / 5, (env.timeouts.stepMs * 2) / 5];
  let last = { reason: 'preview unreachable' };
  for (let attempt = 0; attempt < 3; attempt += 1) {
    if (attempt > 0) await sleep(gaps[attempt - 1]);
    last = await preflightAttempt(env);
    if (!last.reason || last.final) break;
  }
  return last;
}

function stepLimit(attemptClock, run, timeouts) {
  const scenarioLeft = timeouts.scenarioMs - attemptClock.spentMs;
  const budgetLeft = timeouts.runBudgetMs - run.spentMs;
  const limit = Math.min(timeouts.stepMs, scenarioLeft, budgetLeft);
  if (limit >= timeouts.stepMs) return { limit, cause: 'step' };
  return { limit, cause: budgetLeft <= scenarioLeft ? 'budget' : 'scenario' };
}

const CAUSE_REASONS = { scenario: 'scenario timeout', budget: 'run budget spent' };

function locatorFor(page, role, name) {
  return page.getByRole(role, { name, exact: true });
}

async function pollUntil(check, limitMs) {
  const end = Date.now() + limitMs;
  for (;;) {
    const result = await check(Math.max(1, end - Date.now()));
    if (result.ok || Date.now() >= end) return result;
    await sleep(Math.min(POLL_MS, Math.max(1, end - Date.now())));
  }
}

// The text of a `within` element, or of the body. { missing: true } when the element is not there.
async function readScope(page, within, limitMs) {
  const target = within ? locatorFor(page, within.role, within.name) : page.locator('body');
  const count = await raceDeadline(target.count(), limitMs);
  if (count === TIMED_OUT) return { timedOut: true };
  if (count === 0) return { missing: true };
  const text = await raceDeadline(target.first().innerText({ timeout: limitMs }), limitMs);
  return text === TIMED_OUT ? { timedOut: true } : { text: collapse(text) };
}

const missingElement = (role, name) => `element not found: role=${role} name=${name}`;

async function observedFor(page, within) {
  const limitMs = 2000;
  if (within) {
    const scope = await readScope(page, within, limitMs).catch(() => ({ missing: true }));
    return scope.text ?? missingElement(within.role, within.name);
  }
  for (const selector of ['[role=alert], [role=status]', 'main', 'body']) {
    const target = page.locator(selector).first();
    const count = await raceDeadline(target.count(), limitMs).catch(() => 0);
    if (count === TIMED_OUT || !count) continue;
    const text = await raceDeadline(target.innerText({ timeout: limitMs }), limitMs).catch(() => TIMED_OUT);
    if (text !== TIMED_OUT) return collapse(text);
  }
  return '';
}

async function stepGoto(page, step, limitMs, spec, watch) {
  const started = Date.now();
  try {
    await page.goto(new URL(step.path, spec.url.origin).href, { waitUntil: 'load', timeout: limitMs });
    const fonts = await raceDeadline(page.evaluate(() => document.fonts.ready.then(() => true)), Math.max(1, limitMs - (Date.now() - started)));
    if (fonts === TIMED_OUT) return { timedOut: true };
    return { ok: true };
  } catch (error) {
    if (watch.navigationBlocked) return { nocheck: 'redirected off an allowed host' };
    if (error?.name === 'TimeoutError') return { timedOut: true };
    return { nocheck: 'page did not settle' };
  }
}

// click and fill: exactly one match must appear before the limit.
async function stepLocate(page, step, limitMs, act) {
  const target = locatorFor(page, step.role, step.name);
  const found = await pollUntil(async (left) => {
    const count = await raceDeadline(target.count(), left);
    return { ok: count === 1, count: count === TIMED_OUT ? 0 : count };
  }, limitMs);
  if (!found.ok) {
    const observed = found.count > 1 ? `ambiguous: ${found.count} matches` : missingElement(step.role, step.name);
    return { timedOut: true, observed };
  }
  try {
    await act(target, limitMs);
    return { ok: true };
  } catch (error) {
    if (error?.name !== 'TimeoutError') throw error;
    return { timedOut: true, observed: `element not actionable: role=${step.role} name=${step.name}` };
  }
}

async function stepExpectText(page, step, limitMs) {
  const found = await pollUntil(async (left) => {
    const scope = await readScope(page, step.within, left);
    return { ok: Boolean(scope.text !== undefined && scope.text.includes(step.text)), scope };
  }, limitMs);
  if (found.ok) return { ok: true };
  if (found.scope.missing) return { timedOut: true, observed: missingElement(step.within.role, step.within.name) };
  return { timedOut: true, observed: await observedFor(page, step.within) };
}

async function stepExpectNoText(page, step, limitMs) {
  if (limitMs < NO_TEXT_WINDOW_MS) return { timedOut: true, observed: '' };
  const end = Date.now() + NO_TEXT_WINDOW_MS;
  while (Date.now() < end) {
    const scope = await readScope(page, null, limitMs);
    if (scope.text !== undefined && scope.text.includes(step.text)) return { observed: await observedFor(page, null) };
    await sleep(50);
  }
  return { ok: true };
}

async function stepExpectUrl(page, step, limitMs) {
  const current = () => { const url = new URL(page.url()); return url.pathname + url.search; };
  const found = await pollUntil(async () => ({ ok: current() === step.path }), limitMs);
  return found.ok ? { ok: true } : { timedOut: true, observed: `url is ${current()}` };
}

function performStep(page, step, limitMs, spec, watch) {
  if (step.do === 'goto') return stepGoto(page, step, limitMs, spec, watch);
  if (step.do === 'click') return stepLocate(page, step, limitMs, (target, left) => target.click({ timeout: left }));
  if (step.do === 'fill') return stepLocate(page, step, limitMs, (target, left) => target.fill(step.value, { timeout: left }));
  if (step.do === 'expect_text') return stepExpectText(page, step, limitMs);
  if (step.do === 'expect_no_text') return stepExpectNoText(page, step, limitMs);
  return stepExpectUrl(page, step, limitMs);
}

function evidenceName(entry, width, name) {
  const number = entry.id.slice('AC-'.length);
  return `ac-${number}${entry.kind === 'negative' ? '-neg' : ''}-${width}-${name}.png`;
}

async function takeScreenshot(page, env, entry, width, step) {
  const file = evidenceName(entry, width, step.name);
  try {
    await page.screenshot({ path: path.join(env.outDir, file), timeout: env.timeouts.stepMs });
    return file;
  } catch {
    return '';
  }
}

// How a step that did not pass ends the attempt: a timeout caused by a clock is NO-CHECK, a timeout
// of the step itself is the step's own finding.
function interpretStep(result, cause, step) {
  if (result.nocheck) return { status: 'NO-CHECK', reason: result.nocheck, observed: '' };
  if (result.timedOut && cause !== 'step') return { status: 'NO-CHECK', reason: CAUSE_REASONS[cause], observed: '' };
  if (result.timedOut && step.do === 'goto') return { status: 'NO-CHECK', reason: 'page did not settle', observed: '' };
  return { status: 'FAIL', reason: '', observed: result.observed ?? '' };
}

// One scenario at one width in a fresh context. Only time inside a step counts against the clocks.
async function runAttempt(env, item, width) {
  const { guard, spec, timeouts, run } = env;
  const opened = await openPage(env.browser, guard, width);
  const attemptClock = { spentMs: 0 };
  const evidence = [];
  try {
    for (const step of item.entry.steps) {
      if (step.do === 'screenshot') {
        const file = await takeScreenshot(opened.page, env, item.entry, width, step);
        if (!file) return { status: 'NO-CHECK', reason: 'page did not settle', observed: '', evidence };
        evidence.push(file);
        continue;
      }
      const { limit, cause } = stepLimit(attemptClock, run, timeouts);
      if (limit <= 0) return { status: 'NO-CHECK', reason: CAUSE_REASONS[cause] ?? 'run budget spent', observed: '', evidence };
      const started = Date.now();
      const result = await performStep(opened.page, step, limit, spec, opened.watch);
      const spent = Date.now() - started;
      attemptClock.spentMs += spent;
      run.spentMs += spent;
      if (!result.ok) return { ...interpretStep(result, cause, step), evidence };
    }
    return { status: 'PASS', reason: '', observed: '', evidence };
  } finally {
    await closeContext(opened.context);
  }
}

const STATUS_RANK = { FAIL: 2, 'NO-CHECK': 1, PASS: 0 };

function foldViewports(perViewport) {
  const worst = perViewport.reduce((best, entry) => (STATUS_RANK[entry.status] > STATUS_RANK[best.status] ? entry : best), perViewport[0]);
  return {
    status: worst.status,
    reason: worst.reason,
    observed: worst.observed,
    flaky: perViewport.some((entry) => entry.flaky === true),
    viewports: perViewport.map((entry) => ({ width: entry.width, status: entry.status })),
    evidence: perViewport.flatMap((entry) => entry.evidence),
  };
}

async function judgeItem(env, item) {
  const perViewport = [];
  for (const width of env.spec.viewports) {
    let attempt = await runAttempt(env, item, width);
    if (attempt.status === 'FAIL') {
      const retry = await runAttempt(env, item, width);
      if (retry.status === 'PASS') attempt = { ...retry, flaky: true };
    }
    perViewport.push({ width, ...attempt });
  }
  return foldViewports(perViewport);
}

async function runInBrowser(env, record) {
  const sandboxFault = verifySandbox(record, env.runId);
  const blank = { outcomes: new Map(), identity: { status: 'unverified', seen: '' }, environmentReason: sandboxFault };
  if (sandboxFault) return blank;
  const preflight = await runPreflight(env);
  if (preflight.reason) return { ...blank, environmentReason: preflight.reason };
  const identity = judgeIdentity(preflight.raw, env.spec.headSha);
  if (identity.status === 'mismatch') return { ...blank, identity, environmentReason: 'preview is not the head' };
  const outcomes = new Map();
  for (const item of env.runnable) outcomes.set(item.key, await judgeItem(env, item));
  return { ...blank, outcomes, identity, environmentReason: '' };
}

// The browser driver. Receives { spec, runnable, rows, timeouts, runId, outDir, installRoot, playwright } and returns
//   { outcomes: Map<rowKey, { status, reason, observed, flaky, viewports, evidence }>,
//     identity: { status, seen }, blocked_requests, browser, duration_ms, environmentReason }
// One outcome per runnable entry. environmentReason, when set, fails every runnable row at once.
async function driveBrowser(context) {
  const { spec, runnable, timeouts, runId, outDir, installRoot } = context;
  const record = emptyBrowserRecord();
  record.args = [`--kit-ui-verify=${runId}`, WEBRTC_ARG];
  const guard = { allowHosts: spec.allowHosts, blocked: new Map() };
  const fault = (reason, startedAt) => ({
    outcomes: new Map(), identity: { status: 'unverified', seen: '' }, blocked_requests: [], browser: record,
    duration_ms: Date.now() - startedAt, environmentReason: reason,
  });
  const startedAt = Date.now();
  let playwright;
  try {
    playwright = await loadPlaywright(installRoot);
  } catch {
    return fault('install absent: playwright could not be loaded', startedAt);
  }
  let browser;
  try {
    browser = await launchBrowser(playwright, record);
  } catch (error) {
    const text = String(error?.message ?? error);
    return fault(/sandbox/i.test(text) ? 'browser sandbox unavailable' : 'browser did not start', startedAt);
  }
  let driven;
  try {
    driven = await runInBrowser({ browser, guard, spec, runnable, timeouts, runId, outDir, run: { spentMs: 0 } }, record);
  } finally {
    await closeBrowser(browser, record, runId);
  }
  const blocked = Array.from(guard.blocked, ([host, count]) => ({ host, count })).sort((a, b) => a.host.localeCompare(b.host));
  return { ...driven, blocked_requests: blocked, browser: record, duration_ms: Date.now() - startedAt };
}

async function runScenarios(options) {
  const { bytes, parsed } = readScenarioFile(options.scenario);
  const spec = validateScenarioFile(parsed);
  state.scenarioSha = createHash('sha256').update(bytes).digest('hex');
  state.headSha = spec.headSha;
  state.url = spec.url.href;
  state.viewports = spec.viewports;
  state.runId = randomBytes(6).toString('hex');
  checkRunnerOwnPath();
  const outDir = checkOutDir(options.out);
  const unresolvedHosts = await checkAllowedHostAddresses(spec.allowHosts, spec.allowLoopback);
  mkdirSync(outDir, { recursive: true });
  state.outDir = outDir;
  if (process.env.UI_VERIFY_TEST_FAULT === 'internal-error') throw new Error('injected test fault');

  const { rows, runnable } = planRows(spec.scenarios);
  const pin = readPin();
  let environmentReason = '';
  let playwright = 'not installed';
  let driven = { outcomes: new Map(), identity: { status: 'unverified', seen: '' }, blocked_requests: [], browser: emptyBrowserRecord(), duration_ms: 0 };

  if (runnable.length > 0) {
    const { root } = resolveInstallRoot();
    const inspected = inspectInstall(root, pin.version);
    if (inspected.installed) playwright = inspected.installed;
    if (unresolvedHosts.length > 0) environmentReason = 'preview unreachable';
    else if (inspected.state !== 'ready') environmentReason = INSTALL_FAULT_REASONS[inspected.state];
    if (environmentReason) {
      applyEnvironmentFault(runnable, environmentReason);
    } else {
      const timeouts = options.timeouts;
      driven = await driveBrowser({ spec, runnable, rows, timeouts, runId: state.runId, outDir, installRoot: root, playwright });
      environmentReason = driven.environmentReason ?? '';
      if (environmentReason) applyEnvironmentFault(runnable, environmentReason);
      else applyOutcomes(runnable, driven.outcomes);
    }
  }

  const result = buildResult({
    rows, environmentReason, identity: driven.identity, blockedRequests: driven.blocked_requests,
    browser: driven.browser, durationMs: driven.duration_ms, playwright,
  });
  writeFileSync(path.join(outDir, 'result.json'), `${JSON.stringify(result, null, 2)}\n`);
  process.stdout.write(renderStdout(result));
  return exitCodeFor(result.verdict);
}

function reportInternalError(error) {
  const message = oneLine(error instanceof Error ? error.message : error).slice(0, 300);
  try { writeSync(2, `ui-verify: internal error: ${message}\n`); } catch { /* stderr is gone, nothing more to do */ }
  if (state.outDir) {
    try {
      const result = buildResult({
        rows: [], environmentReason: `internal error: ${message}`, identity: { status: 'unverified', seen: '' },
        blockedRequests: [], browser: emptyBrowserRecord(), durationMs: 0, playwright: 'unknown',
      });
      writeFileSync(path.join(state.outDir, 'result.json'), `${JSON.stringify(result, null, 2)}\n`);
    } catch { /* --out is not usable, the stderr line is the record */ }
  }
  return 4;
}

async function main() {
  const options = parseArgs(process.argv);
  if (options.mode === 'doctor') return runDoctor();
  return runScenarios(options);
}

function finish(code) {
  process.exitCode = code;
  setTimeout(() => process.exit(code), 10000).unref();
}

process.on('uncaughtException', (error) => process.exit(reportInternalError(error)));
process.on('unhandledRejection', (error) => process.exit(reportInternalError(error)));

main().then(finish, (error) => {
  if (error instanceof Refusal) {
    process.stderr.write(`ui-verify: refused: ${oneLine(error.message)}\n`);
    finish(3);
    return;
  }
  finish(reportInternalError(error));
});
