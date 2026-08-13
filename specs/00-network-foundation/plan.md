# Implementation Plan: Network Foundation (POC — Single-VNet)

**Branch**: `spec/00-network-foundation` | **Date**: 2026-08-13 | **Spec**: [spec.md](./spec.md)

**Input**: Feature specification from `specs/00-network-foundation/spec.md`

## Summary

Deploy a single, self-contained VNet (`vnet-agent-factory-poc`, `10.0.0.0/16`) with 6 subnets
(APIM, Foundry-delegated, compute, private endpoints, CI/CD agents, Bastion), NSGs on the
APIM/compute subnets, and 6 Private DNS zones linked to the VNet — via parameterized Bicep,
deployed with `az deployment group create` and validated with `what-if`. This replaces the
blueprint's hub-spoke assumption (Ch. 19) with a POC-appropriate single-VNet topology, explicitly
documented as a deviation with a migration path.

## Technical Context

**Language/Version**: Bicep (latest, via Azure CLI `az bicep` — pinned to CLI's bundled version)

**Primary Dependencies**: Azure CLI ≥ 2.60, Azure subscription with Contributor + Network
Contributor + User Access Administrator (for later RBAC, not this spec)

**Storage**: N/A (no data plane in this spec)

**Testing**: `az bicep build` (compile check), `az deployment group what-if` (drift/preview),
manual DNS resolution test via Bastion (Story 2)

**Target Platform**: Azure (single region, TBD pending Issue #4 quota validation)

**Project Type**: Infrastructure-as-Code (Bicep modules + environment parameters)

**Performance Goals**: N/A (network provisioning, not a runtime workload)

**Constraints**: No public IPs except Bastion; idempotent deployment; /24 subnets per Ch. 01's
80%-utilization guidance (except Bastion, which requires a fixed name and supports /26 minimum)

**Scale/Scope**: Single VNet, single region, single environment (`poc`) — no multi-region, no
dev/staging/prod split yet

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

| Principle | Check | Status |
|---|---|---|
| I. Separation of Duties | This spec is infra-only; owned by Platform Engineering per CODEOWNERS (`/infra/`, `/specs/00-network-foundation/`) | ✅ Pass |
| II. Spec Before Infra | This plan follows spec.md; deviation (single-VNet vs hub-spoke) documented explicitly | ✅ Pass |
| III. Private by Default | FR-006 enforces no public IPs except Bastion; NSGs deny direct egress | ✅ Pass |
| IV. Incremental, Testable Slices | Story 1 (network) is independently testable/deployable before Story 2 (Bastion) or Story 3 (quota) | ✅ Pass |
| V. IaC Validated Before Merge | `what-if` output required in PR per FR-008 | ✅ Pass |

No violations — Complexity Tracking section not required.

## Project Structure

### Documentation (this feature)

```text
specs/00-network-foundation/
├── plan.md              # This file
├── spec.md              # Feature specification
└── tasks.md             # Task breakdown (/speckit.tasks output)
```

### Source Code (repository root)

```text
infra/
├── modules/
│   └── network/
│       ├── main.bicep           # VNet + all subnets
│       ├── nsg.bicep            # NSG definitions (apim, compute)
│       ├── private-dns.bicep    # Private DNS zones + VNet links
│       ├── bastion.bicep        # Bastion host + public IP (uses existing AzureBastionSubnet from main.bicep)
│       └── outputs.bicep        # (or output blocks in main.bicep) — subnet IDs for downstream modules (Epic 2 Foundry/APIM)
└── envs/
    └── poc/
        ├── main.bicep            # Root deployment composing network module
        ├── network.parameters.json
        └── README.md             # How to deploy: az deployment group create ...
```

**Structure Decision**: Single infra project (`infra/`), no app code yet. `modules/network/` holds
reusable Bicep; `envs/poc/` holds the environment-specific parameter file and root deployment file
that other epics (Foundry, APIM) will extend by adding their own modules alongside `network`.
Subnet resource IDs are exposed as Bicep outputs so Epic 2 (Foundry + APIM) can consume them
without re-declaring the network.

## Phase 0: Research

Open questions to resolve before/while implementing (tracked as tasks in tasks.md):

1. **Region selection** — depends on Issue #4 (quota validation). Bicep parameterizes `location`;
   do not hardcode until confirmed.
2. **Required NSG allow-rules for APIM VNet-injected mode** — APIM needs outbound access to
   Azure Front Door / control plane IPs (published as `ApiManagement` service tag) and specific
   ports (3443 management endpoint). Document exact rule set from Microsoft Learn before writing
   `nsg.bicep`.
3. **Foundry delegated subnet requirements** — confirm `Microsoft.App/environments` delegation is
   still correct per current Foundry docs (Ch. 01 was written against a specific service version;
   verify no changes).
4. **Bastion SKU** — Basic SKU is sufficient for POC (no native client / IP-based connection
   needed); Standard SKU deferred unless a specific feature is required.

## Phase 1: Design Outputs

- `data-model.md`: not applicable — no application data model for a network-only spec.
- `contracts/`: not applicable — no API contracts; the "contract" between this spec and
  downstream epics is the set of Bicep outputs (subnet resource IDs, VNet ID, DNS zone IDs).
- `quickstart.md`: covered by `infra/envs/poc/README.md` (deployment command + validation steps).

## Complexity Tracking

*No constitution violations — table not needed.*
