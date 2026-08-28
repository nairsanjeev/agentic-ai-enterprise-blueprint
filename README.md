# Agentic AI Enterprise Blueprint — Build Governed Agent Platforms on Azure

## Vision

> Build an enterprise AI agent platform where **developers ship fast** and **security teams sleep well** — not by choosing one over the other, but by making governed development the path of least resistance.

> Establish a **Secure Agent Factory** with clear separation of duties: **IT Platform Engineering** owns infrastructure and policy enforcement, the **AI Center of Excellence** owns standards and quality gates, and **Developers** own agent logic — each role self-sufficient within their boundary, each role unable to accidentally cross into another's.

> Deliver a **global, governed marketplace** of reusable Agents, Tools, and Skills with rich discoverability via API Center and A2A protocol — enabling developers to discover, compose, and deploy agentic applications across the organization without tickets, meetings, or manual onboarding.

> Make **Security, Observability, and Governance** properties of the architecture, not checklists bolted on after the fact. Azure Policy prevents non-compliance at creation time. APIM enforces security on every call. Defender detects threats automatically. Microsoft Agent 365 provides the unified control plane to observe, govern, and secure all agents in production. Foundry Evaluations block bad agents in CI/CD. The platform removes work from every role.

---

## Alignment with Microsoft Frameworks

This blueprint is designed as an **application landing zone** aligned with:

