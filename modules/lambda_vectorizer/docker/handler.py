"""
Lambda Vectorizer Handler
-------------------------
Triggered by S3 ObjectCreated events. Downloads the uploaded document,
splits it into chunks, generates vector embeddings via Amazon Bedrock
Titan Embeddings, and stores them in an Elasticsearch index.

Supported file types: PDF, TXT, DOCX, HTML/HTM
"""

from __future__ import annotations

import io
import json
import logging
import os
import urllib.parse

import boto3
from botocore.exceptions import ClientError

from langchain.text_splitter import RecursiveCharacterTextSplitter
from langchain_aws import BedrockEmbeddings
from langchain_community.document_loaders import PyPDFLoader, TextLoader, Docx2txtLoader
from langchain_elasticsearch import ElasticsearchStore

logger = logging.getLogger(__name__)
logger.setLevel(logging.INFO)

# ── Environment variables ───────────────────────────────────────────────────
ELASTICSEARCH_ENDPOINT = os.environ["ELASTICSEARCH_ENDPOINT"]
ELASTIC_SECRET_NAME    = os.environ["ELASTIC_SECRET_NAME"]
ELASTIC_INDEX_NAME     = os.environ.get("ELASTIC_INDEX_NAME", "documents")
BEDROCK_EMBEDDING_MODEL = os.environ.get(
    "BEDROCK_EMBEDDING_MODEL", "amazon.titan-embed-text-v2:0"
)
AWS_REGION_NAME = os.environ.get("AWS_REGION_NAME", "us-east-1")
CHUNK_SIZE      = int(os.environ.get("CHUNK_SIZE", "1000"))
CHUNK_OVERLAP   = int(os.environ.get("CHUNK_OVERLAP", "200"))

# ── AWS clients (module-level for Lambda warm-start reuse) ──────────────────
s3_client  = boto3.client("s3", region_name=AWS_REGION_NAME)
sm_client  = boto3.client("secretsmanager", region_name=AWS_REGION_NAME)
bedrock_rt = boto3.client("bedrock-runtime", region_name=AWS_REGION_NAME)


def _get_elastic_credentials() -> tuple[str, str]:
    """Retrieve Elasticsearch username and password from Secrets Manager."""
    try:
        response = sm_client.get_secret_value(SecretId=ELASTIC_SECRET_NAME)
        secret = json.loads(response["SecretString"])
        return secret["username"], secret["password"]
    except (ClientError, KeyError, json.JSONDecodeError) as exc:
        logger.error("Failed to retrieve Elastic credentials: %s", exc)
        raise


def _get_embeddings() -> BedrockEmbeddings:
    """Return a BedrockEmbeddings instance for Titan embeddings."""
    return BedrockEmbeddings(
        client=bedrock_rt,
        model_id=BEDROCK_EMBEDDING_MODEL,
        region_name=AWS_REGION_NAME,
    )


def _build_vector_store(username: str, password: str) -> ElasticsearchStore:
    """Return an ElasticsearchStore connected to the configured index."""
    return ElasticsearchStore(
        es_url=ELASTICSEARCH_ENDPOINT,
        es_user=username,
        es_password=password,
        index_name=ELASTIC_INDEX_NAME,
        embedding=_get_embeddings(),
    )


def _download_s3_object(bucket: str, key: str) -> bytes:
    """Download an S3 object and return its raw bytes."""
    logger.info("Downloading s3://%s/%s", bucket, key)
    response = s3_client.get_object(Bucket=bucket, Key=key)
    return response["Body"].read()


def _load_documents(raw_bytes: bytes, key: str) -> list:
    """
    Parse document bytes into LangChain Document objects.

    Supports: PDF, TXT, DOCX, HTML/HTM
    Falls back to raw UTF-8 decoding for unknown types.
    """
    extension = key.rsplit(".", 1)[-1].lower() if "." in key else ""
    tmp_path = f"/tmp/{os.path.basename(key)}"

    # Write to /tmp so file-based loaders can access it
    with open(tmp_path, "wb") as fh:
        fh.write(raw_bytes)

    if extension == "pdf":
        loader = PyPDFLoader(tmp_path)
        docs = loader.load()
    elif extension == "docx":
        loader = Docx2txtLoader(tmp_path)
        docs = loader.load()
    elif extension in ("txt", "md", "rst", "html", "htm"):
        loader = TextLoader(tmp_path, encoding="utf-8", autodetect_encoding=True)
        docs = loader.load()
    else:
        # Generic fallback — treat as plain text
        logger.warning("Unsupported extension '%s'; treating as plain text", extension)
        loader = TextLoader(tmp_path, encoding="utf-8", autodetect_encoding=True)
        docs = loader.load()

    # Enrich metadata
    for doc in docs:
        doc.metadata.update({"source_key": key})

    logger.info("Loaded %d document page(s) from '%s'", len(docs), key)
    return docs


def _split_documents(docs: list) -> list:
    """Split documents into overlapping chunks for embedding."""
    splitter = RecursiveCharacterTextSplitter(
        chunk_size=CHUNK_SIZE,
        chunk_overlap=CHUNK_OVERLAP,
        separators=["\n\n", "\n", ". ", " ", ""],
    )
    chunks = splitter.split_documents(docs)
    logger.info("Split into %d chunks (size=%d, overlap=%d)",
                len(chunks), CHUNK_SIZE, CHUNK_OVERLAP)
    return chunks


def _store_chunks(chunks: list, vector_store: ElasticsearchStore) -> None:
    """Generate embeddings and index chunks in Elasticsearch."""
    logger.info("Generating embeddings and indexing %d chunks …", len(chunks))
    vector_store.add_documents(chunks)
    logger.info("Successfully indexed %d chunks into '%s'", len(chunks), ELASTIC_INDEX_NAME)


# ── Main handler ────────────────────────────────────────────────────────────

def lambda_handler(event: dict, context) -> dict:
    """
    Entry point for S3 ObjectCreated events.

    Expected event structure (standard S3 notification):
    {
        "Records": [
            {
                "s3": {
                    "bucket": {"name": "<bucket>"},
                    "object": {"key": "<url-encoded-key>"}
                }
            }
        ]
    }
    """
    username, password = _get_elastic_credentials()
    vector_store = _build_vector_store(username, password)

    processed = []
    errors = []

    for record in event.get("Records", []):
        bucket = record["s3"]["bucket"]["name"]
        # Keys may be URL-encoded in the S3 notification
        key = urllib.parse.unquote_plus(record["s3"]["object"]["key"])

        try:
            raw_bytes = _download_s3_object(bucket, key)
            docs      = _load_documents(raw_bytes, key)
            chunks    = _split_documents(docs)
            _store_chunks(chunks, vector_store)
            processed.append(key)
            logger.info("Finished processing '%s'", key)
        except Exception as exc:  # pylint: disable=broad-except
            logger.exception("Error processing '%s': %s", key, exc)
            errors.append({"key": key, "error": str(exc)})

    result = {
        "processed": processed,
        "errors": errors,
        "total_processed": len(processed),
        "total_errors": len(errors),
    }

    if errors:
        logger.error("Completed with errors: %s", result)
    else:
        logger.info("All records processed successfully: %s", result)

    return result
