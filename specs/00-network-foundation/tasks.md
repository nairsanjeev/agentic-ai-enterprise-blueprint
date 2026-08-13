---
description: "Task list for Network Foundation (POC — Single-VNet)"
---

# Tasks: Network Foundation (POC — Single-VNet)

**Input**: Design documents from `specs/00-network-foundation/`

**Prerequisites**: plan.md, spec.md

**Tests**: `az bicep build` + `az deployment group what-if` serve as the validation gate for every
infra task (per Constitution Principle V). Manual DNS-resolution test covers Story 2.

**Organization**: Tasks are grouped by user story (US1, US2, US3 from spec.md) so each can be
implemented and validated independently. Maps to GitHub issues #1–#5.

## Phase 1: Setup

- [ ] T001 Create `infra/modules/network/` and `infra/envs/poc/` directory structure
- [ ] T002 [P] Confirm Azure CLI version ≥ 2.60 and `az bicep version` available in dev environment
- [ ] T003 [P] Document required NSG allow-rules for APIM VNet-injected mode (Research Q2 in plan.md) in `infra/modules/network/README.md`

## Phase 2: Foundational — Region & Quota (blocks Story 1)

**⚠️ CRITICAL**: Region must be confirmed before subnet/DNS work proceeds (maps to Issue #4)

- [ ] T004 Query Azure OpenAI/Foundry model quota (TPM) for candidate region(s) via `az cognitiveservices usage list` or Foundry quota portal
- [ ] T005 File quota increase request if insufficient; wait for approval before continuing
- [ ] T006 Finalize region and record it in `infra/envs/poc/network.parameters.json` and spec.md Assumptions

**Checkpoint**: Region confirmed — Story 1 implementation can begin

---

## Phase 3: User Story 1 - Platform Engineer provisions the network from zero (Priority: P1) 🎯 MVP

**Goal**: Deployable VNet with all subnets, NSGs, and DNS zones, matching FR-001 through FR-008

**Independent Test**: Deploy to a fresh resource group; `az network vnet subnet list` shows all
6 subnets with correct prefixes/delegations/NSG associations; DNS zones exist and are linked.

### Implementation for User Story 1

- [ ] T007 [P] [US1] Write `infra/modules/network/main.bicep` — VNet `vnet-agent-factory-poc` (10.0.0.0/16) + 6 subnets per spec.md FR-002 table
- [ ] T008 [US1] Add `Microsoft.App/environments` delegation to `snet-foundry` in main.bicep (depends on T007)
- [ ] T009 [P] [US1] Write `infra/modules/network/nsg.bicep` — NSG for `snet-apim` (allow rules from T003 research) and `snet-compute` (deny direct internet egress to AI services except via APIM subnet)
- [ ] T010 [US1] Associate NSGs from T009 with their subnets in main.bicep (depends on T007, T009)
- [ ] T011 [P] [US1] Write `infra/modules/network/private-dns.bicep` — 6 zones (Cognitive Services, OpenAI, APIM, Key Vault, Blob Storage, SQL) each VNet-linked
- [ ] T012 [US1] Add Bicep outputs for VNet ID and all subnet resource IDs in main.bicep, for downstream Epic 2 consumption (depends on T007, T008, T010)
- [ ] T013 [US1] Write `infra/envs/poc/main.bicep` composing the network module with `infra/envs/poc/network.parameters.json` (region, address space overrides if needed)
- [ ] T014 [US1] Run `az bicep build` on all modules — fix any compile errors
- [ ] T015 [US1] Run `az deployment group what-if` against POC resource group — attach output to PR
- [ ] T016 [US1] Deploy via `az deployment group create`; verify via `az network vnet subnet list` and `az network private-dns zone list`

**Checkpoint**: Network fully provisioned and independently verifiable — Story 1 (MVP) done

---

## Phase 4: User Story 2 - Platform Engineer validates admin connectivity (Priority: P2)

**Goal**: Bastion access to a test VM with no public IP, proving private DNS resolution works

**Independent Test**: Connect via Bastion to a test VM in `snet-privateendpoints`; run `nslookup`
against a private endpoint DNS name; confirm it resolves to a `10.0.x.x` address.

### Implementation for User Story 2

- [ ] T017 [P] [US2] Write `infra/modules/network/bastion.bicep` — Bastion public IP + Bastion host (Basic SKU per plan.md Research Q4), deployed into existing `AzureBastionSubnet` created by main.bicep
- [ ] T018 [US2] Wire bastion.bicep into `infra/envs/poc/main.bicep` (depends on T013, T017)
- [ ] T019 [US2] Deploy a throwaway test VM (no public IP) into `snet-privateendpoints` for validation only — document as a manual/temporary step in `infra/envs/poc/README.md`, not a persistent resource
- [ ] T020 [US2] Validate: connect via Bastion, run `nslookup` for a placeholder private DNS record, confirm private IP resolution
- [ ] T021 [US2] Tear down the test VM after validation; document teardown command in README

**Checkpoint**: Admin connectivity and DNS resolution proven — Story 2 done

---

## Phase 5: User Story 3 - Team confirms quota/region before deployment (Priority: P1)

**Note**: This story's core work (T004–T006) is already required as a Phase 2 blocking
prerequisite. Remaining task here is documentation/traceability only.

- [ ] T022 [US3] Document final quota numbers and region decision with sign-off in `specs/00-network-foundation/spec.md` Assumptions section and close Issue #4

**Checkpoint**: All three user stories complete

---

## Phase 6: Polish & Cross-Cutting

- [ ] T023 [P] Write `infra/modules/network/README.md` documenting module inputs/outputs for Epic 2 consumers
- [ ] T024 [P] Write `infra/envs/poc/README.md` with the exact deployment command sequence (create RG → what-if → deploy → verify)
- [ ] T025 Update `specs/00-network-foundation/spec.md` if any deviations occurred during implementation
- [ ] T026 Close Issues #1, #2, #3, #4, #5 with links to the merged PR(s)

---

## Dependencies & Execution Order

- **Setup (Phase 1)**: No dependencies — start immediately
- **Foundational (Phase 2, region/quota)**: Blocks Story 1 subnet/DNS work (T007+) but not Setup
- **User Story 1 (Phase 3)**: Depends on Phase 2 completion — this is the MVP; nothing else in the
  blueprint can proceed without it
- **User Story 2 (Phase 4)**: Depends on Story 1 completion (needs subnets to exist)
- **User Story 3 (Phase 5)**: Its core work is folded into Phase 2; only documentation remains,
  can be done any time after T006
- **Polish (Phase 6)**: After all stories complete

### Parallel Opportunities

- T002, T003 in Setup can run in parallel
- T007, T009, T011 (main.bicep, nsg.bicep, private-dns.bicep) can be drafted in parallel by
  different people since they are different files, though T010/T012 need T007 merged first
- T023, T024 (docs) can run in parallel with each other

## Implementation Strategy

### MVP First
1. Complete Setup (T001–T003)
2. Complete Foundational region/quota gate (T004–T006) — do not proceed without this
3. Complete User Story 1 (T007–T016) — deploy and verify the network
4. **STOP and VALIDATE** independently before moving to Bastion/connectivity work

### Incremental Delivery
1. Foundational + Story 1 → network exists, verifiable, ready for Epic 2 to build on top
2. Story 2 → admin connectivity proven
3. Story 3 documentation → traceability closed out
4. Polish → hand off clean docs to whoever picks up Epic 2

## Notes

- [P] tasks touch different files with no ordering dependency
- [US1]/[US2]/[US3] map tasks back to spec.md user stories for traceability
- Every Bicep task must pass `az bicep build` before its PR is opened (Constitution Principle V)
- Commit after each task or logical group; open PR referencing this tasks.md and the relevant
  GitHub issue(s) #1–#5
