#!/usr/bin/env bash
set -Eeuo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${ROOT_DIR}"
ROOT_NAME="$(basename "${ROOT_DIR}")"

RUN_DIR="${FACTORY_RUN_DIR:-.omx/runs}"
NIGHT_SESSION_NAME="${FACTORY_SESSION_NAME:-factory-night-${ROOT_NAME}}"
DAY_SESSION_NAME="${FACTORY_DAY_SESSION_NAME:-factory-${ROOT_NAME}}"
HANDOFF_FILE="${RUN_DIR}/latest-day-handoff.md"
HANDOFF_JSON="${RUN_DIR}/latest-day-handoff.json"
DAY_LAUNCH_STATE="${RUN_DIR}/latest-day-launch.json"
HERMES_BOOTSTRAP_FILE="${RUN_DIR}/latest-day-hermes-bootstrap.md"
SUMMARY_TMP=""
FACTORY_DAY_TMUX="${FACTORY_DAY_TMUX:-auto}"
FACTORY_DAY_TMUX_ATTACH="${FACTORY_DAY_TMUX_ATTACH:-auto}"
FACTORY_DAY_TMUX_SPLIT_PANE="${FACTORY_DAY_TMUX_SPLIT_PANE:-auto}"
FACTORY_DAY_STALE_AFTER_HOURS="${FACTORY_DAY_STALE_AFTER_HOURS:-10}"
FACTORY_DAY_PRIMARY_COMMAND="${FACTORY_DAY_PRIMARY_COMMAND:-${FACTORY_DAY_HERMES_COMMAND:-omx}}"
FACTORY_DAY_HERMES_AUTOSTART="${FACTORY_DAY_HERMES_AUTOSTART:-0}"

show_help() {
  cat <<'HELP'
Usage:
  factory                 Day launcher: handoff + tmux panes
  factory summary         Handoff summary only
  factory-night [task]    Nightly autonomous run

Day launcher behavior:
  - reads the latest factory-night artifacts from .omx/runs
  - writes .omx/runs/latest-day-handoff.{md,json}
  - creates/attaches the day tmux session when interactive
  - pane 1: OmX/Codex primary conversation (Hermes is optional tooling)
  - pane 2: OMX execution/log tail
  - default posture: talk to OmX/Codex directly; use Hermes only for auxiliary features

Environment:
  FACTORY_DAY_TMUX=0              disable tmux creation
  FACTORY_DAY_TMUX_ATTACH=0       do not attach, even in a TTY
  FACTORY_DAY_TMUX_SPLIT_PANE=0   force single-pane day session
  FACTORY_DAY_PRIMARY_COMMAND=...  override pane 1 command (default: omx)
  FACTORY_DAY_HERMES_AUTOSTART=1  send the Hermes handoff prompt when pane 1 is Hermes
HELP
}

case "${1:-}" in
  help|-h|--help)
    show_help
    exit 0
    ;;
  --no-tmux)
    FACTORY_DAY_TMUX=0
    shift || true
    ;;
esac

mkdir -p "${RUN_DIR}"

cleanup() {
  if [[ -n "${SUMMARY_TMP}" && -f "${SUMMARY_TMP}" ]]; then
    rm -f "${SUMMARY_TMP}"
  fi
}
trap cleanup EXIT

night_session_exists="false"
if tmux has-session -t "${NIGHT_SESSION_NAME}" 2>/dev/null; then
  night_session_exists="true"
fi

day_session_exists="false"
if tmux has-session -t "${DAY_SESSION_NAME}" 2>/dev/null; then
  day_session_exists="true"
fi

status_json="{}"
if status_json_candidate="$(bash scripts/factory-status.sh --json 2>/dev/null)"; then
  status_json="${status_json_candidate}"
fi

SUMMARY_TMP="$(mktemp "${RUN_DIR}/day-summary.XXXXXX")"
if ! bash scripts/factory-summary.sh > "${SUMMARY_TMP}" 2>/dev/null; then
  printf '# Factory Summary\n\n- unavailable: scripts/factory-summary.sh failed\n' > "${SUMMARY_TMP}"
