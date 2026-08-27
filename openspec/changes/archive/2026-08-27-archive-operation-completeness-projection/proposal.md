## Why

An upload receipt and a terminal Platform operation do not currently carry the backend's
AI-archive completeness outcome. Clients therefore cannot truthfully distinguish a complete
import from one with gaps without parsing private service data or inventing a status.

## What Changes

- Define the bounded, privacy-safe typed AI archive import summary that an import producer attaches
  to its terminal Platform operation result.
- Define how Platform preserves that typed summary in its existing operation snapshot, and how clients
  treat its absence and unreachable reads as unknown rather than as an import result.
- Record the rollout order for `ratatoskr-contracts`, `ratatoskr-export-agent`, the AI archive
  producers, and Platform. Platform projects the added field through its existing operation route;
  producer publication additionally requires an archive-acceptance operation correlation path.

## Capabilities

### New Capabilities

- `ai-archive-operation-summary`: A safe, bounded completeness projection carried by an AI archive
  import operation result.

### Modified Capabilities

None. The existing `operation-progress` requirement already retains additive result fields.

## Impact

The contract is consumed by Platform, ChatGPT/Claude archive import producers, and export-agent.
It contains only provider, identifiers, aggregate counts, completeness classification, bounded
gap/warning counts, and a report reference; it contains no export content, titles, paths, or
credentials. Rollback is safe because older clients preserve or ignore the additive result field;
new clients present its absence as unverified rather than complete.
