# AWS Infrastructure Architecture Documentation

## 1. Executive Summary & Why We Built This

### The Purpose of This Assignment
This project demonstrates an enterprise-grade, highly available **3-Tier Web Application Architecture** on Amazon Web Services (AWS), fully provisioned through **Terraform (Infrastructure as Code)** and deployed via an automated **GitHub Actions CI/CD Pipeline**.

### Why Build a Live Web Application & Dashboard?
In traditional DevOps interviews, most candidates submit Terraform code that either provisions empty infrastructure or boots a generic "Hello World" / default Nginx page. 

By delivering a complete, interactive **Live System Dashboard**, you provide **tangible proof** to the interviewer that every single component of the cloud architecture is actively working and properly integrated:

| Component Proved | What the Dashboard Shows | Why It Wows Interviewers |
| :--- | :--- | :--- |
| **Networking & ALB** | Traffic routes seamlessly through the ALB into private subnets | Proves VPC routing, subnets, route tables, and Target Group health checks are 100% operational. |
| **Compute & IMDSv2** | Displays live EC2 Instance ID and Availability Zone retrieved via IMDSv2 tokens | Proves compliance with modern AWS security standards (mitigating SSRF vulnerabilities). |
| **Private Database (RDS)** | Status indicator showing **"Connected"** to MySQL 8.0 with real-time CRUD note creation | Proves secure database connectivity across private subnets without public exposure. |
| **Security & Secrets** | Credentials retrieved dynamically from AWS Secrets Manager | Proves zero hardcoded passwords in code or environment variables. |
| **Object Storage (S3)** | Interactive "Test S3 Upload" button uploading files via the AWS SDK | Proves IAM Instance Profile least-privilege role permissions are working. |
| **Observability** | Standardized `/health` endpoint returning machine-readable JSON (HTTP 200) | Demonstrates site reliability engineering (SRE) and ALB health check best practices. |

> **Is this good to share with the interviewer?**
> **Yes, absolutely!** It elevates your submission from a theoretical script into a working, production-grade cloud system. It proves you understand not just how to provision resources, but how infrastructure serves real applications.

---

## 2. Simple Architecture Overview (The 30-Second Summary)

At its core, this architecture follows the classic **3-Tier Web Architecture Pattern**:

```
+-----------------------------------------------------------------------------------+
|                                  PUBLIC INTERNET                                  |
+-----------------------------------------------------------------------------------+
                                          |
                      HTTPS (Port 443) / HTTP (Port 80)
                                          v
+===================================================================================+
| TIER 1: PUBLIC WEB ENTRY (Public Subnets: 10.0.1.0/24 & 10.0.2.0/24)              |
|                                                                                   |
|   [ Application Load Balancer (ALB) ] <--- SSL Terminated via ACM Certificate     |
|              |                                                                    |
|              +--- Routes traffic to Target Group instances                        |
|                                                                                   |
|   [ Free-Tier NAT Instance (t3.micro) ] <--- Provides $0.00 Outbound Internet     |
+===================================================================================+
                                          |
                        Forward HTTP Port 80 (Internal Only)
                                          v
+===================================================================================+
| TIER 2: PRIVATE APPLICATION (Private App Subnets: 10.0.11.0/24 & 10.0.12.0/24)    |
|                                                                                   |
|   [ EC2 Auto Scaling Group ] (Amazon Linux 2023 / Node.js 20 App)                 |
|       - NO Public IP addresses (Protected from direct internet attacks)           |
|       - Authenticates to AWS services via IAM Instance Profile                    |
|       - Fetches DB password from AWS Secrets Manager                              |
|       - Stores application assets in Amazon S3 Bucket                             |
|       - Sends outbound package/git requests via Free-Tier NAT Instance            |
+===================================================================================+
                                          |
                        MySQL Protocol Port 3306 (Internal Only)
                                          v
+===================================================================================+
| TIER 3: PRIVATE DATABASE (Private DB Subnets: 10.0.21.0/24 & 10.0.22.0/24)        |
|                                                                                   |
|   [ Amazon RDS MySQL 8.0 (db.t3.micro) ]                                          |
|       - Completely isolated in dedicated DB subnet group                          |
|       - ZERO route to Internet Gateway (Strictly unreachable from internet)       |
|       - Security group ONLY accepts connections from Tier 2 Application SG        |
|       - Encrypted at rest using AWS KMS                                           |
+===================================================================================+
```

