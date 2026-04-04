'use strict';

const express = require('express');
const winston = require('winston');
const { v4: uuidv4 } = require('uuid');

// ---------------------------------------------------------------------------
// Logger — JSON to stdout
// ---------------------------------------------------------------------------
const logger = winston.createLogger({
  level: 'debug',
  format: winston.format.combine(
    winston.format.timestamp({ format: () => new Date().toISOString() }),
    winston.format.printf((info) => {
      const { timestamp, level, message, ...rest } = info;
      return JSON.stringify({
        timestamp,
        level,
        service: 'auth-service',
        message,
        ...rest,
      });
    })
  ),
  transports: [new winston.transports.Console()],
});

const app = express();
app.use(express.json());

// ---------------------------------------------------------------------------
// In-memory session store
// ---------------------------------------------------------------------------
const sessions = new Map();
const USERS = Array.from({ length: 50 }, (_, i) => `usr_${String(i + 1).padStart(4, '0')}`);
const IPS = ['10.0.0.1', '10.0.0.2', '192.168.1.100', '172.16.0.5', '203.0.113.42'];
const METHODS = ['oauth', 'password', 'sso', 'mfa', 'api_key'];

function randomItem(arr) {
  return arr[Math.floor(Math.random() * arr.length)];
}

function randomInt(min, max) {
  return Math.floor(Math.random() * (max - min + 1)) + min;
}

// ---------------------------------------------------------------------------
// Background log loop — every 2-5 seconds
// ---------------------------------------------------------------------------
const bgScenarios = [
  () => {
    const userId = randomItem(USERS);
    const sessionId = `sess_${uuidv4().replace(/-/g, '').slice(0, 16)}`;
    logger.info('token validated', {
      user_id: userId,
      session_id: sessionId,
      token_age_s: randomInt(10, 3500),
      scopes: ['read:profile', 'write:orders'],
    });
  },
  () => {
    const userId = randomItem(USERS);
    logger.warn('token expired', {
      user_id: userId,
      session_id: `sess_${uuidv4().replace(/-/g, '').slice(0, 16)}`,
      expired_at: new Date(Date.now() - randomInt(1000, 60000)).toISOString(),
      reason: 'max_age_exceeded',
    });
  },
  () => {
    const userId = randomItem(USERS);
    logger.info('login attempt', {
      user_id: userId,
      ip: randomItem(IPS),
      method: randomItem(METHODS),
      user_agent: 'Mozilla/5.0 (compatible; TinkerTest/1.0)',
    });
  },
  () => {
    const userId = randomItem(USERS);
    logger.error('suspicious login detected', {
      user_id: userId,
      ip: '198.51.100.99',
      method: 'password',
      signals: ['geo_anomaly', 'new_device', 'credential_stuffing_pattern'],
      risk_score: (Math.random() * 0.3 + 0.7).toFixed(3),
    });
  },
  () => {
    const userId = randomItem(USERS);
    const sessionId = `sess_${uuidv4().replace(/-/g, '').slice(0, 16)}`;
    sessions.set(sessionId, { userId, createdAt: Date.now() });
    logger.info('session created', {
      user_id: userId,
      session_id: sessionId,
      ip: randomItem(IPS),
      method: randomItem(METHODS),
      ttl_s: 3600,
    });
  },
  () => {
    const sessionIds = Array.from(sessions.keys());
    if (sessionIds.length === 0) return;
    const sessionId = randomItem(sessionIds);
    sessions.delete(sessionId);
    logger.info('session destroyed', {
      session_id: sessionId,
      reason: randomItem(['user_logout', 'timeout', 'admin_revoke']),
    });
  },
  () => {
    logger.debug('token refresh cycle', {
      active_sessions: sessions.size,
      expired_count: randomInt(0, 5),
      refresh_latency_ms: randomInt(8, 120),
    });
  },
];

function startBackgroundLoop() {
  const tick = () => {
    try {
      randomItem(bgScenarios)();
    } catch (err) {
      logger.error('background loop error', { error: err.message });
    }
    const delay = randomInt(2000, 5000);
    setTimeout(tick, delay);
  };
  tick();
}

// ---------------------------------------------------------------------------
// Health endpoint
// ---------------------------------------------------------------------------
app.get('/health', (req, res) => {
  res.json({ status: 'ok', service: 'auth-service', timestamp: new Date().toISOString() });
});

