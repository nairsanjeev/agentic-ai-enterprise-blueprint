@description('Name of the existing API Management service from Chapter 02.')
param apimName string

@description('Rate limit applied independently to the MCP server and A2A backend.')
@minValue(1)
param callsPerMinute int = 30

resource apim 'Microsoft.ApiManagement/service@2025-09-01-preview' existing = {
  name: apimName
}

resource agentToolsProduct 'Microsoft.ApiManagement/service/products@2025-09-01-preview' = {
  parent: apim
  name: 'agent-tools'
  properties: {
    displayName: 'Agent Tools'
    description: 'Approved MCP tools and A2A agents published by the AI Center of Excellence.'
    state: 'published'
    subscriptionRequired: false
  }
}

resource weatherApi 'Microsoft.ApiManagement/service/apis@2025-09-01-preview' = {
  parent: apim
  name: 'weather-api'
  properties: {
    type: 'http'
    path: 'weather'
    displayName: 'City Weather API'
    description: 'Returns current weather for a city. This REST operation is also exposed as an MCP tool.'
    protocols: [
      'https'
    ]
    serviceUrl: 'https://wttr.in'
    subscriptionRequired: false
  }
}

resource getCityWeather 'Microsoft.ApiManagement/service/apis/operations@2025-09-01-preview' = {
  parent: weatherApi
  name: 'get-city-weather'
  properties: {
    displayName: 'Get current weather by city'
    description: 'Find current temperature, conditions, humidity, wind, and observation time for a city.'
    method: 'GET'
    urlTemplate: '/{city}'
    templateParameters: [
      {
        name: 'city'
        type: 'string'
        required: true
        description: 'City name, for example Seattle or London.'
      }
    ]
    responses: [
      {
        statusCode: 200
        description: 'Current weather data.'
        representations: [
          {
            contentType: 'application/json'
          }
        ]
      }
    ]
  }
}

resource weatherOperationPolicy 'Microsoft.ApiManagement/service/apis/operations/policies@2025-09-01-preview' = {
  parent: getCityWeather
  name: 'policy'
  properties: {
    format: 'rawxml'
    value: '<policies><inbound><base /><set-query-parameter name="format" exists-action="override"><value>j1</value></set-query-parameter></inbound><backend><forward-request /></backend><outbound><base /></outbound><on-error><base /></on-error></policies>'
  }
}

resource weatherMcp 'Microsoft.ApiManagement/service/apis@2025-09-01-preview' = {
  parent: apim
  name: 'weather-mcp'
  properties: {
    type: 'mcp'
    path: 'mcp/weather'
    displayName: 'City Weather MCP Server'
    description: 'Streamable HTTP MCP server generated from the approved City Weather REST API.'
    protocols: [
      'https'
    ]
    subscriptionRequired: false
    mcpProperties: {
      transportType: 'streamable'
      endpoints: any({
        mcp: {
          name: 'mcp'
          uriTemplate: '/mcp'
        }
      })
    }
  }
}

resource weatherMcpTool 'Microsoft.ApiManagement/service/apis/tools@2025-09-01-preview' = {
  parent: weatherMcp
  name: 'get-city-weather'
  properties: {
    displayName: 'get-city-weather'
    description: 'Get current weather conditions for a city.'
    operationId: getCityWeather.id
  }
}

resource weatherMcpPolicy 'Microsoft.ApiManagement/service/apis/policies@2025-09-01-preview' = {
  parent: weatherMcp
  name: 'policy'
  properties: {
    format: 'rawxml'
    value: '<policies><inbound><base /><rate-limit-by-key calls="${callsPerMinute}" renewal-period="60" counter-key="@(context.Request.IpAddress)" /></inbound><backend><base /></backend><outbound><base /></outbound><on-error><base /></on-error></policies>'
  }
}

resource a2aBackendApi 'Microsoft.ApiManagement/service/apis@2025-09-01-preview' = {
  parent: apim
  name: 'packing-advisor-backend'
  properties: {
    type: 'http'
    path: 'a2a/packing-advisor-backend'
    displayName: 'Packing Advisor A2A Backend'
    description: 'Sample JSON-RPC A2A backend and agent card. Import its card as an A2A Agent API in APIM.'
    protocols: [
      'https'
    ]
    subscriptionRequired: false
  }
}

resource getAgentCard 'Microsoft.ApiManagement/service/apis/operations@2025-09-01-preview' = {
  parent: a2aBackendApi
  name: 'get-agent-card'
  properties: {
    displayName: 'Get A2A agent card'
    method: 'GET'
    urlTemplate: '/.well-known/agent-card.json'
    responses: [
      {
        statusCode: 200
        description: 'A2A agent card.'
      }
    ]
  }
}

