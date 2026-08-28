# Chapter 06 — Foundry IQ Knowledge Base

Reproducible IaC for the Chapter 06 grounding infrastructure. Foundry IQ grounds agents on your
documents via a **knowledge index** (vector store in Azure AI Search + an embedding model + documents
in Blob Storage).

## What `main.bicep` deploys (management plane)

- **Embedding model** `text-embedding-3-small` on the Standard Foundry account
  (`agent-blueprint-dev-foundry-std-vlpnxwtn`) — used to vectorize documents and queries.
- **`knowledge-base` blob container** in the agent storage account (`ststdfbconcwrg7ntw`) — created via
  ARM so it works despite the storage account's private data plane.

## What is NOT in the template (data plane — do from inside the VNet)

- **Uploading documents** to the container (storage public access is disabled).
- **Creating the knowledge index** itself — a Foundry data-plane object created from the private
  project via the **Foundry portal** (Knowledge → Create Knowledge Index) or the **Python SDK**.

The Standard project already has the AI Search vector store (`agent-blueprint-dev-search-vlpnxwtn`) and
the `agent-storage` connection from Chapter 01a, which the index reuses.

## Prerequisites

- Chapter 01a deployed (Standard account, AI Search, storage, connections)
- A host inside `agent-blueprint-dev-vnet` (or peered `demovnet`) for the data-plane steps
- Sample documents — this folder ships `sample-docs/travel-policy.md` and `sample-docs/expense-policy.md`

## Deploy

```powershell
# Preview only
.\infra\chapter-06-foundry-iq\deploy.ps1

# Deploy the embedding model + container
.\infra\chapter-06-foundry-iq\deploy.ps1 -Execute
```

## Then, from inside the VNet

AI Search stays private (Option A), so build the index with the SDK from a host on the VNet (the
portal Knowledge blade can't reach a private search):

```powershell
# On the peered VM, after `az login`:
python -m pip install -r .\infra\chapter-06-foundry-iq\requirements.txt
python .\infra\chapter-06-foundry-iq\create-knowledge-index.py   # uploads docs + creates index + test query
```

Then attach the `enterprise-policies` index to a prompt agent in the Foundry portal (Standard project)
and validate with [`TEST.md`](./TEST.md).

## Two knowledge-index build paths

The GA `azure-ai-projects` SDK only *registers* an existing AI Search index; the blob auto-build
pipeline is portal-only. So there are two ways to build the index while keeping the search private:

- **Path 1 (portal auto-pipeline):** temporarily set the search `--public-access enabled`, build the
  knowledge base in the Foundry **Knowledge** blade (auto chunk + embed), then re-disable. Runtime stays
  private.
- **Path 2 (fully private, push model):** run [`build-private-index.py`](./build-private-index.py) from a
  host on the VNet — it embeds via the private endpoint and pushes vectors into the private search (no
  shared private links). Requires the user roles and (for a peered VNet) the DNS link in
  [`TEST.md`](./TEST.md) §B4.

> The AI Search service also needs the **semantic ranker** enabled
> (`az search service update ... --semantic-search free`) — Foundry IQ requires it. This is set in the
> Chapter 01a Bicep (`semanticSearch: 'free'`).

> Building from a **peered** admin VNet (e.g., `demovnet`) requires the `privatelink.search.windows.net`
> and `privatelink.documents.azure.com` zones to be linked to that VNet too (Chapter 01a
> `additionalLinkedVnetIds`), or the host resolves the search to a public IP and is denied.