fi

cat > "${HERMES_BOOTSTRAP_FILE}" <<EOF
You are Hermes in daytime factory mode.

Use the handoff already printed above and the files written under ${RUN_DIR}.
When the user asks for implementation work, route it through omx team or omx exec.
Do not edit code directly in the launcher shell; keep the interaction conversational.
Summarize what changed overnight, what remains, and what the user should decide next.
EOF

node - "${ROOT_DIR}" "${RUN_DIR}" "${NIGHT_SESSION_NAME}" "${DAY_SESSION_NAME}" "${night_session_exists}" "${day_session_exists}" "${status_json}" "${SUMMARY_TMP}" "${HANDOFF_FILE}" "${HANDOFF_JSON}" "${DAY_LAUNCH_STATE}" "${HERMES_BOOTSTRAP_FILE}" "${FACTORY_DAY_STALE_AFTER_HOURS}" <<'NODE'
const fs = require('fs');
const path = require('path');

const [rootDir, runDir, nightSessionName, daySessionName, nightSessionExistsRaw, daySessionExistsRaw, statusJsonRaw, summaryTmp, handoffFile, handoffJson, dayLaunchState, bootstrapFile, staleAfterHoursRaw] = process.argv.slice(2);
const nightSessionExists = nightSessionExistsRaw === 'true';
const daySessionExists = daySessionExistsRaw === 'true';
const staleAfterHours = Number(staleAfterHoursRaw || 10);

