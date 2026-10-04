#!/bin/bash
# Runs once when each app server first boots.
set -euo pipefail

dnf install -y nginx

# IMDSv2: get a session token first, then read instance details.
TOKEN=$(curl -s -X PUT "http://169.254.169.254/latest/api/token" -H "X-aws-ec2-metadata-token-ttl-seconds: 300")
ID=$(curl -s -H "X-aws-ec2-metadata-token: $TOKEN" http://169.254.169.254/latest/meta-data/instance-id)
AZ=$(curl -s -H "X-aws-ec2-metadata-token: $TOKEN" http://169.254.169.254/latest/meta-data/placement/availability-zone)

cat > /usr/share/nginx/html/index.html <<HTML
<!doctype html>
<html>
<head>
<title>aws-3tier-terraform</title>
<style>body{font-family:sans-serif;max-width:640px;margin:60px auto;padding:0 20px;line-height:1.5}</style>
</head>
<body>
<h1>Highly available 3-tier app</h1>
<p>Served by <b>$ID</b> in <b>$AZ</b></p>
<p>Refresh to watch the load balancer switch between instances.</p>
</body>
</html>
HTML

echo "instance=$ID az=$AZ" > /usr/share/nginx/html/whoami.txt

systemctl enable --now nginx
