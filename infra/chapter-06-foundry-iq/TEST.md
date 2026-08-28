# Chapter 06 — Foundry IQ Knowledge Base: Test & Validation

**Environment**
- Resource group: `rg-agentic-ai-blueprint-dev`
- Standard Foundry account: `agent-blueprint-dev-foundry-std-vlpnxwtn`
- Storage: `ststdfbconcwrg7ntw` · container `knowledge-base`
- AI Search (vector store): `agent-blueprint-dev-search-vlpnxwtn`

---

## A. Control-plane prerequisites

### A1. Embedding model is deployed
```powershell
az cognitiveservices account deployment list -g rg-agentic-ai-blueprint-dev -n agent-blueprint-dev-foundry-std-vlpnxwtn --query "[?properties.model.name=='text-embedding-3-small'].{name:name,version:properties.model.version,state:properties.provisioningState}" -o table
```
✅ Expect: `text-embedding-3-small` / `1` / `Succeeded`.

### A2. Knowledge-base container exists
```powershell
az storage container-rm show --storage-account ststdfbconcwrg7ntw -g rg-agentic-ai-blueprint-dev --name knowledge-base --query "{name:name,public:publicAccess}" -o table
```
✅ Expect: `knowledge-base`, public access `None`.

### A3. Storage is private + Entra-only
```powershell
az storage account show -g rg-agentic-ai-blueprint-dev -n ststdfbconcwrg7ntw --query "{public:publicNetworkAccess,sharedKey:allowSharedKeyAccess}" -o table
```
✅ Expect: `Disabled`, `False`.

### A4. Project identity can read the documents
```powershell
$projMi = az rest --method GET --url "https://management.azure.com/subscriptions/$((az account show --query id -o tsv))/resourceGroups/rg-agentic-ai-blueprint-dev/providers/Microsoft.CognitiveServices/accounts/agent-blueprint-dev-foundry-std-vlpnxwtn/projects/agent-blueprint-dev-project-std?api-version=2025-06-01" --query "identity.principalId" -o tsv
az role assignment list --assignee $projMi --all --query "[?contains(roleDefinitionName,'Storage Blob')].roleDefinitionName" -o table
```
✅ Expect: `Storage Blob Data Owner` (grants the knowledge index read access to the container).

---

## B. Data plane (run from inside the VNet — storage/Foundry/search are private)

> **Design choice (Option A):** AI Search stays `publicNetworkAccess: Disabled`. The Foundry portal
> Knowledge blade can't reach it (it runs outside the VNet), so create the index with the **SDK from a
> host inside the VNet**. The agent runtime still queries the index over the private endpoint.
> The search service also needs the **semantic ranker enabled** (`semanticSearch = free|standard`).

### B0. Semantic ranker is enabled (required by Foundry IQ)
```powershell
az search service show -g rg-agentic-ai-blueprint-dev -n agent-blueprint-dev-search-vlpnxwtn --query "{semantic:semanticSearch,public:publicNetworkAccess}" -o table
```
✅ Expect: `semanticSearch = free` (or `standard`), `publicNetworkAccess = Disabled`.

### B1. Build the index from the VNet (fully private — use the push-model script)
From the peered VM (`az login` first). The GA `azure-ai-projects` SDK can't auto-build from blob, so use
the push-model script (details + role prereqs in **B4**):
```powershell
$py='C:\Users\<you>\AppData\Local\Programs\Python\Python312\python.exe'
& $py -m pip install azure-identity azure-search-documents openai
& $py .\infra\chapter-06-foundry-iq\build-private-index.py
```
✅ Expect: `index ready: enterprise-policies`, `uploaded 7/7 chunks`, and a scored result whose text
contains `Europe: €90/day`.
❌ From a public workstation this fails (storage + search are private) — run it on the VM.
(`create-knowledge-index.py` is the older Foundry-IQ SDK variant; it does **not** work with the GA
`azure-ai-projects` 2.x — prefer `build-private-index.py`.)

### B2. Attach the index to a prompt agent and test grounding
In the Foundry portal (Standard project), create/edit a prompt agent → add **Knowledge** → select the
`enterprise-policies` index. Then ask questions answerable only from the docs:

