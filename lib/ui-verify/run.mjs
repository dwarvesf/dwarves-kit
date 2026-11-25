// ui-verify runner: drives a pinned Playwright through a lead-written scenario file and judges every
// row itself. Usage and contract: lib/ui-verify/README.md.
//   node run.mjs scenario --scenario <file> --out <dir> [--step-timeout-ms N] [--scenario-timeout-ms N] [--run-budget-ms N]
//   node run.mjs --doctor
// Exit codes: 0 every row PASS, 1 a row FAIL, 2 no FAIL but something unchecked, 3 refused before any
// browser started, 4 internal error. Doctor: 0 ready, 20 no Playwright, 21 version differs, 22 no browser.
import { spawnSync } from 'node:child_process';
import { createHash, randomBytes } from 'node:crypto';
import dns from 'node:dns/promises';
import { existsSync, lstatSync, mkdirSync, mkdtempSync, readdirSync, readFileSync, realpathSync, rmSync, statSync, writeFileSync, writeSync } from 'node:fs';
import net from 'node:net';
import { tmpdir } from 'node:os';
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
const OBSERVED_READ_MS = 2000;
const OBSERVE_RESERVE_MS = 1000;
const SETTLE_MAX_MS = 1000;
const NO_TEXT_WINDOW_MS = 500;
const MAX_BLOCKED = 50;
const MAX_BLOCKED_NAME = 100;
const DEFAULT_PORTS = { 'http:': '80', 'https:': '443', 'ws:': '80', 'wss:': '443' };
const WEBRTC_ARG = '--force-webrtc-ip-handling-policy=disable_non_proxied_udp';
const NO_PROXY_ARG = '--no-proxy-server';
const KILL_WAIT_MS = 2000;
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

const state = { browser: null, record: null, closingCode: 0, outDir: null, browserHome: '', browserPaths: [], headSha: '', url: '', scenarioSha: '', runId: '', viewports: DEFAULT_VIEWPORTS };

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
    if (key === 'stepMs' && Number(value) < NO_TEXT_WINDOW_MS) refuse(`${args[i]} must be at least ${NO_TEXT_WINDOW_MS}`);
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

function checkPagePath(value, where) {
  checkString(value, where, 1, MAX_STRING);
  if (!/^\/([^/\\\s][^\\\s]*)?$/.test(value)) refuse(`${where} must be a path starting with exactly one /`);
}

function checkRole(value, where) {
  if (!ROLES.includes(value)) refuse(`${where} must be one of the twelve roles`);
}

function checkStep(step, where) {
  if (!isObject(step)) refuse(`${where} must be an object`);
  if (typeof step.do !== 'string' || !Object.hasOwn(STEP_SHAPES, step.do)) refuse(`${where}.do is not a known step verb`);
  const shape = STEP_SHAPES[step.do];
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
  let entries;
  try { entries = readdirSync(real); } catch { refuse('--out cannot be read'); }
  if (entries.length > 0) refuse('--out exists and is not empty');
  return real;
}

const loopbackList = new net.BlockList();
loopbackList.addSubnet('127.0.0.0', 8, 'ipv4');
loopbackList.addAddress('::1', 'ipv6');
const privateList = new net.BlockList();
for (const [base, bits] of [['0.0.0.0', 8], ['10.0.0.0', 8], ['100.64.0.0', 10], ['169.254.0.0', 16], ['172.16.0.0', 12],
  ['192.0.0.0', 24], ['192.168.0.0', 16], ['198.18.0.0', 15], ['224.0.0.0', 4], ['240.0.0.0', 4]]) privateList.addSubnet(base, bits, 'ipv4');
for (const [base, bits] of [['fc00::', 7], ['fe80::', 10], ['fec0::', 10], ['ff00::', 8], ['64:ff9b::', 96], ['64:ff9b:1::', 48], ['2001::', 32], ['2002::', 16], ['100::', 64], ['::', 96]]) privateList.addSubnet(base, bits, 'ipv6');

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

