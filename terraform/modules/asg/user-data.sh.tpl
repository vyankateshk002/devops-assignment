#!/bin/bash
set -xe

# Log everything to user-data.log for debugging
exec > >(tee /var/log/user-data.log|logger -t user-data -s 2>/dev/console) 2>&1

echo "=========================================="
echo "Starting DevOps Assignment EC2 Bootstrap"
echo "=========================================="

# 1. Update OS and install Node.js 20 & Git
dnf update -y
dnf install -y nodejs npm git

# 2. Create Application Directory
mkdir -p /opt/app
cd /opt/app

# 3. Create package.json
cat <<'EOF' > /opt/app/package.json
{
  "name": "devops-assignment-app",
  "version": "1.0.0",
  "main": "server.js",
  "dependencies": {
    "@aws-sdk/client-s3": "^3.758.0",
    "@aws-sdk/client-secrets-manager": "^3.758.0",
    "cors": "^2.8.5",
    "dotenv": "^16.4.7",
    "express": "^4.21.2",
    "mysql2": "^3.12.0"
  }
}
EOF

# 4. Install Node dependencies
npm install --omit=dev

# 5. Write server.js
cat <<'EOF' > /opt/app/server.js
const express = require('express');
const cors = require('cors');
const path = require('path');
const mysql = require('mysql2/promise');
const { S3Client, PutObjectCommand } = require('@aws-sdk/client-s3');
const { SecretsManagerClient, GetSecretValueCommand } = require('@aws-sdk/client-secrets-manager');

require('dotenv').config();

const app = express();
const port = process.env.PORT || 80;
const region = process.env.AWS_REGION || 'us-east-1';

app.use(cors());
app.use(express.json());
app.use(express.static(path.join(__dirname, 'public')));

let dbPool = null;
let s3Client = new S3Client({ region });
let dbConfig = {
  host: process.env.DB_HOST || 'localhost',
  user: process.env.DB_USER || 'admin',
  password: process.env.DB_PASSWORD || '',
  database: process.env.DB_NAME || 'devops_db',
  port: parseInt(process.env.DB_PORT || '3306'),
  waitForConnections: true,
  connectionLimit: 10,
  queueLimit: 0
};

async function loadSecretCredentials() {
  if (process.env.SECRET_NAME) {
    try {
      const smClient = new SecretsManagerClient({ region });
      const response = await smClient.send(
        new GetSecretValueCommand({ SecretId: process.env.SECRET_NAME })
      );
      if (response.SecretString) {
        const secret = JSON.parse(response.SecretString);
        dbConfig.host = secret.host || dbConfig.host;
        dbConfig.user = secret.username || dbConfig.user;
        dbConfig.password = secret.password || dbConfig.password;
        dbConfig.database = secret.dbname || dbConfig.database;
        dbConfig.port = parseInt(secret.port || dbConfig.port);
        console.log('[SecretsManager] Successfully loaded credentials for host:', dbConfig.host);
      }
    } catch (err) {
      console.error('[SecretsManager] Error loading secret:', err.message);
    }
  }
}

async function initDatabase() {
  try {
    await loadSecretCredentials();
    dbPool = mysql.createPool(dbConfig);
    const [rows] = await dbPool.query('SELECT 1 + 1 AS solution');
    console.log('[MySQL] Connected successfully. Test query solution:', rows[0].solution);

    await dbPool.query(
      'CREATE TABLE IF NOT EXISTS notes (' +
      '  id INT AUTO_INCREMENT PRIMARY KEY,' +
      '  title VARCHAR(255) NOT NULL,' +
      '  content TEXT NOT NULL,' +
      '  created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP' +
      ')'
    );
    console.log('[MySQL] Table "notes" verified / created.');
  } catch (err) {
    console.error('[MySQL] Initialization error:', err.message);
  }
}

