#!/usr/bin/env node

const fs = require("node:fs");
const path = require("node:path");

const [hooksPath, helperPath] = process.argv.slice(2);
if (!hooksPath || !helperPath) {
  console.error("usage: merge_hooks.cjs /path/to/hooks.json /path/to/flyingsnowfluffctl");
  process.exit(2);
}

let document = {};
if (fs.existsSync(hooksPath)) {
  try {
    document = JSON.parse(fs.readFileSync(hooksPath, "utf8"));
  } catch (error) {
    console.error(`Refusing to overwrite invalid hooks JSON: ${error.message}`);
    process.exit(1);
  }
}
if (!document || typeof document !== "object" || Array.isArray(document)) document = {};
if (!document.hooks || typeof document.hooks !== "object" || Array.isArray(document.hooks)) {
  document.hooks = {};
}
if (!document.description) {
  document.description = "User lifecycle hooks, including the local Flying Snowfluff desktop-pet bridge.";
}

const marker = "flyingsnowfluffctl";
for (const [event, groups] of Object.entries(document.hooks)) {
  if (!Array.isArray(groups)) continue;
  document.hooks[event] = groups
    .map((group) => {
      if (!group || typeof group !== "object" || !Array.isArray(group.hooks)) return group;
      return {
        ...group,
        hooks: group.hooks.filter((hook) =>
          !(hook && typeof hook.command === "string" && hook.command.includes(marker))
        ),
      };
    })
    .filter((group) => !(group && Array.isArray(group.hooks) && group.hooks.length === 0));
}

const quotedHelper = `"${helperPath.replaceAll("\\", "\\\\").replaceAll('"', '\\"')}"`;
const mappings = {
  UserPromptSubmit: "userPromptSubmit",
  PreToolUse: "preToolUse",
  PermissionRequest: "permissionRequest",
  PostToolUse: "postToolUse",
  Stop: "stop",
  SessionEnd: "sessionEnd",
};

for (const [event, argument] of Object.entries(mappings)) {
  if (!Array.isArray(document.hooks[event])) document.hooks[event] = [];
  document.hooks[event].push({
    hooks: [{
      type: "command",
      command: `${quotedHelper} --event ${argument}`,
      timeout: 1,
    }],
  });
}

fs.mkdirSync(path.dirname(hooksPath), { recursive: true, mode: 0o700 });
if (fs.existsSync(hooksPath)) {
  const backup = `${hooksPath}.backup-${new Date().toISOString().replaceAll(/[:.]/g, "-")}`;
  fs.copyFileSync(hooksPath, backup);
  fs.chmodSync(backup, 0o600);
}
const temporary = `${hooksPath}.flying-snowfluff.tmp`;
fs.writeFileSync(temporary, `${JSON.stringify(document, null, 2)}\n`, { mode: 0o600 });
fs.renameSync(temporary, hooksPath);
fs.chmodSync(hooksPath, 0o600);
console.log(`Merged Flying Snowfluff hooks into ${hooksPath}`);
