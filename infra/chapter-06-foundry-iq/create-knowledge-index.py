"""
Chapter 06 — Foundry IQ: create a knowledge index against the PRIVATE AI Search, from inside the VNet.

Run this from a host that is on `agent-blueprint-dev-vnet` (or the peered `demovnet`), because the
storage account and the AI Search service have public network access disabled. The agent runtime
already reaches the private search over its private endpoint once the index exists.

Prereqs (Chapter 06 infra deployed):
  - Embedding model `text-embedding-3-small` on the Standard account
  - `knowledge-base` blob container in the agent storage account
  - Semantic ranker enabled on the AI Search service
  - The project managed identity has Storage Blob Data + AI Search roles (from Chapter 01a)

Auth: uses AzureCliCredential — run `az login` first as a user with data access.

Install: python -m pip install -r requirements.txt
"""

from __future__ import annotations

import os
from pathlib import Path

from azure.identity import AzureCliCredential
from azure.storage.blob import BlobServiceClient
from azure.ai.projects import AIProjectClient

# ---- Configuration (override via environment variables) ---------------------------------------
PROJECT_ENDPOINT = os.environ.get(
    "FOUNDRY_PROJECT_ENDPOINT",
    "https://agent-blueprint-dev-foundry-std-vlpnxwtn.services.ai.azure.com/api/projects/agent-blueprint-dev-project-std",
)
STORAGE_ACCOUNT = os.environ.get("KB_STORAGE_ACCOUNT", "ststdfbconcwrg7ntw")
CONTAINER = os.environ.get("KB_CONTAINER", "knowledge-base")
STORAGE_CONNECTION_NAME = os.environ.get("KB_STORAGE_CONNECTION", "agent-storage")
INDEX_NAME = os.environ.get("KB_INDEX_NAME", "enterprise-policies")
EMBEDDING_MODEL = os.environ.get("KB_EMBEDDING_MODEL", "text-embedding-3-small")
DOCS_DIR = Path(os.environ.get("KB_DOCS_DIR", str(Path(__file__).parent / "sample-docs")))


def upload_documents(credential: AzureCliCredential) -> None:
    """Upload the sample docs to the private container (Entra auth, no shared keys)."""
    account_url = f"https://{STORAGE_ACCOUNT}.blob.core.windows.net"
    blob_service = BlobServiceClient(account_url=account_url, credential=credential)
    container = blob_service.get_container_client(CONTAINER)
    for doc in sorted(DOCS_DIR.glob("*.md")):
        with doc.open("rb") as data:
            container.upload_blob(name=doc.name, data=data, overwrite=True)
        print(f"uploaded {doc.name}")


def create_index(project: AIProjectClient) -> None:
    """Create/update the Foundry IQ knowledge index grounded on the blob container."""
    storage_conn = project.connections.get(STORAGE_CONNECTION_NAME)
    index = project.indexes.create_or_update(
        name=INDEX_NAME,
        description="Enterprise travel and expense policies for agent grounding.",
        source={
            "type": "azure_blob_storage",
            "connection_id": storage_conn.id,
            "container_name": CONTAINER,
        },
        embedding_model=EMBEDDING_MODEL,
        search_type="hybrid",
    )
    print(f"knowledge index ready: {index.name}")


def test_query(project: AIProjectClient) -> None:
    """Sanity-check retrieval from the private search."""
    results = project.indexes.query(
        index_name=INDEX_NAME,
        query="What is the per diem rate for meals in Europe?",
        top=3,
    )
    for r in results:
        score = getattr(r, "score", 0.0)
        content = getattr(r, "content", "")
        print(f"score={score:.4f} :: {content[:160]}...")


def main() -> None:
    with AzureCliCredential() as credential:
        upload_documents(credential)
        with AIProjectClient(endpoint=PROJECT_ENDPOINT, credential=credential) as project:
            create_index(project)
            test_query(project)


if __name__ == "__main__":
    main()