// ---------------------------------------------------------------------------
// Business endpoints
// ---------------------------------------------------------------------------
app.post('/login', (req, res) => {
  const { user_id, password, method = 'password' } = req.body || {};
  if (!user_id) {
    logger.warn('login rejected — missing user_id', { ip: req.ip });
    return res.status(400).json({ error: 'user_id required' });
  }
  const sessionId = `sess_${uuidv4().replace(/-/g, '').slice(0, 16)}`;
  sessions.set(sessionId, { userId: user_id, createdAt: Date.now() });
  logger.info('user logged in', {
    user_id,
    session_id: sessionId,
    ip: req.ip || randomItem(IPS),
    method,
  });
  res.json({ session_id: sessionId, expires_in: 3600 });
});

app.post('/logout', (req, res) => {
  const { session_id } = req.body || {};
  if (session_id && sessions.has(session_id)) {
    const session = sessions.get(session_id);
    sessions.delete(session_id);
    logger.info('user logged out', { user_id: session.userId, session_id });
  }
  res.json({ status: 'ok' });
});

app.get('/validate', (req, res) => {
  const token = req.headers['authorization']?.replace('Bearer ', '');
  if (!token || !sessions.has(token)) {
    logger.warn('token validation failed — invalid or missing token', {
      ip: req.ip,
      token_present: !!token,
    });
    return res.status(401).json({ valid: false });
  }
  const session = sessions.get(token);
  logger.debug('token validated', { user_id: session.userId, session_id: token });
  res.json({ valid: true, user_id: session.userId });
});

// ---------------------------------------------------------------------------
// Trigger-error endpoint
// ---------------------------------------------------------------------------
app.post('/trigger-error', (req, res) => {
  const errorType = req.query.type;
  logger.warn('trigger-error endpoint called', { error_type: errorType });

  switch (errorType) {
    case 'null_pointer':
      return triggerNullPointer(res);
    case 'db_timeout':
      return triggerDbTimeout(res);
    case 'unhandled_promise':
      return triggerUnhandledPromise(res);
    default:
      return res.status(400).json({
        error: `Unknown error type: ${errorType}. Valid types: null_pointer, db_timeout, unhandled_promise`,
      });
  }
});

function triggerNullPointer(res) {
  try {
    // Simulate a null session object from a failed DB lookup
    const session = null;
    // This will throw: TypeError: Cannot read properties of null (reading 'userId')
    const userId = session.userId;
    res.json({ user_id: userId });
  } catch (err) {
    logger.error('null pointer error in session handler', {
      error: err.message,
      error_type: err.constructor.name,
      stack: err.stack,
      session_id: `sess_${uuidv4().replace(/-/g, '').slice(0, 16)}`,
      endpoint: '/validate',
    });
    res.status(500).json({ error: err.message, stack: err.stack });
  }
}

function dbQuery(depth, userId) {
  if (depth === 0) {
    // Simulate a timed-out DB connection
    const conn = null;
    return conn.execute('SELECT * FROM sessions WHERE user_id = $1', [userId]);
  }
  return dbQuery(depth - 1, userId);
}

function triggerDbTimeout(res) {
  try {
    const userId = randomItem(USERS);
    logger.warn('DB connection timeout — retrying', {
      user_id: userId,
      host: 'postgres-auth.internal',
      port: 5432,
      timeout_ms: 5000,
      attempt: 3,
    });
    dbQuery(3, userId);
  } catch (err) {
    logger.error('database connection timeout', {
      error: err.message,
      error_type: err.constructor.name,
      stack: err.stack,
      host: 'postgres-auth.internal',
      timeout_ms: 5000,
      pool_exhausted: true,
    });
    res.status(503).json({ error: `Connection timeout after 5000ms: ${err.message}` });
  }
}

function triggerUnhandledPromise(res) {
  // Fire off a promise that rejects — caught by the process handler below
  const failingOperation = async () => {
    await new Promise((resolve) => setTimeout(resolve, 50));
    const data = null;
    // Will throw inside the async function
    return data.userId;
  };

  failingOperation().catch((err) => {
    logger.error('unhandled promise rejection in auth flow', {
      error: err.message,
      error_type: err.constructor.name,
      stack: err.stack,
      operation: 'session_refresh',
      user_id: randomItem(USERS),
    });
  });

  // Respond immediately — the error appears asynchronously in logs
  res.json({
    status: 'promise_rejection_triggered',
    note: 'Check logs for unhandled_promise_rejection error',
  });
}

// Global unhandled rejection handler — logs but does not crash
process.on('unhandledRejection', (reason, promise) => {
  logger.error('unhandled promise rejection', {
    reason: String(reason),
    stack: reason instanceof Error ? reason.stack : undefined,
  });
});

// ---------------------------------------------------------------------------
// Start server
// ---------------------------------------------------------------------------
const PORT = 8002;
app.listen(PORT, () => {
  logger.info('auth-service started', { port: PORT });
  startBackgroundLoop();
});
