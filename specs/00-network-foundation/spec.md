# Feature Specification: Network Foundation (POC — Single-VNet)

**Feature Branch**: `spec/00-network-foundation`

**Created**: 2026-08-13

**Status**: Draft

**Input**: Issue #1 — Write spec: Network Foundation (POC-simplified single-VNet), tracked under
Milestone "Epic 1: Network Foundation".

**Blueprint reference**: Chapters [01-foundry-byo-networking](../../chapters/01-foundry-byo-networking.md)
and [19-network-and-gateway](../../chapters/19-network-and-gateway.md).

## Scope Deviation from Blueprint (documented per Constitution Principle II)

The blueprint (Ch. 19) assumes a **hub-and-spoke** topology: a pre-existing hub VNet with Azure
Firewall, Bastion, ExpressRoute/VPN, and centralized Private DNS zones, with this platform deployed
as a spoke. Our subscription starts from **zero** — no hub exists.

**POC decision**: deploy a **single, self-contained VNet** (`vnet-agent-factory-poc`) that holds
all subnets described in Ch. 19, plus a Bastion subnet for admin access, in place of a hub-spoke
peering. Azure Firewall and ExpressRoute are **out of scope** for the POC; NSGs provide traffic
control instead of a hub firewall.

**Future migration path**: when moving beyond POC, this VNet becomes the spoke; peer it to a new
hub VNet, move Bastion/Firewall to the hub, and update UDRs to route egress through the hub
firewall. This is documented here so the deviation is never silently permanent.

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Platform Engineer provisions the network from zero (Priority: P1)

As an IT Platform Engineer starting from an empty subscription, I need to stand up a VNet with
purpose-built subnets, NSGs, and Private DNS zones so that Foundry, APIM, and compute workloads
have a private, segmented network to deploy into — with no public exposure.

**Why this priority**: Nothing else in the blueprint (Foundry, APIM, agents) can be deployed
without this network existing first. It is the literal foundation.

**Independent Test**: Deploy the Bicep module to a fresh resource group; verify via `az network
vnet subnet list` that all 6+ subnets exist with correct address prefixes, delegations, and NSG
associations; verify Private DNS zones are linked to the VNet.

**Acceptance Scenarios**:

1. **Given** an empty resource group, **When** the network Bicep module is deployed, **Then** a
   VNet with address space `10.0.0.0/16` and 6 subnets (APIM, Foundry-delegated, Compute,
   Private Endpoints, CI/CD Agents, Bastion) exists.
2. **Given** the VNet exists, **When** an NSG is inspected on the compute subnet, **Then** direct
   internet egress to AI services is denied except through the APIM subnet.
3. **Given** the VNet exists, **When** Private DNS zones for Foundry/OpenAI/APIM/Key
   Vault/Storage/SQL are queried, **Then** all zones exist and are linked to the VNet.

---

### User Story 2 - Platform Engineer validates admin connectivity (Priority: P2)

As an IT Platform Engineer, I need a way to reach private resources (e.g., a test VM to validate
DNS resolution) without exposing any public IP, so that I can troubleshoot the network before
Foundry/APIM are deployed on top of it.

**Why this priority**: Needed to validate Story 1's output, but not blocking for other teams to
start planning on top of the network once it exists.

**Independent Test**: Deploy Azure Bastion into the Management subnet; connect to a test VM in
the Private Endpoints subnet via Bastion; resolve a private DNS name from within that VM.

**Acceptance Scenarios**:

1. **Given** Bastion is deployed, **When** a platform engineer connects via the Azure Portal,
   **Then** they reach a test VM with no public IP assigned.
2. **Given** a private endpoint and its DNS zone exist, **When** `nslookup` is run from the test
   VM, **Then** it resolves to the private IP, not a public one.

---

### User Story 3 - Team confirms quota/region before deployment (Priority: P1)

As the team planning this POC, I need to confirm Azure OpenAI/Foundry model quota (TPM) is
available in the target region before deploying network + Foundry, so that the network isn't
built in a region that later blocks model deployment.

