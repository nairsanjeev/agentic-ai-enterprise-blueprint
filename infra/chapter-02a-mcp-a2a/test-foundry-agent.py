"""Create a temporary Microsoft Foundry toolbox + agent and test Chapter 02a tools.

The toolbox bundles the Chapter 02a weather MCP tool and the Packing Advisor A2A
agent. Both inner tools authenticate to the private APIM gateway with the agent
identity (AgenticIdentityToken connections). The agent then consumes the toolbox
through its MCP-compatible endpoint.
"""

import argparse
import json
import os
import sys
from typing import Any

from azure.ai.projects import AIProjectClient
from azure.ai.projects.models import (
    A2APreviewToolboxTool,
    MCPTool,
    MCPToolboxTool,
    PromptAgentDefinition,
)
from azure.identity import DefaultAzureCredential


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Test the Chapter 02a MCP and A2A endpoints from a Foundry toolbox agent."
    )
    parser.add_argument(
        "--project-endpoint",
        default=os.getenv("FOUNDRY_PROJECT_ENDPOINT"),
        help="Foundry project endpoint, or set FOUNDRY_PROJECT_ENDPOINT.",
    )
    parser.add_argument(
        "--model",
        default=os.getenv("FOUNDRY_MODEL_NAME", "gpt-4o"),
        help="Foundry model deployment name (default: FOUNDRY_MODEL_NAME or gpt-4o).",
    )
    parser.add_argument(
        "--mcp-url",
        default=os.getenv(
            "CHAPTER_02A_MCP_URL",
            "https://apim-agent-blueprint-dev-a5jiq4re.azure-api.net/mcp/weather/mcp",
        ),
        help="Chapter 02a streamable HTTP MCP URL used inside the toolbox.",
    )
    parser.add_argument(
        "--mcp-connection",
        default=os.getenv("CHAPTER_02A_MCP_CONNECTION"),
        help="Name of the RemoteTool AgenticIdentityToken connection for the MCP server.",
    )
    parser.add_argument(
        "--a2a-connection",
        default=os.getenv("CHAPTER_02A_A2A_CONNECTION"),
        help="Name of the RemoteA2A AgenticIdentityToken connection for the Packing Advisor.",
    )
    parser.add_argument(
        "--toolbox-connection",
        default=os.getenv("CHAPTER_02A_TOOLBOX_CONNECTION"),
        help="Name of the RemoteTool connection to the toolbox endpoint (audience https://ai.azure.com).",
    )
    parser.add_argument(
        "--toolbox-name",
        default=os.getenv("CHAPTER_02A_TOOLBOX_NAME", "chapter02a-agent-tools"),
        help="Name of the temporary Foundry toolbox.",
    )
    parser.add_argument(
        "--agent-name",
        default="Chapter02aConnectivityTest",
        help="Name of the temporary Foundry agent.",
    )
    parser.add_argument(
        "--keep-resources",
        action="store_true",
        help="Keep the created toolbox and agent versions for troubleshooting.",
    )
    args = parser.parse_args()

    missing = []
    if not args.project_endpoint:
        missing.append("--project-endpoint or FOUNDRY_PROJECT_ENDPOINT")
    if not args.mcp_connection:
        missing.append("--mcp-connection or CHAPTER_02A_MCP_CONNECTION")
    if not args.a2a_connection:
        missing.append("--a2a-connection or CHAPTER_02A_A2A_CONNECTION")
    if not args.toolbox_connection:
        missing.append("--toolbox-connection or CHAPTER_02A_TOOLBOX_CONNECTION")
    if missing:
        parser.error("missing " + ", ".join(missing))
    return args


def as_dict(value: Any) -> Any:
    if hasattr(value, "model_dump"):
        return value.model_dump(mode="json")
    if isinstance(value, list):
        return [as_dict(item) for item in value]
    if isinstance(value, dict):
        return {key: as_dict(item) for key, item in value.items()}
    return value


def collect_types(value: Any) -> set[str]:
    types: set[str] = set()
    if isinstance(value, dict):
        item_type = value.get("type")
        if isinstance(item_type, str):
            types.add(item_type.lower())
        for item in value.values():
            types.update(collect_types(item))
    elif isinstance(value, list):
        for item in value:
            types.update(collect_types(item))
    return types


def collect_tool_names(value: Any) -> set[str]:
    names: set[str] = set()
    if isinstance(value, dict):
        for key in ("name", "tool_name"):
            candidate = value.get(key)
            if isinstance(candidate, str):
                names.add(candidate)
        for item in value.values():
            names.update(collect_tool_names(item))
    elif isinstance(value, list):
        for item in value:
            names.update(collect_tool_names(item))
    return names


def assert_mcp_trace(response: Any, test_name: str) -> set[str]:
    response_data = as_dict(response)
    output = response_data.get("output", [])
    output_types = collect_types(output)
    if not any("mcp" in item_type for item_type in output_types):
        raise AssertionError(
            f"{test_name}: no MCP tool-call trace found, so the toolbox tool was not "
            f"invoked. Output item types: {sorted(output_types)}\n"
            f"{json.dumps(output, indent=2)}"
        )
    return collect_tool_names(output)


def assert_contains(text: str, expected_terms: tuple[str, ...], test_name: str) -> None:
    normalized = text.lower()
    missing = [term for term in expected_terms if term.lower() not in normalized]
    if missing:
        raise AssertionError(
            f"{test_name} response did not contain {missing}. Response: {text}"
        )


