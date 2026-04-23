export async function onEvent(payload) {
  return {
    ...payload,
    plugin: "sample-hook",
    recorded_at: new Date().toISOString(),
  };
}