// Resolves every allowed host once. A private or loopback answer refuses the run. The validated address of each
// host is returned as a pin, so the browser can be held to it.
async function checkAllowedHostAddresses(allowHosts, allowLoopback) {
  const unresolved = [];
  const pins = new Map();
  for (const host of allowHosts) {
    const bare = host.replace(/^\[|\]$/g, '');
    const addresses = net.isIP(bare) ? [bare] : await lookupWithCap(host);
    if (!addresses || addresses.length === 0) { unresolved.push(host); continue; }
    for (const address of addresses) {
      const kind = classifyAddress(address);
      if (kind === 'private') refuse(`allowed host ${oneLine(host)} resolves to a private, link-local or shared address`);
      if (kind === 'loopback' && !allowLoopback) refuse(`allowed host ${oneLine(host)} resolves to a loopback address (allow_loopback is false)`);
    }
    pins.set(host, net.isIP(bare) ? bare : addresses.find((address) => net.isIPv4(address)) ?? addresses[0]);
  }
  return { unresolved, pins };
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

const STICKY_BIT = 0o1000;
const OTHERS_WRITE_BITS = 0o022;

// A directory that group or others can write to, and that is not sticky, lets them replace what sits below it.
function isOpenToWriters(directory) {
  try {
    const { mode } = statSync(directory);
    return (mode & OTHERS_WRITE_BITS) !== 0 && (mode & STICKY_BIT) === 0;
  } catch {
    return false;
  }
}

const WALKED_TREES = ['node_modules', 'browsers'];
const MAX_REASON_PATH = 100;

const reasonPath = (relative) => Array.from(sanitize(relative)).slice(0, MAX_REASON_PATH).join('');

// One entry under a walked tree: a regular file or a directory owned by the current user and not writable by group
// or others. A link is not judged by its mode (the bits differ between macOS and Linux); it must resolve to a place
// inside a walked tree, so no link leads to code the walk never looks at. Anything else (a FIFO, a socket, a
// device) is refused.
function entryFault(covered, entryPath, info) {
  if (info.isSymbolicLink()) {
    let target;
    try { target = realpathSync(entryPath); } catch { return 'is a link that cannot be resolved'; }
    return covered.some((tree) => isInside(target, tree)) ? '' : 'is a link that leaves node_modules and browsers';
  }
  if (!info.isDirectory() && !info.isFile()) return 'is not a file, a directory or a link';
  if (typeof process.getuid === 'function' && info.uid !== process.getuid()) return 'is not owned by the current user';
  return (info.mode & OTHERS_WRITE_BITS) !== 0 ? 'is writable by group or others' : '';
}

// The real paths of the walked trees that exist. A tree that is itself a link is a fault: the walk would stand
// on the link's target instead of the tree.
function coveredTrees(real) {
  const covered = [];
  for (const tree of WALKED_TREES) {
    const top = path.join(real, tree);
    let resolved;
    try { resolved = realpathSync(top); } catch { continue; }
    if (resolved !== top) return { fault: `${tree} is a link` };
    covered.push(resolved);
  }
  return { covered };
}

// Everything under one tree, checked recursively, first offender wins. Links are not followed. An entry that
// cannot be inspected or read is a fault, never skipped.
function treeReason(real, tree, covered) {
  const pending = [tree];
  while (pending.length > 0) {
    const relative = pending.pop();
    const entryPath = path.join(real, ...relative.split('/'));
    let info;
    try { info = lstatSync(entryPath); } catch { return `${reasonPath(relative)} cannot be inspected`; }
    const fault = entryFault(covered, entryPath, info);
    if (fault) return `${reasonPath(relative)} ${fault}`;
    if (!info.isDirectory()) continue;
    let names;
    try { names = readdirSync(entryPath).sort().reverse(); } catch { return `${reasonPath(relative)} cannot be read`; }
    for (const name of names) pending.push(`${relative}/${name}`);
  }
  return '';
}

// node_modules and the browser cache, both inside the install root: the runner imports the first and launches the
// second.
function installTreesReason(real) {
  const { covered, fault } = coveredTrees(real);
  if (fault) return fault;
  for (const tree of WALKED_TREES) {
    if (!existsSync(path.join(real, tree))) continue;
    const reason = treeReason(real, tree, covered);
    if (reason) return reason;
  }
  return '';
}

// The runner imports code from the install root, so a root that anyone else could have written is not used.
// That covers the root, every directory above it up to /, and everything under its node_modules and browsers.
function untrustedReason(root) {
  let info;
  try { info = statSync(root); } catch { return ''; }
  const real = realpathSync(root);
  if (gitRootAbove(real)) return 'inside a git work tree';
  if (typeof process.getuid === 'function' && info.uid !== process.getuid()) return 'not owned by the current user';
  if ((info.mode & OTHERS_WRITE_BITS) !== 0) return 'writable by group or others';
  for (let dir = path.dirname(real); ; dir = path.dirname(dir)) {
    if (isOpenToWriters(dir)) return 'a parent directory is writable by group or others and is not sticky';
    if (path.dirname(dir) === dir) break;
  }
  return installTreesReason(real);
}

function inspectInstall(root, pinnedVersion) {
  if (!root) return { state: 'absent', installed: '' };
  const detail = untrustedReason(root);
  if (detail) return { state: 'untrusted', installed: '', detail };
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

const installFaultReason = (inspected) => (inspected.state === 'untrusted' ? `install root not trusted: ${inspected.detail}` : INSTALL_FAULT_REASONS[inspected.state]);

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
  const quoted = (text) => `'${text.replaceAll("'", "'\\''")}'`;
  const installCommand = [
    'umask 022',
    `mkdir -p ${quoted(root)}`,
    `chmod go-w ${quoted(root)}`,
    `cp ${quoted(path.join(RUNNER_DIR, 'package.json'))} ${quoted(path.join(RUNNER_DIR, 'package-lock.json'))} ${quoted(root)}/`,
    `cd ${quoted(root)}`,
    'npm ci --ignore-scripts',
    `PLAYWRIGHT_BROWSERS_PATH=${quoted(path.join(root, 'browsers'))} ./node_modules/.bin/playwright install chromium`,
  ].join(' && ');
  let code = 0;
  let verdict = age !== null && age > PIN_WARN_DAYS ? `READY (pin older than ${PIN_WARN_DAYS} days: bump it)` : 'READY';
  if (inspected.state === 'absent') { code = 20; verdict = 'NOT READY: playwright is not installed in the install root'; }
  if (inspected.state === 'untrusted') { code = 20; verdict = `NOT READY: ${installFaultReason(inspected)}`; }
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
  return { sandbox: false, no_sandbox_seen: false, args: [], launch_attempts: 0, env_keys: [], pids: [], leftover_pids: [] };
}

function emptyDriven(environmentReason = '', browser = emptyBrowserRecord()) {
  return {
    outcomes: new Map(), identity: { status: 'unverified', seen: '' }, blocked_requests: [], blocked_requests_truncated: false,
    browser, duration_ms: 0, environmentReason,
  };
}

function buildResult(parts) {
  const { rows, environmentReason, driven, playwright } = parts;
  const summary = deriveSummary(rows, environmentReason);
  return {
    schema: 1,
    runner: { path: RUNNER_PATH, playwright },
    head_sha: state.headSha,
    scenario_sha256: state.scenarioSha,
    run_id: state.runId,
    url: state.url,
    identity: driven.identity,
    viewports: state.viewports,
    verdict: summary.verdict,
    reason: summary.reason,
    counts: summary.counts,
    rows,
    blocked_requests: driven.blocked_requests,
    blocked_requests_truncated: driven.blocked_requests_truncated,
    browser: driven.browser,
    duration_ms: driven.duration_ms,
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

// The run's own browser processes, found by the run id and the browser path under the install root on their
// command line. A process that holds only the run id (it is printed on stderr) is not the run's.
function scanRunProcesses(runId) {
  const marker = `--kit-ui-verify=${runId}`;
  if (state.browserPaths.length === 0) return [];
  const listed = spawnSync('ps', ['-axww', '-o', 'pid=,command='], { encoding: 'utf8', timeout: 15000, maxBuffer: 64 * 1024 * 1024 });
  if (listed.status !== 0 || typeof listed.stdout !== 'string') return [];
  const found = [];
  for (const line of listed.stdout.split('\n')) {
    const match = /^\s*(\d+)\s+(.*)$/.exec(line);
    if (!match || !match[2].includes(marker) || !state.browserPaths.some((dir) => match[2].includes(dir)) || Number(match[1]) === process.pid) continue;
    found.push({ pid: Number(match[1]), command: match[2] });
  }
  return found;
}

class InstallNotTrusted extends Error {}

// The trust check runs again here, with nothing between it and the import.
async function loadPlaywright(installRoot) {
  const untrusted = untrustedReason(installRoot);
  if (untrusted) throw new InstallNotTrusted(untrusted);
  const browsersDir = path.join(installRoot, 'browsers');
  process.env.PLAYWRIGHT_BROWSERS_PATH = browsersDir;
  state.browserPaths = [...new Set([browsersDir, realPathOfPossibleNew(browsersDir)])];
  return import(pathToFileURL(path.join(installRoot, 'node_modules', 'playwright', 'index.mjs')).href);
}

// The browser gets a minimal environment, never the operator's tokens or proxy settings, and a home of its own.
function launchBrowser(playwright, record, browserHome) {
  record.launch_attempts = 1;
  if (process.env.UI_VERIFY_TEST_FAULT === 'sandbox-unavailable') throw new Error('injected test fault: the sandbox cannot start');
  const childEnv = { PATH: process.env.PATH ?? '', HOME: browserHome };
  record.env_keys = Object.keys(childEnv).sort();
  return playwright.chromium.launch({
    headless: true, chromiumSandbox: true, timeout: LAUNCH_CAP_MS, args: record.args, env: childEnv,
    handleSIGINT: false, handleSIGTERM: false, handleSIGHUP: false,
  });
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

async function waitForNoRunProcess(runId, waitMs) {
  const until = Date.now() + waitMs;
  let left = scanRunProcesses(runId);
  while (left.length > 0 && Date.now() < until) {
    await sleep(250);
    left = scanRunProcesses(runId);
  }
  return left;
}

// Closes the browser, then kills any process that still carries the run id (the id is the run's own) and
// records the pids that survived even that.
async function closeBrowser(browser, record, runId) {
  await raceDeadline(browser.close(), 15000).catch(() => {});
  let left = await waitForNoRunProcess(runId, LEFTOVER_WAIT_MS);
  for (const item of left) {
    try { process.kill(item.pid, 'SIGKILL'); } catch { /* already gone */ }
  }
  if (left.length > 0) left = await waitForNoRunProcess(runId, KILL_WAIT_MS);
  record.leftover_pids = left.map((item) => item.pid);
}

function hostOfUrl(raw) {
  try { return normalizeHost(new URL(raw).hostname); } catch { return ''; }
}

function portOfUrl(url) {
  return url.port || DEFAULT_PORTS[url.protocol] || '';
}

// The target host may use the port of the target URL. Every other allowed host may use only the default port of
// the request's scheme. The resolver rules carry no port, so this check is what holds the port.
function isAllowedUrl(guard, raw) {
  let url;
  try { url = new URL(raw); } catch { return false; }
  const host = normalizeHost(url.hostname);
  const port = portOfUrl(url);
  if (!port || !guard.allowHosts.has(host)) return false;
  return port === (host === guard.targetHost ? guard.targetPort : DEFAULT_PORTS[url.protocol]);
}

function blockedName(guard, raw) {
  const host = hostOfUrl(raw);
  if (!host) return 'unparsable';
  return guard.allowHosts.has(host) ? `${host}:${portOfUrl(new URL(raw))}` : host;
}

function noteBlocked(guard, raw) {
  const name = Array.from(sanitize(blockedName(guard, raw))).slice(0, MAX_BLOCKED_NAME).join('') || 'unparsable';
  if (!guard.blocked.has(name) && guard.blocked.size >= MAX_BLOCKED) { guard.truncated = true; return; }
  guard.blocked.set(name, (guard.blocked.get(name) ?? 0) + 1);
}

function isMainFrameNavigation(request) {
  try { return request.isNavigationRequest() && request.frame().parentFrame() === null; } catch { return false; }
}

// Chromium resolves only the allowed hosts, each to the address checked at startup, and every other name or
// IP literal fails at name resolution. A name that later re-resolves to a private address, and a redirect to
// a host off the list (a request the route handler never sees again), both end there.
function hostResolverRules(pins) {
  const maps = Array.from(pins, ([host, address]) => `MAP ${host} ${net.isIPv6(address) ? `[${address}]` : address}`);
  return `--host-resolver-rules=${[...maps, 'MAP * ~NOTFOUND'].join(', ')}`;
}

// Every HTTP request and every WebSocket goes through the host check. Anything off the list is aborted (a socket
// is closed and never connected), counted, and a blocked top-level navigation is flagged so a redirect off the
// allowed hosts gets its own reason. The route handler never sees a redirect hop, so every request that was
// redirected is checked here with the same rule. A hop that fails it is counted and flagged for the whole
// context (hopBlocked): the hop request has already left by then, which makes this detection, not prevention.
async function containContext(context, guard) {
  const watch = { navigationBlocked: false, hopBlocked: false, pending: new Set() };
  const noted = new WeakSet();
  const noteHop = (request) => {
    if (noted.has(request)) return;
    noted.add(request);
    noteBlocked(guard, request.url());
    watch.hopBlocked = true;
    if (isMainFrameNavigation(request)) watch.navigationBlocked = true;
  };
  await context.route('**/*', async (route) => {
    try {
      const request = route.request();
      const url = request.url();
      if (/^https?:/i.test(url) && isAllowedUrl(guard, url)) { await route.continue(); return; }
      noteBlocked(guard, url);
      if (isMainFrameNavigation(request)) watch.navigationBlocked = true;
      await route.abort('blockedbyclient');
    } catch { /* the page went away while the request was in flight */ }
  });
  const settled = (request) => { watch.pending.delete(request); };
  context.on('requestfinished', settled);
  context.on('request', (request) => {
    watch.pending.add(request);
    if (request.redirectedFrom() !== null && !isAllowedUrl(guard, request.url())) noteHop(request);
  });
  context.on('requestfailed', (request) => {
    settled(request);
    if (guard.allowHosts.has(hostOfUrl(request.url())) || !/ERR_NAME_NOT_RESOLVED/.test(request.failure()?.errorText ?? '')) return;
    noteHop(request);
  });
  await context.routeWebSocket(/.*/, async (socket) => {
    try {
      const url = socket.url();
      if (/^wss?:/i.test(url) && isAllowedUrl(guard, url)) { socket.connectToServer(); return; }
      noteBlocked(guard, url);
      await socket.close();
    } catch { /* the page went away while the socket was opening */ }
  });
  return watch;
}

// The page URL after a navigation committed. A redirect hop never reaches the route handler, so the final
// address is checked here.
function leftAllowedHosts(page, guard) {
  const current = page.url();
  return current !== 'about:blank' && !isAllowedUrl(guard, current);
}

const hasEscaped = (opened, guard) => opened.watch.hopBlocked || leftAllowedHosts(opened.page, guard);

// A request the context already knows about may still bring a redirect hop, so the end of a scenario waits for
// those to finish, never longer than limitMs. A request that has not started yet (a timer that has not fired) is
// not known and is not waited for: a hop that begins after the scenario's last step is outside its row.
async function waitForKnownRequests(watch, limitMs) {
  const end = Date.now() + limitMs;
  while (watch.pending.size > 0 && !watch.hopBlocked && Date.now() < end) await sleep(POLL_MS / 2);
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
  const seen = sanitize(value.slice(0, 12));
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
      return opened.watch.navigationBlocked || opened.watch.hopBlocked ? { reason: 'redirected off an allowed host', final: true } : { reason: 'preview unreachable' };
    }
    if (leftAllowedHosts(opened.page, guard) || opened.watch.hopBlocked) return { reason: 'redirected off an allowed host', final: true };
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

// The text of one element. { missing: true } when it is not there, { timedOut: true } when it cannot be read in time.
async function readLocator(target, limitMs) {
  const deadline = Date.now() + limitMs;
  const count = await raceDeadline(target.count(), limitMs);
  if (count === TIMED_OUT) return { timedOut: true };
  if (count === 0) return { missing: true };
  const left = Math.max(1, deadline - Date.now());
  const text = await raceDeadline(target.first().innerText({ timeout: left }), left);
  return text === TIMED_OUT ? { timedOut: true } : { text: collapse(text) };
}

const readScope = (page, within, limitMs) => readLocator(within ? locatorFor(page, within.role, within.name) : page.locator('body'), limitMs);

const missingElement = (role, name) => `element not found: role=${role} name=${name}`;

// What the page says instead, for the observed field: the within element, else the first alert or status, main, body.
async function observedFor(page, within, limitMs) {
  const deadline = Date.now() + Math.min(limitMs, OBSERVED_READ_MS);
  const left = () => Math.max(1, deadline - Date.now());
  if (within) {
    const scope = await readScope(page, within, left()).catch(() => ({ missing: true }));
    return scope.text ?? missingElement(within.role, within.name);
  }
  for (const selector of ['[role=alert], [role=status]', 'main', 'body']) {
    const scope = await readLocator(page.locator(selector).first(), left()).catch(() => ({ missing: true }));
    if (scope.text !== undefined) return scope.text;
  }
  return '';
}

async function stepGoto(page, step, limitMs, spec) {
  const started = Date.now();
  try {
    await page.goto(new URL(step.path, spec.url.origin).href, { waitUntil: 'load', timeout: limitMs });
    const fonts = await raceDeadline(page.evaluate(() => document.fonts.ready.then(() => true)), Math.max(1, limitMs - (Date.now() - started)));
    if (fonts === TIMED_OUT) return { timedOut: true };
    return { ok: true };
  } catch (error) {
    if (error?.name === 'TimeoutError') return { timedOut: true };
    return { nocheck: 'page did not settle' };
  }
}

// click and fill: exactly one match must appear before the limit.
async function stepLocate(page, step, limitMs, act) {
  const deadline = Date.now() + limitMs;
  const target = locatorFor(page, step.role, step.name);
  let seen = 0;
  const found = await pollUntil(async (left) => {
    const count = await raceDeadline(target.count(), left);
    if (count !== TIMED_OUT) seen = count;
    return { ok: count === 1, count: seen };
  }, limitMs);
  if (!found.ok) {
    const observed = found.count > 1 ? `ambiguous: ${found.count} matches` : missingElement(step.role, step.name);
    return { timedOut: true, observed };
  }
  try {
    await act(target, Math.max(1, deadline - Date.now()));
    return { ok: true };
  } catch (error) {
    const observed = `element not actionable: role=${step.role} name=${step.name}`;
    return error?.name === 'TimeoutError' ? { timedOut: true, observed } : { observed };
  }
}

async function stepExpectText(page, step, limitMs) {
  const deadline = Date.now() + limitMs;
  const found = await pollUntil(async (left) => {
    const scope = await readScope(page, step.within, left);
    return { ok: Boolean(scope.text !== undefined && scope.text.includes(step.text)), scope };
  }, limitMs - Math.min(OBSERVE_RESERVE_MS, Math.floor(limitMs / 2)));
  if (found.ok) return { ok: true };
  if (found.scope.missing) return { timedOut: true, observed: missingElement(step.within.role, step.within.name) };
  return { timedOut: true, observed: await observedFor(page, step.within, deadline - Date.now()) };
}

// Passes only when the page was read at least once inside the window and never showed the text.
async function stepExpectNoText(page, step, limitMs) {
  const deadline = Date.now() + limitMs;
  if (limitMs < NO_TEXT_WINDOW_MS) return { timedOut: true, observed: '' };
  const end = Date.now() + NO_TEXT_WINDOW_MS;
  let reads = 0;
  while (Date.now() < end) {
    const scope = await readScope(page, null, Math.max(1, end - Date.now()));
    if (scope.text !== undefined) reads += 1;
    if (scope.text?.includes(step.text)) return { observed: await observedFor(page, null, deadline - Date.now()) };
    await sleep(50);
  }
  return reads > 0 ? { ok: true } : { nocheck: 'page did not settle' };
}

async function stepExpectUrl(page, step, limitMs) {
  const current = () => { const url = new URL(page.url()); return url.pathname + url.search; };
  const found = await pollUntil(async () => ({ ok: current() === step.path }), limitMs);
  return found.ok ? { ok: true } : { timedOut: true, observed: `url is ${current()}` };
}

function performStep(page, step, limitMs, spec) {
  if (step.do === 'goto') return stepGoto(page, step, limitMs, spec);
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
  if (run.spentMs >= timeouts.runBudgetMs) return { status: 'NO-CHECK', reason: CAUSE_REASONS.budget, observed: '', evidence: [] };
  const opened = await openPage(env.browser, guard, width);
  const attemptClock = { spentMs: 0 };
  const evidence = [];
  const escapedRow = () => ({ status: 'NO-CHECK', reason: 'redirected off an allowed host', observed: '', evidence });
  try {
    for (const step of item.entry.steps) {
      if (step.do === 'screenshot') {
        const file = await takeScreenshot(opened.page, env, item.entry, width, step);
        if (hasEscaped(opened, guard)) return escapedRow();
        if (!file) return { status: 'NO-CHECK', reason: 'page did not settle', observed: '', evidence };
        evidence.push(file);
        continue;
      }
      const { limit, cause } = stepLimit(attemptClock, run, timeouts);
      if (limit <= 0) return { status: 'NO-CHECK', reason: CAUSE_REASONS[cause], observed: '', evidence };
      opened.watch.navigationBlocked = false;
      const started = Date.now();
      const result = await performStep(opened.page, step, limit, spec);
      const spent = Date.now() - started;
      attemptClock.spentMs += spent;
      run.spentMs += spent;
      if (hasEscaped(opened, guard) || (!result.ok && opened.watch.navigationBlocked)) return escapedRow();
      if (!result.ok) return { ...interpretStep(result, cause, step), evidence };
    }
    await waitForKnownRequests(opened.watch, Math.max(0, Math.min(SETTLE_MAX_MS, stepLimit(attemptClock, run, timeouts).limit)));
    if (hasEscaped(opened, guard)) return escapedRow();
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

// The browser driver. Receives { spec, runnable, timeouts, pins, runId, outDir, installRoot } and returns
//   { outcomes: Map<rowKey, { status, reason, observed, flaky, viewports, evidence }>,
//     identity: { status, seen }, blocked_requests, blocked_requests_truncated, browser, duration_ms, environmentReason }
// One outcome per runnable entry. environmentReason, when set, fails every runnable row at once.
async function driveBrowser(context) {
  const browserHome = mkdtempSync(path.join(tmpdir(), 'kit-ui-verify-'));
  state.browserHome = browserHome;
  try {
    return await driveBrowserWithHome(context, browserHome);
  } finally {
    rmSync(browserHome, { recursive: true, force: true });
  }
}

async function driveBrowserWithHome(context, browserHome) {
  const { spec, runnable, timeouts, pins, runId, outDir, installRoot } = context;
  const record = emptyBrowserRecord();
  record.args = [`--kit-ui-verify=${runId}`, WEBRTC_ARG, NO_PROXY_ARG, hostResolverRules(pins)];
  const guard = { allowHosts: spec.allowHosts, targetHost: normalizeHost(spec.url.hostname), targetPort: portOfUrl(spec.url), blocked: new Map(), truncated: false };
  const fault = (reason, startedAt) => ({ ...emptyDriven(reason, record), duration_ms: Date.now() - startedAt });
  const startedAt = Date.now();
  let playwright;
  try {
    playwright = await loadPlaywright(installRoot);
  } catch (error) {
    if (error instanceof InstallNotTrusted) return fault(`install root not trusted: ${error.message}`, startedAt);
    return fault('install absent: playwright could not be loaded', startedAt);
  }
  let browser;
  try {
    browser = await launchBrowser(playwright, record, browserHome);
  } catch (error) {
    const text = String(error?.message ?? error);
    return fault(/sandbox/i.test(text) ? 'browser sandbox unavailable' : 'browser did not start', startedAt);
  }
  state.browser = browser;
  state.record = record;
  let driven;
  try {
    driven = await runInBrowser({ browser, guard, spec, runnable, timeouts, runId, outDir, run: { spentMs: 0 } }, record);
  } finally {
    await closeBrowser(browser, record, runId);
  }
  const blocked = Array.from(guard.blocked, ([host, count]) => ({ host, count })).sort((a, b) => a.host.localeCompare(b.host));
  return { ...driven, blocked_requests: blocked, blocked_requests_truncated: guard.truncated, browser: record, duration_ms: Date.now() - startedAt };
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
  const { unresolved: unresolvedHosts, pins } = await checkAllowedHostAddresses(spec.allowHosts, spec.allowLoopback);
  try { mkdirSync(outDir, { recursive: true }); } catch { refuse('--out cannot be created'); }
  state.outDir = outDir;
  process.stderr.write(`ui-verify: run ${state.runId}\n`);
  if (process.env.UI_VERIFY_TEST_FAULT === 'internal-error') throw new Error('injected test fault');

  const { rows, runnable } = planRows(spec.scenarios);
  const pin = readPin();
  let environmentReason = '';
  let playwright = 'not installed';
  let driven = emptyDriven();

  if (runnable.length > 0) {
    const { root } = resolveInstallRoot();
    const inspected = inspectInstall(root, pin.version);
    if (inspected.installed) playwright = inspected.installed;
    if (unresolvedHosts.length > 0) environmentReason = 'preview unreachable';
    else if (inspected.state !== 'ready') environmentReason = installFaultReason(inspected);
    if (environmentReason) {
      applyEnvironmentFault(runnable, environmentReason);
    } else {
      const timeouts = options.timeouts;
      driven = await driveBrowser({ spec, runnable, timeouts, pins, runId: state.runId, outDir, installRoot: root });
      environmentReason = driven.environmentReason ?? '';
      if (environmentReason) applyEnvironmentFault(runnable, environmentReason);
      else applyOutcomes(runnable, driven.outcomes);
    }
  }

  const result = buildResult({ rows, environmentReason, driven, playwright });
  writeFileSync(path.join(outDir, 'result.json'), `${JSON.stringify(result, null, 2)}\n`);
  process.stdout.write(renderStdout(result));
  return exitCodeFor(result.verdict);
}

function reportInternalError(error) {
  const message = oneLine(error instanceof Error ? error.message : error).slice(0, 300);
  try { writeSync(2, `ui-verify: internal error: ${message}\n`); } catch { /* stderr is gone, nothing more to do */ }
  if (state.outDir) {
    try {
      const result = buildResult({ rows: [], environmentReason: `internal error: ${message}`, driven: emptyDriven(), playwright: 'unknown' });
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

// The one exit 4 guarantee: any throw or rejection that nothing else handled lands here (Node raises an unhandled
// rejection as an uncaught exception).
process.on('uncaughtException', (error) => {
  if (!state.closingCode) process.exit(reportInternalError(error));
});

// Stops what the run started: a launched browser is closed, one still launching (no handle yet) is found by the
// run id and killed. True when there was a browser to stop.
async function stopBrowser() {
  if (state.browser) {
    await closeBrowser(state.browser, state.record, state.runId).catch(() => {});
    return true;
  }
  if (!state.runId) return false;
  const stray = scanRunProcesses(state.runId);
  for (const item of stray) {
    try { process.kill(item.pid, 'SIGKILL'); } catch { /* already gone */ }
  }
  if (stray.length > 0) await waitForNoRunProcess(state.runId, KILL_WAIT_MS);
  return stray.length > 0;
}

// A signal stops the browser first; the pages that fail while it closes are not an internal error.
async function shutDown(code) {
  if (state.closingCode) return;
  state.closingCode = code;
  const stopped = await stopBrowser();
  if (state.browserHome) { try { rmSync(state.browserHome, { recursive: true, force: true }); } catch { /* the exit code matters more than the leftover directory */ } }
  writeSync(2, stopped ? 'ui-verify: interrupted, browser closed\n' : 'ui-verify: interrupted, no browser was running\n');
  process.exit(code);
}
for (const [signal, code] of [['SIGTERM', 143], ['SIGINT', 130], ['SIGHUP', 129]]) process.on(signal, () => shutDown(code));

main().then(finish, (error) => {
  if (!(error instanceof Refusal)) throw error;
  process.stderr.write(`ui-verify: refused: ${oneLine(error.message)}\n`);
  finish(3);
});
