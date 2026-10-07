#!/bin/bash
set -xe

exec > >(tee /var/log/user-data.log|logger -t user-data -s 2>/dev/console) 2>&1

echo "=========================================="
echo "Starting DevOps Assignment EC2 Bootstrap"
echo "=========================================="

# 1. Wait for NAT instance routing readiness
for i in {1..10}; do
  if ping -c 1 8.8.8.8; then
    echo "Outbound connectivity established."
    break
  fi
  echo "Waiting for NAT instance routing... ($i/10)"
  sleep 3
done

# 2. Install Node.js & Git
for i in {1..5}; do
  if dnf install -y nodejs npm git; then
    echo "Node.js and Git installed successfully."
    break
  fi
  echo "Retrying package installation ($i/5)..."
  sleep 5
done

# 3. Start immediate bootstrap HTTP server so ALB health checks pass instantly
mkdir -p /opt/devops-assignment/app
cd /opt/devops-assignment/app

cat << 'BOOTSTRAP_EOF' > /opt/devops-assignment/app/bootstrap-server.js
const http = require('http');
const server = http.createServer((req, res) => {
  if (req.url === '/health') {
    res.writeHead(200, { 'Content-Type': 'application/json' });
    res.end(JSON.stringify({ status: 'UP', message: 'Bootstrap server active', timestamp: new Date().toISOString() }));
    return;
  }
  res.writeHead(200, { 'Content-Type': 'text/html' });
  res.end('<!DOCTYPE html><html><body style="font-family:sans-serif;text-align:center;padding:50px;background:#0f172a;color:#f8fafc;"><h1>🚀 DevOps Assignment Application Initializing...</h1><p>The system is syncing latest files and connecting to RDS MySQL. Please refresh in 15 seconds.</p></body></html>');
});
server.listen(80, '0.0.0.0', () => console.log('Bootstrap health responder running on port 80'));
BOOTSTRAP_EOF

/usr/bin/node /opt/devops-assignment/app/bootstrap-server.js &
BOOTSTRAP_PID=$!
echo "Bootstrap server started with PID: $BOOTSTRAP_PID"

# 4. Clone full application repository
for i in {1..8}; do
  rm -rf /opt/devops-assignment/repo
  if git clone https://github.com/vyankateshk002/devops-assignment.git /opt/devops-assignment/repo; then
    cp -r /opt/devops-assignment/repo/app/* /opt/devops-assignment/app/
    echo "Repository cloned successfully."
    break
  fi
  echo "Retrying git clone ($i/8)..."
  sleep 5
done

# 5. Install Node.js production dependencies
cd /opt/devops-assignment/app
npm install --omit=dev || true

# 6. Configure environment variables for production service
cat <<EOF > /opt/devops-assignment/app/.env
PORT=80
AWS_REGION=${aws_region}
SECRET_NAME=${secret_name}
S3_BUCKET_NAME=${s3_bucket_name}
EOF

# 7. Terminate temporary bootstrap server
kill $BOOTSTRAP_PID || true
sleep 1

# 8. Create Systemd Service Unit for the full application
cat <<'EOF' > /etc/systemd/system/devops-app.service
[Unit]
Description=DevOps Assignment Web Application
After=network.target

[Service]
Type=simple
User=root
WorkingDirectory=/opt/devops-assignment/app
EnvironmentFile=/opt/devops-assignment/app/.env
ExecStart=/usr/bin/node /opt/devops-assignment/app/server.js
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
