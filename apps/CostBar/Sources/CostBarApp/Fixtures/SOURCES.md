Recorded 2026-10-12 from public provider documentation. No account data or secrets.

- openrouter-key.json: selected fields from https://openrouter.ai/docs/api/api-reference/api-keys/get-current-api-key . Usage values are unchanged; the label is anonymized. BYOK costs must not be included in OpenRouter credit spend.
- openrouter-credits.json: https://openrouter.ai/docs/api/api-reference/credits/get-credits . Example values are unchanged.
- anthropic.json: selected fields from https://platform.claude.com/docs/en/api/http/beta/organization/cost_report/retrieve . Description shortened; dates, amount and pagination preserved. Cents are converted to dollars per https://platform.claude.com/docs/en/manage-claude/usage-cost-api . This fixture is a first page, not a complete monthly report.
- openai.json: response example from https://developers.openai.com/api/reference/resources/admin/subresources/organization/subresources/usage/methods/costs . Dates, amounts and pagination unchanged.

Screenshots use OpenRouter's key example with an explicit Sample data caption. Bundled fixtures are exact copies of these test files; scripts/sync_fixtures.sh maintains them.
