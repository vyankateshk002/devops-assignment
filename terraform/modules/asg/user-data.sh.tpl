#!/bin/bash
set -xe

exec > >(tee /var/log/user-data.log|logger -t user-data -s 2>/dev/console) 2>&1

echo "=========================================="
echo "Starting DevOps Assignment EC2 Bootstrap"
echo "=========================================="

# 1. Update OS and install Node.js 20 & Git
dnf update -y
dnf install -y nodejs npm git

# 2. Clone application repository from GitHub (with retries for network readiness)
mkdir -p /opt
cd /opt

for i in {1..5}; do
  if [ -d "/opt/devops-assignment" ]; then
    cd /opt/devops-assignment && git pull && break
  else
    git clone https://github.com/vyankateshk002/devops-assignment.git /opt/devops-assignment && break
  fi
  echo "Retrying git clone in 5 seconds..."
  sleep 5
done

cd /opt/devops-assignment/app
npm install --omit=dev

# 3. Create Environment File for Systemd Service
cat <<EOF > /opt/devops-assignment/app/.env
PORT=80
AWS_REGION=${aws_region}
SECRET_NAME=${secret_name}
S3_BUCKET_NAME=${s3_bucket_name}
EOF

# 4. Create Systemd Service Unit
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

# 5. Reload Systemd and Enable/Start Application Service
systemctl daemon-reload
systemctl enable --now devops-app

echo "=========================================="
echo "DevOps Assignment Web Application Running"
echo "=========================================="