async function getInstanceMetadata() {
  try {
    const http = require('http');
    const fetchToken = () => new Promise((resolve, reject) => {
      const req = http.request({
        hostname: '169.254.169.254',
        path: '/latest/api/token',
        method: 'PUT',
        headers: { 'X-aws-ec2-metadata-token-ttl-seconds': '60' },
        timeout: 1000
      }, (res) => {
        let data = '';
        res.on('data', chunk => data += chunk);
        res.on('end', () => resolve(data));
      });
      req.on('error', reject);
      req.on('timeout', () => { req.destroy(); reject(new Error('IMDS timeout')); });
      req.end();
    });

    const fetchMeta = (p, token) => new Promise((resolve, reject) => {
      const req = http.request({
        hostname: '169.254.169.254',
        path: '/latest/meta-data/' + p,
        method: 'GET',
        headers: { 'X-aws-ec2-metadata-token': token },
        timeout: 1000
      }, (res) => {
        let data = '';
        res.on('data', chunk => data += chunk);
        res.on('end', () => resolve(data));
      });
      req.on('error', reject);
      req.on('timeout', () => { req.destroy(); reject(new Error('IMDS timeout')); });
      req.end();
    });

    const token = await fetchToken();
    const instanceId = await fetchMeta('instance-id', token);
    const az = await fetchMeta('placement/availability-zone', token);
    const localIp = await fetchMeta('local-ipv4', token);

    return { instanceId, az, localIp, isEc2: true };
  } catch (err) {
    return {
      instanceId: 'i-unknown',
      az: 'us-east-1',
      localIp: '127.0.0.1',
      isEc2: false
    };
  }
}

app.get('/health', async (req, res) => {
  let dbStatus = 'disconnected';
  if (dbPool) {
    try {
      await dbPool.query('SELECT 1');
      dbStatus = 'connected';
    } catch (err) {
      dbStatus = 'error: ' + err.message;
    }
  }

  res.status(200).json({
    status: 'healthy',
    uptime: process.uptime(),
    timestamp: new Date().toISOString(),
    database: dbStatus,
    s3Bucket: process.env.S3_BUCKET_NAME || 'not-configured',
    secretsManager: process.env.SECRET_NAME || 'not-configured'
  });
});

app.get('/api/info', async (req, res) => {
  const metadata = await getInstanceMetadata();
  let dbStatus = 'disconnected';
  if (dbPool) {
    try {
      await dbPool.query('SELECT 1');
      dbStatus = 'connected';
    } catch (err) {
      dbStatus = 'error';
    }
  }

  res.json({
    app: 'DevOps Assignment 3-Tier Web Application',
    version: '1.0.0',
    metadata,
    dbStatus,
    dbHost: dbConfig.host,
    s3Bucket: process.env.S3_BUCKET_NAME,
    region
  });
});