def print_agent_identity_help(error: Exception) -> None:
    message = str(error)
    if "ARA request" not in message and "agentic identity" not in message.lower():
        return
    print(
        "\nThe agent identity token exchange failed (ARA BadRequest). Check, in order:\n"
        "  1. Provision the identity: create at least one agent in this project once so the\n"
        "     shared project agent identity exists, then copy agentIdentityId from the\n"
        "     project's Azure portal JSON view.\n"
        "  2. Fix the audience: the AgenticIdentityToken connection audience must be a valid\n"
        "     Microsoft Entra resource identifier (an app registration Application ID URI such\n"
        "     as api://<app-id>), NOT the APIM gateway URL. A wrong audience is the most common\n"
        "     cause of ARA BadRequest.\n"
        "  3. Grant access: assign that agentIdentityId the role/app-role the APIM-fronted MCP\n"
        "     and A2A APIs require for the token to be accepted.\n"
        "  4. Confirm both inner connections use authType AgenticIdentityToken (RemoteTool for\n"
        "     MCP, RemoteA2A for A2A) and are shared to the project.",
        file=sys.stderr,
    )


def resolve_connection(project: AIProjectClient, name: str) -> Any:
    connection = project.connections.get(name)
    conn_type = getattr(connection, "type", None)
    print(f"Resolved connection {name}: id={connection.id} type={conn_type}")
    return connection


def main() -> int:
    args = parse_args()
    credential = DefaultAzureCredential()
    project = AIProjectClient(endpoint=args.project_endpoint, credential=credential)
    toolbox = None
    agent = None

    try:
        mcp_connection = resolve_connection(project, args.mcp_connection)
        a2a_connection = resolve_connection(project, args.a2a_connection)
        toolbox_connection = resolve_connection(project, args.toolbox_connection)

        toolbox = project.toolboxes.create_version(
            name=args.toolbox_name,
            description="Chapter 02a weather MCP tool and Packing Advisor A2A agent.",
            tools=[
                MCPToolboxTool(
                    server_label="chapter02a_weather",
                    server_url=args.mcp_url,
                    require_approval="never",
                    project_connection_id=mcp_connection.id,
                ),
                A2APreviewToolboxTool(project_connection_id=a2a_connection.id),
            ],
        )
        toolbox_mcp_url = (
            f"{args.project_endpoint}/toolboxes/{toolbox.name}"
            f"/versions/{toolbox.version}/mcp?api-version=v1"
        )
        print(f"Created toolbox {toolbox.name}, version {toolbox.version}.")

        agent = project.agents.create_version(
            agent_name=args.agent_name,
            definition=PromptAgentDefinition(
                model=args.model,
                instructions=(
                    "You validate governed Chapter 02a integrations through the toolbox. For "
                    "weather requests, call the get-city-weather tool. For packing requests, "
                    "call the Packing Advisor tool. Never answer either request from general "
                    "model knowledge."
                ),
                tools=[
                    MCPTool(
                        server_label="chapter02a_toolbox",
                        server_url=toolbox_mcp_url,
                        require_approval="never",
                        project_connection_id=toolbox_connection.id,
                    )
                ],
            ),
        )
        print(f"Created Foundry agent {agent.name}, version {agent.version}.")

        openai = project.get_openai_client()
        weather_response = openai.responses.create(
            input=(
                "Use the toolbox weather tool to get Seattle's current weather. Include the "
                "city and current condition in your answer."
            ),
            tool_choice={"type": "mcp", "server_label": "chapter02a_toolbox"},
            extra_body={
                "agent_reference": {"name": agent.name, "type": "agent_reference"}
            },
        )
        weather_tools = assert_mcp_trace(weather_response, "MCP")
        assert_contains(weather_response.output_text, ("Seattle",), "MCP")
        print(f"PASS MCP (tools: {sorted(weather_tools)}): {weather_response.output_text}")

        packing_response = openai.responses.create(
            input=(
                "Use the toolbox Packing Advisor tool to get a Seattle packing checklist and "
                "return its checklist. Do not call the weather tool."
            ),
            tool_choice="required",
            extra_body={
                "agent_reference": {"name": agent.name, "type": "agent_reference"}
            },
        )
        packing_tools = assert_mcp_trace(packing_response, "A2A")
        assert_contains(
            packing_response.output_text,
            ("Seattle", "identification", "charger", "reusable water bottle"),
            "A2A",
        )
        print(f"PASS A2A (tools: {sorted(packing_tools)}): {packing_response.output_text}")
        print(
            "PASS: Foundry toolbox agent reached both governed Chapter 02a endpoints "
            "with the agent identity."
        )
        return 0
    except Exception as error:
        print(f"FAIL: {error}", file=sys.stderr)
        print_agent_identity_help(error)
        return 1
    finally:
        if not args.keep_resources:
            if agent is not None:
                project.agents.delete_version(
                    agent_name=agent.name, agent_version=agent.version
                )
                print(f"Deleted temporary agent {agent.name}, version {agent.version}.")
            if toolbox is not None:
                try:
                    project.toolboxes.delete_version(
                        name=toolbox.name, version=toolbox.version
                    )
                    print(
                        f"Deleted temporary toolbox {toolbox.name}, version {toolbox.version}."
                    )
                except Exception as cleanup_error:
                    print(
                        f"Could not delete toolbox {toolbox.name}: {cleanup_error}",
                        file=sys.stderr,
                    )
        project.close()
        credential.close()


if __name__ == "__main__":
    raise SystemExit(main())