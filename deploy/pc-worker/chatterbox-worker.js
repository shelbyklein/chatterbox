#!/usr/bin/env node
// Chatterbox PC worker. Chatterbox on the Mac runs `ssh -T <host> node chatterbox-worker.js`
// and sends one JSON header line on stdin:
//   {"v":1,"exe":"claude","args":[...],"cwd":"D:\\...","env":{"KEY":"value"}}
// The worker starts that program with the rest of stdin as its input and its output passed
// through byte for byte. Secrets arrive in `env`, so they never appear on a command line.
// When stdin closes (the Mac stopped the chat or SSH dropped) the whole process tree is killed.
//
// Desktop apps: agents here run over SSH, in Windows' session 0, with no desktop. Slippy's
// Photoshop and Illustrator panels serve MCP on localhost from the desktop session, which
// session 0 can reach, so Claude Code and Codex started here get them as tools whenever
// they're listening. Their tokens are read here and never go to the Mac.
'use strict';

const { spawn, execFileSync } = require('child_process');
const fs = require('fs');
const net = require('net');
const os = require('os');
const path = require('path');

const VERSION = '3';

const SLIPPY = [
  { name: 'slippy-photoshop', app: 'Photoshop', port: 7332 },
  { name: 'slippy-illustrator', app: 'Illustrator', port: 7331 },
];

function listening(port) {
  return new Promise((resolve) => {
    const socket = net.connect({ host: '127.0.0.1', port });
    const done = (ok) => { socket.destroy(); resolve(ok); };
    socket.setTimeout(400, () => done(false));
    socket.on('connect', () => done(true));
    socket.on('error', () => done(false));
  });
}

/// The Slippy servers that are up right now, with their URLs.
async function desktopServers() {
  const appData = process.env.APPDATA || path.join(os.homedir(), 'AppData', 'Roaming');
  const found = [];
  for (const server of SLIPPY) {
    let token;
    try { token = fs.readFileSync(path.join(appData, 'slippy', server.app, 'token'), 'utf8').trim(); } catch (_) { continue; }
    if (token && await listening(server.port)) found.push({ ...server, url: `http://127.0.0.1:${server.port}/mcp/${token}` });
  }
  return found;
}

/// Adds the desktop tools to the agent's arguments. Claude gets them in a config file only
/// this user can read; an open-model Claude (--strict-mcp-config) gets none, as its small
/// context can't take their schemas. Codex's app-server gets them as config overrides.
async function withDesktopTools(header) {
  const args = header.args || [];
  const exe = path.basename(header.exe).toLowerCase().replace(/\.(exe|cmd)$/, '');
  const isClaude = exe === 'claude' && !args.includes('--strict-mcp-config');
  const isCodex = exe === 'codex' && args[0] === 'app-server';
  if (!isClaude && !isCodex) return args;
  const servers = await desktopServers();
  if (!servers.length) return args;
  if (isClaude) {
    const file = path.join(os.tmpdir(), `chatterbox-desktop-mcp-${process.pid}.json`);
    const config = { mcpServers: Object.fromEntries(servers.map((s) => [s.name, { type: 'http', url: s.url }])) };
    fs.writeFileSync(file, JSON.stringify(config), { mode: 0o600 });
    process.on('exit', () => { try { fs.unlinkSync(file); } catch (_) {} });
    return [...args, '--mcp-config', file];
  }
  return [...args, ...servers.flatMap((s) => ['-c', `mcp_servers.${s.name}.url="${s.url}"`])];
}

if (process.argv.includes('--version')) {
  process.stdout.write(`chatterbox-worker ${VERSION}\n`);
  process.exit(0);
}

let child = null;
let buffered = Buffer.alloc(0);
let stdinEnded = false;
let killTimer = null;

function fail(message) {
  process.stderr.write(`chatterbox-worker: ${message}\n`);
  process.exit(127);
}

function killTree() {
  if (!child || child.exitCode !== null) return;
  try {
    if (process.platform === 'win32') {
      execFileSync('taskkill', ['/T', '/F', '/PID', String(child.pid)], { stdio: 'ignore' });
    } else {
      process.kill(-child.pid, 'SIGKILL');
    }
  } catch (_) {
    try { child.kill('SIGKILL'); } catch (_) {}
  }
}

async function start(header) {
  if (header.v !== 1 || typeof header.exe !== 'string') fail('unsupported header');
  const cwd = header.cwd || process.cwd();
  try { fs.mkdirSync(cwd, { recursive: true }); } catch (error) { fail(`cannot create ${cwd}: ${error.message}`); }
  const env = { ...process.env, ...(header.env || {}) };
  // `chatterbox-desktop` (screen control) lives beside this worker.
  const pathKey = Object.keys(env).find((k) => k.toLowerCase() === 'path') || 'PATH';
  env[pathKey] = __dirname + path.delimiter + (env[pathKey] || '');
  for (const key of header.unset || []) delete env[key];
  let args = header.args || [];
  try { args = await withDesktopTools(header); } catch (_) {}
  child = spawn(header.exe, args, {
    cwd,
    env,
    stdio: ['pipe', 'pipe', 'pipe'],
    windowsHide: true,
    detached: process.platform !== 'win32',
  });
  child.on('error', (error) => fail(`cannot start ${header.exe}: ${error.message}`));
  child.stdout.pipe(process.stdout);
  child.stderr.pipe(process.stderr);
  child.stdin.on('error', () => {});
  child.on('exit', (code, signal) => {
    if (killTimer) clearTimeout(killTimer);
    process.exitCode = code === null ? 1 : code;
    // Let piped output drain before exiting.
    setImmediate(() => process.exit(process.exitCode));
  });
  if (buffered.length) child.stdin.write(buffered);
  buffered = null;
  if (stdinEnded) closeChildInput();
}

function closeChildInput() {
  if (!child) return;
  child.stdin.end();
  // Claude exits by itself once its input closes; anything still running after a grace period
  // was abandoned by the Mac and is killed with its children.
  killTimer = setTimeout(killTree, 2000);
}

let starting = false;

process.stdin.on('data', (chunk) => {
  if (child) { child.stdin.write(chunk); return; }
  buffered = Buffer.concat([buffered, chunk]);
  if (starting) return;
  const newline = buffered.indexOf(0x0a);
  if (newline < 0) {
    if (buffered.length > 1 << 20) fail('header too long');
    return;
  }
  let header;
  try { header = JSON.parse(buffered.subarray(0, newline).toString('utf8')); } catch (_) { fail('bad header'); }
  buffered = buffered.subarray(newline + 1);
  starting = true;
  start(header);
});

process.stdin.on('end', () => {
  stdinEnded = true;
  if (child) closeChildInput();
  else if (!starting) process.exit(0);
});

for (const signal of ['SIGINT', 'SIGTERM', 'SIGHUP', 'SIGBREAK']) {
  process.on(signal, () => { killTree(); process.exit(130); });
}
process.on('exit', () => killTree());
