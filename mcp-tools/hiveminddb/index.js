#!/usr/bin/env node

/**
 * HiveMindDB MCP Server
 *
 * Provides AI coding agents (Claude Code, OpenCode, Aider) with persistent,
 * distributed memory via HiveMindDB.
 *
 * Compatible with AgentCore's agent-memory interface (remember, recall, forget,
 * search, list_topics) PLUS extended HiveMindDB tools (graph, channels,
 * extraction, etc.)
 *
 * Usage:
 *   npx hiveminddb-mcp --url http://localhost:8100
 *   # or with env:
 *   HIVEMINDDB_URL=http://localhost:8100 npx hiveminddb-mcp
 */

const { Server } = require("@modelcontextprotocol/sdk/server/index.js");
const {
  StdioServerTransport,
} = require("@modelcontextprotocol/sdk/server/stdio.js");
const {
  CallToolRequestSchema,
  ListToolsRequestSchema,
} = require("@modelcontextprotocol/sdk/types.js");

const BASE_URL =
  process.argv.find((a) => a.startsWith("--url="))?.split("=")[1] ||
  process.argv[process.argv.indexOf("--url") + 1] ||
  process.env.HIVEMINDDB_URL ||
  "http://localhost:8100";

async function apiCall(method, path, body) {
  const url = `${BASE_URL}${path}`;
  const options = {
    method,
    headers: { "Content-Type": "application/json" },
  };
  if (body) options.body = JSON.stringify(body);

  const resp = await fetch(url, options);
  if (!resp.ok) {
    const text = await resp.text();
    throw new Error(`${method} ${path} failed (${resp.status}): ${text}`);
  }
  const contentType = resp.headers.get("content-type") || "";
  if (contentType.includes("json")) {
    return resp.json();
  }
  return resp.text();
}

// ============================================================================
// Tool Definitions
// ============================================================================

