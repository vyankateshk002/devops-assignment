# DevOps Practical Task – AWS Infrastructure & CI/CD

[![Terraform CI/CD Pipeline](https://img.shields.io/badge/CI%2FCD-GitHub%20Actions-blue?logo=github-actions)](.github/workflows/terraform.yml)
[![Infrastructure as Code](https://img.shields.io/badge/IaC-Terraform%20v1.10%2B-purple?logo=terraform)](terraform/)
[![AWS Free Tier](https://img.shields.io/badge/AWS-Free%20Tier%20Compliant-orange?logo=amazon-aws)](docs/ARCHITECTURE.md#3-cost-optimization-strategy-aws-free-tier-compliance)
[![License](https://img.shields.io/badge/License-MIT-green.svg)](LICENSE)

An enterprise-grade, highly available **3-Tier Web Application Infrastructure** on Amazon Web Services (AWS), provisioned using **Terraform** and automated via a **GitHub Actions CI/CD Pipeline**.

This implementation was specifically engineered for **100% AWS Free Tier compliance ($0.00 operational cost)** while adhering strictly to AWS Well-Architected and Security Best Practices.

---

## 🏛️ High-Level Architecture

```mermaid
flowchart TD
    subgraph Internet ["Public Internet"]
        Users["Users (HTTPS:443 / HTTP:80)"]
        GitHub["GitHub Actions (CI/CD Pipeline)"]
    end

    subgraph AWS_VPC ["Amazon VPC (10.0.0.0/16) - High Availability Across 2 AZs"]
        IGW["Internet Gateway"]
        
        subgraph Public_Subnets ["Public Subnets (us-east-1a & us-east-1b)"]
            ALB["Application Load Balancer (HTTPS / ACM Cert)"]
            NAT["Free-Tier NAT Instance (t3.micro / $0.00)"]
        end

        subgraph Private_App_Subnets ["Private App Subnets (us-east-1a & us-east-1b)"]
            ASG["Auto Scaling Group (EC2 t3.micro)"]
            App["Node.js 3-Tier Web App (Port 80)"]
        end

        subgraph Private_DB_Subnets ["Private DB Subnets (us-east-1a & us-east-1b)"]
            RDS[("Amazon RDS MySQL 8.0 (db.t3.micro)")]
        end

        SM["AWS Secrets Manager (DB Credentials)"]
        S3_App["Amazon S3 (App Storage Bucket)"]
        S3_Logs["Amazon S3 (ALB Access Logs Bucket)"]
    end

    Users -->|HTTPS:443 (ACM)| ALB
    Users -->|HTTP:80| ALB
    ALB -->|Target Group / Health Check: /health| ASG
    ASG --- App
    App -->|Port 3306 (Private)| RDS
    App -->|IAM Instance Profile| SM
    App -->|IAM Instance Profile| S3_App
    ALB -->|Access Logging| S3_Logs
    ASG -->|Outbound Package Updates| NAT
    NAT --> IGW
    GitHub -->|Terraform Plan / Apply| AWS_VPC
```

---

## 📋 Scope & Features Implemented

| Category | Component | Description |
| :--- | :--- | :--- |
| **Networking** | **VPC & Subnets** | Custom VPC (`10.0.0.0/16`) spanning 2 AZs with 6 subnets (2 Public, 2 Private App, 2 Private DB). |
| **Networking** | **Routing & Gateways** | Internet Gateway for public ingress/egress; strictly isolated route table for database subnets. |
| **FinOps / Cost** | **Free-Tier NAT** | Implemented a `t3.micro` NAT instance with iptables forwarding ($0.00 cost) avoiding the $32.40/mo AWS NAT Gateway fee. |
| **Compute** | **EC2 ASG & Launch Template** | Amazon Linux 2023 `t3.micro` instances with systemd service bootstrap, IMDSv2 enforcement, and CPU Target Tracking. |
| **Load Balancing** | **ALB & ACM HTTPS** | Application Load Balancer with HTTP (port 80) and HTTPS (port 443) listeners using an AWS Certificate Manager (ACM) SSL certificate. |
| **Database** | **RDS MySQL 8.0** | `db.t3.micro` Single-AZ with 20GB gp3 storage deployed in isolated private subnets with encryption at rest. |
| **Security** | **Secrets Manager** | Dynamic master password generation with JSON storage in Secrets Manager; zero cleartext passwords in git. |
| **Security** | **Security Groups & IAM** | Strict least-privilege chaining (ALB -> App -> RDS) with IAM Instance Profile for S3 and Secrets Manager. |
| **Storage** | **Amazon S3** | Two encrypted S3 buckets: one for application storage, one for ALB HTTP/HTTPS access logs with lifecycle expiration. |
| **Automation** | **GitHub Actions CI/CD** | Full pipeline: linting, validation, Trivy security scanning, automated plan on PR, auto-apply on merge, and teardown dispatch. |

---

## 💰 AWS Free Tier Compliance (Zero Cost Strategy)

| AWS Resource | Standard Cost Trap | Our Free-Tier Safe Implementation | Monthly Cost |
| :--- | :--- | :--- | :--- |
| **NAT Gateway** | ~$32.40/mo per NAT GW | **Free-Tier EC2 NAT Instance (`t3.micro`)** with iptables masquerading | **$0.00** |
| **EC2 Compute** | Exceeding 750 hrs | `t3.micro` instances (`min=1`, `desired=1`, `max=2`) within 750 free hours/month | **$0.00** |
| **RDS MySQL** | Multi-AZ charges | `db.t3.micro` Single-AZ with 20GB gp3 storage within 750 free hours/month | **$0.00** |
| **ACM SSL Cert** | Paid domain verification | Self-signed RSA certificate imported directly into **AWS Certificate Manager** | **$0.00** |
| **S3 Buckets** | Growth over time | App storage bucket + ALB logs with 14-day auto-cleanup lifecycle rule | **$0.00** |
| **Secrets Manager** | $0.40/secret/mo | Covered under AWS 30-day Free Trial with zero-day recovery window on destroy | **$0.00** |

---

## 📁 Repository Structure

```
.
├── .github/
│   └── workflows/
│       └── terraform.yml          # GitHub Actions CI/CD Pipeline (Validate, Plan, Apply, Destroy)
├── app/                           # Production 3-Tier Web Application
│   ├── public/
│   │   ├── index.html             # Responsive Dark-Mode System Dashboard
│   │   └── style.css              # Custom Modern CSS
│   ├── Dockerfile                 # Multi-stage production container build
│   ├── package.json               # Node.js dependencies
│   └── server.js                  # Express.js server (RDS pool, S3 uploads, Secrets Manager, /health)
├── docs/
│   ├── ARCHITECTURE.md            # Detailed Architecture & Security Documentation
│   └── DEPLOYMENT.md              # Step-by-Step Local & CI/CD Deployment Guide
├── terraform/
│   ├── modules/
│   │   ├── alb/                   # ALB, Target Group, ACM HTTPS Listener, Access Logs
│   │   ├── asg/                   # Launch Template, Auto Scaling Group, User Data
│   │   ├── rds/                   # RDS MySQL 8.0, Subnet Group, Secrets Manager
│   │   ├── s3/                    # App Bucket & ALB Access Logs Bucket
│   │   ├── security/              # Least-Privilege SGs, IAM Roles & Instance Profile
│   │   └── vpc/                   # VPC, Subnets, Route Tables, IGW, Free-Tier NAT
│   ├── main.tf                    # Root Module Wiring
│   ├── outputs.tf                 # Public URLs, ALB DNS, and Resource Endpoints
│   ├── variables.tf               # Root Variables with Free-Tier Defaults
│   ├── versions.tf                # Provider Versions & Profile Configuration
│   └── terraform.tfvars.example   # Example Variable Overrides
├── .gitignore                     # Rigorous security rules ignoring credentials & tfstate
└── README.md
```

---

## 🚀 Quick Start & Deployment

### 1. Configure Dedicated AWS Profile
To ensure your default local AWS configuration remains completely untouched, configure the named profile:

```powershell
aws configure --profile assignment-access-key
```

Verify profile authentication:
```powershell
aws sts get-caller-identity --profile assignment-access-key
```

### 2. Deploy via Terraform

```powershell
cd terraform
terraform init
terraform validate
terraform plan
terraform apply -auto-approve
```

### 3. Verify Deployment
Once `apply` finishes, Terraform displays the live endpoints:

```text
Outputs:

alb_public_dns        = "devops-assignment-alb-xxxxxxxxxx.us-east-1.elb.amazonaws.com"
http_application_url  = "http://devops-assignment-alb-xxxxxxxxxx.us-east-1.elb.amazonaws.com"
https_application_url = "https://devops-assignment-alb-xxxxxxxxxx.us-east-1.elb.amazonaws.com"
health_check_url      = "http://devops-assignment-alb-xxxxxxxxxx.us-east-1.elb.amazonaws.com/health"
rds_endpoint          = "devops-assignment-mysql.xxxxxxxxxx.us-east-1.rds.amazonaws.com:3306"
```

1. **Health Check:** `curl http://<alb_public_dns>/health` (Returns HTTP 200 OK with DB and S3 health)
2. **HTTPS Access:** Open `https://<alb_public_dns>` in your browser (Terminates SSL via ACM Certificate)
3. **Dashboard & Database Verification:** Open `http://<alb_public_dns>` to interact with live MySQL CRUD operations and test S3 uploads.

### 4. Automated CI/CD via GitHub Actions
1. Push this repository to GitHub.
2. In your GitHub repository, go to **Settings > Secrets and variables > Actions** and add:
   - `AWS_ACCESS_KEY_ID`
   - `AWS_SECRET_ACCESS_KEY`
3. Opening a Pull Request automatically runs validation, linting, and `terraform plan`.
4. Merging to `main` automatically applies the changes to AWS.

### 5. Clean Teardown (Zero-Cost Guarantee)
To avoid any charges after demoing or taking screenshots:
```powershell
terraform destroy -auto-approve
```

---

## 🛡️ Security Highlights

1. **Database Isolation:** RDS MySQL is placed in private database subnets with no public IP, no route to the Internet Gateway, and only accepts connections from the application security group on port 3306.
2. **Credential Safety:** Database credentials are generated dynamically using cryptographic randomness and stored in AWS Secrets Manager. EC2 instances retrieve them at runtime using IAM role authentication.
3. **IMDSv2 Enforced:** Instance Metadata Service v2 is enforced on all EC2 instances (`http_tokens = "required"`), protecting against SSRF attacks.
4. **Access Logging:** ALB access logs are recorded to a dedicated, encrypted S3 bucket for security auditing.
