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

**Decision:** App servers run on t4g.micro and the database on db.t4g.small, both AWS Graviton. The database was planned as db.t4g.micro but moved up one size when AWS had no micro capacity (see Challenges).

**Why:** Graviton instances typically cost around 20 percent less than comparable x86 instances, with equal or better performance for this kind of workload. The architecture is a module variable, so switching back to x86 is a one-line change.

---

## 13. RDS Extended Support left at the default, for now

**Decision:** The lab keeps AWS's default, which enrolls the database in RDS Extended Support.

**Why:** It costs nothing until PostgreSQL 16 leaves standard support. But it's a common surprise bill: once standard support ends, AWS keeps running the old version for an additional fee instead of requiring an upgrade.

**In production:** Set the engine lifecycle option deliberately and plan major-version upgrades, rather than paying for extended support by default.

---

## 14. Golden AMI built with Packer and hardened with Ansible

**Decision:** App servers launch from a pre-built image instead of installing software at boot. Packer builds it from the newest Amazon Linux 2023 ARM image, applies all updates, pre-installs nginx and the database client, and runs an Ansible playbook that applies a CIS-aligned hardening baseline. Terraform picks the newest image automatically by name.

**Why:** Immutable infrastructure. Every server starts identical, patched, and hardened, boots faster, and needs no internet access at startup. Changes happen by building a new image and rolling it out, not by patching running servers.

**Honest scope:** The playbook covers a focused subset of CIS controls (SSH, kernel and network parameters, core dumps, unused filesystems, audit rules, file permissions, and a login banner), not the full benchmark.

**Build security:** Packer's temporary security group allows SSH only from my own IP, the build instance requires IMDSv2, and Ansible is installed in a throwaway environment and removed before the image is captured.

**In production:** Build in a private subnet over Session Manager instead of SSH, scan images with Amazon Inspector before use, run the build in a pipeline on a schedule, and consider EC2 Image Builder as a managed alternative. Enable AMI deregistration protection on images that live Auto Scaling groups use, since a deregistered image silently breaks scaling and self-healing, and keep only the current and previous images to control snapshot cost.

---

## 15. Target-tracking scaling on CPU

**Decision:** A target-tracking policy keeps average CPU across the group around 50 percent, between 2 and 4 instances, with one-minute detailed monitoring.

**Why:** Target tracking is the simplest correct scaling policy: AWS creates and manages the CloudWatch alarms, adding instances under load and removing them when it drops. Detailed monitoring makes it react in minutes instead of ten.

**In production:** Consider scaling on requests per target instead of CPU for a web tier, add scheduled scaling for predictable peaks, and set the maximum based on database connection limits.

---

## 16. Health checks tuned for a lab, measured under failure

**Decision:** Target group health checks every 15 seconds, with two failures marking a server unhealthy, and an Auto Scaling health check type of ELB.

**Measured result:** I terminated a server under live traffic. Requests to it failed for about 25 seconds (two 502s and three timeouts) while the other AZ kept serving, then the load balancer routed around it. Auto Scaling launched a replacement about 1 minute 47 seconds after the failure, in the same AZ to keep the group balanced, and it was serving about 2 minutes 45 seconds after the failure. The site never fully went down.

**Why it's documented this way:** A sudden server loss isn't zero-downtime with these settings, and I'd rather show measured numbers than claim otherwise. Planned removals (scale-in, instance refresh) are graceful because Auto Scaling drains connections before terminating.

**In production:** A 5-second health check interval to shrink the error window, retries in clients or the application, and alarms on unhealthy host count so a human hears about repeated failures.

---

## 17. AWS WAF with managed rules and rate limiting

**Decision:** A regional WAF web ACL on the load balancer with four AWS-managed rule groups (IP reputation, the common rule set, known bad inputs, and SQL injection) plus a per-IP rate limit. Requests and decisions are logged to CloudWatch Logs.

**Why:** It stops common attacks before they reach the servers, and the managed groups are kept up to date by AWS. The SQL injection group matters here because the app has a database tier.