---

## 3. Detailed Architecture Diagram

```mermaid
flowchart TD
    subgraph Clients ["Public Users & CI/CD"]
        User["User Browser\n(HTTP:80 / HTTPS:443)"]
        GH["GitHub Actions\n(CI/CD Pipeline)"]
    end

    subgraph AWS_Cloud ["AWS Cloud (us-east-1)"]
        subgraph VPC ["Custom Amazon VPC: 10.0.0.0/16"]
            IGW["Internet Gateway (IGW)"]

            subgraph Public_Tier ["Tier 1: Public Subnets (AZ-a & AZ-b)"]
                ALB["Application Load Balancer\n(devops-assignment-alb)\nHTTP:80 & HTTPS:443 (ACM)"]
                NAT["Free-Tier NAT Instance\n(t3.micro - $0.00)\nnftables & iptables forwarding"]
            end

            subgraph App_Tier ["Tier 2: Private App Subnets (AZ-a & AZ-b)"]
                ASG["EC2 Auto Scaling Group\n(devops-assignment-asg)\nAmazon Linux 2023 | Node.js App"]
            end

            subgraph DB_Tier ["Tier 3: Private DB Subnets (AZ-a & AZ-b)"]
                RDS[("Amazon RDS MySQL 8.0\n(devops-assignment-mysql)\nPort: 3306 | gp3 20GB")]
            end

            subgraph AWS_Managed ["AWS Managed Security & Storage Services"]
                SM["AWS Secrets Manager\n(DB Credentials Secret)"]
                S3_App["Amazon S3 App Bucket\n(app-storage)"]
                S3_Logs["Amazon S3 Logs Bucket\n(alb-access-logs)"]
            end
        end
    end

    User -->|HTTP:80 & HTTPS:443| ALB
    GH -->|Terraform Plan / Apply| VPC
    ALB -->|Target Group Health Check: /health| ASG
    ALB -.->|Access Logs| S3_Logs
    ASG -->|Port 3306 (Private)| RDS
    ASG -->|IAM Role: GetSecretValue| SM
    ASG -->|IAM Role: PutObject / GetObject| S3_App
    ASG -->|Outbound Internet / Updates| NAT
    NAT --> IGW
    IGW -->|Internet| AWS_Cloud
```

---

## 4. HTTPS (SSL/TLS) Deep-Dive: Why Does the Browser Show a Warning?

### The Question: "Why does HTTPS show a certificate warning?"
When opening `https://devops-assignment-alb-xxxxxxxxxx.us-east-1.elb.amazonaws.com` in Google Chrome or Microsoft Edge, you will see:
> **"Your connection is not private"** (`NET::ERR_CERT_AUTHORITY_INVALID` or `NET::ERR_CERT_COMMON_NAME_INVALID`)

### The Technical Explanation (Crucial for Interviews):
1. **AWS Domain Ownership Rules:**
   - AWS owns the root domain `*.elb.amazonaws.com`.
   - AWS Certificate Manager (ACM) will **never** issue a public, trusted SSL certificate for Amazon's own domain name to a customer account. Public ACM certificates require DNS validation via a domain that *you* own (e.g., `mycompany.com`).
2. **Project Constraint:**
   - Per the assignment instructions, you do **not** own a custom domain and requested a dummy domain (`app.devops-assignment.internal`) with **zero paid infrastructure** (avoiding Route53 hosted zone fees).
3. **How We Satisfied the HTTPS Requirement:**
   - We used Terraform's `tls` provider to generate a cryptographic 2048-bit RSA private key and self-signed X.509 certificate.
   - We automatically imported that certificate into **AWS Certificate Manager (ACM)**.
   - We attached the ACM certificate to the ALB's **HTTPS:443 listener**.
