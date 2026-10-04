# Design Decisions

Why this 3-tier app is built the way it is. Each entry records the choice, the reasoning, and what I'd change at production scale.

---

## 1. Three subnet tiers across two availability zones

**Decision:** Public subnets hold only the load balancer and NAT gateway. App servers run in private subnets. The database tier has its own private subnets with no route to the internet at all. Every tier spans two availability zones.

**Why:** Each tier is only as reachable as it needs to be. Spreading across two AZs means the app keeps running if one data center has a problem.

---

## 2. One NAT gateway instead of one per AZ

**Decision:** A single NAT gateway in the first availability zone.

**Why:** NAT gateways bill by the hour, and one is enough for a lab.

**In production:** One NAT gateway per AZ, so losing an AZ doesn't cut every app server off from outbound internet.

---

## 3. No SSH: admin access through SSM Session Manager

**Decision:** No port 22, no SSH keys, and no bastion host. Engineers connect through SSM Session Manager.

**Why:** No inbound admin port means one less thing to attack. Session Manager access is controlled by IAM, works with SSO, and can be logged centrally, while SSH keys tend to get copied around and never rotated.

---

## 4. Chained security groups

**Decision:** The load balancer accepts HTTP from the internet; app servers accept HTTP only from the load balancer's security group, not from IP ranges.

**Why:** Referencing a security group instead of a CIDR keeps the rule correct even when instances and IPs change, and nothing can reach the app servers directly.

---

## 5. Hardened instances by default

**Decision:** IMDSv2 required, encrypted root volumes, and the latest Amazon Linux 2023 AMI looked up at deploy time.

**Why:** IMDSv2 blocks the metadata-credential theft used in SSRF attacks. Looking up the AMI from AWS's public parameter avoids hard-coded, aging images.

---

## 6. HTTP only, for now

**Decision:** The load balancer listens on HTTP port 80.

**Why:** HTTPS needs a domain name and a certificate, which this lab doesn't have.

**In production:** HTTPS with an ACM certificate, and port 80 redirecting to 443.

---

## 7. Reusable modules

**Decision:** The network and the web tier are separate Terraform modules, wired together by a small root module.

**Why:** Each module can be reused for another environment (staging, prod) by passing different inputs, and each layer can be reviewed on its own.