**Verified:** A normal request returned 200; SQL injection, cross-site scripting, and a Log4j exploit string in a header each returned 403, and sampled requests tied each block to its rule. Within hours of going live, sampled requests also showed real automated scanners probing robots.txt, sitemap.xml, and security.txt, blocked by the IP reputation list. The rate limit switched one IP from 200 to 403 after it crossed 100 requests a minute; WAF evaluates rates on a rolling window, so the block lands slightly after the threshold.

**Lab trade-off:** The 100-per-minute limit is low on purpose so it can be demonstrated. A production limit would come from observed traffic, with new rules run in count mode first to check for false positives. A rate limit stops a single noisy source, not a distributed attack; that needs CloudFront and AWS Shield.

---

## 18. AWS Backup with an encrypted cross-region copy

**Decision:** An AWS Backup plan backs up the database daily at 05:00 UTC into a vault in us-east-1 and copies each recovery point to a vault in us-west-2, encrypted with a customer-managed key in that region. Recovery points are kept for 7 days.

**Why:** RDS automated backups live in the same region as the database. A copy in a second region protects against a regional outage. A KMS key only works in its own region, so the copies need their own key in us-west-2.

**Verified:** The scheduled backup ran on its own at exactly 05:00 UTC. A cross-region copy completed, kept the original point in time, and was encrypted with the us-west-2 key.

**Lesson:** A copy started by hand in the console defaulted to 35-day retention instead of the plan's 7. Manual jobs don't inherit a plan's lifecycle settings, so they can keep data, and cost, longer than policy allows. I corrected it to 7 days. In production, copies run through backup plans, and AWS Backup Audit Manager flags any recovery point whose retention doesn't match policy.

**In production:** Vaults in a separate account so a compromised workload account can't delete its own backups, Vault Lock in compliance mode, and continuous backup for point-in-time restore.

---

## 19. Restore tested and measured: RTO and RPO

**Test:** Wrote 5 rows, took an on-demand backup at 22:04:52, wrote 3 more rows, then restored that backup to a new database instance.

**Measured results:**

| Measure | Result |
|---|---|
| Backup duration | About 4 minutes |
| Restore duration | 16 minutes 48 seconds |
| Rows in live database | 8 |
| Rows in restored database | 5 (everything after the backup was lost) |

**What the numbers mean:** The restore itself took about 17 minutes. End-to-end RTO also includes detecting the failure, deciding to restore, and pointing the app at the new database, so I'd plan for about 30 minutes and rehearse the cutover. With a daily backup, the worst-case RPO is 24 hours.

**In production:** Continuous backup (point-in-time restore to within minutes) for a tighter RPO, Multi-AZ to avoid restores for most failures, a scripted cutover, and scheduled restore tests (AWS Backup restore testing) so the RTO stays proven.

---

## Challenges

**AWS ran out of capacity.** The first apply failed with InsufficientCapacity errors: no t4g.micro capacity for the app servers in one zone, and no db.t4g.micro capacity for the database in either zone. I destroyed the partial build to stop the billing and retried; the app tier came up, and the database succeeded one size up, on db.t4g.small. In production, I'd use an Auto Scaling mixed-instances policy with several instance types, Multi-AZ for the database, and capacity reservations for critical workloads.

**A change Terraform didn't see.** After the size change, the apply failed again with the old instance class in the error. The edit hadn't been saved in the right block. I confirmed the setting with Select-String and checked the plan showed the new size before approving it.

**A failure test that didn't fail.** My first two runs showed both servers answering every request: the terminate confirmation hadn't been clicked, and `curl -s` hides errors anyway. I rewrote the test to print a timestamp and HTTP status for every request, confirmed the instance actually entered Shutting-down, and re-ran it to get the measured results in decision 16.

**Placeholder values in a remote shell.** Commands on the app server failed with AccessDenied and "could not translate host name" because template placeholders had been pasted instead of real values. Variables set in PowerShell on my laptop don't exist in a Session Manager shell on the server. I now generate the exact lines with real values and check them with echo before using them.

**Choosing the right recovery point.** By the time I ran the restore test, the scheduled overnight backup had also run and already contained the post-backup rows. Restoring it would have shown no data loss and proven nothing, so I deliberately restored the earlier on-demand backup.