- **"What is the per diem rate for meals in Europe?"** → expect **€90/day** (`travel-policy.md`).
- **"How many days do I have to submit an expense report?"** → expect **30 days** (`expense-policy.md`).

✅ The agent answers from the documents (grounded) over the private search path, not generic knowledge.

### B4. Path 2 — fully-private build (push model), if the SDK auto-build isn't available
The GA `azure-ai-projects` `indexes` API only *registers* an existing search index (no blob auto-build —
that pipeline is portal-only). To stay fully private, build the vector index with the **push model** from
the VM: it embeds each chunk via the private embedding endpoint and pushes vectors straight into the
private search (no AI Search shared private links needed).

Prereqs (grant once, to the user running it):
```powershell
$u='<your-user-object-id>'
$search='/subscriptions/<sub>/resourceGroups/rg-agentic-ai-blueprint-dev/providers/Microsoft.Search/searchServices/agent-blueprint-dev-search-vlpnxwtn'
$foundry='/subscriptions/<sub>/resourceGroups/rg-agentic-ai-blueprint-dev/providers/Microsoft.CognitiveServices/accounts/agent-blueprint-dev-foundry-std-vlpnxwtn'
az role assignment create --assignee $u --role 'Search Service Contributor'      --scope $search
az role assignment create --assignee $u --role 'Search Index Data Contributor'   --scope $search
az role assignment create --assignee $u --role 'Cognitive Services OpenAI User'  --scope $foundry
```
Build + register:
```powershell
$py='C:\Users\<you>\AppData\Local\Programs\Python\Python312\python.exe'
& $py -m pip install azure-identity azure-search-documents openai
& $py .\infra\chapter-06-foundry-iq\build-private-index.py   # create index + embed + push + test query
```
✅ Expect: `uploaded 7/7 chunks` and a scored result whose text contains `Europe: €90/day`. Then register
the index in the project (already done for this deployment):
`AzureAISearchIndex(connection_name='agent-vector-store', index_name='enterprise-policies')` via
`project.indexes.create_or_update(name='enterprise-policies', version='1', index=...)`.

> **Peered-VNet DNS (critical):** if you build from a **peered** admin VNet (e.g., `demovnet`), the new
> `privatelink.search.windows.net` / `privatelink.documents.azure.com` zones must be **linked to that
> VNet** too — otherwise the host resolves the search to a **public IP** and gets
> `publicNetworkAccess: Disabled` denied. Deploy Chapter 01a with `additionalLinkedVnetIds` set to the
> peered VNet's resource ID, or add the link manually:
> `az network private-dns link vnet create -g rg-agentic-ai-blueprint-dev --zone-name privatelink.search.windows.net --name link-demovnet --virtual-network <demovnet-id> --registration-enabled false`

---

## C. Error-to-fix map

| Symptom | Cause | Fix |
|---|---|---|
| Index creation can't see the container | Project MI lacks Storage Blob Data role | Grant `Storage Blob Data Owner` (A4) |
| Upload fails from workstation | Storage public access disabled | Upload from inside the VNet / peered VM (B1) |
| Index build fails on embeddings | Embedding model missing | Deploy `text-embedding-3-small` (A1) |
| Empty/irrelevant results | Documents not indexed or wrong container | Confirm blobs uploaded (B1) and index points at `knowledge-base` |
| Retrieval blocked over network | Private endpoint / DNS | Agent must run on the network-injected Standard project (Chapter 01a) |
| Portal Knowledge blade: `publicNetworkAccess: Disabled` | Portal runs outside the VNet | Expected with Option A — create the index via SDK from the VNet (B1), not the portal |
| `semantic ranker is required` | Semantic ranker off | `az search service update -n agent-blueprint-dev-search-vlpnxwtn -g rg-agentic-ai-blueprint-dev --semantic-search free` |
| Build script: `publicNetworkAccess: Disabled` denied *from the VM* | Peered VNet not linked to the search/documents private DNS zone — host resolves to a public IP | Link the zone to the peered VNet (Chapter 01a `additionalLinkedVnetIds`) and `Clear-DnsClientCache` |
| Build script: `not authorized` on search/embeddings | User missing Search or OpenAI roles | Grant Search Service/Index Data Contributor + Cognitive Services OpenAI User (B4), wait for propagation |
