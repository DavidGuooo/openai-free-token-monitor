# Free Token Monitor

A minimal native macOS menu bar app for this OpenAI organization. **The only
setup field is the Admin API key.** The popup shows two allowance bars (blue
input, purple output, gray remaining), today's paid tokens, and the reset countdown.
It deliberately has no Dock icon or main window.

## Run

Requires macOS 14+ and Swift 6 (Xcode).

```sh
./script/build_and_run.sh
```

The Codex **Run** action uses the same script. It stages and locally signs
`dist/FreeTokenMonitor.app`; open that app in Finder to run it later.

Click the key icon to add or replace an organization Admin key. **Save** stores
it in this Mac's Keychain. Existing saved keys are reused automatically after
updates. There are no model, allowance, tier, or refresh-interval fields.
A link in the key window opens
[OpenAI's Admin-key page](https://platform.openai.com/settings/organization/admin-keys).
The secure connector available in this session only creates project keys,
which cannot read organization usage. Never send keys in chat or source control.

## Automatic policy

Verified on October 3, 2026:

- This account's signed-in Limits page reports **Usage tier 1**; the data-sharing
  page confirms enrollment, but does not display numeric account-specific quotas.
- OpenAI's published Tier 1–2 policy is **250,000/day** for the larger pool and
  **2,500,000/day** for the smaller pool, input plus output combined.
- This account's Usage API returns **incentivized-tier** for free traffic and
  **default** for paid traffic. Those mappings are built in.
- Model groups are populated from the official help article in
  `Sources/MonitorCore/ComplimentaryPolicy.swift`. Aliases, dated snapshots, and
  the observed underscore form of GPT-6.1 Sol are matched automatically.
- The current article puts **gpt-6-luna in the larger pool** and **gpt-5.6-luna in
  the smaller pool**. Similar-looking model names are not matched by prefix.
- **GPT-6.1 Sol** is observed in this account's free tier but omitted from the
  published model list. It is assigned to the larger pool **by inference** from
  the Sol family. Its pool entitlement is not independently verified.

The allowance total’s tooltip explains both the policy-based caps and
GPT-6.1 Sol inference. The app does not pretend
these are API-returned balances. If observed free use exceeds a published cap,
counts and percentages remain truthful and an overage note appears. Unknown
models and unknown tiers are shown only when they have current-day usage.
Old manual preferences are ignored; adding a key is sufficient.

This is the profile researched for this specific Tier 1 organization. If the
organization upgrades usage tiers or its offer changes, update the policy in
source. The API used here does not expose the complimentary cap or account tier.

## Accounting

- Makes only `GET /v1/organization/usage/completions` requests, grouped by model
  and service tier, across the organization with no project/key filter.
- Pagination is handled. Reads seven UTC days, but **only today's UTC bucket**
  contributes to the popup. No inference requests, clip processing, sharing
  changes, or pipeline stopping.
- Cached and cache-write input are already included in `input_tokens`; never
  add them again. Free use is input plus output counted normally.
- **Paid tokens** is the organization-wide total for its verified `default`
  tier, across all models. Other service tiers remain unclassified. It is read
  independently from the API, not calculated by subtracting the estimated cap
  from free usage. Free usage above the estimate can therefore coexist with
  zero reported paid tokens; this does not establish the actual allowance.
- Refreshes automatically every **five minutes** while running, including when
  the popup is closed. No scheduled automation or login item is installed.
  Transient connection failures get one immediate retry and another refresh
  after 30 seconds. Authentication and certificate-validation failures are not
  immediately retried. The UI reports timeout, DNS, offline, and TLS failures
  separately without exposing request details.
- Resets at **00:00 UTC / 08:00 China time**. Old-day counts are hidden until a
  successful new-day refresh. Errors preserve same-day counts with a visible error.
- Reporting can lag; a request crossing the quota can be billed in full. The
  monitor displays usage; it does not enforce a spending cap.

## Security

Keys stay in a nonsynchronized macOS Keychain item. No plaintext key is written
to project files, preferences, logs, screenshots, or diagnostic output. Usage is
held in memory. HTTP uses an ephemeral session with a fixed OpenAI origin and
refuses redirects. Server error bodies are never displayed. Revoke the Admin
key on OpenAI's page to invalidate it remotely.

## Verification

```sh
swift test
./script/build_and_run.sh --verify
./script/build_and_run.sh --preview
./script/build_and_run.sh --render-preview /private/tmp/free-token-monitor-preview.png
```

Preview is clearly labeled **DEMO**, never reads the Keychain or calls OpenAI,
and illustrates 10% input / 30% output / 60% remaining in both pools.

For an authenticated check using the already saved key:

```sh
./script/build_and_run.sh --render-live /private/tmp/free-token-monitor-live.png
```

The render command captures only the app's own view to PNG and exits. Its
live variant contains account token totals, never credentials. Relaunch the
normal app afterward. Tests cover automatic policy defaults and model aliases,
UTC resets, cached-token accounting, pool separation, cap overflow, pagination,
unknown classifications, and safe error handling with synthetic API responses.

## Sources

- [Complimentary tokens and model groups](https://help.openai.com/en/articles/10306912-sharing-feedback-evaluation-and-fine-tuning-data-and-api-inputs-and-outputs-with-openai)
- [Organization completions Usage API](https://developers.openai.com/api/reference/resources/admin/subresources/organization/subresources/usage/methods/completions)
- [Admin API authentication](https://developers.openai.com/api/docs/guides/admin-apis)

Sources checked on October 3, 2026, plus the signed-in account settings and
October 3 LingTok tracker handoff. Historical observations are not used as live counts.
