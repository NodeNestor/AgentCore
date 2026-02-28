#!/usr/bin/env node
// task-watcher.js — WebSocket client daemon that subscribes to HiveMindDB
// for incoming task assignments and writes them to a local inbox file.
// Uses Node.js built-in WebSocket (Node 22+). No external dependencies.

'use strict';

const fs = require('fs');
const path = require('path');

// ---------------------------------------------------------------------------
// Configuration from environment
// ---------------------------------------------------------------------------
const HIVEMINDDB_URL = process.env.HIVEMINDDB_URL || '';
const AGENT_ID = process.env.AGENT_ID || 'default';
const AGENT_NAME = process.env.AGENT_NAME || AGENT_ID;
const TASK_INBOX_FILE = process.env.TASK_INBOX_FILE || '/workspace/.state/task-inbox.json';

// ---------------------------------------------------------------------------
// Logging helpers (always to stderr so stdout stays clean)
// ---------------------------------------------------------------------------
function log(level, msg) {
  const ts = new Date().toISOString();
  process.stderr.write(`[${ts}] [task-watcher] [${level}] ${msg}\n`);
}
function logInfo(msg)  { log('INFO', msg); }
function logWarn(msg)  { log('WARN', msg); }
function logError(msg) { log('ERROR', msg); }

// ---------------------------------------------------------------------------
// Validate required env
// ---------------------------------------------------------------------------
if (!HIVEMINDDB_URL) {
  logError('HIVEMINDDB_URL is not set — exiting.');
  process.exit(1);
}

// ---------------------------------------------------------------------------
// Derive WebSocket URL from HTTP URL
// ---------------------------------------------------------------------------
function toWsUrl(httpUrl) {
  let url = httpUrl.replace(/\/+$/, '');
  if (url.startsWith('https://')) {
    url = 'wss://' + url.slice('https://'.length);
  } else if (url.startsWith('http://')) {
    url = 'ws://' + url.slice('http://'.length);
  } else if (!url.startsWith('ws://') && !url.startsWith('wss://')) {
    url = 'ws://' + url;
  }
  return url + '/ws';
}

const WS_URL = toWsUrl(HIVEMINDDB_URL);

// ---------------------------------------------------------------------------
// Inbox helpers — read/append/clear the task inbox JSON file
// ---------------------------------------------------------------------------
function readInbox() {
  try {
    if (!fs.existsSync(TASK_INBOX_FILE)) return [];
    const raw = fs.readFileSync(TASK_INBOX_FILE, 'utf8').trim();
    if (!raw) return [];
    const parsed = JSON.parse(raw);
    return Array.isArray(parsed) ? parsed : [];
  } catch {
    return [];
  }
}

function writeInbox(tasks) {
  const dir = path.dirname(TASK_INBOX_FILE);
  if (!fs.existsSync(dir)) {
    fs.mkdirSync(dir, { recursive: true });
  }
  fs.writeFileSync(TASK_INBOX_FILE, JSON.stringify(tasks, null, 2) + '\n', 'utf8');
}

function appendTask(task) {
  const tasks = readInbox();
  // Deduplicate by task id if present
  if (task.id && tasks.some(t => t.id === task.id)) {
    logInfo(`Task #${task.id} already in inbox — skipping.`);
    return;
  }
  tasks.push(task);
  writeInbox(tasks);
  logInfo(`Task appended to inbox (${tasks.length} total): ${task.title || task.id || 'unknown'}`);
}

// ---------------------------------------------------------------------------
// Reconnection state
// ---------------------------------------------------------------------------
const BASE_DELAY_MS = 1000;
const MAX_DELAY_MS  = 30000;
let reconnectDelay  = BASE_DELAY_MS;
let reconnectTimer  = null;
let ws              = null;
let shuttingDown    = false;

