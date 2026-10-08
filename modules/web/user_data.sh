#!/bin/bash
# Runs once when each app server first boots. With the golden AMI,
# everything is already installed, so this needs no internet access.
set -euo pipefail

# Stock AMI fallback only: install nginx if the image doesn't have it.
rpm -q nginx >/dev/null 2>&1 || dnf install -y nginx

# IMDSv2: get a session token first, then read instance details.
TOKEN=$(curl -s -X PUT "http://169.254.169.254/latest/api/token" -H "X-aws-ec2-metadata-token-ttl-seconds: 300")
ID=$(curl -s -H "X-aws-ec2-metadata-token: $TOKEN" http://169.254.169.254/latest/meta-data/instance-id)
AZ=$(curl -s -H "X-aws-ec2-metadata-token: $TOKEN" http://169.254.169.254/latest/meta-data/placement/availability-zone)
AMI=$(curl -s -H "X-aws-ec2-metadata-token: $TOKEN" http://169.254.169.254/latest/meta-data/ami-id)
ARCH=$(uname -m)

cat > /usr/share/nginx/html/index.html <<HTML
<!doctype html>
<html>
<head>
<title>aws-3tier-terraform</title>
<style>body{font-family:sans-serif;max-width:640px;margin:60px auto;padding:0 20px;line-height:1.5}</style>
</head>
<body>
<h1>Highly available 3-tier app</h1>
<p>Served by <b>$ID</b> in <b>$AZ</b> on <b>$ARCH</b></p>
<p>Image: <b>$AMI</b></p>
<p>Refresh to watch the load balancer switch between instances.</p>
</body>
</html>
HTML

echo "instance=$ID az=$AZ arch=$ARCH ami=$AMI" > /usr/share/nginx/html/whoami.txt

systemctl enable --now nginx

# Stock AMI fallback only: database client tools. Non-fatal.
set +e
rpm -q jq >/dev/null 2>&1 || dnf install -y postgresql16 jq || dnf install -y postgresql15 jq
exit 0