resource agentCardPolicy 'Microsoft.ApiManagement/service/apis/operations/policies@2025-09-01-preview' = {
  parent: getAgentCard
  name: 'policy'
  properties: {
    format: 'rawxml'
    value: '<policies><inbound><base /><return-response><set-status code="200" reason="OK" /><set-header name="Content-Type" exists-action="override"><value>application/json</value></set-header><set-body>{"protocolVersion":"0.3.0","name":"Packing Advisor","description":"Creates a practical packing checklist for a destination.","url":"https://${apim.name}.azure-api.net/a2a/packing-advisor-backend","preferredTransport":"JSONRPC","capabilities":{"streaming":false,"pushNotifications":false},"defaultInputModes":["text/plain"],"defaultOutputModes":["text/plain"],"skills":[{"id":"create-packing-list","name":"Create packing list","description":"Create a short packing checklist. Send the destination as the message text.","tags":["travel","packing","checklist"],"examples":["Seattle","London"],"inputModes":["text/plain"],"outputModes":["text/plain"]}]}</set-body></return-response></inbound><backend><base /></backend><outbound><base /></outbound><on-error><base /></on-error></policies>'
  }
}

resource sendA2aMessage 'Microsoft.ApiManagement/service/apis/operations@2025-09-01-preview' = {
  parent: a2aBackendApi
  name: 'send-message'
  properties: {
    displayName: 'Send A2A message'
    description: 'Accepts an A2A message/send JSON-RPC request and returns a completed task.'
    method: 'POST'
    urlTemplate: '/'
    request: {
      representations: [
        {
          contentType: 'application/json'
        }
      ]
    }
    responses: [
      {
        statusCode: 200
        description: 'Completed A2A task.'
      }
    ]
  }
}

resource a2aMessagePolicy 'Microsoft.ApiManagement/service/apis/operations/policies@2025-09-01-preview' = {
  parent: sendA2aMessage
  name: 'policy'
  properties: {
    format: 'rawxml'
    value: '<policies><inbound><base /><rate-limit-by-key calls="${callsPerMinute}" renewal-period="60" counter-key="@(context.Request.IpAddress)" /><set-variable name="request" value="@((JObject)context.Request.Body.As&lt;JObject&gt;(preserveContent: true))" /><set-variable name="requestId" value="@(((JObject)context.Variables[&quot;request&quot;])[&quot;id&quot;]?.ToString() ?? &quot;1&quot;)" /><set-variable name="destination" value="@(((JObject)context.Variables[&quot;request&quot;]).SelectToken(&quot;params.message.parts[0].text&quot;)?.ToString() ?? &quot;your destination&quot;)" /><return-response><set-status code="200" reason="OK" /><set-header name="Content-Type" exists-action="override"><value>application/json</value></set-header><set-body>@{ var id = (string)context.Variables[&quot;requestId&quot;]; var destination = (string)context.Variables[&quot;destination&quot;]; var taskId = Guid.NewGuid().ToString(); var messageId = Guid.NewGuid().ToString(); return new JObject(new JProperty(&quot;jsonrpc&quot;, &quot;2.0&quot;), new JProperty(&quot;id&quot;, id), new JProperty(&quot;result&quot;, new JObject(new JProperty(&quot;id&quot;, taskId), new JProperty(&quot;contextId&quot;, taskId), new JProperty(&quot;status&quot;, new JObject(new JProperty(&quot;state&quot;, &quot;completed&quot;), new JProperty(&quot;message&quot;, new JObject(new JProperty(&quot;role&quot;, &quot;agent&quot;), new JProperty(&quot;messageId&quot;, messageId), new JProperty(&quot;parts&quot;, new JArray(new JObject(new JProperty(&quot;kind&quot;, &quot;text&quot;), new JProperty(&quot;text&quot;, &quot;Packing checklist for &quot; + destination + &quot;: identification, weather-appropriate layers, comfortable shoes, medication, charger, and reusable water bottle.&quot;))))))))))).ToString(); }</set-body></return-response></inbound><backend><base /></backend><outbound><base /></outbound><on-error><base /></on-error></policies>'
  }
}

resource weatherProductLink 'Microsoft.ApiManagement/service/products/apiLinks@2025-09-01-preview' = {
  parent: agentToolsProduct
  name: 'weather-api'
  properties: {
    apiId: weatherApi.id
  }
}

resource mcpProductLink 'Microsoft.ApiManagement/service/products/apiLinks@2025-09-01-preview' = {
  parent: agentToolsProduct
  name: 'weather-mcp'
  properties: {
    apiId: weatherMcp.id
  }
}

resource a2aBackendProductLink 'Microsoft.ApiManagement/service/products/apiLinks@2025-09-01-preview' = {
  parent: agentToolsProduct
  name: 'packing-advisor-backend'
  properties: {
    apiId: a2aBackendApi.id
  }
}

output weatherApiUrl string = 'https://${apim.name}.azure-api.net/weather/Seattle'
output mcpServerUrl string = 'https://${apim.name}.azure-api.net/mcp/weather/mcp'
output a2aAgentCardUrl string = 'https://${apim.name}.azure-api.net/a2a/packing-advisor-backend/.well-known/agent-card.json'
output a2aRuntimeUrl string = 'https://${apim.name}.azure-api.net/a2a/packing-advisor-backend'