**Why this priority**: Rework cost of re-deploying an entire VNet in a different region is high;
this must be resolved before infra work (see Issue #4, dependency of this spec).

**Independent Test**: Query current quota via `az cognitiveservices usage list` / Azure AI Foundry
quota page for the candidate region(s); confirm sufficient TPM for planned POC agent traffic.

**Acceptance Scenarios**:

1. **Given** a candidate region, **When** quota is queried, **Then** available TPM for the chosen
   model(s) meets or exceeds the POC traffic estimate, or a quota increase request has been filed
   and approved before proceeding.

### Edge Cases

- What happens if the delegated Foundry subnet runs out of IPs during POC scaling? → Ch. 01
  recommends /24 sizing with 80% max utilization; POC uses /24 per subnet to leave headroom
  (see Requirements below).
- How does the system handle a region with insufficient OpenAI/Foundry quota? → Story 3 above
  blocks deployment until resolved; do not proceed with network deployment in an unconfirmed
  region.
- What happens when NSG rules conflict with Foundry/APIM's own required outbound rules (e.g.,
  Azure Front Door dependencies for APIM VNet-injected mode)? → Document required allow-rules
  from Microsoft's published service tags in `plan.md` before implementation.

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: The network MUST provide a single VNet (`vnet-agent-factory-poc`) with address
  space `10.0.0.0/16`, deployed via Bicep (no manual portal creation).
- **FR-002**: The VNet MUST contain the following subnets, matching Ch. 19's design (sizes
  increased to /24 per Ch. 01's 80%-utilization guidance where the blueprint used smaller ranges):
  | Subnet | Purpose | CIDR |
  |---|---|---|
  | `snet-apim` | APIM VNet injection | 10.0.1.0/24 |
  | `snet-foundry` | Foundry delegated subnet (Microsoft.App/environments) | 10.0.2.0/24 |
  | `snet-compute` | ACA / App Service compute | 10.0.3.0/24 |
  | `snet-privateendpoints` | Private endpoints (Storage, Key Vault, SQL, Foundry, OpenAI) | 10.0.4.0/24 |
  | `snet-cicd-agents` | Self-hosted CI/CD agents (if used) | 10.0.5.0/24 |
  | `snet-bastion` | AzureBastionSubnet (fixed name, min /26) | 10.0.6.0/26 |
- **FR-003**: The `snet-foundry` subnet MUST be delegated to `Microsoft.App/environments`.
- **FR-004**: NSGs MUST be applied to `snet-apim` and `snet-compute` at minimum, denying direct
  internet egress from compute to AI services except via the APIM subnet.
- **FR-005**: Private DNS zones MUST be created and VNet-linked for: Foundry/Cognitive Services
  (`privatelink.cognitiveservices.azure.com`), Azure OpenAI (`privatelink.openai.azure.com`),
  APIM (`privatelink.azure-api.net`), Key Vault (`privatelink.vaultcore.azure.net`), Storage Blob
  (`privatelink.blob.core.windows.net`), and SQL (`privatelink.database.windows.net`) if used.
- **FR-006**: No subnet or resource in this spec MAY have a public IP assigned, except the
  Bastion public IP required by the Bastion service itself.
- **FR-007**: All resources MUST be deployable/re-deployable idempotently via
  `az deployment group create` against `infra/envs/poc` parameters.
- **FR-008**: The deployment MUST be validated with `az deployment group what-if` prior to merge,
  with output attached to the PR (per Constitution Principle V).

### Key Entities

- **VNet**: `vnet-agent-factory-poc` — top-level container, address space `10.0.0.0/16`.
- **Subnet**: one per workload purpose (see FR-002 table); each has an address prefix, optional
  delegation, optional NSG association.
- **NSG**: security rule set attached to `snet-apim` and `snet-compute`.
- **Private DNS Zone**: one per Azure PaaS service requiring private endpoint resolution; each
  linked to the VNet.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: A platform engineer can deploy the entire network from an empty resource group to
  fully provisioned (VNet + 6 subnets + NSGs + DNS zones) in under 15 minutes via one
  `az deployment group create` command.
- **SC-002**: Zero public IPs exist on any resource in this spec except the Bastion public IP.
- **SC-003**: `az deployment group what-if` produces no unexpected changes when re-run against an
  already-deployed environment (idempotency).
- **SC-004**: DNS resolution for a private endpoint resource (once deployed by Epic 2) resolves
  to a `10.0.x.x` address from a VM inside the VNet, verified via Bastion session.

## Assumptions

- POC runs in a single Azure region, finalized once Issue #4 (quota validation) completes; this
  spec's Bicep parameterizes region so it is not hardcoded.
- No pre-existing hub VNet, ExpressRoute, or ExpressRoute/VPN Gateway is available — confirmed
  greenfield subscription per user's original request.
- Azure Firewall is deferred; NSGs are sufficient traffic control for POC scope. This will be
  revisited if/when this environment is promoted beyond POC (see Scope Deviation above).
- Subscription-level permissions (Contributor + Network Contributor at minimum) are available to
  the platform engineer executing this spec; broader Entra ID prerequisites are tracked separately
  in Issue #5.
- Team size is 2–3 people (per constitution); this spec does not need multi-region or
  multi-environment (dev/staging/prod) network topology yet — POC is single-environment.
