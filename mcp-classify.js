#!/usr/bin/env node
// =============================================================================
// MCP Classification Engine
// Called by post-tool-use.sh (PostToolUse hook)
//
// Scans settings files for MCP servers/plugins, classifies new ones,
// updates registry and guardrail whitelist.
//
// Usage: node mcp-classify.js <registry> <guardrail> <repo-root> <global-settings>
// =============================================================================

const fs = require("fs");
const path = require("path");

const [registryPath, guardrailPath, repoRoot, globalSettings] = process.argv.slice(2);

if (!registryPath || !guardrailPath) {
  process.exit(0);
}

// Load registry
let registry;
try {
  registry = JSON.parse(fs.readFileSync(registryPath, "utf8"));
} catch (e) {
  process.stderr.write("  MCP AUTO-UPDATE: Cannot read registry, skipping.\n");
  process.exit(0);
}

// Collect all settings files
const settingsFiles = [];
const projectSettings = path.join(repoRoot, ".claude", "settings.json");
const projectLocalSettings = path.join(repoRoot, ".claude", "settings.local.json");

if (fs.existsSync(projectSettings)) settingsFiles.push(projectSettings);
if (fs.existsSync(projectLocalSettings)) settingsFiles.push(projectLocalSettings);
if (globalSettings && fs.existsSync(globalSettings)) settingsFiles.push(globalSettings);

if (settingsFiles.length === 0) process.exit(0);

// Known MCP prefixes
const knownLocal = Object.keys(registry.local || {});
const knownExternal = Object.keys(registry.external || {});
const allKnown = [...knownLocal, ...knownExternal];

// Scan settings for MCP/plugin configurations
const discovered = [];

for (const sf of settingsFiles) {
  try {
    const cfg = JSON.parse(fs.readFileSync(sf, "utf8"));

    // Check enabledPlugins (format: pluginName@marketplace)
    if (cfg.enabledPlugins) {
      for (const [pluginKey, enabled] of Object.entries(cfg.enabledPlugins)) {
        if (!enabled) continue;
        const pluginName = pluginKey.split("@")[0];
        const safeName = pluginName.replace(/-/g, "_");
        const prefix = "mcp__plugin_" + safeName + "_" + safeName + "__";
        discovered.push({ prefix, name: pluginName, source: "plugin", file: sf });
      }
    }

    // Check mcpServers (custom MCP server configs)
    if (cfg.mcpServers) {
      for (const [serverName, serverCfg] of Object.entries(cfg.mcpServers)) {
        const safeName = serverName.replace(/-/g, "_");
        const prefix = "mcp__" + safeName + "__";
        const transport = serverCfg.command ? "stdio" : (serverCfg.url || serverCfg.endpoint || "");
        discovered.push({ prefix, name: serverName, source: "mcpServer", transport, config: serverCfg, file: sf });
      }
    }
  } catch (e) {
    // Skip unparseable
  }
}

// Find NEW (unregistered) MCPs
const newEntries = [];

for (const mcp of discovered) {
  const isKnown = allKnown.some(k =>
    mcp.prefix === k || mcp.prefix.startsWith(k) || k.startsWith(mcp.prefix)
  );
  if (isKnown) continue;

  let classification = "external";
  let reason = "Default: unrecognized MCP classified as EXTERNAL (safe default)";
  const nameLower = mcp.name.toLowerCase();

  // 1. Check local indicators from registry
  const localMatch = (registry.local_indicators || []).find(ind => nameLower.includes(ind));
  if (localMatch) {
    classification = "local";
    reason = "Auto-classified: name contains local indicator [" + localMatch + "]";
  }

  // 2. Check external indicators (overrides local if both match)
  const extMatch = (registry.external_indicators || []).find(ind => nameLower.includes(ind));
  if (extMatch) {
    classification = "external";
    reason = "Auto-classified: name contains external indicator [" + extMatch + "]";
  }

  // 3. For mcpServers: check transport type
  if (mcp.source === "mcpServer" && mcp.transport !== undefined) {
    if (!mcp.transport || mcp.transport === "stdio") {
      if (!extMatch) {
        classification = "local";
        reason = "Auto-classified: stdio transport (local process)";
      }
    } else if (typeof mcp.transport === "string") {
      if (mcp.transport.match(/localhost|127\.0\.0\.1|::1|0\.0\.0\.0/)) {
        if (!extMatch) {
          classification = "local";
          reason = "Auto-classified: localhost URL (local service)";
        }
      } else {
        classification = "external";
        reason = "Auto-classified: remote URL detected";
      }
    }
  }

  // 4. Safe plugin patterns (known non-network plugins)
  if (mcp.source === "plugin") {
    const safePlugins = [
      "skill-creator", "document-skills", "frontend-design",
      "claude-md-management", "security-guidance"
    ];
    if (safePlugins.some(p => mcp.name === p || mcp.name.startsWith(p))) {
      classification = "local";
      reason = "Auto-classified: recognized safe plugin [" + mcp.name + "]";
    }
  }

  newEntries.push({ ...mcp, classification, reason });
}

// No new MCPs? Exit silently.
if (newEntries.length === 0) process.exit(0);

// ---------------------------------------------------------------------------
// Report findings to stderr
// ---------------------------------------------------------------------------
process.stderr.write("\n");
process.stderr.write("================================================================\n");
process.stderr.write("  MCP AUTO-UPDATE: New MCP/Plugin Detected\n");
process.stderr.write("================================================================\n\n");

let registryChanged = false;
const newLocalPrefixes = [];

for (const entry of newEntries) {
  const icon = entry.classification === "local" ? "LOCAL" : "EXTERNAL";
  const action = entry.classification === "local"
    ? "Auto-whitelisted in guardrail"
    : "Guardrail consent enforced (Allow/Deny prompt)";

  process.stderr.write("  [" + icon + "] " + entry.name + "\n");
  process.stderr.write("    Prefix : " + entry.prefix + "\n");
  process.stderr.write("    Source : " + entry.source + " (from " + path.basename(entry.file) + ")\n");
  process.stderr.write("    Reason : " + entry.reason + "\n");
  process.stderr.write("    Action : " + action + "\n\n");

  if (entry.classification === "local") {
    registry.local[entry.prefix] = { name: entry.name, reason: entry.reason };
    newLocalPrefixes.push({ prefix: entry.prefix, name: entry.name });
  } else {
    registry.external[entry.prefix] = { name: entry.name, reason: entry.reason };
  }
  registryChanged = true;
}

// Save updated registry
if (registryChanged) {
  registry._updated = new Date().toISOString().split("T")[0];
  fs.writeFileSync(registryPath, JSON.stringify(registry, null, 2) + "\n");
  process.stderr.write("  Registry updated: " + path.basename(registryPath) + "\n");
}

// Registry is the source of truth for LOCAL classification.
// check-mcp-guardrail.sh reads it dynamically — no shell patching needed.

// Summary
const localCount = newEntries.filter(e => e.classification === "local").length;
const extCount = newEntries.filter(e => e.classification === "external").length;

process.stderr.write("\n----------------------------------------------------------------\n");
if (localCount > 0) {
  process.stderr.write("  " + localCount + " new LOCAL MCP(s) auto-whitelisted (no consent needed)\n");
}
if (extCount > 0) {
  process.stderr.write("  " + extCount + " new EXTERNAL MCP(s) require Allow/Deny consent\n");
  process.stderr.write("  To reclassify: edit .claude/hooks/mcp-registry.json\n");
  process.stderr.write("  Move entry from [external] to [local] to auto-whitelist.\n");
}
process.stderr.write("================================================================\n\n");