app.get('/api/notes', async (req, res) => {
  if (!dbPool) return res.status(503).json({ error: 'Database not initialized' });
  try {
    const [rows] = await dbPool.query('SELECT * FROM notes ORDER BY created_at DESC LIMIT 20');
    res.json(rows);
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
});

app.post('/api/notes', async (req, res) => {
  if (!dbPool) return res.status(503).json({ error: 'Database not initialized' });
  const { title, content } = req.body;
  if (!title || !content) return res.status(400).json({ error: 'Title and content required' });

  try {
    const [result] = await dbPool.query(
      'INSERT INTO notes (title, content) VALUES (?, ?)',
      [title, content]
    );
    res.status(201).json({ id: result.insertId, title, content, message: 'Note saved to RDS MySQL' });
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
});

app.post('/api/s3/test', async (req, res) => {
  const bucket = process.env.S3_BUCKET_NAME;
  if (!bucket) return res.status(400).json({ error: 'S3_BUCKET_NAME not set' });

  const fileName = 'test-' + Date.now() + '.txt';
  const fileContent = 'DevOps S3 Verification at ' + new Date().toISOString();

  try {
    await s3Client.send(new PutObjectCommand({
      Bucket: bucket,
      Key: fileName,
      Body: fileContent,
      ContentType: 'text/plain'
    }));

    res.json({ message: 'File successfully uploaded to S3', bucket, fileName });
  } catch (err) {
    res.status(500).json({ error: 'S3 Upload Error: ' + err.message });
  }
});

app.get('*', (req, res) => {
  res.sendFile(path.join(__dirname, 'public', 'index.html'));
});

initDatabase().finally(() => {
  app.listen(port, () => {
    console.log('[Server] DevOps Application running on port ' + port);
  });
});
EOF

# 6. Copy frontend assets
mkdir -p /opt/app/public
cat <<'EOF' > /opt/app/public/index.html
<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <title>DevOps Practical Task | AWS 3-Tier Architecture Dashboard</title>
  <link rel="stylesheet" href="style.css">
  <link href="https://fonts.googleapis.com/css2?family=Inter:wght@400;600;700&family=JetBrains+Mono:wght@400;600&display=swap" rel="stylesheet">
</head>
<body>
  <div class="app-container">
    <header class="header">
      <div class="logo-area">
        <div class="badge-tag">AWS CLOUD &bull; TERRAFORM IAC</div>
        <h1>DevOps Infrastructure & CI/CD</h1>
        <p class="subtitle">Highly Available 3-Tier Architecture on AWS Free Tier with Auto Scaling & RDS</p>
      </div>
      <div class="health-badge" id="overallHealth">
        <span class="status-dot"></span>
        <span id="healthText">Checking Health...</span>
      </div>
    </header>

    <section class="arch-flow">
      <div class="flow-step">
        <div class="step-icon">🌐</div>
        <div class="step-label">ALB (HTTPS / 443)</div>
        <div class="step-sub">ACM SSL Certificate</div>
      </div>
      <div class="flow-arrow">➔</div>
      <div class="flow-step">
        <div class="step-icon">⚡</div>
        <div class="step-label">EC2 Auto Scaling</div>
        <div class="step-sub" id="flowAz">Loading AZ...</div>
      </div>
      <div class="flow-arrow">➔</div>
      <div class="flow-step">
        <div class="step-icon">🗄️</div>
        <div class="step-label">RDS MySQL 8.0</div>
        <div class="step-sub">Private Subnet</div>
      </div>
      <div class="flow-arrow">➔</div>
      <div class="flow-step">
        <div class="step-icon">🪣</div>
        <div class="step-label">S3 App Storage</div>
        <div class="step-sub">SSE-S3 Encrypted</div>
      </div>
    </section>

    <section class="grid-cards">
      <div class="card">
        <div class="card-header">
          <h3>EC2 Instance Details</h3>
          <span class="badge blue">Compute</span>
        </div>
        <div class="card-body">
          <div class="metric-row"><span class="label">Instance ID:</span><span class="value mono" id="instId">Loading...</span></div>
          <div class="metric-row"><span class="label">Availability Zone:</span><span class="value mono" id="instAz">Loading...</span></div>
          <div class="metric-row"><span class="label">Private IP:</span><span class="value mono" id="instIp">Loading...</span></div>
          <div class="metric-row"><span class="label">Auto Scaling Group:</span><span class="value green">Active (Self-Healing)</span></div>
        </div>
      </div>

      <div class="card">
        <div class="card-header">
          <h3>RDS MySQL (Private Subnet)</h3>
          <span class="badge purple">Database</span>
        </div>
        <div class="card-body">
          <div class="metric-row"><span class="label">Status:</span><span class="value" id="dbStatusBadge">Checking...</span></div>
          <div class="metric-row"><span class="label">DB Engine:</span><span class="value mono">MySQL 8.0 (db.t3.micro)</span></div>
          <div class="metric-row"><span class="label">Host:</span><span class="value mono truncate" id="dbHost">Private Subnet</span></div>
          <div class="metric-row"><span class="label">Secrets Manager:</span><span class="value green">Secured</span></div>
        </div>
      </div>

      <div class="card">
        <div class="card-body">
          <div class="card-header" style="padding-top:0">
            <h3>S3 Storage & Logs</h3>
            <span class="badge yellow">Storage</span>
          </div>
          <div class="metric-row"><span class="label">App Bucket:</span><span class="value mono truncate" id="s3Bucket">Loading...</span></div>
          <div class="metric-row"><span class="label">ALB Access Logs:</span><span class="value green">Enabled</span></div>
          <div class="metric-row"><span class="label">Encryption:</span><span class="value">AES-256</span></div>
          <button class="btn btn-secondary" id="testS3Btn" onclick="testS3Upload()">Test S3 PutObject</button>
          <div class="action-feedback" id="s3Feedback"></div>
        </div>
      </div>
    </section>

    <section class="data-section">
      <div class="section-header">
        <h2>Live Database CRUD Verification</h2>
        <p>Demonstrates active read/write operations from EC2 instances to RDS MySQL in private subnets</p>
      </div>

      <div class="crud-container">
        <form class="note-form" id="noteForm" onsubmit="handleCreateNote(event)">
          <h3>Insert Record into MySQL</h3>
          <div class="form-group">
            <label>Title</label>
            <input type="text" id="noteTitle" required placeholder="e.g. Terraform Deployment Verified" />
          </div>
          <div class="form-group">
            <label>Content</label>
            <textarea id="noteContent" rows="3" required placeholder="e.g. HTTPS ALB + ASG + RDS connected"></textarea>
          </div>
          <button type="submit" class="btn btn-primary" id="submitBtn">Save to Database</button>
        </form>

        <div class="notes-display">
          <div class="display-header">
            <h3>Recent Records</h3>
            <button class="btn btn-sm" onclick="loadNotes()">Refresh</button>
          </div>
          <div class="notes-list" id="notesList">
            <div class="loading-state">Loading records...</div>
          </div>
        </div>
      </div>
    </section>

    <footer class="footer">
      <p>DevOps Engineer Practical Assignment &bull; Terraform, AWS Free Tier, GitHub Actions</p>
      <div class="footer-links">
        <a href="/health" target="_blank">Health Check (/health)</a>
        <a href="/api/info" target="_blank">Metadata API (/api/info)</a>
      </div>
    </footer>
  </div>

  <script>
    async function loadInfo() {
      try {
        const res = await fetch('/api/info');
        const data = await res.json();
        document.getElementById('instId').textContent = data.metadata.instanceId || 'i-dev';
        document.getElementById('instAz').textContent = data.metadata.az || 'us-east-1a';
        document.getElementById('flowAz').textContent = 'AZ: ' + (data.metadata.az || 'us-east-1');
        document.getElementById('instIp').textContent = data.metadata.localIp || '10.0.11.x';
        document.getElementById('dbHost').textContent = data.dbHost || 'Configured via Secrets Manager';
        document.getElementById('s3Bucket').textContent = data.s3Bucket || 'devops-storage';
        document.getElementById('dbStatusBadge').innerHTML = data.dbStatus === 'connected' ? '<span class="pill green">Connected</span>' : '<span class="pill red">Disconnected</span>';
      } catch (err) {}
    }

    async function checkHealth() {
      try {
        const res = await fetch('/health');
        const data = await res.json();
        const badge = document.getElementById('overallHealth');
        const text = document.getElementById('healthText');
        if (data.status === 'healthy') {
          badge.className = 'health-badge healthy';
          text.textContent = 'System Healthy (200 OK)';
        } else {
          badge.className = 'health-badge degraded';
          text.textContent = 'Degraded';
        }
      } catch (err) {
        document.getElementById('overallHealth').className = 'health-badge degraded';
        document.getElementById('healthText').textContent = 'Unreachable';
      }
    }

    async function loadNotes() {
      const container = document.getElementById('notesList');
      try {
        const res = await fetch('/api/notes');
        const notes = await res.json();
        if (!Array.isArray(notes) || notes.length === 0) {
          container.innerHTML = '<div class="empty-state">No records yet. Insert a test record using the form!</div>';
          return;
        }
        container.innerHTML = notes.map(function(n) {
          return '<div class="note-card">' +
            '<div class="note-header">' +
              '<span class="note-id">#' + n.id + '</span>' +
              '<strong class="note-title">' + escapeHtml(n.title) + '</strong>' +
              '<span class="note-time">' + new Date(n.created_at).toLocaleTimeString() + '</span>' +
            '</div>' +
            '<p class="note-body">' + escapeHtml(n.content) + '</p>' +
          '</div>';
        }).join('');
      } catch (err) {
        container.innerHTML = '<div class="error-state">Failed: ' + err.message + '</div>';
      }
    }

    async function handleCreateNote(e) {
      e.preventDefault();
      const title = document.getElementById('noteTitle').value.trim();
      const content = document.getElementById('noteContent').value.trim();
      const btn = document.getElementById('submitBtn');
      btn.disabled = true;
      try {
        const res = await fetch('/api/notes', {
          method: 'POST',
          headers: { 'Content-Type': 'application/json' },
          body: JSON.stringify({ title: title, content: content })
        });
        if (res.ok) {
          document.getElementById('noteTitle').value = '';
          document.getElementById('noteContent').value = '';
          await loadNotes();
        }
      } catch (err) {
        alert(err.message);
      } finally {
        btn.disabled = false;
      }
    }

    async function testS3Upload() {
      const fb = document.getElementById('s3Feedback');
      fb.textContent = 'Uploading test object...';
      try {
        const res = await fetch('/api/s3/test', { method: 'POST' });
        const data = await res.json();
        if (res.ok) {
          fb.textContent = 'Success: Uploaded ' + data.fileName;
          fb.className = 'action-feedback success';
        } else {
          fb.textContent = data.error || 'Failed';
          fb.className = 'action-feedback error';
        }
      } catch (err) {
        fb.textContent = err.message;
        fb.className = 'action-feedback error';
      }
    }

    function escapeHtml(str) {
      return (str || '').replace(/[&<>"']/g, function(m) {
        return {
          '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;'
        }[m];
      });
    }

    loadInfo();
    checkHealth();
    loadNotes();
    setInterval(checkHealth, 15000);
  </script>
</body>
</html>
EOF

# Copy CSS
cat <<'EOF' > /opt/app/public/style.css
:root {
  --bg-dark: #0b0f19;
  --bg-card: #111827;
  --border-color: #374151;
  --text-main: #f9fafb;
  --text-muted: #9ca3af;
  --primary-color: #3b82f6;
  --accent-green: #10b981;
  --accent-purple: #8b5cf6;
  --accent-yellow: #f59e0b;
  --accent-red: #ef4444;
  --font-mono: 'JetBrains Mono', monospace;
}
* { box-sizing: border-box; margin: 0; padding: 0; }
body { background: var(--bg-dark); color: var(--text-main); font-family: 'Inter', sans-serif; padding: 2rem 1rem; }
.app-container { max-width: 1050px; margin: 0 auto; }
.header { display: flex; justify-content: space-between; align-items: center; border-bottom: 1px solid var(--border-color); padding-bottom: 1.5rem; margin-bottom: 2rem; flex-wrap: wrap; gap: 1rem; }
.badge-tag { background: rgba(59,130,246,0.15); color: #60a5fa; padding: 0.25rem 0.75rem; font-size: 0.75rem; font-weight: 700; border-radius: 9999px; margin-bottom: 0.5rem; display: inline-block; }
.subtitle { color: var(--text-muted); font-size: 0.95rem; }
.health-badge { display: flex; align-items: center; gap: 0.5rem; background: var(--bg-card); padding: 0.6rem 1.2rem; border-radius: 9999px; border: 1px solid var(--border-color); font-weight: 600; font-size: 0.875rem; }
.health-badge .status-dot { width: 10px; height: 10px; border-radius: 50%; background: #6b7280; }
.health-badge.healthy .status-dot { background: var(--accent-green); box-shadow: 0 0 10px var(--accent-green); }
.health-badge.degraded .status-dot { background: var(--accent-red); box-shadow: 0 0 10px var(--accent-red); }
.arch-flow { display: flex; justify-content: space-between; align-items: center; background: #131b2e; border: 1px solid #1e293b; border-radius: 12px; padding: 1.5rem; margin-bottom: 2rem; overflow-x: auto; }
.flow-step { text-align: center; min-width: 130px; }
.step-icon { font-size: 1.8rem; margin-bottom: 0.3rem; }
.step-label { font-weight: 600; font-size: 0.85rem; }
.step-sub { font-size: 0.75rem; color: var(--text-muted); }
.flow-arrow { color: var(--text-muted); font-size: 1.2rem; }
.grid-cards { display: grid; grid-template-columns: repeat(auto-fit, minmax(300px, 1fr)); gap: 1.5rem; margin-bottom: 2rem; }
.card { background: var(--bg-card); border: 1px solid var(--border-color); border-radius: 12px; padding: 1.5rem; }
.card-header { display: flex; justify-content: space-between; align-items: center; margin-bottom: 1rem; border-bottom: 1px solid rgba(255,255,255,0.05); padding-bottom: 0.5rem; }
.badge { font-size: 0.75rem; padding: 0.2rem 0.5rem; border-radius: 4px; font-weight: 600; }
.badge.blue { background: rgba(59,130,246,0.2); color: #93c5fd; }
.badge.purple { background: rgba(139,92,246,0.2); color: #c4b5fd; }
.badge.yellow { background: rgba(245,158,11,0.2); color: #fcd34d; }
.metric-row { display: flex; justify-content: space-between; margin-bottom: 0.6rem; font-size: 0.85rem; }
.metric-row .label { color: var(--text-muted); }
.metric-row .value { font-weight: 500; }
.mono { font-family: var(--font-mono); font-size: 0.8rem; }
.truncate { max-width: 160px; white-space: nowrap; overflow: hidden; text-overflow: ellipsis; }
.green { color: var(--accent-green); }
.pill { padding: 0.15rem 0.5rem; border-radius: 4px; font-size: 0.75rem; font-weight: 600; }
.pill.green { background: rgba(16,185,129,0.2); color: #34d399; }
.pill.red { background: rgba(239,68,68,0.2); color: #f87171; }
.btn { display: inline-block; padding: 0.6rem 1rem; border-radius: 6px; font-weight: 500; font-size: 0.875rem; border: none; cursor: pointer; width: 100%; }
.btn-primary { background: var(--primary-color); color: white; }
.btn-secondary { background: #1f2937; color: #e5e7eb; border: 1px solid var(--border-color); margin-top: 0.5rem; }
.btn-sm { width: auto; padding: 0.3rem 0.6rem; font-size: 0.75rem; background: #1f2937; color: white; border: 1px solid var(--border-color); }
.data-section { background: var(--bg-card); border: 1px solid var(--border-color); border-radius: 12px; padding: 1.5rem; margin-bottom: 2rem; }
.crud-container { display: grid; grid-template-columns: 1fr 1fr; gap: 1.5rem; margin-top: 1rem; }
@media (max-width: 768px) { .crud-container { grid-template-columns: 1fr; } }
.form-group { display: flex; flex-direction: column; gap: 0.3rem; margin-bottom: 0.8rem; }
.form-group label { font-size: 0.8rem; color: var(--text-muted); }
.form-group input, .form-group textarea { background: #0b0f19; border: 1px solid var(--border-color); border-radius: 6px; padding: 0.5rem; color: white; font-family: inherit; }
.display-header { display: flex; justify-content: space-between; align-items: center; margin-bottom: 0.8rem; }
.notes-list { display: flex; flex-direction: column; gap: 0.6rem; max-height: 250px; overflow-y: auto; }
.note-card { background: #0b0f19; border: 1px solid #1f2937; border-radius: 6px; padding: 0.6rem; font-size: 0.85rem; }
.note-header { display: flex; justify-content: space-between; margin-bottom: 0.3rem; }
.note-id { color: var(--primary-color); font-family: var(--font-mono); }
.note-time { color: var(--text-muted); font-size: 0.75rem; }
.action-feedback { margin-top: 0.5rem; font-size: 0.75rem; font-family: var(--font-mono); }
.action-feedback.success { color: var(--accent-green); }
.action-feedback.error { color: var(--accent-red); }
.footer { text-align: center; border-top: 1px solid var(--border-color); padding-top: 1rem; color: var(--text-muted); font-size: 0.8rem; }
.footer-links { display: flex; justify-content: center; gap: 1rem; margin-top: 0.5rem; }
.footer-links a { color: #60a5fa; text-decoration: none; }
EOF

# 7. Create Environment File for Systemd Service
cat <<EOF > /opt/app/.env
PORT=80
AWS_REGION=${aws_region}
SECRET_NAME=${secret_name}
S3_BUCKET_NAME=${s3_bucket_name}
EOF

# 8. Create Systemd Service Unit
cat <<'EOF' > /etc/systemd/system/devops-app.service
[Unit]
Description=DevOps Assignment Web Application
After=network.target

[Service]
Type=simple
User=root
WorkingDirectory=/opt/app
EnvironmentFile=/opt/app/.env
ExecStart=/usr/bin/node /opt/app/server.js
Restart=always
RestartSec=5
StandardOutput=syslog
StandardError=syslog
SyslogIdentifier=devops-app

[Install]
WantedBy=multi-user.target
EOF

# 9. Reload Systemd and Enable/Start Application Service
systemctl daemon-reload
systemctl enable --now devops-app

echo "=========================================="
echo "DevOps Assignment Web Application Running"
echo "=========================================="