// ---------------------------------------------------------------------------
// WebSocket connection
// ---------------------------------------------------------------------------
function connect() {
  if (shuttingDown) return;

  logInfo(`Connecting to ${WS_URL} ...`);

  try {
    ws = new WebSocket(WS_URL);
  } catch (err) {
    logError(`Failed to create WebSocket: ${err.message}`);
    scheduleReconnect();
    return;
  }

  ws.addEventListener('open', () => {
    logInfo('WebSocket connected.');
    reconnectDelay = BASE_DELAY_MS;   // reset backoff on success

    // Subscribe to task assignments for this agent
    const subscribeTasksMsg = JSON.stringify({
      type: 'subscribe_tasks',
      capabilities: [],
      agent_id: AGENT_ID
    });
    ws.send(subscribeTasksMsg);
    logInfo(`Sent subscribe_tasks for agent ${AGENT_ID}`);

    // Subscribe to the "tasks" channel
    const subscribeChannelMsg = JSON.stringify({
      type: 'subscribe',
      channels: ['tasks'],
      agent_id: AGENT_ID
    });
    ws.send(subscribeChannelMsg);
    logInfo('Sent subscribe to "tasks" channel.');
  });

  ws.addEventListener('message', (event) => {
    let data;
    try {
      const raw = typeof event.data === 'string' ? event.data : event.data.toString();
      data = JSON.parse(raw);
    } catch {
      logWarn(`Non-JSON message received: ${event.data}`);
      return;
    }

    // Handle task_created messages
    if (data.type === 'task_created' || data.type === 'task_assigned') {
      logInfo(`Received ${data.type}: ${JSON.stringify(data)}`);
      const task = data.task || data;
      appendTask(task);
      return;
    }

    // Handle channel broadcast messages that contain task data
    if (data.type === 'broadcast' && data.channel === 'tasks' && data.data) {
      logInfo(`Received tasks broadcast: ${JSON.stringify(data.data)}`);
      const task = data.data.task || data.data;
      if (task && (task.id || task.title)) {
        appendTask(task);
      }
      return;
    }

    // Log other messages at debug level
    logInfo(`Received message type=${data.type || 'unknown'}`);
  });

  ws.addEventListener('error', (err) => {
    logError(`WebSocket error: ${err.message || 'unknown'}`);
  });

  ws.addEventListener('close', (event) => {
    logWarn(`WebSocket closed (code=${event.code}, reason=${event.reason || 'none'}).`);
    ws = null;
    if (!shuttingDown) {
      scheduleReconnect();
    }
  });
}

// ---------------------------------------------------------------------------
// Reconnect with exponential backoff
// ---------------------------------------------------------------------------
function scheduleReconnect() {
  if (shuttingDown) return;
  logInfo(`Reconnecting in ${reconnectDelay / 1000}s ...`);
  reconnectTimer = setTimeout(() => {
    reconnectTimer = null;
    connect();
  }, reconnectDelay);
  // Exponential backoff: 1s, 2s, 4s, 8s, 16s, 30s, 30s, ...
  reconnectDelay = Math.min(reconnectDelay * 2, MAX_DELAY_MS);
}

// ---------------------------------------------------------------------------
// Graceful shutdown
// ---------------------------------------------------------------------------
function shutdown(signal) {
  if (shuttingDown) return;
  shuttingDown = true;
  logInfo(`Received ${signal} — shutting down.`);
  if (reconnectTimer) {
    clearTimeout(reconnectTimer);
    reconnectTimer = null;
  }
  if (ws) {
    try { ws.close(1000, 'shutdown'); } catch { /* ignore */ }
    ws = null;
  }
  process.exit(0);
}

process.on('SIGTERM', () => shutdown('SIGTERM'));
process.on('SIGINT',  () => shutdown('SIGINT'));

// ---------------------------------------------------------------------------
// Main
// ---------------------------------------------------------------------------
logInfo(`Task watcher starting — agent=${AGENT_ID} (${AGENT_NAME}), inbox=${TASK_INBOX_FILE}`);
connect();