const TOOLS = [
  // --- AgentCore-compatible interface (drop-in replacement) ---
  {
    name: "remember",
    description:
      "Store a memory under a topic. The memory is replicated across all HiveMindDB nodes.",
    inputSchema: {
      type: "object",
      properties: {
        topic: {
          type: "string",
          description: "Topic/category for the memory",
        },
        content: { type: "string", description: "The memory content to store" },
      },
      required: ["topic", "content"],
    },
  },
  {
    name: "recall",
    description:
      "Recall all memories for a given topic. Returns all stored memories under that topic.",
    inputSchema: {
      type: "object",
      properties: {
        topic: { type: "string", description: "Topic to recall memories for" },
      },
      required: ["topic"],
    },
  },
  {
    name: "forget",
    description: "Forget (invalidate) all memories for a topic.",
    inputSchema: {
      type: "object",
      properties: {
        topic: {
          type: "string",
          description: "Topic to forget all memories for",
        },
      },
      required: ["topic"],
    },
  },
  {
    name: "search",
    description:
      "Search across all memories by keyword or semantic query. Uses hybrid search (keyword + vector similarity when embeddings are configured).",
    inputSchema: {
      type: "object",
      properties: {
        keyword: {
          type: "string",
          description: "Search query (keyword or natural language)",
        },
      },
      required: ["keyword"],
    },
  },
  {
    name: "list_topics",
    description:
      "List all memory topics with their memory counts and last update times.",
    inputSchema: { type: "object", properties: {} },
  },

  // --- Extended HiveMindDB tools ---
  {
    name: "memory_add",
    description:
      "Add a memory with full metadata (type, agent_id, user_id, tags).",
    inputSchema: {
      type: "object",
      properties: {
        content: { type: "string", description: "Memory content" },
        memory_type: {
          type: "string",
          enum: ["fact", "episodic", "procedural", "semantic"],
          description: "Type of memory (default: fact)",
        },
        agent_id: { type: "string", description: "Agent that created this" },
        user_id: { type: "string", description: "Associated user" },
        tags: {
          type: "array",
          items: { type: "string" },
          description: "Tags for categorization",
        },
      },
      required: ["content"],
    },
  },
  {
    name: "memory_search",
    description:
      "Hybrid search (keyword + vector similarity) across all memories with filters.",
    inputSchema: {
      type: "object",
      properties: {
        query: { type: "string", description: "Search query" },
        agent_id: { type: "string", description: "Filter by agent" },
        user_id: { type: "string", description: "Filter by user" },
        tags: {
          type: "array",
          items: { type: "string" },
          description: "Filter by tags",
        },
        limit: { type: "number", description: "Max results (default: 10)" },
      },
      required: ["query"],
    },
  },
  {
    name: "memory_history",
    description: "Get the full audit trail for a specific memory.",
    inputSchema: {
      type: "object",
      properties: {
        memory_id: {
          type: "number",
          description: "ID of the memory to get history for",
        },
      },
      required: ["memory_id"],
    },
  },
  {
    name: "extract",
    description:
      "Extract knowledge from conversation text using LLM. Automatically identifies facts, entities, relationships, and handles conflict resolution with existing memories.",
    inputSchema: {
      type: "object",
      properties: {
        messages: {
          type: "array",
          items: {
            type: "object",
            properties: {
              role: { type: "string", description: "Message role (user, assistant, system)" },
              content: { type: "string", description: "Message content" },
            },
            required: ["role", "content"],
          },
          description: "Conversation messages to extract knowledge from",
        },
        agent_id: { type: "string", description: "Agent performing extraction" },
        user_id: { type: "string", description: "User the conversation is about" },
      },
      required: ["messages"],
    },
  },
  {
    name: "graph_add_entity",
    description:
      "Add an entity to the knowledge graph (person, project, concept, etc.).",
    inputSchema: {
      type: "object",
      properties: {
        name: { type: "string", description: "Entity name" },
        entity_type: {
          type: "string",
          description: 'Entity type (e.g., "Person", "Project", "Technology")',
        },
        description: {
          type: "string",
          description: "Optional description of the entity",
        },
      },
      required: ["name", "entity_type"],
    },
  },
  {
    name: "graph_add_relation",
    description:
      'Create a relationship between two entities (e.g., "Alice maintains RaftTimeDB").',
    inputSchema: {
      type: "object",
      properties: {
        source_entity_id: { type: "number", description: "Source entity ID" },
        target_entity_id: { type: "number", description: "Target entity ID" },
        relation_type: {
          type: "string",
          description:
            'Relationship type (e.g., "maintains", "prefers", "uses")',
        },
        description: { type: "string", description: "Optional description" },
      },
      required: ["source_entity_id", "target_entity_id", "relation_type"],
    },
  },
  {
    name: "graph_query",
    description:
      "Find an entity by name and show its relationships in the knowledge graph.",
    inputSchema: {
      type: "object",
      properties: {
        name: { type: "string", description: "Entity name to look up" },
      },
      required: ["name"],
    },
  },
  {
    name: "graph_traverse",
    description:
      "Traverse the knowledge graph from an entity, exploring connected entities up to a given depth.",
    inputSchema: {
      type: "object",
      properties: {
        entity_id: { type: "number", description: "Starting entity ID" },
        depth: { type: "number", description: "Max traversal depth (default: 2)" },
      },
      required: ["entity_id"],
    },
  },
  {
    name: "channel_create",
    description:
      "Create a hivemind channel for sharing memories between agents in real-time.",
    inputSchema: {
      type: "object",
      properties: {
        name: {
          type: "string",
          description:
            'Channel name (e.g., "project:rafttimedb", "team:backend")',
        },
        description: { type: "string", description: "Channel description" },
      },
      required: ["name"],
    },
  },
  {
    name: "channel_share",
    description: "Share a memory to a hivemind channel.",
    inputSchema: {
      type: "object",
      properties: {
        channel_id: { type: "number", description: "Channel ID" },
        memory_id: { type: "number", description: "Memory ID to share" },
      },
      required: ["channel_id", "memory_id"],
    },
  },
  {
    name: "channel_list",
    description: "List all hivemind channels.",
    inputSchema: { type: "object", properties: {} },
  },
  {
    name: "agent_register",
    description: "Register this agent with the HiveMindDB hivemind.",
    inputSchema: {
      type: "object",
      properties: {
        agent_id: { type: "string", description: "Unique agent identifier" },
        name: { type: "string", description: "Human-readable agent name" },
        agent_type: {
          type: "string",
          description:
            'Agent type (e.g., "claude-code", "opencode", "aider")',
        },
        capabilities: {
          type: "array",
          items: { type: "string" },
          description: "Agent capabilities",
        },
      },
      required: ["agent_id", "name", "agent_type"],
    },
  },
  {
    name: "agent_status",
    description: "List all agents registered in the hivemind and their status.",
    inputSchema: { type: "object", properties: {} },
  },
  {
    name: "hivemind_status",
    description: "Get HiveMindDB cluster status — memory counts, embedding stats, extraction availability.",
    inputSchema: { type: "object", properties: {} },
  },
];