function readJson(file) {
  try { return JSON.parse(fs.readFileSync(file, 'utf8')); } catch { return null; }
}
function readText(file) {
  try { return fs.readFileSync(file, 'utf8'); } catch { return ''; }
}
function latestByPrefix(prefix, suffix = '') {
  try {
    return fs.readdirSync(runDir)
      .filter((name) => name.startsWith(prefix) && (!suffix || name.endsWith(suffix)))
      .map((name) => path.join(runDir, name))
      .map((file) => ({ file, mtime: fs.statSync(file).mtimeMs }))
      .sort((a, b) => b.mtime - a.mtime)[0]?.file || '';
  } catch { return ''; }
}
function compact(value, max = 180) {
  const text = String(value || '').replace(/\s+/g, ' ').trim();
  return text.length > max ? `${text.slice(0, max - 1)}…` : text;
}
function isoAgeHours(iso) {
  const ms = Date.parse(iso || '');
  if (!Number.isFinite(ms)) return null;
  return (Date.now() - ms) / 36e5;
}
function section(markdown, heading) {
  const lines = markdown.split(/\r?\n/);
  const out = [];
  let active = false;
  for (const line of lines) {
    if (/^##\s+/.test(line)) {
      if (active) break;
      active = line.replace(/^##\s+/, '').trim().toLowerCase() === heading.toLowerCase();
      continue;
    }
    if (active && line.trim()) out.push(line);
  }
  return out.slice(0, 10);
}
function bulletLines(lines, fallback = '- none') {
  const filtered = lines.map((line) => line.trim()).filter(Boolean);
  return filtered.length ? filtered.join('\n') : fallback;
}
function tailLines(file, count = 24) {
  const text = readText(file);
  if (!text) return [];
  return text.split(/\r?\n/).filter(Boolean).slice(-count);
}

let status = null;
try { status = JSON.parse(statusJsonRaw); } catch { status = null; }

const metaFile = path.join(runDir, 'latest-run.json');
const finishFile = path.join(runDir, 'latest-finish.json');
const shutdownFile = path.join(runDir, 'latest-shutdown.json');
const eventsFile = path.join(runDir, 'factory-night-events.log');
const meta = readJson(metaFile) || {};
const finish = readJson(finishFile) || {};
const shutdown = readJson(shutdownFile) || {};
const latestLog = meta.run_log || latestByPrefix('run-', '.log');
const finalSummaryFile = meta.final_summary_file || finish.summary_file || latestByPrefix('final-summary-', '.md');
const summaryFromFile = finalSummaryFile ? readText(finalSummaryFile) : '';
const summaryText = summaryFromFile || readText(summaryTmp);
const keepPrune = section(summaryText, 'KEEP / PRUNE CANDIDATES');
const remainingFromSummary = section(summaryText, 'NEEDS YOUR DECISION');
const done = section(summaryText, 'DONE');
const eventTail = tailLines(eventsFile, 8).map((line) => `- ${compact(line, 220)}`);
const logTail = latestLog ? tailLines(latestLog, 50) : [];
const notableLogLines = logTail
  .filter((line) => /(factory-night|ERROR|WARN|failed|finished|completed|stalled|started|rc=)/i.test(line))
  .slice(-8)
  .map((line) => `- ${compact(line, 220)}`);

const metaStatus = meta.status || status?.run_state || 'unknown';
const phase = meta.phase || 'unknown';
const agentAlive = meta.agent_alive === true || status?.run_state === 'running';
const startedAge = isoAgeHours(meta.started_at || meta.last_update_at);
let boundaryState = 'ready_for_day';
let boundaryReason = 'no factory-night tmux session is present';
if (nightSessionExists) {
  if (metaStatus === 'running' || agentAlive) {
    boundaryState = startedAge !== null && startedAge >= staleAfterHours ? 'stale_factory_night_needs_finish' : 'active_factory_night_needs_finish';
    boundaryReason = `factory-night tmux session ${nightSessionName} still exists; finish or inspect it before treating this as a clean day launch`;
  } else {
    boundaryState = 'stale_factory_night_needs_finish';
    boundaryReason = `factory-night tmux session ${nightSessionName} still exists after run status=${metaStatus}`;
  }
} else if (metaStatus === 'running' || meta.agent_alive === true) {
  boundaryState = 'stale_metadata_needs_finish';
  boundaryReason = 'latest-run metadata still says the night run is active, but the tmux session is missing';
} else if (finish.poweroff_ready === true || meta.phase === 'finish_complete') {
  boundaryState = 'finished_ready_for_day';
  boundaryReason = 'latest finish state says the run was closed out';
} else if (metaStatus === 'completed') {
  boundaryState = 'handoff_ready_needs_review';
  boundaryReason = 'night run completed; review keep/prune and remaining actions';
} else if (metaStatus === 'failed' || metaStatus === 'stalled') {
  boundaryState = `${metaStatus}_needs_triage`;
  boundaryReason = `night run ended with status=${metaStatus}`;
}

const remaining = [];
if (Array.isArray(meta.remaining_manual_actions)) remaining.push(...meta.remaining_manual_actions);
if (Array.isArray(finish.remaining_manual_actions)) remaining.push(...finish.remaining_manual_actions);
if (status && Array.isArray(status.remaining_manual_actions)) remaining.push(...status.remaining_manual_actions);
const uniqueRemaining = [...new Set(remaining.filter(Boolean))];
if (boundaryState.includes('needs_finish') && !uniqueRemaining.includes('finish_or_shutdown_factory_night')) {
  uniqueRemaining.unshift('finish_or_shutdown_factory_night');
}

const generatedAt = new Date().toISOString();
const payload = {
  schema_version: '1.0',
  generated_at: generatedAt,
  repo_path: rootDir,
  boundary_state: boundaryState,
  boundary_reason: boundaryReason,
  night_session_name: nightSessionName,
  night_session_exists: nightSessionExists,
  day_session_name: daySessionName,
  day_session_exists: daySessionExists,
  latest_run_meta: metaFile,
  latest_run_status: metaStatus,
  latest_run_phase: phase,
  latest_run_started_at: meta.started_at || null,
  latest_run_finished_at: meta.finished_at || null,
  latest_run_last_update_at: meta.last_update_at || null,
  night_task: meta.night_task || '',
  run_log: latestLog || '',
  event_log: fs.existsSync(eventsFile) ? eventsFile : '',
  summary_file: finalSummaryFile || '',
  finish_state_file: fs.existsSync(finishFile) ? finishFile : '',
  shutdown_state_file: fs.existsSync(shutdownFile) ? shutdownFile : '',
  finish_poweroff_ready: finish.poweroff_ready ?? meta.poweroff_ready ?? null,
  shutdown_result: shutdown.result || meta.team_shutdown_result || '',
  remaining_manual_actions: uniqueRemaining,
};

const md = [];
md.push('# Factory Day Handoff');
md.push('');
md.push(`Generated: ${generatedAt}`);
md.push(`Boundary: ${boundaryState}`);
md.push(`Reason: ${boundaryReason}`);
md.push('');
md.push('## Overnight');
md.push(`- run: status=${metaStatus} phase=${phase} mode=${meta.night_mode || meta.execution_mode || 'unknown'} last_event=${meta.last_event || 'unknown'}`);
md.push(`- task: ${compact(meta.night_task || 'unknown', 220)}`);
md.push(`- log: ${latestLog || 'none'}`);
md.push(`- summary: ${finalSummaryFile || 'generated from current metadata'}`);
if (done.length) md.push(...done.slice(0, 6));
if (eventTail.length) {
  md.push('');
  md.push('Recent night events:');
  md.push(...eventTail);
}
if (notableLogLines.length) {
  md.push('');
  md.push('Notable log tail:');
  md.push(...notableLogLines);
}
md.push('');
md.push('## Keep / Prune');
md.push(bulletLines(keepPrune));
md.push('');
md.push('## Remaining');
if (uniqueRemaining.length) {
  md.push(...uniqueRemaining.map((item) => `- ${item}`));
} else {
  md.push(bulletLines(remainingFromSummary));
}
md.push('');
md.push('## Finish / Shutdown State');
md.push(`- finish: poweroff_ready=${String(payload.finish_poweroff_ready ?? 'unknown')} file=${payload.finish_state_file || 'none'}`);
md.push(`- shutdown: result=${payload.shutdown_result || 'none'} file=${payload.shutdown_state_file || 'none'}`);
md.push('');
md.push('## Day Launcher');
md.push(`- day session: ${daySessionName}`);
md.push('- pane 1: Hermes orchestration / user conversation (auto-started)');
md.push('- pane 2: OMX execution/log tail');
md.push('- Hermes should route implementation requests through omx team or omx exec; do not edit directly in the launcher');
md.push(`- hermes bootstrap: ${bootstrapFile}`);
md.push(`- handoff json: ${handoffJson}`);
md.push('');

fs.writeFileSync(handoffFile, `${md.join('\n')}\n`, 'utf8');
fs.writeFileSync(handoffJson, `${JSON.stringify(payload, null, 2)}\n`, 'utf8');
fs.writeFileSync(dayLaunchState, `${JSON.stringify({
  schema_version: '1.0',
  generated_at: generatedAt,
  day_session_name: daySessionName,
  night_session_name: nightSessionName,
  boundary_state: boundaryState,
  boundary_reason: boundaryReason,
  handoff_file: handoffFile,
  handoff_json: handoffJson,
  run_log: latestLog || '',
}, null, 2)}\n`, 'utf8');

process.stdout.write(md.slice(0, 42).join('\n') + '\n');
NODE

log_to_tail=""
if [[ -f "${HANDOFF_JSON}" ]]; then
  log_to_tail="$(node -e 'const fs=require("fs");try{const j=JSON.parse(fs.readFileSync(process.argv[1],"utf8"));process.stdout.write(j.run_log||"");}catch{}' "${HANDOFF_JSON}")"
fi

tmux_enabled=0
case "${FACTORY_DAY_TMUX}" in
  0|false|no|off)
    tmux_enabled=0
    ;;
  auto)
    if command -v tmux >/dev/null 2>&1; then
      tmux_enabled=1
    fi
    ;;
  1|true|yes|on)
    tmux_enabled=1
    ;;
  *)
    echo "[WARN] Unknown FACTORY_DAY_TMUX=${FACTORY_DAY_TMUX}; treating as auto." >&2
    if command -v tmux >/dev/null 2>&1; then
      tmux_enabled=1
    fi
    ;;
