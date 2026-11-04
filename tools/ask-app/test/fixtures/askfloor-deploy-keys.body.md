# IDE-308: model provider keys for production

Production's GitHub environment now has every secret a release needs except the model provider keys. They are optional: a key that isn't set is sent empty, and the feature that uses it is off in production. Staging has two of them, `GEMINI_API_KEY` and `OPENAI_API_KEY`.

The production secrets that could be set: `GEMINI_API_KEY`, `VERTEXAI_API_KEY`, `OPENAI_API_KEY`, `CEREBRAS_API_KEY`, `GROQ_API_KEY`, `DEEPSEEK_API_KEY`, `OPENROUTER_API_KEY`, `CLAUDE_CODE_OAUTH_TOKEN`, `ANTHROPIC_API_KEY`.

GitHub never shows a secret's value, so no agent can copy staging's keys across. Whichever option you pick, the values have to come from you: set them yourself with `gh secret set <NAME> --env production -R example-org/kit`, or point to where they live (for example a local `.env` file), and app:deploy sets them without printing them.

The deploy window does not wait on this. If nobody decides, production launches with these features off.

## Choose one: production's model provider keys
Lean: OFF
IfUnanswered: production launches with these features off.
- [ ] [REUSE] Use the same keys as staging (`GEMINI_API_KEY`, `OPENAI_API_KEY`)
  Production gets Gemini and OpenAI features from launch, billed to the same accounts as staging.
  Cost: you supply the two values once (or say where they live); staging and production share quota and a leak of one exposes both.
- [ ] [SEPARATE] Separate production keys (name which in the note)
  Production's usage and billing stay apart from staging's.
  Cost: you create and supply new keys for each provider you want on.
- [ ] [OFF] Leave them off in production for now (recommended until the launch is green)
  Nothing to do now; the launch proceeds without model features, and keys can be added later with no deploy change.
  Cost: model-backed features are unavailable in production until keys are set.

