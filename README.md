# RAG Conversational Agent — Elastic Cloud + Amazon Bedrock + AWS Lambda

End-to-end Terraform solution for deploying a Retrieval Augmented Generation (RAG) pipeline that:

1. **Ingests** documents uploaded to S3 → auto-triggers a Lambda vectorizer
2. **Embeds** content using Amazon Bedrock Titan Embeddings and stores vectors in Elastic Cloud
3. **Answers** questions via an API Gateway endpoint backed by a RAG Lambda agent

---

## Architecture

```
User
 │  POST /agent {"question": "..."}
 ▼
API Gateway (HTTP API)

Lambda Agent (RAG)
 ├─► Elastic Cloud (PrivateLink) ── similarity search ──► top-k chunks
 └─► Amazon Bedrock (Titan LLM) ── generates answer with context
                    ▲
                    │ (embeddings)
             Lambda Vectorizer ◄── S3 ObjectCreated trigger
                    │
             Amazon Bedrock (Titan Embeddings)
                    │
             S3 Bucket (your documents)

All Lambdas run inside a private VPC:
  • Elastic Cloud reachable via AWS PrivateLink (no public internet)
  • Amazon Bedrock reachable via NAT Gateway
  • S3 reachable via S3 Gateway VPC Endpoint (free, no data charges)
```

## Module structure

```
.
├── main.tf                       # Root: wires all modules together
├── variables.tf                  # Input variable declarations
├── outputs.tf                    # Deployment outputs (bucket name, API URL)
├── providers.tf                  # AWS + Elastic Stack providers
├── terraform.tfvars.example      # Template — copy to terraform.tfvars
└── modules/
    ├── vpc/                      # VPC, subnets, IGW, NAT GWs, route tables
    ├── data_source/              # S3 bucket, S3 VPC Gateway Endpoint, bucket policy
    ├── private_link/             # Elastic PrivateLink VPC Endpoint + Route53 private zone
    ├── lambda_vectorizer/        # ECR + Lambda + S3 trigger → generates + stores embeddings
    │   └── docker/
    │       ├── Dockerfile
    │       ├── requirements.txt
    │       └── handler.py        # LangChain + PyPDF + Bedrock embeddings → Elastic
    ├── lambda_agent/             # ECR + Lambda → RAG agent (retrieval + LLM generation)
    │   └── docker/
    │       ├── Dockerfile
    │       ├── requirements.txt
    │       └── handler.py        # LangChain retriever + Bedrock Titan LLM
    └── api_gateway/              # HTTP API GW → Lambda Agent integration
```

---

## Prerequisites

