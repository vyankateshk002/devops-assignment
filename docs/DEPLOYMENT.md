# DevOps Assignment: Deployment & Execution Guide

This document provides a step-by-step walkthrough to deploy, validate, and tear down the 3-Tier AWS Infrastructure using both **Local CLI** and **GitHub Actions CI/CD**.

---

## 1. Prerequisites

- **AWS Free Tier Account**
- **Terraform v1.5+** (`terraform -version`)
- **AWS CLI v2** (`aws --version`)
- **Git** (`git --version`)

---

## 2. Setting Up AWS Credentials 

### Step 1: Configure Named Profile
Run the following commands in PowerShell or Terminal:
```powershell
aws configure --profile assignment-access-key
```
When prompted, provide:
- **AWS Access Key ID:** ``
- **AWS Secret Access Key:** `
- **Default region name:** `us-east-1`
- **Default output format:** `json`

### Step 2: Verify Profile Connectivity
```powershell
aws sts get-caller-identity --profile assignment-access-key
```
You should see:
```json
```

---

## 3. Local Deployment via Terraform

### Step 1: Navigate to the Terraform Directory
```powershell
cd terraform
```

### Step 2: Initialize Terraform
```powershell
terraform init
```

### Step 3: Validate Configuration & Formatting
```powershell
terraform fmt -check
terraform validate
```

### Step 4: Preview Infrastructure Execution (Plan)
```powershell
terraform plan
```
> [!NOTE]
> By default, `enable_nat_instance = true` and `enable_nat_gateway = false`. This spins up a `t3.micro` NAT instance instead of a paid NAT Gateway, keeping your deployment **100% Free-Tier compliant ($0.00)**.

### Step 5: Deploy the Infrastructure (Apply)
```powershell
terraform apply -auto-approve
```
*Deployment takes approximately 6-8 minutes (primarily for RDS MySQL provisioning and ALB health checks).*

---

## 4. Validating the Deployment

Once `terraform apply` finishes, Terraform will output the public endpoints:

```text
Outputs:

acm_certificate_arn         = "arn:aws:acm:us-east-1:919519434135:certificate/..."
alb_public_dns              = "devops-assignment-alb-123456789.us-east-1.elb.amazonaws.com"
health_check_url            = "http://devops-assignment-alb-123456789.us-east-1.elb.amazonaws.com/health"
http_application_url        = "http://devops-assignment-alb-123456789.us-east-1.elb.amazonaws.com"
https_application_url       = "https://devops-assignment-alb-123456789.us-east-1.elb.amazonaws.com"
nat_strategy                = "100% Free-Tier EC2 NAT Instance (t3.micro - $0.00)"
rds_endpoint                = "devops-assignment-mysql.cr123456789.us-east-1.rds.amazonaws.com:3306"
s3_alb_access_logs_bucket   = "devops-assignment-alb-logs-abc123"
s3_app_storage_bucket       = "devops-assignment-app-storage-abc123"
secrets_manager_secret_name = "devops-assignment-db-secret-mysql"
```

### Testing the Endpoints:

#### 1. Test Application Health Check (`/health`)
```powershell
curl http://<alb_public_dns>/health
```
**Expected Response (HTTP 200 OK):**
```json
{
  "status": "healthy",
  "uptime": 124.5,
  "timestamp": "2026-10-07T08:00:00.000Z",
  "database": "connected",
  "s3Bucket": "devops-assignment-app-storage-abc123",
  "secretsManager": "devops-assignment-db-secret-mysql"
}
```

#### 2. Test HTTPS with ACM Certificate
```powershell
curl -k https://<alb_public_dns>/health
```
*(The `-k` flag allows accepting self-signed certificates in cURL. In a browser, proceed past the certificate warning to view the working HTTPS dashboard).*

#### 3. Test Web Dashboard & RDS MySQL
Open `http://<alb_public_dns>` in your web browser:
- Review the **EC2 Instance ID & Availability Zone**
- Confirm the **RDS MySQL status is green ("Connected")**
- Use the **Insert Record** form to add a new note. Refresh to confirm persistence in MySQL!
- Click **Test S3 PutObject** to verify IAM Instance Profile permissions against Amazon S3!

---

## 5. Automated CI/CD Deployment via GitHub Actions

This repository includes a production-grade CI/CD pipeline at `.github/workflows/terraform.yml`.

### Step 1: Configure GitHub Repository Secrets
In your GitHub Repository, navigate to **Settings > Secrets and variables > Actions > New repository secret**:
1. `AWS_ACCESS_KEY_ID`: `<Your Access Key ID>`
2. `AWS_SECRET_ACCESS_KEY`: `<Your Secret Access Key>`

### Step 2: Automated Workflow Triggers
- **Pull Request to `main`:** Runs `terraform fmt`, `terraform validate`, security scans with Trivy, and outputs a detailed `terraform plan`.
- **Merge to `main`:** Automatically deploys the changes to AWS with `terraform apply`.
- **Manual Trigger (`workflow_dispatch`):** Allows selecting **Plan**, **Apply**, or **Destroy** directly from the GitHub Actions UI.

---

## 6. Clean Teardown (Destroying Infrastructure)

To ensure **zero lingering cloud costs**, tear down all resources when you have finished taking screenshots and recording your demo:

```powershell
terraform destroy -auto-approve
```
This safely deletes:
- The Auto Scaling Group & Launch Template
- The Application Load Balancer, Target Groups & ACM Certificate
- The RDS MySQL database (skipping final snapshot)
- The S3 buckets (app storage and logs)
- The Free-Tier NAT instance, VPC, Subnets, and Security Groups
