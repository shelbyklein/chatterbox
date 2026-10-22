#!/usr/bin/env node
// Chatterbox PC worker. Chatterbox on the Mac runs `ssh -T <host> node chatterbox-worker.js`
// and sends one JSON header line on stdin:
//   {"v":1,"exe":"claude","args":[...],"cwd":"D:\\...","env":{"KEY":"value"}}
// The worker starts that program with the rest of stdin as its input and its output passed
// through byte for byte. Secrets arrive in `env`, so they never appear on a command line.
// When stdin closes (the Mac stopped the chat or SSH dropped) the whole process tree is killed.
'use strict';

const { spawn, execFileSync } = require('child_process');
const fs = require('fs');
const path = require('path');

const VERSION = '1';

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

function start(header) {
  if (header.v !== 1 || typeof header.exe !== 'string') fail('unsupported header');
  const cwd = header.cwd || process.cwd();
  try { fs.mkdirSync(cwd, { recursive: true }); } catch (error) { fail(`cannot create ${cwd}: ${error.message}`); }
  const env = { ...process.env, ...(header.env || {}) };
  for (const key of header.unset || []) delete env[key];
  child = spawn(header.exe, header.args || [], {
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

process.stdin.on('data', (chunk) => {
  if (child) { child.stdin.write(chunk); return; }
  buffered = Buffer.concat([buffered, chunk]);
  const newline = buffered.indexOf(0x0a);
  if (newline < 0) {
    if (buffered.length > 1 << 20) fail('header too long');
    return;
  }
  let header;
  try { header = JSON.parse(buffered.subarray(0, newline).toString('utf8')); } catch (_) { fail('bad header'); }
  buffered = buffered.subarray(newline + 1);
  start(header);
});

process.stdin.on('end', () => {
  stdinEnded = true;
  if (child) closeChildInput();
  else process.exit(0);
});

for (const signal of ['SIGINT', 'SIGTERM', 'SIGHUP', 'SIGBREAK']) {
  process.on(signal, () => { killTree(); process.exit(130); });
}
process.on('exit', () => killTree());
