---
name: senior-review
description: Run the Gemini senior review script, read the feedback, and fix the code directly. Repeat up to 2 times maximum before committing.
---

# Senior Review Protocol

You are the primary executor. You must fix the code yourself based on the senior architect's review. **Do NOT delegate this to a sub-agent or another codex command.**

## Workflow
1. Run Round 1: `SENIOR_REVIEW_ROUND=1 bash scripts/get-senior-review.sh`
2. Read `.tmp-gemini-review-round1.json` and run `node scripts/review-gate.mjs --file .tmp-gemini-review-round1.json`.
3. If the verdict is "pass", the review is complete. You may proceed.
4. If the verdict is "fail" and there are issues, **YOU** must directly modify the files to fix the reported issues.
5. After applying your fixes, run Round 2: `SENIOR_REVIEW_ROUND=2 bash scripts/get-senior-review.sh`.
6. Read `.tmp-gemini-review-round2.json` and run `node scripts/review-gate.mjs --file .tmp-gemini-review-round2.json --final`.
7. You **MUST STOP** after a maximum of 2 review rounds, even if minor issues remain. Do not loop a third time.
8. Hard gate: if any `severity="critical"` remains after Round 2, **DO NOT commit**.
9. Hard gate: if AGENTS.md violations or architectural inconsistency remain after Round 2, **DO NOT commit**.
10. Once the loop is complete and all gates pass, proceed to create your durable checkpoint or git commit.
