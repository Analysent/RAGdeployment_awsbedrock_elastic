"""
Lambda Agent Handler
--------------------
Receives a question via API Gateway POST, performs a similarity search
against the Elasticsearch vector index, then uses Amazon Bedrock Titan
to generate a context-aware response (RAG pattern).

Request body (JSON):
    { "question": "What is cloud-native DevOps?" }

Response body (JSON):
    {
        "question": "...",
        "answer": "...",
        "sources": ["<source_key>", ...]
    }
"""

from __future__ import annotations

import json
import logging
import os

import boto3
from botocore.exceptions import ClientError

from langchain_aws import BedrockEmbeddings, BedrockLLM
from langchain_elasticsearch import ElasticsearchStore
from langchain_core.prompts import PromptTemplate
from langchain_core.output_parsers import StrOutputParser
from langchain_core.runnables import RunnablePassthrough

logger = logging.getLogger(__name__)
logger.setLevel(logging.INFO)

# ── Environment variables ───────────────────────────────────────────────────
ELASTICSEARCH_ENDPOINT  = os.environ["ELASTICSEARCH_ENDPOINT"]
ELASTIC_SECRET_NAME     = os.environ["ELASTIC_SECRET_NAME"]
ELASTIC_INDEX_NAME      = os.environ.get("ELASTIC_INDEX_NAME", "documents")
BEDROCK_EMBEDDING_MODEL = os.environ.get(
    "BEDROCK_EMBEDDING_MODEL", "amazon.titan-embed-text-v2:0"
)
BEDROCK_LLM_MODEL = os.environ.get(
    "BEDROCK_LLM_MODEL", "amazon.titan-text-express-v1"
)
AWS_REGION_NAME = os.environ.get("AWS_REGION_NAME", "us-east-1")
TOP_K_RESULTS   = int(os.environ.get("TOP_K_RESULTS", "5"))

# ── AWS clients ─────────────────────────────────────────────────────────────
sm_client  = boto3.client("secretsmanager", region_name=AWS_REGION_NAME)
bedrock_rt = boto3.client("bedrock-runtime", region_name=AWS_REGION_NAME)

# ── RAG prompt template ──────────────────────────────────────────────────────
RAG_PROMPT = PromptTemplate.from_template(
    """You are a helpful assistant. Use ONLY the context below to answer the question.
If the context does not contain enough information, say "I don't have enough information to answer that."

Context:
{context}

Question: {question}

Answer:"""
)


def _get_elastic_credentials() -> tuple[str, str]:
    """Retrieve Elasticsearch username and password from Secrets Manager."""
    try:
        response = sm_client.get_secret_value(SecretId=ELASTIC_SECRET_NAME)
        secret = json.loads(response["SecretString"])
        return secret["username"], secret["password"]
    except (ClientError, KeyError, json.JSONDecodeError) as exc:
        logger.error("Failed to retrieve Elastic credentials: %s", exc)
        raise


def _build_retriever(username: str, password: str):
    """Build an Elasticsearch retriever backed by Titan embeddings."""
    embeddings = BedrockEmbeddings(
        client=bedrock_rt,
        model_id=BEDROCK_EMBEDDING_MODEL,
        region_name=AWS_REGION_NAME,
    )
    store = ElasticsearchStore(
        es_url=ELASTICSEARCH_ENDPOINT,
        es_user=username,
        es_password=password,
        index_name=ELASTIC_INDEX_NAME,
        embedding=embeddings,
    )
    return store.as_retriever(search_kwargs={"k": TOP_K_RESULTS})


def _build_llm() -> BedrockLLM:
    """Return a Bedrock LLM instance."""
    return BedrockLLM(
        client=bedrock_rt,
        model_id=BEDROCK_LLM_MODEL,
        region_name=AWS_REGION_NAME,
        model_kwargs={
            "maxTokenCount": 1024,
            "temperature": 0.1,
            "topP": 0.9,
        },
    )


def _format_docs(docs: list) -> str:
    """Combine retrieved document chunks into a single context string."""
    return "\n\n---\n\n".join(doc.page_content for doc in docs)


def _extract_sources(docs: list) -> list[str]:
    """Extract unique source keys from retrieved documents."""
    seen = set()
    sources = []
    for doc in docs:
        key = doc.metadata.get("source_key", "unknown")
        if key not in seen:
            seen.add(key)
            sources.append(key)
    return sources


def _parse_request(event: dict) -> str:
    """
    Extract the question from an API Gateway event.

    Handles both:
    - API Gateway HTTP API (payload format 2.0): event["body"]
    - Direct Lambda invocation: event["question"]
    """
    # Direct invocation
    if "question" in event:
        return event["question"].strip()

    # API Gateway HTTP API / REST API
    body_raw = event.get("body", "{}")
    if isinstance(body_raw, str):
        body = json.loads(body_raw)
    else:
        body = body_raw or {}

    question = body.get("question", "").strip()
    if not question:
        raise ValueError("Missing 'question' field in request body")
    return question


def _build_response(status_code: int, body: dict) -> dict:
    """Build an API Gateway compatible response."""
    return {
        "statusCode": status_code,
        "headers": {
            "Content-Type": "application/json",
            "Access-Control-Allow-Origin": "*",
        },
        "body": json.dumps(body),
    }


# ── Main handler ─────────────────────────────────────────────────────────────

def lambda_handler(event: dict, context) -> dict:
    """
    RAG agent entry point.

    1. Parse question from API Gateway event
    2. Retrieve relevant document chunks from Elasticsearch
    3. Generate answer using Amazon Bedrock Titan LLM
    4. Return structured JSON response
    """
    logger.info("Received event: %s", json.dumps(event))

    try:
        question = _parse_request(event)
    except (ValueError, json.JSONDecodeError) as exc:
        logger.warning("Bad request: %s", exc)
        return _build_response(400, {"error": str(exc)})

    logger.info("Processing question: %s", question)

    try:
        username, password = _get_elastic_credentials()
        retriever = _build_retriever(username, password)
        llm       = _build_llm()

        # ── Retrieve relevant chunks ──────────────────────────────────────
        retrieved_docs = retriever.invoke(question)
        logger.info("Retrieved %d documents from Elasticsearch", len(retrieved_docs))

        if not retrieved_docs:
            return _build_response(200, {
                "question": question,
                "answer": (
                    "No relevant documents were found in the knowledge base. "
                    "Please upload documents to the S3 bucket first."
                ),
                "sources": [],
            })

        context_text = _format_docs(retrieved_docs)
        sources      = _extract_sources(retrieved_docs)

        # ── Build RAG chain ───────────────────────────────────────────────
        rag_chain = (
            {"context": lambda _: context_text, "question": RunnablePassthrough()}
            | RAG_PROMPT
            | llm
            | StrOutputParser()
        )

        answer = rag_chain.invoke(question)
        logger.info("Generated answer (first 200 chars): %s", answer[:200])

        return _build_response(200, {
            "question": question,
            "answer":   answer.strip(),
            "sources":  sources,
        })

    except Exception as exc:  # pylint: disable=broad-except
        logger.exception("Unhandled error: %s", exc)
        return _build_response(500, {
            "error": "Internal server error",
            "detail": str(exc),
        })
