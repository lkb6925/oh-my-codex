---
name: deepsearch
description: Perform a thorough repository search and map how a concept is implemented
---

# Deep Search

Use this skill when the user needs a broad but concrete map of where a concept lives in the codebase.

## Workflow

1. Search exact terms and likely variants.
2. Read the main matches, not just filenames.
3. Follow imports, callers, and related modules.
4. Separate primary implementation from peripheral references.
5. Summarize the code path and the important files.

## Output

- Primary locations
- Related files
- Usage patterns
- Key conventions or gotchas
