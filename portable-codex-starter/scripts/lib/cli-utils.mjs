export function parseArgs(argv) {
  const parsed = {};

  for (let index = 0; index < argv.length; index += 1) {
    const arg = argv[index];
    if (!arg.startsWith("--")) continue;

    const inlineEquals = arg.indexOf("=");
    if (inlineEquals !== -1) {
      const key = arg.slice(2, inlineEquals);
      const value = arg.slice(inlineEquals + 1);
      parsed[key] = value === "" ? true : value;
      continue;
    }

    const key = arg.slice(2);
    const next = argv[index + 1];
    if (!next || next.startsWith("--")) {
      parsed[key] = true;
      continue;
    }

    parsed[key] = next;
    index += 1;
  }

  return parsed;
}
