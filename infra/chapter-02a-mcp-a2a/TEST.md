# Chapter 02a Test Guide

Run data-plane tests from the peered VM used in Chapter 02 because APIM is internal.

## 1. Confirm the resources

```powershell
az apim api list -g rg-agentic-ai-blueprint-dev --service-name apim-agent-blueprint-dev-a5jiq4re `
  --query "[].{Name:name,Type:apiType,Path:path}" -o table
```

Expect `weather-api`, `weather-mcp`, and `packing-advisor-backend`.

## 2. Test the weather REST API

```powershell
curl.exe "https://apim-agent-blueprint-dev-a5jiq4re.azure-api.net/weather/Seattle"
```

Expect JSON containing `current_condition` and `nearest_area`.

## 3. Test MCP discovery

Add this HTTP server URL with **MCP: Add Server** in VS Code:

```text
https://apim-agent-blueprint-dev-a5jiq4re.azure-api.net/mcp/weather/mcp
```

Enable `get-city-weather`, then ask: `What is the weather in Seattle?`

## 4. Test the A2A backend and card

```powershell
curl.exe "https://apim-agent-blueprint-dev-a5jiq4re.azure-api.net/a2a/packing-advisor-backend/.well-known/agent-card.json"

$body = @{
  jsonrpc = '2.0'
  id = 'demo-1'
  method = 'message/send'
  params = @{
    message = @{
      role = 'user'
      messageId = 'message-1'
      parts = @(@{ kind = 'text'; text = 'Seattle' })
    }
  }
} | ConvertTo-Json -Depth 8 -Compress

Invoke-RestMethod -Method Post `
  -Uri 'https://apim-agent-blueprint-dev-a5jiq4re.azure-api.net/a2a/packing-advisor-backend' `
  -ContentType 'application/json' -Body $body | ConvertTo-Json -Depth 10
