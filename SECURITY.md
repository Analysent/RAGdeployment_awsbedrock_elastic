# Security Policy

## Reporting a vulnerability

If you discover a security vulnerability in this project, please **do not** open a public GitHub issue.

Instead, report it privately via GitHub's Security Advisory feature:
- Go to **Security → Report a vulnerability** in this repository.

We will respond within 5 business days and work with you on a coordinated disclosure.

---

## Sensitive data — what belongs in this repo and what does not

### NEVER commit to version control

| Data type | Where it belongs |
|---|---|
| Elastic Cloud API key (`EC_API_KEY`) | Shell environment variable only |
| Elasticsearch username / password | AWS Secrets Manager |
| AWS access key / secret key | `~/.aws/credentials` or IAM role |
| Terraform state files (`*.tfstate`) | Remote backend (S3 + DynamoDB lock) |
| Your `terraform.tfvars` file | Local filesystem only — excluded by `.gitignore` |
| VPC CIDR ranges, subnet IDs, Account IDs | `terraform.tfvars` (local only) |
| Elastic deployment ID | `terraform.tfvars` (local only) |
| Elastic PrivateLink service name | `terraform.tfvars` (local only) |

### Safe to commit

| File | Why it is safe |
|---|---|
| `terraform.tfvars.example` | Contains only `<PLACEHOLDER>` tokens — no real values |
| `variables.tf` | Declares variable types and descriptions — no real values |
| `*.tf` modules | Infrastructure logic only — all sensitive values come from variables |
| Python handler code | Reads secrets at runtime from Secrets Manager — nothing hardcoded |
| `Dockerfile` / `requirements.txt` | Public base images and open-source packages only |

---

## Before opening a pull request

Run the following checks locally to catch accidental credential exposure:

```bash
# Install gitleaks (https://github.com/gitleaks/gitleaks)
brew install gitleaks         # macOS
# or: go install github.com/zricethezav/gitleaks/v8@latest

# Scan the repository for leaked secrets
gitleaks detect --source . --verbose

# Scan only staged changes before committing
gitleaks protect --staged
```

Alternatively, enable **GitHub secret scanning** in your repository settings — it will alert you automatically when a known secret pattern is pushed.

---

## Runtime security measures in this project

| Measure | Implementation |
|---|---|
| No hardcoded secrets | All credentials read from AWS Secrets Manager at Lambda startup |
| Least-privilege IAM | Each Lambda role grants only the Bedrock models and secrets it needs |
| VPC isolation | Lambdas run inside a private VPC; Elastic reachable only via PrivateLink |
| S3 private access | Bucket policy denies all access except from the S3 VPC Gateway Endpoint |
| Encryption at rest | S3 bucket encrypted with `aws:kms`; Secrets Manager encrypted by default |
| No public Elastic endpoint | PrivateLink + Route53 private zone — Elasticsearch not exposed to internet |
| Container image scanning | ECR scan-on-push enabled for both Lambda repositories |
