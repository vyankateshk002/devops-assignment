const express = require('express');
const cors = require('cors');
const path = require('path');
const mysql = require('mysql2/promise');
const { S3Client, PutObjectCommand, GetObjectCommand, ListObjectsV2Command } = require('@aws-sdk/client-s3');
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

// Fetch DB credentials from Secrets Manager if SECRET_NAME is set
async function loadSecretCredentials() {
  if (process.env.SECRET_NAME) {
    console.log(`[SecretsManager] Fetching DB credentials from secret: ${process.env.SECRET_NAME}`);
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
        console.log(`[SecretsManager] Successfully loaded credentials for host: ${dbConfig.host}`);
      }
    } catch (err) {
      console.error(`[SecretsManager] Error loading secret: ${err.message}`);
    }
  }
}

// Initialize MySQL pool and table
async function initDatabase() {
  try {
    await loadSecretCredentials();
    dbPool = mysql.createPool(dbConfig);

    // Verify connection and create table
    const [rows] = await dbPool.query('SELECT 1 + 1 AS solution');
    console.log('[MySQL] Connected successfully. Test query solution:', rows[0].solution);

    await dbPool.query(`
      CREATE TABLE IF NOT EXISTS notes (
        id INT AUTO_INCREMENT PRIMARY KEY,
        title VARCHAR(255) NOT NULL,
        content TEXT NOT NULL,
        created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
      )
    `);
    console.log('[MySQL] Table "notes" verified / created.');
  } catch (err) {
    console.error('[MySQL] Initialization error:', err.message);
  }
}

// Fetch instance metadata via IMDSv2
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

    const fetchMeta = (path, token) => new Promise((resolve, reject) => {
      const req = http.request({
        hostname: '169.254.169.254',
        path: `/latest/meta-data/${path}`,
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
      instanceId: process.env.INSTANCE_ID || 'i-local-dev',
      az: process.env.AWS_AZ || 'us-east-1a',
      localIp: '127.0.0.1',
      isEc2: false
    };
  }
}

// Health Check Endpoint (For ALB & Monitoring)
app.get('/health', async (req, res) => {
  let dbStatus = 'disconnected';
  if (dbPool) {
    try {
      await dbPool.query('SELECT 1');
      dbStatus = 'connected';
    } catch (err) {
      dbStatus = `error: ${err.message}`;
    }
  }

  const status = {
    status: 'healthy',
    uptime: process.uptime(),
    timestamp: new Date().toISOString(),
    database: dbStatus,
    s3Bucket: process.env.S3_BUCKET_NAME || 'not-configured',
    secretsManager: process.env.SECRET_NAME || 'not-configured'
  };

  res.status(200).json(status);
});

// System Info Endpoint
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
    s3Bucket: process.env.S3_BUCKET_NAME || 'devops-assignment-app-storage',
    region
  });
});

// API - Get Notes from MySQL
app.get('/api/notes', async (req, res) => {
  if (!dbPool) {
    return res.status(503).json({ error: 'Database connection not initialized' });
  }
  try {
    const [rows] = await dbPool.query('SELECT * FROM notes ORDER BY created_at DESC LIMIT 20');
    res.json(rows);
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
});

// API - Create Note in MySQL
app.post('/api/notes', async (req, res) => {
  if (!dbPool) {
    return res.status(503).json({ error: 'Database connection not initialized' });
  }
  const { title, content } = req.body;
  if (!title || !content) {
    return res.status(400).json({ error: 'Title and content are required' });
  }

  try {
    const [result] = await dbPool.query(
      'INSERT INTO notes (title, content) VALUES (?, ?)',
      [title, content]
    );
    res.status(201).json({ id: result.insertId, title, content, message: 'Note saved successfully to RDS MySQL' });
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
});

// API - Test S3 upload and read
app.post('/api/s3/test', async (req, res) => {
  const bucket = process.env.S3_BUCKET_NAME;
  if (!bucket) {
    return res.status(400).json({ error: 'S3_BUCKET_NAME environment variable not set' });
  }

  const fileName = `test-${Date.now()}.txt`;
  const fileContent = `DevOps Assignment S3 Test - Generated at ${new Date().toISOString()}`;

  try {
    await s3Client.send(new PutObjectCommand({
      Bucket: bucket,
      Key: fileName,
      Body: fileContent,
      ContentType: 'text/plain'
    }));

    res.json({
      message: 'File successfully uploaded to S3',
      bucket,
      fileName,
      content: fileContent
    });
  } catch (err) {
    res.status(500).json({ error: `S3 Upload Error: ${err.message}` });
  }
});

// Fallback HTML route
app.get('*', (req, res) => {
  res.sendFile(path.join(__dirname, 'public', 'index.html'));
});

// Start Server
initDatabase().finally(() => {
  app.listen(port, () => {
    console.log(`[Server] DevOps Application running on port ${port}`);
  });
});
