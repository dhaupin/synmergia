# labs/prompts/ -- generation prompt staging

Briefs in this folder are for the human to run through the image
generator (Gemini). Convention:

- `gemini_<subject>.md` -- one brief per file.
- Every brief embeds the **style lock** from `labs/art-direction.md`
  so renders come back on-model; do not strip it.
- Keep the brief copy-pasteable: the final "PROMPT" section should be
  a single self-contained block.
- After rendering: drop results in the shared Drive, attach favorites
  in chat for critique, and they either iterate or get canonized.