| Framework | Alignment |
|-----------|-----------|
| **[Azure AI Landing Zones](https://azure.github.io/AI-Landing-Zones/)** | AI Foundry Landing Zone + AI Gateway Landing Zone deployed as a spoke in hub-and-spoke topology |
| **[Cloud Adoption Framework — AI Scenario](https://learn.microsoft.com/en-us/azure/cloud-adoption-framework/scenarios/ai/)** | Covers AI Ready → Govern AI → Secure AI → Manage AI phases |
| **[Well-Architected Framework — AI Workloads](https://learn.microsoft.com/en-us/azure/well-architected/ai/)** | Security, reliability, cost, and operational excellence design areas |

The four-part structure maps to the CAF AI adoption lifecycle:

```
CAF Phase:     AI Ready              Govern AI + Secure AI           Manage AI
               ────────              ─────────────────────           ─────────
Blueprint:     Part 1                Part 2                Part 3               Part 4
               Build the Platform    Establish the CoE     Automated Build-Out  Ship Your Agent
               (IT Platform Eng)     (AI CoE)              (Self-Service)       (Developers)
```

---

## Foundry Topology — How Many Instances Do You Need?

Before building, decide the Foundry topology that fits your organization:

```
Enterprise (Recommended)
├── 1 Platform Subscription (IT Platform Engineering)
│   ├── Hub VNet: Azure Firewall, Bastion, DNS Zones, ExpressRoute
│   ├── Shared Services: Log Analytics, APIM, API Center, Defender
│   └── AI Landing Zone Spoke (this blueprint)
│       ├── 1 AI Foundry Resource (hub) per billing boundary / region
│       │   ├── Project: customer-support-dev     → Team Alpha
│       │   ├── Project: customer-support-prod    → Team Alpha
│       │   ├── Project: hr-assistant-dev         → Team Beta
│       │   └── Project: finance-agent-dev        → Team Gamma
│       ├── 1 APIM instance (AI Gateway) — shared across all projects
│       └── 1 Content Safety instance — shared across all projects
│
└── Additional Foundry Resources needed when:
    • Different billing boundary (separate BU / cost center)
    • Regional requirements (data residency in different geography)
    • Quota exhaustion (TPM limits reached in primary region)
    • Compliance isolation (regulated workload requiring physical separation)
```

**Decision Rules (per [AI Landing Zone R-R4](https://azure.github.io/AI-Landing-Zones/architecture/design-checklist/)):**

| Boundary | Create Separate... | Reason |
|----------|-------------------|--------|
| Billing / cost center | Foundry Resource | Cost attribution at resource level |
| Team / application | Foundry Project | RBAC isolation, data separation |
| Environment (dev/staging/prod) | Foundry Project | Same resource, different project with different RBAC |
| Region / data residency | Foundry Resource + VNet spoke | Compliance; data must stay in-region |
| Quota ceiling | Foundry Resource | TPM limits are per-resource |

---

## Lab Structure — Four Parts, Three Personas

```
┌────────────────────────────────────────────────────────────────────────┐
│  Part 1: Build the Platform Foundation        🏗️ IT Platform Eng      │
│  ══════════════════════════════════════                                │
│  Build once. Everyone benefits.                                       │
│  Foundry + VNet + APIM + Policy + Observability + Defender            │
│                                                                        │
├────────────────────────────────────────────────────────────────────────┤
│  Part 2: Establish Governed Self-Service      🧠 AI CoE               │
│  ════════════════════════════════════════                              │
│  Operationalize the factory.                                          │
│  Roles + Blueprints + Identity + Tool Registry + CI/CD Gates          │
│                                                                        │
├────────────────────────────────────────────────────────────────────────┤
│  Part 3: Automated Project Build-Out          🚀 Self-Service         │
│  ═══════════════════════════════════                                   │
│  Request a project, get everything provisioned automatically.         │
│  Self-service portal + two-phase approval + zero-touch provisioning   │
│                                                                        │
├────────────────────────────────────────────────────────────────────────┤
│  Part 4: Ship Your Agent                      👩‍💻 Developers           │
│  ═══════════════════════                                              │
│  Consume the platform. Build and deploy in a day.                     │
│  Agent Framework + Knowledge + Tools + Channels + Production          │
│                                                                        │
└────────────────────────────────────────────────────────────────────────┘
```

---

### Part 1: Build the Platform Foundation — 🏗️ IT Platform Engineering

*IT builds a secure, private AI foundation. This is done once and shared across the entire organization.*

| Chapter | Title | Focus |
|---------|-------|-------|
| [00](./chapters/00-overview.md) | Platform Overview & Architecture | Architecture deep-dive, topology decisions, IQ ecosystem, security philosophy |
| [01](./chapters/01-foundry-byo-networking.md) | Create Microsoft Foundry with BYO Networking | Foundry resource with private VNet, delegated subnets, private endpoints |
| [02](./chapters/02-ai-gateway.md) | Build the AI Gateway (APIM) | APIM as GenAI gateway, VNet injection, unified model API, MCP server hosting |
| [02a](./chapters/02a-mcp-a2a-samples.md) | Publish MCP Tools and A2A Agents | Deploy a weather MCP tool, A2A agent sample, and CoE publication runbook |
| [04](./chapters/04-api-center.md) | Create Azure API Center | Centralized registry for all MCP servers, agents, skills, and APIs |
| [15](./chapters/15-observability.md) | Observability, Evaluation & Red Teaming | Log Analytics, App Insights, dashboards, evaluators, Agent 365 registry |
| [16](./chapters/16-defender.md) | Implement Microsoft Defender for AI | Agent inventory, risk assessment, threat detection, Agent 365 integration |
| [18](./chapters/18-azure-policy-enforcement.md) | Azure Policy — Block Non-Compliant Deployments | 8 custom policies + initiative enforcing the security baseline |
| [19](./chapters/19-network-and-gateway.md) | Network Foundation & APIM AI Gateway | VNet design, subnets, NSGs, Firewall/UDR, DDoS, private DNS zones |
| [20](./chapters/20-observability-and-defender.md) | Observability & Defender Stack (Production) | Production monitoring: alert rules, KQL dashboards, Defender for AI, Agent 365 |

**What you'll have built:** A fully private AI platform with zero public exposure, all traffic through APIM, Azure Policy preventing non-compliant resources, Defender watching for threats, and observability capturing every call. No developer can bypass this foundation.

---

### Part 2: Establish Governed Self-Service — 🧠 AI Center of Excellence

*The AI CoE operationalizes the platform — creating blueprints, processes, and guardrails that let developers self-serve securely.*

| Chapter | Title | Focus |
|---------|-------|-------|
| [17](./chapters/17-roles-and-governance.md) | Governance Model, Roles & Separation of Duties | Three roles, RBAC, Entra ID groups, Conditional Access, Agent 365 governance |
| [21](./chapters/21-foundry-project-blueprint.md) | Lab: Foundry Project Blueprint | Hands-on lab: Bicep template, provisioning script, intake process (learn the mechanics) |
| [22](./chapters/22-identity-rbac-guardrails.md) | Identity, RBAC & Guardrails by Default | Per-agent managed identity, Content Safety, Prompt Shield, SecureAgentRuntime |
| [23](./chapters/23-tool-governance.md) | Tool Governance & Approved MCP Registry | API Center as tool catalog, approval workflow, APIM publication |
| [06](./chapters/06-foundry-iq-knowledge.md) | Create a Foundry IQ Knowledge Base | Enterprise knowledge indexes provisioned by CoE for agent grounding |
| [12](./chapters/12-model-router.md) | Create a Model Router in Foundry | CoE defines model strategy, routing rules, cost optimization across LLMs |
| [25](./chapters/25-cicd-gates.md) | CI/CD Gates — Promote to Production | 6-gate pipeline: security, prompt safety, red team, quality, cost, compliance |
| [28](./chapters/28-day-in-life-ai-coe.md) | Day in the Life: AI CoE | Full day walkthrough — provisioning, gate reviews, tool approvals, alerts |

**What you'll have built:** A governed self-service layer with blueprints, identity guardrails, tool governance, and CI/CD gates — the rules and processes that make self-service safe.

---

### Part 3: Automated Project Build-Out — 🚀 Self-Service Onboarding

*A developer requests a project through the portal, selects models and tools from the approved catalog, and receives a fully provisioned environment — automatically, with zero manual steps.*

| Chapter | Title | Focus |
|---------|-------|-------|
| [21a](./chapters/21a-self-service-portal.md) | Self-Service Portal: Automated Provisioning | Fully automated UX portal — developer requests, IT approves (infra auto-deploys), CoE approves (governance auto-deploys), zero manual steps |
| [27](./chapters/27-developer-journey.md) | The Governed Developer Journey | End-to-end scenario: request → onboard → build → submit → production |
| [26](./chapters/26-end-to-end-walkthrough.md) | Secure Agent Factory End-to-End Walkthrough | Complete flow from request to production, proof no bypass is possible |

**What you'll have built:** A fully automated onboarding pipeline — developers request a project through a UX portal, IT and CoE approve with one click, and the platform auto-provisions the Foundry project, models, tools, memory, identity, APIM routes, CI/CD pipelines, and the onboarding package. Zero CLI, zero tickets, zero wait.

---

### Part 4: Ship Your Agent — 👩‍💻 Developers

*Developers consume the platform — build agents, connect data sources, test locally, push to production in a day.*

| Chapter | Title | Focus |
|---------|-------|-------|
| [03](./chapters/03-agent-framework.md) | Build an Agent with Microsoft Agent Framework | Create agent, memory, harness, expose via A2A protocol |
| [05](./chapters/05-react-discovery-ui.md) | Build a React Discovery UI | Custom UI for agent, MCP tool, and skill discovery |
| [07](./chapters/07-prompt-agent.md) | Build a Prompt Agent in Foundry | Agent with knowledge base, MCP tools, and A2A calls |
| [08](./chapters/08-hosted-agent.md) | Build a Hosted Agent in Foundry | Deploy Agent Framework agent as hosted agent, expose via A2A in APIM |
| [09](./chapters/09-work-iq.md) | Connect Your Agent with Work IQ | Microsoft 365 data grounding (emails, Teams, SharePoint, calendar) |
| [10](./chapters/10-serverless-agent.md) | Create a Serverless Agent with Azure Functions | Event-driven agents with the serverless agents runtime |
| [11](./chapters/11-fabric-iq.md) | Connect Your Agent with Fabric IQ (Optional) | Lakehouse, ontology, and Fabric IQ integration for data analytics |
| [13](./chapters/13-m365-custom-engine.md) | Expose as Custom Engine Agent in M365 | Surface hosted agent in Microsoft 365 Copilot and Teams |
| [14](./chapters/14-copilot-studio-vnet.md) | Connect Copilot Studio to APIM MCP via VNet | Private endpoint connectivity, VNet integration, low-code MCP access |
| [24](./chapters/24-developer-build-experience.md) | Developer Experience — Build an Agent | Constrained sandbox, APIM-only access, local testing with guardrails |

**What you'll have built:** Production-ready agents using approved models, governed tools, and pre-configured guardrails — deployed through CI/CD gates in the same day, with zero infrastructure work.

---

### Validation & Operations (Cross-cutting)

| Chapter | Title | Focus |
|---------|-------|-------|
| [29](./chapters/29-day-in-life-it-platform.md) | Day in the Life: IT Platform Engineering | Platform health, policy enforcement, security triage, capacity planning |

---

### Reading Order by Persona

| If you are... | Start here | Then... |
|---|---|---|
| **IT Platform Engineer** | Part 1 (Chapters 00, 01, 02, 04, 15, 16, 18, 19, 20) → Chapter 29 | You build the foundation and operate it |
| **AI CoE member** | Part 2 (Chapters 17, 21, 22, 23, 06, 12, 25) → Chapter 28 | You govern, provision, and approve |
| **Developer** | Part 3 (Chapters 21a, 27, 26) → Part 4 (Chapters 03, 07, 08, 24) | Request a project, then build agents within guardrails |
| **Architect / Decision maker** | Chapter 00 → This README → Part 3 (Chapter 26) | You validate the architecture end-to-end |

---

## The Secure Agent Factory — Why It Exists

### The Problem: Shadow AI & Ungoverned Agents

As organizations adopt AI agents, a dangerous pattern emerges:

| Without Governance | What Happens |
|---|---|
| Developers create AI resources directly | No visibility into what's deployed or who owns it |
| Direct model endpoint access | No rate limits, no content filtering, no audit trail |
| Any tool, any MCP server | Data exfiltration risk, prompt injection from untrusted tools |
| Shared API keys and secrets | Credential sprawl, no revocation, lateral movement risk |
| No deployment gates | Hallucinating, unsafe, or expensive agents reach production |
| Optional observability | Incidents discovered by users, not by the platform |

The result is **Shadow AI** — untracked, ungoverned, and potentially dangerous agents operating across the enterprise with no central oversight, no cost control, and no safety guarantees.

### The Solution: A Factory That Makes Security the Default

The **Secure Agent Factory** is a governance layer that wraps the Internet of Agents platform (Chapters 00-16) to ensure that every agent built, tested, and deployed follows enterprise security and compliance standards — **without slowing developers down**.

The core principle: **developers should be productive, but they should never be able to bypass security — even if they try.**

```
┌─────────────────────────────────────────────────────────────────────────┐
│                     SECURE AGENT FACTORY                                 │
│                                                                         │
│  ┌─────────────────┐    ┌──────────────────┐    ┌───────────────────┐  │
│  │  PLATFORM        │    │  AI CENTER OF    │    │  DEVELOPERS       │  │
│  │  ENGINEERING     │    │  EXCELLENCE      │    │                   │  │
│  │                  │    │  (AI CoE)        │    │  • Build agents   │  │
│  │  • Provisions    │    │                  │    │  • Use approved   │  │
│  │    infrastructure│    │  • Approves      │    │    models & tools │  │
│  │  • Azure Policy  │    │    projects      │    │  • Push through   │  │
│  │  • Network/VNet  │    │  • Onboards      │    │    CI/CD gates   │  │
│  │  • Defender      │    │    developers    │    │  • Cannot bypass  │  │
│  │  • Agent 365     │    │  • Reviews PRs   │    │    guardrails    │  │
│  │  • Observability │    │  • Deploys to    │    │  • No infra      │  │
│  │    stack         │    │    production    │    │    access         │  │
│  └────────┬─────────┘    └────────┬─────────┘    └────────┬──────────┘  │
│           │                       │                        │             │
│           ▼                       ▼                        ▼             │
│  ┌────────────────────────────────────────────────────────────────────┐ │
│  │                    ENFORCEMENT PLANE                                │ │
│  │                                                                    │ │
│  │   Azure Policy    │  Network (NSG/APIM)  │  Identity (RBAC)       │ │
│  │   "Cannot create  │  "Cannot reach models │  "Cannot escalate     │ │
│  │    non-compliant  │   except through APIM" │   beyond developer   │ │
│  │    resources"     │                        │   role"              │ │
│  ├───────────────────┼────────────────────────┼──────────────────────┤ │
│  │   Content Safety  │  Tool Governance       │  CI/CD Gates         │ │
│  │   "Every I/O is   │  "Only approved MCP   │  "6 gates must pass  │ │
│  │    filtered"      │   servers reachable"   │   before production" │ │
│  └────────────────────────────────────────────────────────────────────┘ │
│                                                                         │
│           ┌───────────────────────────────────────────────┐             │
│           │         INTERNET OF AGENTS PLATFORM            │             │
│           │    (Foundry, APIM, MCP, Agent Framework,       │             │
│           │     API Center, Agent 365, Observability,      │             │
│           │     Defender)                                   │             │
│           └───────────────────────────────────────────────┘             │
└─────────────────────────────────────────────────────────────────────────┘
```

### The Three Roles — Separation of Duties

The Secure Agent Factory enforces a strict separation between three personas. No single role can provision infrastructure **and** write agent code **and** deploy to production:

```
┌───────────────────────────────────────────────────────────────────────┐
│                                                                       │
│   PLATFORM ENGINEERING          AI CoE              DEVELOPERS        │
│   ════════════════════          ═════               ══════════        │
│                                                                       │
│   "We build the rails"    "We govern the train"   "We ride the train"│
│                                                                       │
│   ┌───────────────────┐   ┌───────────────────┐   ┌────────────────┐│
│   │ • Deploy VNets,   │   │ • Approve project │   │ • Write agent  ││
│   │   NSGs, Firewall  │   │   requests        │   │   code         ││
│   │ • Configure APIM  │   │ • Run Bicep       │   │ • Use APIM     ││
│   │   AI Gateway      │   │   blueprint to    │   │   endpoints    ││
│   │ • Set Azure Policy│   │   create Foundry  │   │   (only path)  ││
│   │ • Deploy Defender │   │   projects        │   │ • Test locally ││
│   │   & App Insights  │   │ • Manage tool     │   │   with         ││
│   │ • Manage DNS &    │   │   registry        │   │   guardrails   ││
│   │   private zones   │   │ • Review PRs as   │   │ • Submit PRs   ││
│   │                   │   │   CODEOWNERS      │   │   for review   ││
│   │ CANNOT:           │   │ • Deploy to prod  │   │                ││
│   │ ✗ Write agent code│   │                   │   │ CANNOT:        ││
│   │ ✗ Access models   │   │ CANNOT:           │   │ ✗ Create infra ││
│   │ ✗ Deploy agents   │   │ ✗ Modify network  │   │ ✗ Access models││
│   │                   │   │ ✗ Change policies │   │   directly     ││
│   │                   │   │ ✗ Disable logging │   │ ✗ Deploy to    ││
│   │                   │   │                   │   │   production   ││
│   │                   │   │                   │   │ ✗ Disable      ││
│   │                   │   │                   │   │   guardrails   ││
│   └───────────────────┘   └───────────────────┘   └────────────────┘│
│                                                                       │
│   Entra ID Group:          Entra ID Group:         Entra ID Group:   │
│   sg-platform-engineering  sg-ai-coe               sg-agent-developers│
│                                                                       │
│   Azure Role:              Azure Role:             Azure Role:        │
│   Contributor (infra RG)   AI CoE Custom Role      Cognitive Services │
│   + Network Contributor    (Foundry project scope)  User (via APIM)  │
└───────────────────────────────────────────────────────────────────────┘
```

### How It All Connects — The Agent Lifecycle

```
     Developer                    AI CoE                   Platform Eng
     ─────────                    ──────                   ────────────
         │                           │                          │
    1. Submit Project Request ──────▶│                          │
         │                           │                          │
         │                    2. Approve & Run ────────────────▶│
         │                       Blueprint                      │
         │                           │                    3. Infrastructure
         │                           │◀───── already exists ───(in place)
         │                           │
         │◀──── 4. Onboarding ───────│
         │         Package           │
         │                           │
    5. Build Agent                   │
       (APIM-only access)            │
         │                           │
    6. Push PR ─────────────────────▶│
         │                           │
         │                    7. CI/CD 6 Gates
         │                       (automated)
         │                           │
         │                    8. Review & Approve
         │                           │
         │                    9. Deploy to Prod ───────────────▶│
         │                           │                   (monitored forever)
         │                           │                          │
```

### Key Design Principles

| Principle | Implementation |
|-----------|---------------|
| **Zero Trust** | Every call authenticated, every network path explicitly allowed, no implicit trust |
| **Least Privilege** | Each role has minimum permissions; developers cannot escalate |
| **Security by Default** | Content Safety, Prompt Shield, and observability are non-optional |
| **No Shadow AI** | APIM is the only network path to models; direct access is blocked by NSGs |
| **Governed Tools** | API Center + APIM allowlist = only approved MCP tools are reachable |
| **Automated Enforcement** | Azure Policy denies non-compliant resources before they exist |
| **Quality Gates** | 6 CI/CD gates (security, prompt safety, red team, quality, cost, compliance) |
| **Full Audit Trail** | Every model call, tool invocation, and deployment logged and queryable |
| **Developer Velocity** | Same-day builds via starter templates, self-service catalog, automated onboarding |

---

## Prerequisites

- Azure subscription with Owner or Contributor access
- Microsoft 365 Copilot license (for Work IQ and M365 chapters)
- Microsoft Fabric capacity (for Fabric IQ chapter)
- Azure CLI installed and authenticated
- Visual Studio Code with GitHub Copilot extension
- Python 3.11+ and Node.js 20+
- Docker Desktop (for container deployments)

---

## Architecture Overview

```
┌─────────────────────────────────────────────────────────────────────┐
│                    User, Channel & Discovery Layer                  │
│  M365 Copilot │ Teams │ Custom React UI │ Headless API │ Portals  │
└──────────────────────────────┬──────────────────────────────────────┘
                               │
┌──────────────────────────────▼──────────────────────────────────────┐
│              Enterprise Agency Platform / Agency Hub                 │
│                                                                     │
│  ┌──────────────┐  ┌─────────────────────┐  ┌───────────────────┐  │
│  │  Enterprise   │  │ Agent Collaboration │  │  Developer +      │  │
│  │  Catalog      │  │ Mesh (A2A)          │  │  Admin Portal     │  │
│  │  • Agent Reg  │  │ • Discovery         │  │  • Marketplace    │  │
│  │  • MCP Tools  │  │ • Delegation        │  │  • Publish/Certify│  │
│  │  • Skills     │  │ • Orchestration     │  │  • Usage + Cost   │  │
│  │  • Knowledge  │  │                     │  │                   │  │
│  └──────────────┘  └─────────────────────┘  └───────────────────┘  │
│                                                                     │
│  Internal Agents                    External / Partner Agents       │
│  • Research, Procurement, Data      • AWS, Google, 3rd-party       │
└──────────────────────────────┬──────────────────────────────────────┘
                               │
┌──────────────────────────────▼──────────────────────────────────────┐
│          Governance, Security & Observability Plane                  │
│  Microsoft Defender │ Azure Monitor │ Foundry Evaluations │         │
│  Content Safety │ Responsible AI │ Guardrails │ Audit Logs │ Policy │
└──────────────────────────────┬──────────────────────────────────────┘
                               │
┌──────────────────────────────▼──────────────────────────────────────┐
│     AI Gateway & Agent Connectivity Layer (Central Control Plane)    │
│                                                                     │
│  ┌───────────┐    ┌───────────────────────┐    ┌─────────────────┐ │
│  │ REST APIs  │───▶│  Azure API Center     │    │ Runtime Controls│ │
│  │ MCP Endpts │───▶│  • API Center         │    │ • Model routing │ │
│  │ Agent Endpts│──▶│  • MCP Registry       │───▶│ • Semantic cache│ │
│  │ A2A Endpts │   │  • Tool Catalog       │    │ • Load balancing│ │
│  └───────────┘    │  • Tool Discovery     │    │ • Token optimize│ │
│                    └───────────┬───────────┘    │ • Rate limiting │ │
│                                │                │ • AuthN/AuthZ   │ │
│                    ┌───────────▼───────────┐    │ • Policy controls│ │
│                    │   AI Gateway (APIM)    │    └─────────────────┘ │
│                    │   • VNet Injection     │                        │
│                    │   • Private Endpoints  │───▶ Azure OpenAI      │
│                    │   • MCP Gateway        │───▶ Azure AI Models   │
│                    │   • A2A Broker         │───▶ Anthropic Claude  │
│                    └───────────────────────┘───▶ AWS Bedrock        │
│                                              ───▶ Google Gemini     │
└──────────────────────────────┬──────────────────────────────────────┘
                               │
┌──────────────────────────────▼──────────────────────────────────────┐
│                   Memory & Learning Layer                            │
│  Long-Term Agent Memory ──▶ Semantic Memory ──▶ Episodic Memory     │
│  ──▶ Durable Execution ──▶ Human Feedback Loop ──▶ Planning +       │
│      Reflection                                                     │
└─────────────────────────────────────────────────────────────────────┘
```

---

## Network Architecture (Zero-Trust)

```
┌─────────────────────────────────────────────────────────────────┐
│                    Enterprise Network Boundary                   │
│                                                                 │
│  ┌──────────────────────┐    ┌──────────────────────────────┐  │
│  │   Hub VNet            │    │  Spoke VNet (AI Platform)    │  │
│  │   • Azure Firewall    │◄──▶│  • APIM Subnet (delegated)  │  │
│  │   • Azure Bastion     │    │  • App Service Subnet        │  │
│  │   • VPN/ExpressRoute  │    │  • Foundry Delegated Subnet  │  │
│  │   • DNS Forwarders    │    │  • Private Endpoint Subnet   │  │
│  └──────────────────────┘    │  • ACA Subnet                │  │
│                               └──────────────────────────────┘  │
│                                                                 │
│  Private DNS Zones:                                             │
│  • privatelink.azure-api.net    • privatelink.openai.azure.com │
│  • privatelink.blob.core.windows.net                           │
│  • privatelink.vaultcore.azure.net                             │
│  • privatelink.database.windows.net                            │
│  • privatelink.cognitiveservices.azure.com                     │
└─────────────────────────────────────────────────────────────────┘
```

---

## Getting Started

1. **Read [Chapter 00 — Platform Overview](./chapters/00-overview.md)** for the architecture deep-dive
2. **Pick your persona** from the Reading Order table above and follow that path
3. **Validate with [Chapter 26](./chapters/26-end-to-end-walkthrough.md)** to see the complete end-to-end flow

Each part is self-contained — IT Platform can complete Part 1 independently, CoE completes Part 2 on top, and Developers use Part 3 immediately once Parts 1 and 2 are in place.

### Reference Implementations (IaC)

| Repository | Use |
|-----------|-----|
| [Azure AI Landing Zones — Bicep](https://github.com/Azure/AI-Landing-Zones) | Official IaC for AI Foundry + AI Gateway landing zones |
| [Azure AI Landing Zones — Terraform](https://github.com/Azure/AI-Landing-Zones) | Terraform variant of the same architecture |

This blueprint extends the AI Landing Zone reference by adding: persona-based governance (Ch 17-23), CI/CD quality gates (Ch 25), agent development patterns (Ch 03-14), and Microsoft Agent 365 integration (Ch 15-16, 20).