esac

if [[ "${tmux_enabled}" == "1" ]]; then
  if ! command -v tmux >/dev/null 2>&1; then
    echo "[WARN] tmux is not available; handoff artifacts were prepared without launcher panes." >&2
  else
    if ! tmux has-session -t "${DAY_SESSION_NAME}" 2>/dev/null; then
      PRIMARY_PANE_SCRIPT="cd $(printf '%q' "${ROOT_DIR}") && clear && cat $(printf '%q' "${HANDOFF_FILE}") && echo && echo '[factory] Pane 1: OmX/Codex primary conversation.' && echo '[factory] Hermes is optional; use FACTORY_DAY_PRIMARY_COMMAND to override this pane.' && echo && exec ${FACTORY_DAY_PRIMARY_COMMAND}"
      tmux new-session -d -s "${DAY_SESSION_NAME}" -c "${ROOT_DIR}" bash -lc "${PRIMARY_PANE_SCRIPT}"

      should_split=0
      case "${FACTORY_DAY_TMUX_SPLIT_PANE}" in
        auto|1|true|yes|on) should_split=1 ;;
        0|false|no|off) should_split=0 ;;
      esac

      if [[ "${should_split}" == "1" ]]; then
        if [[ -n "${log_to_tail}" && -f "${log_to_tail}" ]]; then
          LOG_PANE_SCRIPT="cd $(printf '%q' "${ROOT_DIR}") && echo '[factory] Pane 2: OMX execution/log tail.' && echo '[factory] tailing: ${log_to_tail}' && echo && tail -n 80 -F $(printf '%q' "${log_to_tail}")"
        else
          LOG_PANE_SCRIPT="cd $(printf '%q' "${ROOT_DIR}") && echo '[factory] Pane 2: OMX execution/logs.' && echo '[factory] No run log found yet. Handoff:' && echo $(printf '%q' "${HANDOFF_FILE}") && echo && exec bash --noprofile --norc"
        fi
        if tmux split-window -t "${DAY_SESSION_NAME}:0" -h -c "${ROOT_DIR}" bash -lc "${LOG_PANE_SCRIPT}"; then
          tmux select-pane -t "${DAY_SESSION_NAME}:0.0" -T "${FACTORY_DAY_PRIMARY_PANE_TITLE:-omx-conversation}" 2>/dev/null || true
          tmux select-pane -t "${DAY_SESSION_NAME}:0.1" -T "${FACTORY_DAY_LOG_PANE_TITLE:-omx-logs}" 2>/dev/null || true
          tmux select-pane -t "${DAY_SESSION_NAME}:0.0" 2>/dev/null || true
        else
          echo "[WARN] failed to create the OMX log pane; day session is single-pane." >&2
        fi
      fi
      if [[ "${FACTORY_DAY_HERMES_AUTOSTART}" == "1" ]]; then
        tmux send-keys -t "${DAY_SESSION_NAME}:0.0" "$(tr '\n' ' ' < "${HERMES_BOOTSTRAP_FILE}" | sed 's/[[:space:]]\+/ /g; s/^ //; s/ $//')" C-m 2>/dev/null || true
      fi
      echo "[factory] day tmux session prepared: ${DAY_SESSION_NAME}"
    else
      echo "[factory] day tmux session exists: ${DAY_SESSION_NAME}"
    fi

    should_attach=0
    case "${FACTORY_DAY_TMUX_ATTACH}" in
      auto)
        if [[ -t 1 ]]; then
          should_attach=1
        fi
        ;;
      1|true|yes|on)
        should_attach=1
        ;;
    esac
    if [[ "${should_attach}" == "1" ]]; then
      if [[ -n "${TMUX:-}" ]]; then
        tmux switch-client -t "${DAY_SESSION_NAME}:0"
      else
        tmux attach-session -t "${DAY_SESSION_NAME}"
      fi
    else
      echo "[factory] attach with: tmux attach -t ${DAY_SESSION_NAME}"
    fi
  fi
else
  echo "[factory] tmux launcher disabled; handoff: ${HANDOFF_FILE}"
fi
