# Agentic AI Enterprise Blueprint — POC Constitution

## Core Principles

### I. Separation of Duties (NON-NEGOTIABLE)
No single role provisions infrastructure AND writes agent code AND deploys to
production. Three roles govern all work: **IT Platform Engineering** (network,
Foundry, APIM, Azure Policy, Defender), **AI CoE** (governance, tool approval,
CI/CD gates, model strategy), **Developers** (agent logic only, no direct
infra access). CODEOWNERS enforces this boundary at the PR level.

### II. Spec Before Infra
Every capability slice (network, gateway, agent, governance) gets a
`specs/<NN-capability>/spec.md` + `plan.md` + `tasks.md` before any Bicep/
Terraform is written in `infra/`. Specs document POC-scope deviations from
the full blueprint (e.g., single-VNet vs. hub-spoke) explicitly — silent
drift from the documented architecture is not allowed.

### III. Private by Default, No Bypass
No public endpoints on Foundry, APIM backends, or storage. All model/tool
traffic flows through the AI Gateway (APIM) as the single chokepoint.
Content Safety and logging cannot be disabled by developers. This mirrors
the blueprint's "governed development is the path of least resistance."

### IV. Incremental, Independently-Testable Slices
Each epic/spec must produce a working, independently verifiable increment
(e.g., "network reachable via Bastion", "one agent callable through APIM").
Prefer a thin end-to-end vertical slice over building all layers before
anything works. Defer scale-out concerns (self-service portal, multi-IQ,
multi-region) until the core factory is proven.

### V. Infrastructure as Code, Validated Before Merge
All infra changes are Bicep or Terraform, parameterized per environment
(`infra/envs/poc`), and validated with `az bicep build` / `az deployment
group what-if` or `terraform plan` output attached to the PR. No manual
portal changes for anything tracked in `infra/`.

## Governance Scope for This POC

- **Subscription**: single POC subscription, greenfield (no pre-existing hub).
- **Region**: single region for POC (documented per-spec); multi-region is
  out of scope until Epic 5+.
- **Team size**: 2–3 contributors; branching/PR process is lightweight but
  mandatory (see Development Workflow).

## Development Workflow

- Trunk-based development off `master` (protected: 1 approving review
  required, no direct pushes).
- Branch prefixes: `spec/<capability>`, `infra/<module>`, `feat/<desc>`,
  `fix/<desc>`, `docs/<desc>`, `chore/<desc>`.
- Every PR links an issue, references the relevant spec, and includes
  validation output (see `.github/PULL_REQUEST_TEMPLATE.md`).
- CODEOWNERS enforces review by the correct role (Platform Eng / AI CoE /
  Developers) per Principle I.

## Governance

This constitution supersedes ad-hoc practices for this repository. Amendments
require a PR against this file with rationale, reviewed by whoever owns
`/chapters/` (repo maintainer). All specs and infra PRs are checked against
these principles before merge.

**Version**: 1.0.0 | **Ratified**: 2026-08-13 | **Last Amended**: 2026-08-13