```

Expect a JSON-RPC response whose task state is `completed` and whose text contains a packing checklist.

## 5. Test the imported A2A facade

After completing the chapter's portal import, copy the **Runtime base URL** and **Agent card URL** from the imported A2A API overview. Repeat the card GET and JSON-RPC POST against those URLs. APIM should rewrite the card to advertise its governed hostname.

## 6. Test MCP and A2A from a Microsoft Foundry toolbox agent (agent identity)

Run this test from a host that can reach the private Foundry project endpoint. The Foundry project must use Standard Agent Setup with private networking and have network/DNS access to the internal APIM gateway.

This test uses the recommended **toolbox** pattern: it bundles the weather MCP tool and the Packing Advisor A2A agent into one toolbox, then attaches the toolbox to a prompt agent as a single MCP tool. The two inner tools authenticate to APIM with the **agent identity**.

### 6.1 Fix the agent identity before you run (ARA BadRequest)

The error `Failed to fetch agentic identity access token ... ARA request failed with status BadRequest` means the agent identity token exchange failed. Resolve these in order:

1. **Provision the agent identity.** The shared project agent identity only exists after you create your first agent in the project. Create any agent once, then in the Azure portal open the project > **Overview** > **JSON View** and copy `agentIdentityId`.
2. **Use a valid audience — the most common cause.** The `AgenticIdentityToken` connection audience must be a Microsoft Entra resource identifier (an app registration **Application ID URI**, for example `api://<app-id>`), **not** the APIM gateway URL. Register (or reuse) an Entra app that fronts the APIM MCP/A2A APIs and use its Application ID URI as the audience.
3. **Grant access to the agent identity.** Assign `agentIdentityId` the app role the APIM-fronted APIs require, so APIM accepts the issued token. Exact steps are in [6.1.2](#612-grant-the-agent-identity-access-step-3-in-detail).
4. **Confirm the connection categories.** MCP uses `authType=AgenticIdentityToken`, category `RemoteTool`. A2A uses `authType=AgenticIdentityToken`, category `RemoteA2A`. Both must be shared to the project.

### 6.1.1 Create or find the audience app registration

The audience is a Microsoft Entra app registration that represents the APIM-fronted MCP and A2A APIs. Its **Application (client) ID** is the `<audience-app-id>` used below, and its **Application ID URI** (`api://<audience-app-id>`) is the `<audience>` used in step 2 and in the connections in 6.2. Run these from a workstation signed in with Azure CLI (`az login`) as a user who can register applications.

Check whether one already exists (for example, created when APIM was configured):

```powershell
az ad app list --display-name 'agent-blueprint-apim-agent-tools' `
  --query "[].{name:displayName,appId:appId}" -o table
```

If it exists, capture its client ID and skip to 6.1.2:

```powershell
$apiAppId = az ad app show --id '<existing-app-id-or-name>' --query appId -o tsv
Write-Host "Audience app client ID: $apiAppId"
```

Otherwise create it:

```powershell
# 1. Register the app for the APIM agent-tools APIs.
$apiAppId = az ad app create `
  --display-name 'agent-blueprint-apim-agent-tools' `
  --sign-in-audience AzureADMyOrg `
  --query appId -o tsv

# 2. Set the Application ID URI so issued tokens carry aud = api://<appId>.
az ad app update --id $apiAppId --identifier-uris "api://$apiAppId"

# 3. Create the service principal so the app can be a token audience and hold role assignments.
az ad sp create --id $apiAppId

Write-Host "Audience app client ID (<audience-app-id>): $apiAppId"
Write-Host "Audience (<audience>): api://$apiAppId"
```

Use `api://$apiAppId` as `<audience>` in step 2 and in the 6.2 connections, and `$apiAppId` as `<audience-app-id>` in 6.1.2.

### 6.1.2 Grant the agent identity access (step 3 in detail)

`agentIdentityId` is the object ID of the agent identity **service principal**. The audience app is the Entra app registration from 6.1.1. Run these from a workstation signed in with Azure CLI (`az login`) as a user who can manage that app registration.

If the audience app has no application app role yet, define one first (skip if it already exists). Windows PowerShell mangles inline JSON passed to `az rest --body`, so write the payload to a UTF-8 (no BOM) temp file and pass `--body "@file"`:

```powershell
$apiAppId    = '<audience-app-id>'   # appId (client ID) of the audience app registration
$apiObjectId = az ad app show --id $apiAppId --query id -o tsv

$appRole = @{
  allowedMemberTypes = @('Application')
  description        = 'Allow calling the APIM-fronted MCP and A2A APIs'
  displayName        = 'Invoke APIM agent tools'
  id                 = [guid]::NewGuid().ToString()
  isEnabled          = $true
  value              = 'Mcp.Invoke'
}
$body     = @{ appRoles = @($appRole) } | ConvertTo-Json -Depth 5
$bodyFile = New-TemporaryFile
[System.IO.File]::WriteAllText($bodyFile.FullName, $body)
az rest --method PATCH `
  --url "https://graph.microsoft.com/v1.0/applications/$apiObjectId" `
  --headers 'Content-Type=application/json' `
  --body "@$($bodyFile.FullName)"
Remove-Item $bodyFile.FullName
```

Assign that app role to the agent identity (application permission, client-credentials flow). Use the same temp-file approach for the request body:

```powershell
$agentIdentityId = '<agentIdentityId>'   # object ID of the agent identity service principal
$apiSp     = az ad sp show --id $apiAppId -o json | ConvertFrom-Json
$appRoleId = ($apiSp.appRoles | Where-Object { $_.value -eq 'Mcp.Invoke' -and $_.isEnabled }).id

$assignment = @{
  principalId = $agentIdentityId
  resourceId  = $apiSp.id
  appRoleId   = $appRoleId
} | ConvertTo-Json
$assignFile = New-TemporaryFile
[System.IO.File]::WriteAllText($assignFile.FullName, $assignment)
az rest --method POST `
  --url "https://graph.microsoft.com/v1.0/servicePrincipals/$agentIdentityId/appRoleAssignments" `
  --headers 'Content-Type=application/json' `
  --body "@$($assignFile.FullName)"
Remove-Item $assignFile.FullName
```

Verify the assignment:

```powershell
az rest --method GET `
  --url "https://graph.microsoft.com/v1.0/servicePrincipals/$agentIdentityId/appRoleAssignments" `
  --query "value[].{api:resourceDisplayName,appRoleId:appRoleId}" -o table
```

Finally, make APIM enforce the token so the role is actually required. Apply a `validate-azure-ad-token` policy to **both** APIs the connections call: the MCP server API (`weather-mcp`, path `/mcp/weather`) and the imported A2A Agent API (base path `agents/packing-advisor`).

First get your tenant ID:

```powershell
az account show --query tenantId -o tsv
```

Then, for each of the two APIs, add the policy in the Azure portal:

1. Open the APIM instance `apim-agent-blueprint-dev-a5jiq4re` > **APIs**.
2. Select the API (**City Weather MCP Server**, then repeat for the imported **Packing Advisor A2A**).
3. Select **All operations** (so the policy applies to every operation in the API).
4. On the **Design** tab, in the **Inbound processing** box, select the **`</>`** (code editor) icon.
5. Place the `<validate-azure-ad-token>` element **inside `<inbound>`, immediately after `<base />`**, replacing `<tenant-id>` and `<audience-app-id>`. The result should look like this:

   ```xml
   <policies>
     <inbound>
       <base />
       <validate-azure-ad-token tenant-id="<tenant-id>">
         <audiences>
           <audience>api://<audience-app-id></audience>
         </audiences>
         <required-claims>
           <claim name="roles" match="any">
             <value>Mcp.Invoke</value>
           </claim>
         </required-claims>
       </validate-azure-ad-token>
     </inbound>
     <backend>
       <base />
     </backend>
     <outbound>
       <base />
     </outbound>
     <on-error>
       <base />
     </on-error>
   </policies>
   ```

6. Select **Save**. Keep any existing elements (for example, the Chapter 02a rate-limit policy) — only add the `<validate-azure-ad-token>` element after `<base />`; do not remove what is already there.

> Placing the policy at the **API scope** (All operations) covers every operation, including MCP discovery and the A2A card and JSON-RPC endpoints. `<base />` first ensures product/global policies still run, and the token check runs before the request reaches the backend.

If your APIM policy validates only the audience and issuer (no `roles` claim), the app-role assignment above is still required for Entra to mint a client-credentials token for `api://<audience-app-id>` — without it, the token exchange fails with the same ARA BadRequest.

### 6.2 Create the three project connections

Create these with the Azure Developer CLI (`azd ai connection create`) or the Foundry portal. Replace `<audience>` with the Entra Application ID URI from step 6.1.

```powershell
# Inner MCP connection (agent identity to the APIM MCP server)
azd ai connection create chapter02a-weather-mcp `
  --kind remote-tool `
  --target 'https://apim-agent-blueprint-dev-a5jiq4re.azure-api.net/mcp/weather/mcp' `
  --auth-type agentic-identity --audience '<audience>'

# Inner A2A connection (agent identity to the APIM A2A facade)
azd ai connection create chapter02a-packing-advisor `
  --kind remote-a2a `
  --target 'https://apim-agent-blueprint-dev-a5jiq4re.azure-api.net/agents/packing-advisor' `
  --auth-type agentic-identity --audience '<audience>'

# Outer toolbox connection (caller identity to the toolbox MCP endpoint)
azd ai connection create chapter02a-toolbox-conn `
  --kind remote-tool `
  --target "$env:FOUNDRY_PROJECT_ENDPOINT/toolboxes/chapter02a-agent-tools/mcp?api-version=v1" `
  --auth-type user-entra-token --audience 'https://ai.azure.com'
```

> **Audience rule (do not skip):** the two **inner** connections (`agentic-identity`) must use the
> Entra **Application ID URI** `api://<audience-app-id>` as their audience. Only the **outer**
> toolbox connection (`user-entra-token`) uses `https://ai.azure.com`. Mixing these up — or leaving
> the audience empty — is what produces `Failed to fetch agentic identity access token with status
> code: 400`.

### 6.2.1 Verify and repair the connection audience (prevents the 400 error)

Connections created in the **Foundry portal** or by some `azd` versions can land with
`audience = null` or with the **APIM gateway URL** instead of `api://<audience-app-id>`. Either value
breaks the agent-identity token exchange with a `400`. **Always verify after creating a connection.**

Set context (account resource ID and the audience app URI):

```powershell
$rg      = 'rg-agentic-ai-blueprint-dev'
$acctName = '<your-foundry-account-name>'
$acctId  = "/subscriptions/$((az account show --query id -o tsv))/resourceGroups/$rg/providers/Microsoft.CognitiveServices/accounts/$acctName"
$apiAppId = az ad app list --display-name 'agent-blueprint-apim-agent-tools' --query "[0].appId" -o tsv
$audience = "api://$apiAppId"
```

Verify each inner connection:

```powershell
foreach ($c in 'chapter02a-weather-mcp','chapter02a-packing-advisor') {
  $a = az rest --method GET --url "https://management.azure.com$acctId/connections/$c?api-version=2025-06-01" --query "properties.audience" -o tsv
  Write-Host ("{0,-30} audience = {1}" -f $c, ($a ? $a : '<null>'))
}
```

✅ Expect both to print `api://<audience-app-id>`.
❌ If either prints `<null>` or an `https://...azure-api.net...` URL, repair it in place:

```powershell
# Repeat per connection. Use category 'RemoteTool' + the MCP target for the MCP connection,
# and category 'RemoteA2A' + the A2A target for the A2A connection.
$connName = 'chapter02a-weather-mcp'
$category = 'RemoteTool'
$target   = 'https://apim-agent-blueprint-dev-a5jiq4re.azure-api.net/mcp/weather/mcp'

$body = "{""properties"":{""category"":""$category"",""target"":""$target"",""authType"":""AgenticIdentityToken"",""audience"":""$audience""}}"
$f = New-TemporaryFile; [System.IO.File]::WriteAllText($f.FullName, $body)
az rest --method PUT --url "https://management.azure.com$acctId/connections/$connName?api-version=2025-06-01" `
  --headers 'Content-Type=application/json' --body "@$($f.FullName)" `
  --query "{name:name,audience:properties.audience}" -o json
Remove-Item $f.FullName
```

✅ Re-run the verify loop; both must now read `api://<audience-app-id>` before you test.

### 6.3 Install SDK packages

```powershell
python -m pip install "azure-ai-projects>=2.0.0" azure-identity
```

### 6.4 Run the integration test

```powershell
$env:FOUNDRY_PROJECT_ENDPOINT = 'https://<account>.services.ai.azure.com/api/projects/<project>'
$env:FOUNDRY_MODEL_NAME = 'gpt-4o'
$env:CHAPTER_02A_MCP_CONNECTION = 'chapter02a-weather-mcp'
$env:CHAPTER_02A_A2A_CONNECTION = 'chapter02a-packing-advisor'
$env:CHAPTER_02A_TOOLBOX_CONNECTION = 'chapter02a-toolbox-conn'
python ./test-foundry-agent.py
```

The script resolves the three connections, creates one temporary toolbox (weather MCP tool + Packing Advisor A2A tool) and one prompt agent, invokes each tool, checks tool-call traces and deterministic response content, then deletes the agent and toolbox versions. If the agent identity token exchange fails, it prints the ARA troubleshooting checklist above. Use `--keep-resources` to retain the toolbox and agent for troubleshooting.

---

## 7. Consuming MCP + A2A from a **network-injected** Foundry agent (portal prompt agent)

This section captures the exact issues encountered when attaching the weather **MCP** tool and the
Packing Advisor **A2A** tool directly to a prompt agent in the Foundry portal, and the fixes that make
the flow work end to end. Follow these to avoid re-hitting them.

### 7.0 Prerequisite: network injection

A Foundry agent can only reach the **internal** APIM gateway if its account has **network injection**
(Standard Agent Setup). Without it, tool calls fail with *"The host name could not be resolved from the
selected network path."* Deploy Chapter 01a first:
[`infra/chapter-01a-standard-agent-network-injection`](../chapter-01a-standard-agent-network-injection/README.md).
Build the agent on the **Standard** project (e.g. `agent-blueprint-dev-project-std`).

### 7.1 MCP tool — connection audience (400)

Create the MCP connection with `authType=AgenticIdentityToken` and audience `api://<audience-app-id>`
(never the APIM URL, never null). Verify/repair per [§6.2.1](#621-verify-and-repair-the-connection-audience-prevents-the-400-error).
Grant the project's agent identity the `Mcp.Invoke` app role ([§6.1.2](#612-grant-the-agent-identity-access-step-3-in-detail)).

### 7.2 A2A tool — three fixes the raw backend needs

The A2A tool fetches the agent **card**, then calls JSON-RPC `message/send`. Three things must be true,
or you get (in order) a 404, a JSON-parse error, then an `InvalidRequest`:

**(a) Serve the agent card at the APIM HOST ROOT.**
Foundry's A2A client fetches the card from the **host-root** well-known path
(`https://<apim-host>/.well-known/agent-card.json`, per RFC 8615), **not** under the API sub-path. A
card exposed only at `.../a2a/packing-advisor-backend/.well-known/agent-card.json` returns **404**.
Create a root-path APIM API that serves it:

```powershell
$b = "/subscriptions/<sub>/resourceGroups/<rg>/providers/Microsoft.ApiManagement/service/<apim>"
# 1. Root API (empty path)
$api = '{"properties":{"displayName":"A2A Well-Known Card","path":"","protocols":["https"],"subscriptionRequired":false}}'
$f=New-TemporaryFile; [IO.File]::WriteAllText($f.FullName,$api)
az rest --method PUT --url "https://management.azure.com$b/apis/a2a-wellknown?api-version=2024-05-01" --headers 'Content-Type=application/json' --body "@$($f.FullName)"; Remove-Item $f.FullName
# 2. GET /.well-known/agent-card.json operation
$op = '{"properties":{"displayName":"Get Agent Card","method":"GET","urlTemplate":"/.well-known/agent-card.json","templateParameters":[],"responses":[]}}'
$f=New-TemporaryFile; [IO.File]::WriteAllText($f.FullName,$op)
az rest --method PUT --url "https://management.azure.com$b/apis/a2a-wellknown/operations/get-agent-card?api-version=2024-05-01" --headers 'Content-Type=application/json' --body "@$($f.FullName)"; Remove-Item $f.FullName
```

Then set the operation policy to `return-response` the card JSON (see (b) for the required body), and
set the **A2A connection target to the host root** `https://<apim-host>` (the card's `url` field routes
the actual JSON-RPC to `.../a2a/packing-advisor-backend`).

**(b) The card must include the A2A v0.3 required `version` field.**
Missing it fails with *"AgentCard was missing required properties including: 'version'."* A valid card:

```json
{
  "protocolVersion": "0.3.0",
  "name": "Packing Advisor",
  "description": "Creates a practical packing checklist for a destination.",
  "url": "https://<apim-host>/a2a/packing-advisor-backend",
  "version": "1.0.0",
  "preferredTransport": "JSONRPC",
  "capabilities": { "streaming": false, "pushNotifications": false },
  "defaultInputModes": ["text/plain"],
  "defaultOutputModes": ["text/plain"],
  "skills": [ { "id": "create-packing-list", "name": "Create packing list", "description": "...", "tags": ["travel"], "examples": ["Seattle"], "inputModes": ["text/plain"], "outputModes": ["text/plain"] } ]
}
```

**(c) The JSON-RPC response must carry `kind` discriminators.**
Missing them fails with *"Missing required 'kind' discriminator for A2AResponse."* The `send-message`
response `result` must be a Task with `kind:"task"`, its `status.message` a Message with `kind:"message"`,
and each part `kind:"text"`:

```json
{
  "jsonrpc": "2.0",
  "id": "<request id>",
  "result": {
    "kind": "task",
    "id": "<task id>",
    "contextId": "<context id>",
    "status": {
      "state": "completed",
      "message": {
        "kind": "message",
        "role": "agent",
        "messageId": "<message id>",
        "parts": [ { "kind": "text", "text": "Packing checklist for <destination>: ..." } ]
      }
    }
  }
}
```

> **APIM policy tip:** when applying the card/response policies with `az rest ... format=rawxml`, write
> the JSON body as UTF-8 **without a BOM**, and double-check the C# `return-response` expression has
> balanced parentheses — an off-by-one fails only at runtime.

### 7.3 Attach both tools and test

On the Standard project's agent, add **WeatherMCP** and **PackingAdvisorA2A** tools. Test prompts:

- MCP: *"what is the weather in seattle"* → weather text.
- A2A: *"Ask the packing advisor what to pack for Seattle"* → packing checklist.

If A2A doesn't invoke, make the prompt explicitly require calling the remote agent.

### 7.4 A2A consumption error-to-fix map

| Error | Cause | Fix |
|---|---|---|
| `host name could not be resolved from the selected network path` | Account not network-injected | Deploy Chapter 01a; build agent on the Standard project (7.0) |
| `Failed to fetch agentic identity access token ... 400` | Connection audience null/APIM URL | Set audience `api://<audience-app-id>` (7.1) |
| `Failed to fetch agent card: 404` | Card not at host root | Serve `/.well-known/agent-card.json` at APIM host root; target = host root (7.2a) |
| `AgentCard was missing required properties including: 'version'` | Card missing `version` | Add `version` to the card (7.2b) |
| `Missing required 'kind' discriminator for A2AResponse` | Response lacks `kind` | Add `kind` to result/message/parts (7.2c) |
