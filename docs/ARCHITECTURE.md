# AWS Infrastructure Architecture Documentation

## 1. High-Level Architecture Overview

This project implements a secure, resilient, and highly available **3-Tier Web Application Infrastructure** on AWS, fully automated using **Terraform (Infrastructure as Code)** and deployed via **GitHub Actions CI/CD**.

```
                           +----------------------------------------+
                           |           Public Internet              |
                           +----------------------------------------+
                                    |                       |
                             (HTTPS:443 / HTTP:80)       (CI/CD)
                                    |                       |
                                    v                       v
                      +---------------------------+  +-------------------+
                      | Application Load Balancer |  |  GitHub Actions   |
                      |  (Public Subnets AZ-a/b)  |  |  Terraform CI/CD  |
                      |  SSL via ACM Certificate  |  +-------------------+
                      +---------------------------+            |
                                    |                          |
                   (Internal Forward Port 80)                  |
                                    v                          |
                      +---------------------------+            |
                      | Auto Scaling Group (EC2)  |            |
                      | (Private App Subnets A/B) |            |
                      |  Amazon Linux 2023 / Node |            |
                      +---------------------------+            |
                         /         |            \              |
      (Outbound Updates)/          |             \(Read/Write) |
                       v           |              v            |
             +---------------+     |     +------------------+  |
             | NAT Instance  |     |     | Amazon S3 Bucket |  |
             | (Public / $0) |     |     | (App Storage)    |  |
             +---------------+     |     +------------------+  |
                    |              |                           |
             +---------------+     |                           |
             |  Internet GW  |     v                           |
             +---------------+  +--------------------------+   |
                                | Amazon RDS MySQL 8.0     |<--+
                                | (Private DB Subnets A/B) |
                                | AWS Secrets Manager      |
                                +--------------------------+
```

---

## 2. Network Topology & Subnet Segmentation

The architecture is built inside a custom Amazon Virtual Private Cloud (VPC) with CIDR `10.0.0.0/16`, segmented across two Availability Zones (`us-east-1a` and `us-east-1b`) for high availability:

| Subnet Type | AZ | CIDR Block | Purpose | Egress Routing |
| :--- | :--- | :--- | :--- | :--- |
| **Public Subnet 1** | us-east-1a | `10.0.1.0/24` | ALB Public Endpoint & Free-Tier NAT Instance | Direct to Internet Gateway (`0.0.0.0/0 -> igw`) |
| **Public Subnet 2** | us-east-1b | `10.0.2.0/24` | ALB Multi-AZ Secondary Interface | Direct to Internet Gateway (`0.0.0.0/0 -> igw`) |
| **Private App Subnet 1** | us-east-1a | `10.0.11.0/24` | Auto Scaling EC2 Instances (App Tier) | Routed to NAT Instance (`0.0.0.0/0 -> nat-instance`) |
| **Private App Subnet 2** | us-east-1b | `10.0.12.0/24` | Auto Scaling EC2 Instances (App Tier) | Routed to NAT Instance (`0.0.0.0/0 -> nat-instance`) |
| **Private DB Subnet 1** | us-east-1a | `10.0.21.0/24` | RDS MySQL Primary (Database Tier) | Strictly Local VPC (`10.0.0.0/16`) - No Internet Route |
| **Private DB Subnet 2** | us-east-1b | `10.0.22.0/24` | RDS MySQL Subnet Group Secondary | Strictly Local VPC (`10.0.0.0/16`) - No Internet Route |

---

## 3. Cost-Optimization Strategy (AWS Free Tier Compliance)

A major requirement for this project was to **strictly avoid paid cloud services** and maximize the AWS Free Tier. Here is how our Terraform configuration guarantees $0.00 cost while keeping production standards:

### A. Free-Tier NAT Instance vs. AWS Managed NAT Gateway
- **The Problem:** An AWS Managed NAT Gateway costs ~$32.40/month plus data transfer fees ($0.045/hr), which is **not** covered by the Free Tier.
- **Our Solution:** We implemented an EC2 NAT Instance using `t2.micro` running Amazon Linux 2023 with kernel IP forwarding and `iptables` masquerading.
- **Result:** $0.00 infrastructure cost. A single variable flag (`enable_nat_gateway = false`) allows seamless switching between enterprise NAT Gateway and Free-Tier NAT Instance.

### B. Single-AZ RDS MySQL
- `db.t3.micro` instance class (eligible for 750 free hours/month).
- 20 GB gp3 general-purpose SSD storage (under the 20 GB free limit).
- Automated snapshots set to 0 and final snapshot skipped on destroy to eliminate backup retention storage fees.

### C. SSL / ACM Certificate Without Paid Domain
- Uses Terraform `tls` provider to generate a 2048-bit RSA self-signed SSL certificate for a dummy domain (`app.devops-assignment.internal`).
- Automatically imports the certificate into **AWS Certificate Manager (ACM)**.
- Attaches the imported ACM Certificate to the ALB HTTPS:443 listener at $0.00 cost.

---

## 4. Security & Least Privilege

The infrastructure enforces defense-in-depth across every layer:

1. **Security Groups Chaining:**
   - **ALB Security Group:** Accepts inbound traffic on ports `80` (HTTP) and `443` (HTTPS) from `0.0.0.0/0`.
   - **App Security Group:** Accepts inbound traffic on port `80` **only** from the ALB Security Group. Directly blocking public access.
   - **RDS Security Group:** Accepts inbound MySQL traffic on port `3306` **only** from the App Security Group.
2. **AWS Secrets Manager Integration:**
   - Database credentials are randomly generated during deployment, stored in Secrets Manager, and never exposed in cleartext or commit history.
   - EC2 instances query the secret at startup using the AWS SDK authenticated via an IAM Instance Profile.
3. **IAM Least Privilege:**
   - The EC2 IAM role only grants `secretsmanager:GetSecretValue` on the specific secret ARN, and `s3:GetObject`/`PutObject` on the application bucket.
   - Attached `AmazonSSMManagedInstanceCore` allows secure terminal access via AWS Systems Manager without opening SSH port 22.
4. **IMDSv2 Enforced:**
   - EC2 Launch Template enforces `http_tokens = "required"` (IMDSv2) with hop limit 2, preventing SSRF attacks from stealing instance profile credentials.
