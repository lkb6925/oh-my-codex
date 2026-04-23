#!/usr/bin/env node

import fs from "node:fs/promises";
import { existsSync } from "node:fs";
import { dirname, join, resolve } from "node:path";
import { fileURLToPath, pathToFileURL } from "node:url";

const __filename = fileURLToPath(import.meta.url);
const __dirname = dirname(__filename);
const rootDir = resolve(__dirname, "..");
const eventNameIndex = process.argv.indexOf("--event");
const eventName = eventNameIndex >= 0 ? process.argv[eventNameIndex + 1] : process.argv[2] || "generic";
const detailsIndex = process.argv.indexOf("--details");
const details = detailsIndex >= 0 ? process.argv[detailsIndex + 1] : "";
const metaPath = process.env.FACTORY_META_FILE || join(rootDir, ".omx", "runs", "latest-run.json");
const eventLogPath = process.env.FACTORY_EVENT_LOG || join(rootDir, ".omx", "runs", "hook-events.jsonl");
const pluginPath = join(rootDir, ".omx", "hooks", "sample-plugin.mjs");

await fs.mkdir(dirname(eventLogPath), { recursive: true });
const generatedAt = new Date().toISOString();
let payload = {
  schema_version: "1.0",
  generated_at: generatedAt,
  event: eventName,
  source: "harness-event",
  details,
};

if (existsSync(pluginPath)) {
  try {
    const plugin = await import(pathToFileURL(pluginPath).href);
    if (typeof plugin.onEvent === "function") {
      payload = await plugin.onEvent(payload);
    }
  } catch (error) {
    payload.plugin_error = error instanceof Error ? error.message : String(error);
  }
}

await fs.appendFile(eventLogPath, `${JSON.stringify(payload)}\n`, "utf8");

if (existsSync(metaPath)) {
  try {
    const raw = await fs.readFile(metaPath, "utf8");
    const meta = JSON.parse(raw);
    meta.last_update_at = generatedAt;
    meta.last_event = eventName;
    meta.last_event_details = details || null;
    await fs.writeFile(metaPath, `${JSON.stringify(meta, null, 2)}\n`, "utf8");
  } catch {
    // keep event emission best-effort
  }
}

console.log(JSON.stringify(payload, null, 2));
