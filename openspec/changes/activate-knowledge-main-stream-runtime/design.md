## Context

See `proposal.md` for motivation. The present transport boundary is asymmetric: Extractor already publishes `evt.content.document.extracted.v1`, and the fleet contracts already define the social, AI-archive, and repository-analysis event families, but Platform owns no primary Knowledge durable and the Knowledge process starts no corresponding adapter. The usable analysis components are library-only.

The missing adapter cannot safely call those components directly. Existing source receipt rows have no claim/retry state, intermediate pipeline states are not all resumable, repository content has no production resolver, and only channel recap has a transactional outbox. A crash between receipt and execution or between terminal state and publication would turn redelivery into a duplicate while permanently losing the work or terminal fact.

The fleet remains in development: schema definitions are edited in place, no migration is added, and all contracts remain v1. Platform owns NATS topology and credentials. Knowledge owns analysis admission, budgets, retries, derived data, and terminal publication. GitHub owns README bytes; their `BlobRef` is an authority-bearing reference, not a shared filesystem address.

## Goals / Non-Goals

**Goals:**

- Turn the existing contract families into one continuously running, supervised Knowledge intake without broadening bus authority.
- Separate short transport admission from potentially slow and costly analysis.
- Make every accepted event discoverable work, every state transition restart-safe, and every terminal fact replay-safe.
- Prove the real Extractor document path and canonical fixture paths for currently incomplete producers.
- Preserve owner isolation, privacy deletion, spend controls, and evidence boundaries.

**Non-Goals:**

- Implement or repair the live X, Instagram, Threads, GitHub, ChatGPT, or Claude event publishers.
- Introduce a shared database, allow Knowledge to read GitHub tables, or treat `BlobRef` as a local path or arbitrary URL.
- Run inference inside a JetStream acknowledgement window.
- Promise exactly-once execution of a third-party model call when the provider gives no idempotency or reconciliation primitive.
- Replace the existing channel-recap contract or merge recap work into the primary event durable.

## Decisions

### 1. Register the existing document wire fact without a compatibility lane

`Document` becomes the typed payload for `content.document.extracted.v1`, and Contracts registers the event schema and fixtures beside the existing document schema. The payload remains the current object embedded directly in `EventEnvelope`; there is no wrapper and no v2. Extractor switches from a string-parsed event type and untyped object conversion to the typed constructor after the Contracts release is available.

This is preferable to teaching Knowledge a permanent unregistered exception. A wrapper would change the wire shape, while an adapter-only decoder would leave the registry, generated bindings, and producer/consumer tests disagreeing about a live event.

### 2. Use one exact multi-filter primary durable and keep recap separate

Platform adds `ratatoskr_knowledge_main` on `ratatoskr_events` with the exact subjects in `knowledge-main-event-stream/spec.md`. It also takes ownership of pre-provisioning the already named recap command durable. Edge startup uses the same fixed-consumer inventory used to render and test the NATS permission profile; drift is a startup error, not something Knowledge repairs.

One multi-filter durable gives the primary processor a single replay cursor and one least-privilege permission surface without subscribing to `evt.>`. The installed NATS/async-nats versions must be proven to preserve the exact filter set. If that concrete compatibility test fails, the implementation must return to OpenSpec design rather than silently replacing the specified topology with ephemeral or broad consumers.

Recap stays separate because it is a command workflow with different payloads, output subjects, and readiness policy. Combining command and fact delivery would muddle authority and failure isolation.

### 3. Use one Knowledge NKey with explicit durable and output allowlists

Platform renders one `ratatoskr-knowledge` identity. Its request permissions name only consumer info, pull, and acknowledgement subjects for `ratatoskr_knowledge_main` and `ratatoskr_knowledge_channel_recap`; publish permissions name only Knowledge terminal facts; subscription permits only reply inboxes. Tests start a real broker with generated test credentials and prove both the allow and deny matrices without exposing a production seed.

One identity matches the deployable and keeps configuration tractable. Separate identities per family would improve blast-radius isolation slightly but multiply credential rotation and deployment state without separating processes. A broad `evt.>` subscription or consumer-create authority is rejected because it lets a compromised analyzer observe unrelated user facts or move fleet cursors.

### 4. Split transport admission, work execution, and terminal publication

The runtime has three supervised roles:

1. The event adapter validates transport/envelope/payload identity and commits a receipt plus family-specific source state and schedulable work in one short transaction. It ACKs only after commit, Terms permanent invalid input after a content-free rejection receipt, and NAKs transient persistence failures.
2. Leased workers claim eligible database work independently of JetStream. They prepare context, reserve budget, call the selected provider, validate/repair once under the existing policy, persist artifacts and search projections, and advance explicit durable states.
3. An outbox publisher drains terminal event envelopes independently, supplies the event identifier as `Nats-Msg-Id`, and marks a row sent only after the broker acknowledges it.

This separation prevents a slow model call from exhausting the acknowledgement deadline or head-of-line blocking the durable. Calling a family pipeline inline would be smaller but recreates the confirmed commit-before-analysis loss window and couples broker redelivery to cost control.

### 5. Replace receipt-only deduplication with collision-checking durable work

The current schema definition is edited in place to make one primary receipt/work model authoritative. Each receipt stores event identity, exact subject, canonical immutable envelope digest, tenant, aggregate, family, and accepted time. Reusing an event ID with another digest or identity is a permanent collision, not a duplicate. A work row stores family, source key/revision, state, attempt counters, next eligibility, lease owner/expiry, and the immutable input reference required to resume.

Family-specific projections remain in their owning tables, but admission APIs accept a caller transaction so receipt, source-head comparison, work creation, and any tombstone suppression commit atomically. Repository requests either join this work model or gain the same lease/state fields and atomic admission guarantee; they do not retain a second unclaimable pending queue.

This is chosen over using JetStream as the work queue because inference can exceed delivery windows, retry policy belongs to Knowledge, and deletion ordering must be transactional with Knowledge-owned state. No migration file is added: test and deployment databases are recreated from the corrected first-version schema as required by development status.

### 6. Make state recovery explicit, including uncertain provider outcomes

Every persisted state has one legal restart action. Pure preparation and persistence states can replay deterministically. A durable provider response is never requested again. Retryable responses schedule a bounded next attempt; final validation or budget failures terminate once.

A network failure after a provider may have accepted a request but before Knowledge durably received the response is fundamentally uncertain when the provider offers no idempotency or lookup API. Knowledge records `provider_outcome_unknown` and does not blindly issue another billable request. Automatic retry is allowed only when the configured provider proves idempotent request keys or explicitly reports that it did not accept the call. Operators can inspect and explicitly requeue uncertain work under the existing spend controls. Tests use a scripted idempotent provider to exercise deterministic restart, while the verification record does not claim live-provider exactly-once billing.

This is preferable to automatic timeout retry, which can duplicate charges, or pretending the external side effect participates in the database transaction.

### 7. Apply lifecycle facts before analysis and retain suppression evidence

Social captured/updated facts and AI-archive state-carried facts compare their authoritative revision with the current owner-scoped head before creating work. A social removal or archive tombstone records suppression evidence and deletes scoped analyses, embeddings, and search entries in one transaction. Later facts at an older or equal revision are accepted as transport duplicates/stale observations but do not recreate work. Unknown owners or subjects cannot broaden the deletion scope.

This extends the existing SourceInbox semantics rather than relying on arrival order. Deleting only derived rows without retaining the tombstone would allow an old JetStream replay to resurrect private data.

### 8. Resolve GitHub README bytes through an owner-service API

GitHub Catalog adds a service-authenticated, owner-scoped internal endpoint that accepts the immutable `BlobRef` identity already carried by `RepositoryAnalysisRequested`. It returns only the bounded bytes and media type after verifying owner service, digest, recorded length, tenant/repository association, and caller authority. It does not expose arbitrary lookup by URL or database key.

Knowledge implements `RepositoryReadmeResolver` against this endpoint with an end-to-end timeout and response-size cap, then independently verifies digest, media type, length, and request ownership before context construction. Unavailable service responses are retryable; missing, unauthorized, malformed, oversized, or digest-conflicting responses follow the typed final-failure policy.

A direct GitHub database read would create a shared-schema dependency and bypass service authorization. Fetching the public provider URL would lose immutable evidence and could analyse changed content. Moving README bytes into the event would violate bounded event contracts and privacy expectations.

### 9. Commit terminal state and outbox intent together

One general Knowledge outbox stores canonical terminal envelopes for social, AI archive, repository success/failure, and existing recap outputs where practical. The state transition and insert share a transaction and a uniqueness key derived from logical work plus terminal event type. The publisher operates at least once; JetStream deduplication and downstream inboxes make repeated delivery safe.

Documents currently have no terminal bus contract, so their observable completion is durable analysis/search state rather than a new undocumented fact. A document completion event can be proposed separately only if a consumer need emerges.