| Requirement | Notes |
|---|---|
| **Terraform ≥ 1.10** | [Install guide](https://developer.hashicorp.com/terraform/install) |
| **AWS CLI** | Configured with sufficient IAM permissions |
| **Docker** | Used to build and push Lambda container images |
| **Elastic Cloud account** | Via [AWS Marketplace free trial](https://aws.amazon.com/marketplace/pp/prodview-voru33wi6xs7k) |
| **Bedrock model access** | Request access to `amazon.titan-embed-text-v2:0` and `amazon.titan-text-express-v1` in the Bedrock console |
| **EC_API_KEY** | Elastic Cloud API key — set as environment variable |

### 1. Elastic Cloud setup

1. Subscribe to **Elastic Cloud** in AWS Marketplace and complete Quick Launch.
2. Note your **Deployment ID** (visible in the Elastic Cloud Console URL and overview page).
3. Note your **Elasticsearch endpoint** (e.g. `https://<id>.us-east-1.aws.elastic-cloud.com:9243`).
4. Enable **PrivateLink** for your deployment and note the **service name** (format: `com.amazonaws.vpce.<region>.vpce-svc-<id>`).
5. Generate an **API key** and export it:
   ```bash
   export EC_API_KEY="your-elastic-cloud-api-key"
   ```

### 2. AWS Secrets Manager

Create a secret containing your Elastic deployment credentials:

```bash
aws secretsmanager create-secret \
  --name "elastic/deployment/credentials" \
  --secret-string '{"username":"elastic","password":"<your-password>"}'
```

---

## Deployment

```bash
# 1. Clone the repository
git clone <this-repo>
cd <repo-directory>

# 2. Create your tfvars file
cp terraform.tfvars.example terraform.tfvars
# Edit terraform.tfvars with your values

# 3. Initialise Terraform
terraform init

# 4. Review the plan
terraform plan

# 5. Deploy (builds Docker images, creates all AWS resources)
terraform apply
```

Terraform will output:

| Output | Description |
|---|---|
| `bucket_name` | S3 bucket — upload documents here |
| `invoke_url` | API Gateway base URL |
| `agent_endpoint` | Full URL for the RAG agent (`<base>/agent`) |
| `example_curl` | Ready-to-run cURL command |

---

## Using the solution

### Upload a document

```bash
aws s3 cp your-document.pdf s3://<bucket_name>/
```

The Lambda vectorizer fires automatically, chunks the document, generates Titan embeddings and stores them in Elasticsearch index `documents`.

### Ask a question

```bash
curl -X POST https://<invoke_url>/agent \
  -H "Content-Type: application/json" \
  -d '{"question": "What is cloud-native DevOps?"}'
```

Response:

```json
{
  "question": "What is cloud-native DevOps?",
  "answer": "Cloud-native DevOps is ...",
  "sources": ["your-document.pdf"]
}
```

### Monitor vectorizer execution

```bash
aws logs tail /aws/lambda/rag-elastic-vectorizer --follow
```

```bash
aws logs tail /aws/lambda/rag-elastic-agent --follow
```

---

## Configuration reference

| Variable | Default | Description |
|---|---|---|
| `aws_region` | `us-east-1` | AWS region |
| `deployment_id` | *(required)* | Elastic Cloud deployment ID |
| `elasticsearch_endpoint` | *(required)* | Elastic HTTPS endpoint |
| `elasticsearch_connection_secret` | *(required)* | Secrets Manager secret name |
| `elastic_private_link_service_name` | *(required)* | PrivateLink endpoint service name |
| `elastic_private_link_zone_name` | `us-east-1.aws.elastic-cloud.com` | PrivateLink DNS zone |
| `elastic_index_name` | `documents` | Elasticsearch index for vectors |
| `bedrock_embedding_model_id` | `amazon.titan-embed-text-v2:0` | Bedrock embeddings model |
| `bedrock_llm_model_id` | `amazon.titan-text-express-v1` | Bedrock LLM model |
| `lambda_memory_size` | `1024` | Lambda memory (MB) |
| `lambda_timeout` | `300` | Lambda timeout (seconds) |
| `vectorizer_chunk_size` | `1000` | Characters per document chunk |
| `vectorizer_chunk_overlap` | `200` | Character overlap between chunks |

---

## Supported document types

| Extension | Parser |
|---|---|
| `.pdf` | PyPDF |
| `.docx` | python-docx |
| `.txt`, `.md`, `.rst` | Plain text |
| `.html`, `.htm` | Plain text (HTML) |

---

## Troubleshooting

| Symptom | Resolution |
|---|---|
| "Internal Server Error" on multiple consecutive questions | Amazon Bedrock rate limit — request quota increase in the Service Quotas console |
| Vectorizer Lambda times out on large PDFs | Increase `lambda_timeout` (max 900s) or reduce `vectorizer_chunk_size` |
| No index appears in Elastic | Check CloudWatch logs for the vectorizer Lambda; confirm PrivateLink DNS resolves correctly |
| 403 from Elasticsearch | Verify `elasticsearch_connection_secret` secret keys are `username` and `password` |
| Docker build fails during `terraform apply` | Ensure Docker daemon is running and you have write access to ECR |

---

## Teardown

```bash
terraform destroy
```

> **Note:** The S3 bucket has `force_destroy = false` to prevent accidental data loss. Empty the bucket manually before running `terraform destroy`.

---

## Security considerations

- S3 bucket is private and only accessible from within the VPC via the S3 Gateway Endpoint.
- Elastic Cloud is only reachable from within the VPC via PrivateLink — no public internet exposure.
- Lambda IAM roles follow least-privilege (only the Bedrock models and secrets they need).
- All data at rest in S3 is encrypted with AWS KMS (`aws:kms`).
- Secrets are stored in AWS Secrets Manager — never in environment variables or Terraform state.
