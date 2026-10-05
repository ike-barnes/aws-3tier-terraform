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

---

## 8. RDS PostgreSQL in isolated subnets, reachable only from the app tier

**Decision:** PostgreSQL 16 on RDS, in the database subnets that have no internet route, with no public access. Its security group allows port 5432 only from the app servers' security group.

**Why:** The database is the most valuable thing in the stack, so it gets the tightest path: one port, from one security group, with no route to or from the internet.

**Lab trade-offs:** Single-AZ, deletion protection off, and no final snapshot, to keep cost and teardown simple. In production: Multi-AZ for automatic failover, deletion protection on, a final snapshot on delete, and Performance Insights.

---

## 9. Customer-managed KMS key for the data tier

**Decision:** A dedicated KMS key, with automatic yearly rotation, encrypts the database storage, its automated backups, and the secret holding its password.

**Why:** With an AWS-managed key, anyone with RDS access effectively has access to the data. A customer-managed key adds a separate control: access to the data requires permission on the key too, every use is logged in CloudTrail, and disabling the key cuts off access immediately. This is the kind of control NIST SC-12 and SC-28 audits look for.

**Cost note:** Each key costs about $1 a month. Because the lab is destroyed every session, each new key is scheduled for deletion after a 7-day waiting period, the shortest AWS allows.

---

## 10. Database password managed by RDS in Secrets Manager

**Decision:** `manage_master_user_password = true`. RDS generates the password, stores it in Secrets Manager encrypted with the database key, and rotates it automatically.

**Why:** The password never appears in Terraform code, variables, or state, and no person ever types or sees it. The app servers read it at runtime with a narrowly scoped IAM policy: one secret, one key, nothing else. Connections also require TLS, which RDS enforces by default for PostgreSQL 15 and later.

---

## 11. VPC endpoints for AWS service traffic

**Decision:** A free S3 gateway endpoint, plus interface endpoints for SSM, SSM messages, EC2 messages, and Secrets Manager.

**Why:** Session Manager and secret lookups stay on AWS's private network instead of going out through the NAT gateway to public endpoints. That's a smaller attack surface, less NAT data-processing cost, and admin access keeps working even if the NAT gateway has a problem.

**Trade-off:** Interface endpoints cost about $0.01 an hour per AZ each. The NAT gateway is still needed for OS packages at boot; a pre-built golden AMI (next session) is the step that could remove that dependency.

---

## 12. Graviton (ARM) instances

**Decision:** App servers run on t4g.micro and the database on db.t4g.micro, both AWS Graviton.

**Why:** Graviton instances typically cost around 20 percent less than comparable x86 instances, with equal or better performance for this kind of workload. The architecture is a module variable, so switching back to x86 is a one-line change.
