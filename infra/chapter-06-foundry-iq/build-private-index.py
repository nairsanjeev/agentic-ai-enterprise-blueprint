"""
Chapter 06 — Foundry IQ, Path 2 (fully private): build an AI Search vector index with the PUSH model.

Everything runs from a host on the VNet so it can reach the private endpoints:
  - embeds each chunk by calling the private embedding deployment (text-embedding-3-small)
  - pushes documents + vectors straight into the private AI Search index (no indexer/skillset, so no
    AI Search shared private links to storage or the model are needed)

Then register the resulting index in the Foundry project and attach it to a prompt agent.

Prereqs (granted already):
  - You (the signed-in user) have: Search Service Contributor + Search Index Data Contributor on the
    search service, and Cognitive Services OpenAI User on the Foundry account.
  - Semantic ranker enabled on the search service.

Install: <python> -m pip install azure-identity azure-search-documents openai
Run:     az login  (as that user), then run this script from the VM.
"""

from __future__ import annotations

import os
import re
from pathlib import Path

from azure.identity import AzureCliCredential, get_bearer_token_provider
from openai import AzureOpenAI
from azure.search.documents import SearchClient
from azure.search.documents.indexes import SearchIndexClient
from azure.search.documents.indexes.models import (
    SearchIndex,
    SimpleField,
    SearchableField,
    SearchField,
    SearchFieldDataType,
    VectorSearch,
    HnswAlgorithmConfiguration,
    VectorSearchProfile,
    SemanticConfiguration,
    SemanticSearch,
    SemanticPrioritizedFields,
    SemanticField,
)

# ---- Configuration (override via environment variables) ---------------------------------------
SEARCH_ENDPOINT = os.environ.get("KB_SEARCH_ENDPOINT", "https://agent-blueprint-dev-search-vlpnxwtn.search.windows.net")
AOAI_ENDPOINT = os.environ.get("KB_AOAI_ENDPOINT", "https://agent-blueprint-dev-foundry-std-vlpnxwtn.openai.azure.com/")
EMBEDDING_DEPLOYMENT = os.environ.get("KB_EMBEDDING_MODEL", "text-embedding-3-small")
EMBEDDING_DIMS = int(os.environ.get("KB_EMBEDDING_DIMS", "1536"))  # text-embedding-3-small
INDEX_NAME = os.environ.get("KB_INDEX_NAME", "enterprise-policies")
DOCS_DIR = Path(os.environ.get("KB_DOCS_DIR", str(Path(__file__).parent / "sample-docs")))

CRED = AzureCliCredential()


def chunk_text(text: str, max_chars: int = 600) -> list[str]:
    """Split on markdown headings, then pack paragraphs into <= max_chars chunks."""
    sections = re.split(r"(?m)^#{1,6}\s", text)
    chunks: list[str] = []
    for section in sections:
        section = section.strip()
        if not section:
            continue
        buf = ""
        for para in re.split(r"\n\s*\n", section):
            para = para.strip()
            if not para:
                continue
            if len(buf) + len(para) + 1 > max_chars and buf:
                chunks.append(buf.strip())
                buf = para
            else:
                buf = f"{buf}\n{para}" if buf else para
        if buf:
            chunks.append(buf.strip())
    return chunks


def create_index() -> None:
    client = SearchIndexClient(endpoint=SEARCH_ENDPOINT, credential=CRED)
    index = SearchIndex(
        name=INDEX_NAME,
        fields=[
            SimpleField(name="id", type=SearchFieldDataType.String, key=True),
            SearchableField(name="title", type=SearchFieldDataType.String),
            SearchableField(name="content", type=SearchFieldDataType.String),
            SearchField(
                name="contentVector",
                type=SearchFieldDataType.Collection(SearchFieldDataType.Single),
                searchable=True,
                vector_search_dimensions=EMBEDDING_DIMS,
                vector_search_profile_name="vprofile",
            ),
        ],
        vector_search=VectorSearch(
            algorithms=[HnswAlgorithmConfiguration(name="hnsw")],
            profiles=[VectorSearchProfile(name="vprofile", algorithm_configuration_name="hnsw")],
        ),
        semantic_search=SemanticSearch(
            configurations=[
                SemanticConfiguration(
                    name="default",
                    prioritized_fields=SemanticPrioritizedFields(
                        title_field=SemanticField(field_name="title"),
                        content_fields=[SemanticField(field_name="content")],
                    ),
                )
            ]
        ),
    )
    client.create_or_update_index(index)
    print(f"index ready: {INDEX_NAME}")


def embed(texts: list[str]) -> list[list[float]]:
    token_provider = get_bearer_token_provider(CRED, "https://cognitiveservices.azure.com/.default")
    client = AzureOpenAI(
        azure_endpoint=AOAI_ENDPOINT,
        azure_ad_token_provider=token_provider,
        api_version="2024-10-21",
    )
    resp = client.embeddings.create(model=EMBEDDING_DEPLOYMENT, input=texts)
    return [d.embedding for d in resp.data]


def index_documents() -> None:
    docs = []
    for md in sorted(DOCS_DIR.glob("*.md")):
        text = md.read_text(encoding="utf-8")
        title = md.stem.replace("-", " ").title()
        chunks = chunk_text(text)
        vectors = embed(chunks)
        for i, (chunk, vec) in enumerate(zip(chunks, vectors)):
            docs.append(
                {
                    "id": f"{md.stem}-{i}",
                    "title": title,
                    "content": chunk,
                    "contentVector": vec,
                }
            )
    search = SearchClient(endpoint=SEARCH_ENDPOINT, index_name=INDEX_NAME, credential=CRED)
    result = search.upload_documents(documents=docs)
    ok = sum(1 for r in result if r.succeeded)
    print(f"uploaded {ok}/{len(docs)} chunks into '{INDEX_NAME}'")


def test_query() -> None:
    search = SearchClient(endpoint=SEARCH_ENDPOINT, index_name=INDEX_NAME, credential=CRED)
    q = "What is the per diem rate for meals in Europe?"
    qvec = embed([q])[0]
    from azure.search.documents.models import VectorizedQuery

    results = search.search(
        search_text=q,
        vector_queries=[VectorizedQuery(vector=qvec, k_nearest_neighbors=3, fields="contentVector")],
        query_type="semantic",
        semantic_configuration_name="default",
        top=3,
    )
    for r in results:
        print(f"score={r['@search.score']:.4f} :: {r['content'][:160]}...")


def main() -> None:
    create_index()
    index_documents()
    test_query()


if __name__ == "__main__":
    main()