// ============================================================================
// Tool Handlers
// ============================================================================

async function handleTool(name, args) {
  switch (name) {
    // --- AgentCore-compatible ---
    case "remember": {
      const result = await apiCall("POST", "/api/v1/memories", {
        content: args.content,
        memory_type: "fact",
        tags: [args.topic],
        metadata: { topic: args.topic },
      });
      return `Stored memory #${result.id} under topic "${args.topic}"`;
    }

    case "recall": {
      const results = await apiCall("POST", "/api/v1/search", {
        query: args.topic,
        tags: [args.topic],
        limit: 50,
      });
      if (results.length === 0)
        return `No memories found for topic "${args.topic}"`;
      return results
        .map((r) => `[${r.memory.created_at}] ${r.memory.content}`)
        .join("\n\n");
    }

    case "forget": {
      const results = await apiCall("POST", "/api/v1/search", {
        query: args.topic,
        tags: [args.topic],
        limit: 100,
      });
      let count = 0;
      for (const r of results) {
        try {
          await apiCall("DELETE", `/api/v1/memories/${r.memory.id}`, {
            reason: `Topic "${args.topic}" forgotten`,
            changed_by: "mcp",
          });
          count++;
        } catch (e) {
          // Skip failures
        }
      }
      return `Forgot ${count} memories under topic "${args.topic}"`;
    }

    case "search": {
      const results = await apiCall("POST", "/api/v1/search", {
        query: args.keyword,
        limit: 10,
      });
      if (results.length === 0) return "No memories found.";
      return results
        .map(
          (r) =>
            `[#${r.memory.id} score:${r.score.toFixed(2)}] ${r.memory.content}` +
            (r.memory.tags.length
              ? `\n  tags: ${r.memory.tags.join(", ")}`
              : "")
        )
        .join("\n\n");
    }

    case "list_topics": {
      const memories = await apiCall("GET", "/api/v1/memories");
      const topics = {};
      for (const m of memories) {
        for (const tag of m.tags) {
          if (!topics[tag])
            topics[tag] = { count: 0, last_updated: m.updated_at };
          topics[tag].count++;
          if (m.updated_at > topics[tag].last_updated) {
            topics[tag].last_updated = m.updated_at;
          }
        }
      }
      if (Object.keys(topics).length === 0) return "No topics found.";
      return Object.entries(topics)
        .map(
          ([name, info]) =>
            `${name}: ${info.count} memories (last: ${info.last_updated})`
        )
        .join("\n");
    }

    // --- Extended HiveMindDB tools ---
    case "memory_add": {
      const result = await apiCall("POST", "/api/v1/memories", {
        content: args.content,
        memory_type: args.memory_type || "fact",
        agent_id: args.agent_id,
        user_id: args.user_id,
        tags: args.tags || [],
      });
      return JSON.stringify(result, null, 2);
    }

    case "memory_search": {
      const results = await apiCall("POST", "/api/v1/search", {
        query: args.query,
        agent_id: args.agent_id,
        user_id: args.user_id,
        tags: args.tags || [],
        limit: args.limit || 10,
      });
      return JSON.stringify(results, null, 2);
    }

    case "memory_history": {
      const history = await apiCall(
        "GET",
        `/api/v1/memories/${args.memory_id}/history`
      );
      return JSON.stringify(history, null, 2);
    }

    case "extract": {
      const result = await apiCall("POST", "/api/v1/extract", {
        messages: args.messages,
        agent_id: args.agent_id,
        user_id: args.user_id,
      });
      const summary = [];
      if (result.memories_added.length > 0) {
        summary.push(`Added ${result.memories_added.length} memories:`);
        for (const m of result.memories_added) {
          summary.push(`  #${m.id}: ${m.content}`);
        }
      }
      if (result.memories_updated.length > 0) {
        summary.push(`Updated ${result.memories_updated.length} memories:`);
        for (const m of result.memories_updated) {
          summary.push(`  #${m.id}: ${m.content}`);
        }
      }
      if (result.entities_added.length > 0) {
        summary.push(`Added ${result.entities_added.length} entities:`);
        for (const e of result.entities_added) {
          summary.push(`  ${e.name} (${e.entity_type})`);
        }
      }
      if (result.relationships_added.length > 0) {
        summary.push(
          `Added ${result.relationships_added.length} relationships`
        );
      }
      if (result.skipped > 0) {
        summary.push(`Skipped ${result.skipped} already-known facts`);
      }
      return summary.length > 0
        ? summary.join("\n")
        : "No new knowledge extracted.";
    }

    case "graph_add_entity": {
      const result = await apiCall("POST", "/api/v1/entities", {
        name: args.name,
        entity_type: args.entity_type,
        description: args.description,
      });
      return JSON.stringify(result, null, 2);
    }

    case "graph_add_relation": {
      const result = await apiCall("POST", "/api/v1/relationships", {
        source_entity_id: args.source_entity_id,
        target_entity_id: args.target_entity_id,
        relation_type: args.relation_type,
        description: args.description,
        created_by: "mcp",
      });
      return JSON.stringify(result, null, 2);
    }

    case "graph_query": {
      const entity = await apiCall("POST", "/api/v1/entities/find", {
        name: args.name,
      });
      const rels = await apiCall(
        "GET",
        `/api/v1/entities/${entity.id}/relationships`
      );
      return (
        `Entity: ${entity.name} (${entity.entity_type})\n` +
        (entity.description ? `Description: ${entity.description}\n` : "") +
        `\nRelationships:\n` +
        rels
          .map(
            (r) =>
              `  --${r[0].relation_type}--> ${r[1].name} (${r[1].entity_type})`
          )
          .join("\n")
      );
    }

    case "graph_traverse": {
      const result = await apiCall("POST", "/api/v1/graph/traverse", {
        entity_id: args.entity_id,
        depth: args.depth || 2,
      });
      return result
        .map(
          (entry) =>
            `${entry[0].name} (${entry[0].entity_type}) — ${entry[1].length} relationship(s)`
        )
        .join("\n");
    }

    case "channel_create": {
      const result = await apiCall("POST", "/api/v1/channels", {
        name: args.name,
        description: args.description,
        channel_type: "public",
        created_by: "mcp",
      });
      return `Channel "${result.name}" created (id: ${result.id})`;
    }

    case "channel_share": {
      await apiCall("POST", `/api/v1/channels/${args.channel_id}/share`, {
        memory_id: args.memory_id,
        shared_by: "mcp",
      });
      return `Memory #${args.memory_id} shared to channel #${args.channel_id}`;
    }

    case "channel_list": {
      const channels = await apiCall("GET", "/api/v1/channels");
      if (channels.length === 0) return "No channels.";
      return channels
        .map(
          (ch) =>
            `#${ch.id} ${ch.name} (${ch.channel_type}) — by ${ch.created_by}`
        )
        .join("\n");
    }

    case "agent_register": {
      const result = await apiCall("POST", "/api/v1/agents/register", {
        agent_id: args.agent_id,
        name: args.name,
        agent_type: args.agent_type,
        capabilities: args.capabilities || [],
      });
      return `Agent "${result.name}" registered (type: ${result.agent_type})`;
    }

    case "agent_status": {
      const agents = await apiCall("GET", "/api/v1/agents");
      if (agents.length === 0) return "No agents registered.";
      return agents
        .map(
          (a) =>
            `${a.name} (${a.agent_type}) — ${a.status} — ${a.memory_count} memories`
        )
        .join("\n");
    }

    case "hivemind_status": {
      const status = await apiCall("GET", "/api/v1/status");
      return [
        `Memories: ${status.memories} (${status.valid_memories} valid)`,
        `Entities: ${status.entities}`,
        `Relationships: ${status.relationships}`,
        `Agents: ${status.agents}`,
        `Embeddings indexed: ${status.embeddings_indexed}`,
        `Embedding dimensions: ${status.embedding_dimensions}`,
        `Extraction available: ${status.extraction_available}`,
        `Replication enabled: ${status.replication_enabled}`,
      ].join("\n");
    }

    default:
      throw new Error(`Unknown tool: ${name}`);
  }
}

// ============================================================================
// MCP Server Setup
// ============================================================================

async function main() {
  const server = new Server(
    { name: "hiveminddb", version: "0.1.0" },
    { capabilities: { tools: {} } }
  );

  server.setRequestHandler(ListToolsRequestSchema, async () => ({
    tools: TOOLS,
  }));

  server.setRequestHandler(CallToolRequestSchema, async (request) => {
    try {
      const result = await handleTool(
        request.params.name,
        request.params.arguments || {}
      );
      return {
        content: [{ type: "text", text: String(result) }],
      };
    } catch (error) {
      return {
        content: [{ type: "text", text: `Error: ${error.message}` }],
        isError: true,
      };
    }
  });

  const transport = new StdioServerTransport();
  await server.connect(transport);
}

main().catch(console.error);