### 10. Readiness and shutdown observe the full worker set

Production primary mode is explicit configuration, but a configured primary role cannot degrade to admin-only operation. Startup validates storage, broker connection, exact fixed topology, provider role, GitHub resolver configuration, and worker construction before ready. Supervisors retain join handles and health watches; an unexpected exit removes readiness. Indexing, primary intake, leased workers, and outbox publishing all stop claiming new work on cancellation, settle or release in-flight boundaries, join within the configured bound, and close the database last.

The admin endpoint remains available while unready so operators can inspect health. Treating an absent optional block as success is retained only for deliberately non-primary development commands, never for the deployed Knowledge role.

### 11. Integration proof is task-namespaced and evidence-typed

KNO-018 creates isolated child worktrees and a Compose profile with real NATS and Postgres, the real Extractor path, GitHub's internal content endpoint, Knowledge, and a scripted provider. Canonical fixtures inject social, AI-archive, and repository events only where their live publisher is outside scope. Fault controls stop Knowledge at admission, state, and outbox boundaries and exercise broker disconnect, tombstone replay, poison input, and SIGTERM.

The changeset records exact child SHAs and distinguishes repository-local tests, composed fixture proof, push proof, hosted CI, live deployment, provider billing, and live producer coverage. A green fixture cannot close the separately owned producer-runtime gaps.

## Risks / Trade-offs

- [A single multi-filter durable could head-of-line block families if a worker performs slow work inline] → Keep admission short, Term permanent poison input, and move all analysis to independent leased queues; alert on durable lag and per-family pending work.
- [The deployed NATS version may not preserve multiple exact filters] → Prove broker configuration in Platform tests before implementation proceeds; revise the approved topology explicitly if incompatible.
- [Schema replacement requires recreation of development databases] → Record the destructive development-only reset in repository runbooks and never add migration tooling while the development-status rule applies.
- [An external model call can have an unknowable outcome] → Never blind-retry an uncertain accepted call; require provider idempotency for automatic replay and expose explicit requeue with budget accounting otherwise.
- [One Knowledge identity can publish several terminal families] → Exact subject allowlists, fixed durable routes, no source publication, and broker deny tests limit blast radius.
- [Tombstone races can erase or resurrect the wrong data] → Compare owner-scoped source revision and commit suppression evidence with deletion; test stale and cross-tenant replay.
- [GitHub content API adds runtime coupling] → Use bounded timeouts and durable retry state; keep references immutable so retries resolve the same evidence.
- [A large backlog can consume inference budget after activation] → Preserve durable cursor and intake, but gate work claims through existing daily budget/concurrency controls and expose backlog age without high-cardinality labels.
- [Synthetic producer fixtures can be mistaken for fleet completion] → Encode proof type in the changeset and block wording that claims live producer or deployment evidence.

## Migration Plan

1. Create KNO-018 task worktrees from current `origin/main` for Contracts, Platform, GitHub, Knowledge, Extractor, and Workspace; record base SHAs, roles, and dependencies. Baseline submodules remain untouched.
2. Publish the typed document event from Contracts and make its generated artifacts and compatibility fixtures green.
3. Land Platform's fixed consumers, least-privilege identity, startup validation, and broker permission tests. Deploy/provision these consumers before any new Knowledge instance can become ready.
4. Land GitHub's backward-compatible immutable-content endpoint and authorization tests. No GitHub bus publisher is activated by this step.
5. Land Knowledge's bus adapter, corrected current schema, work recovery, content resolver, terminal outbox, readiness, metrics, and bounded shutdown. Start it with work claims disabled, verify topology and backlog visibility, then enable claims under configured budget.
6. Land Extractor's typed event construction and validate that its existing wire fixture is unchanged.
7. Run repository-local gates, then the KNO-018 composed fault/replay matrix. Open child PRs in dependency order and record merged SHAs.
8. Advance Workspace pins only to merged child commits, regenerate the lock/snapshot, rerun topology and integration validation, then publish the workspace commit.

Rollback stops affected upstream event publication or Knowledge work claims first, drains Knowledge within the bound, stops Knowledge, and rolls child deployment/pins back in reverse order. It preserves `ratatoskr_knowledge_main`, its cursor, and all Knowledge receipt/work/outbox rows. Because the system is in development and the corrected schema replaces the first-version definition, a rollback that returns to the old Knowledge binary uses a recreated development database; it never attempts a down migration or deletes accepted broker state.