4. **Why Browsers Flag It:**
   - Modern browsers trust only certificates issued by pre-installed root Certificate Authorities (like DigiCert, Let's Encrypt).
   - Because our certificate is self-signed, the browser encrypts the session with TLS, but warns you that the root CA is not in its trusted store.
5. **How to Test HTTPS:**
   - **In Browser:** Click **"Advanced"** → **"Proceed to devops-assignment-alb... (unsafe)"**. The page will load over HTTPS (Port 443)!
   - **In Terminal:** Run `curl.exe -k https://<alb_dns>/health` (the `-k` flag accepts self-signed certificates). It will return `HTTP 200 {"status":"healthy"}`.
   - **For Zero Warnings:** Use the standard HTTP endpoint: `http://<alb_dns>`.
6. **How This Translates to Enterprise Production:**
   - In a production environment, you purchase a domain or point an existing domain in **Amazon Route 53** (e.g., `app.mycompany.com`).
   - You request a 100% free public ACM certificate with DNS validation.
   - You create an `Alias (A)` record in Route 53 pointing to the ALB.
   - The browser shows the familiar green padlock with zero warnings!

---

## 5. Network Segmentation & Subnet Breakdown

The custom VPC (`10.0.0.0/16`) spans two Availability Zones (`us-east-1a` and `us-east-1b`) with strict subnet isolation:

| Subnet Name | AZ | CIDR Block | Tier | Purpose | Internet Routing |
| :--- | :--- | :--- | :--- | :--- | :--- |
| `devops-assignment-public-subnet-1` | `us-east-1a` | `10.0.1.0/24` | Tier 1 | ALB Public Interface & Free-Tier NAT Instance | Direct route to Internet Gateway (`0.0.0.0/0 -> igw`) |
| `devops-assignment-public-subnet-2` | `us-east-1b` | `10.0.2.0/24` | Tier 1 | ALB Secondary Interface (Multi-AZ HA) | Direct route to Internet Gateway (`0.0.0.0/0 -> igw`) |
| `devops-assignment-private-app-subnet-1` | `us-east-1a` | `10.0.11.0/24` | Tier 2 | EC2 Auto Scaling App Instances | Outbound only via NAT Instance (`0.0.0.0/0 -> nat-instance-eni`) |
| `devops-assignment-private-app-subnet-2` | `us-east-1b` | `10.0.12.0/24` | Tier 2 | EC2 Auto Scaling App Instances | Outbound only via NAT Instance (`0.0.0.0/0 -> nat-instance-eni`) |
| `devops-assignment-private-db-subnet-1` | `us-east-1a` | `10.0.21.0/24` | Tier 3 | Amazon RDS MySQL Primary | Strictly Local VPC (`10.0.0.0/16`) - NO INTERNET ROUTE |
| `devops-assignment-private-db-subnet-2` | `us-east-1b` | `10.0.22.0/24` | Tier 3 | Amazon RDS MySQL Subnet Group Secondary | Strictly Local VPC (`10.0.0.0/16`) - NO INTERNET ROUTE |

---

## 6. FinOps & 100% Free Tier Optimization ($0.00 Guarantee)

| Service | Enterprise Cloud Trap | Our Free-Tier Solution | Monthly Cost |
| :--- | :--- | :--- | :--- |
| **NAT Gateway** | AWS Managed NAT Gateway costs ~$32.40/mo per AZ + $0.045/GB data fees | Custom `t3.micro` EC2 NAT instance running native `nftables` & `iptables` IP forwarding | **$0.00** |
| **EC2 Compute** | Exceeding 750 free hours/month | Auto Scaling Group configured with `min=1`, `desired=1`, `max=2` on `t3.micro` | **$0.00** |
| **RDS MySQL** | Multi-AZ standby instances incur charges | Single-AZ `db.t3.micro` MySQL 8.0 with 20 GB gp3 storage | **$0.00** |
| **SSL Certificate** | Domain registrar fees & Route53 hosted zone costs ($0.50/mo) | Generated 2048-bit RSA TLS cert imported directly into AWS Certificate Manager | **$0.00** |
| **S3 Storage** | Unbounded log accumulation | App storage bucket + ALB access logs bucket with 14-day auto-expiration lifecycle rules | **$0.00** |
| **Secrets Manager** | $0.40 per secret per month | Fully covered under AWS 30-day Free Trial with zero-day recovery deletion on teardown | **$0.00** |

---

## 7. Security Architecture: Defense-in-Depth

### 1. Security Group Chaining (Least-Privilege Firewalls)
```
[ Public Internet ]
       |
       |  Inbound TCP 80 & 443
       v
+-------------------------------+
|     ALB Security Group        |
+-------------------------------+
       |
       |  Inbound TCP 80 ONLY from ALB-SG (Source SG referenced)
       v
+-------------------------------+
|     App Security Group        |
+-------------------------------+
       |
       |  Inbound TCP 3306 ONLY from App-SG (Source SG referenced)
       v
+-------------------------------+
|     RDS Security Group        |
+-------------------------------+
```

### 2. IAM Instance Profile & Least-Privilege Policy
- EC2 instances do **not** use static AWS access keys or passwords.
- The attached IAM Role grants:
  - `secretsmanager:GetSecretValue` on the specific MySQL secret ARN.
  - `s3:GetObject` and `s3:PutObject` on the application bucket ARN.
  - `AmazonSSMManagedInstanceCore` for secure terminal management via AWS Systems Manager without opening port 22 (SSH).

### 3. IMDSv2 (Instance Metadata Service v2)
- Enforces session tokens with `http_tokens = "required"` and `http_put_response_hop_limit = 2`.
- Prevents Server-Side Request Forgery (SSRF) vulnerabilities from harvesting instance profile credentials.

---

## 8. CI/CD Pipeline Workflow (GitHub Actions)

The repository includes a 4-stage automated pipeline at `.github/workflows/terraform.yml`:

1. **Lint & Validate (Automated on all PRs and pushes):**
   - Runs `terraform fmt -check` to enforce styling standards.
   - Runs `terraform validate` to verify syntax and provider references.
   - Runs **Aqua Security Trivy** to perform security and vulnerability scanning on Terraform IaC.
2. **Terraform Plan (Automated on Pull Requests):**
   - Authenticates to AWS via GitHub Secrets (`AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY`).
   - Runs `terraform plan` against the persistent remote S3 state backend and posts the plan summary.
3. **Terraform Apply (Automated on Merge to `main`):**
   - Automatically provisions and updates infrastructure changes with zero manual intervention.
   - Publishes live endpoint outputs to the GitHub Actions Job Summary.
4. **Terraform Destroy (Manual Trigger via `workflow_dispatch`):**
   - Provides a one-click teardown action directly in GitHub Actions to completely destroy all cloud resources and prevent unnecessary cloud costs.

---

## 9. Interview Cheat Sheet: Questions You Might Be Asked

### Q1: "Why did you use an EC2 NAT instance instead of AWS Managed NAT Gateway?"
> **Answer:** "In an enterprise environment, AWS Managed NAT Gateway is preferred for high availability and automatic scaling up to 100 Gbps. However, for an assignment or development environment, a NAT Gateway costs ~$32.40/month per AZ even with zero traffic. To respect the AWS Free Tier constraint and achieve a $0.00 infrastructure bill, I implemented a `t3.micro` Free-Tier NAT instance with Linux IP forwarding and masquerading. I also engineered the Terraform module with an `enable_nat_gateway` boolean variable so the entire architecture can toggle to an enterprise NAT Gateway with a single line change."

### Q2: "How did you handle database credentials securely?"
> **Answer:** "I avoided hardcoding passwords in `.tfvars` or git commits. Instead, I used Terraform's `random_password` provider to generate a cryptographically secure 16-character string, stored it as a JSON payload in AWS Secrets Manager, and configured an IAM Instance Profile on the EC2 instances. The Node.js application dynamically queries Secrets Manager on boot using the AWS SDK, connects to MySQL, and never logs cleartext secrets."

### Q3: "How does HTTPS work without a registered domain?"
> **Answer:** "AWS ALB requires an ACM certificate to terminate SSL on port 443. Because AWS does not allow public ACM certificates for `*.elb.amazonaws.com` without DNS validation on an owned domain, I generated a 2048-bit RSA self-signed TLS certificate in Terraform and imported it into ACM. While browsers flag self-signed certificates as untrusted, the ALB listener successfully terminates TLS traffic on port 443. In production, we would simply configure a Route 53 Hosted Zone and request a free public ACM certificate with DNS validation."

### Q4: "How is the architecture protected against network attacks?"
> **Answer:** "We use defense-in-depth:
> 1. Multi-tier subnet isolation: Only the ALB and NAT instance reside in public subnets. EC2 app instances and RDS MySQL have no public IPs and sit in private subnets.
> 2. Security group chaining: The App security group only accepts port 80 from the ALB security group, and RDS only accepts port 3306 from the App security group.
> 3. IMDSv2 is enforced on all instances to prevent SSRF credential theft.
> 4. SSH port 22 is completely closed; secure management is handled via AWS SSM Session Manager."
