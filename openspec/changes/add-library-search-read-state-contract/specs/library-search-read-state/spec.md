## Purpose

Defines the authenticated fleet boundary through which clients search or browse their library, observe effective read state, and replace that state without bypassing Knowledge ownership.

## ADDED Requirements

### Requirement: Platform exposes one bounded authenticated library search

Platform SHALL serve `GET /v1/library/search` only to a valid session principal. The request SHALL accept optional `q`, optional `read_state` from the closed values `read` and `unread`, `limit` from 1 through 100, and a non-negative `offset`; omitted or whitespace-only `q` SHALL mean recency browse. A non-empty query longer than 512 Unicode scalar values, an unknown read-state value, an out-of-range page bound, or any public tenant selector SHALL fail as an invalid request before Knowledge is queried.

#### Scenario: Authenticated text search succeeds

- **WHEN** an authenticated user requests `/v1/library/search?q=durable&limit=5&offset=0`
- **THEN** Platform returns one bounded page belonging only to that user and the page records the requested limit, offset, and whether another result exists

#### Scenario: Blank query browses by recency

- **WHEN** an authenticated user requests the search route with no `q` or a whitespace-only `q`
- **THEN** the response contains that user's items in deterministic descending recency order without claiming a relevance match

#### Scenario: Public tenant selection is refused

- **WHEN** an authenticated user adds a `tenant` parameter naming any tenant
- **THEN** Platform returns the stable invalid-request error and does not issue a Knowledge query

### Requirement: Library summaries carry authoritative identity and effective read state

Each returned item SHALL contain an accepted analysis identifier, its document identifier, a title of at most 256 Unicode scalar values, an optional snippet of at most 512 Unicode scalar values, an optional finite positive relevance score, and the effective `read` or `unread` state. A tenant-owned accepted analysis with no persisted state row SHALL be reported as `unread`. Matched search results SHALL be ordered by descending relevance with a deterministic tie-break; recency browse SHALL omit snippet and score.

#### Scenario: Missing state is unread

- **WHEN** a tenant-owned accepted analysis matches a query and has no read-state record
- **THEN** its result contains its accepted analysis and document identifiers and reports `read_state` as `unread`

#### Scenario: Ranked and browse result semantics differ explicitly

- **WHEN** the same item appears once in a non-empty search and once in a blank-query browse
- **THEN** the matched result may carry bounded snippet and score while the browse result carries neither

### Requirement: Read-state filtering precedes ordering and pagination

When `read_state` is present, Knowledge SHALL filter the authenticated tenant's effective states before ranking or recency ordering, page truncation, `has_more` calculation, and offset application. The filter SHALL NOT expose a count, identifier, title, or timing fact about another tenant.

#### Scenario: Unread page is filled before pagination

- **WHEN** a tenant has interleaved read and unread results and requests `read_state=unread&limit=2&offset=0`
- **THEN** the page contains the first two unread results in the selected ordering rather than fewer items produced by post-page filtering

#### Scenario: Foreign matches affect no page facts

- **WHEN** another tenant has matching unread items ahead of the caller's results
- **THEN** the caller's items, `has_more`, and page positions are identical to a database in which those foreign items do not exist

### Requirement: Read state is an idempotent owner-scoped resource

Platform SHALL serve `PUT /v1/library/items/{analysis_id}/read-state` with an exact body containing one closed `read_state` value. The authenticated principal SHALL be the only tenant authority. Replacing state with its existing value SHALL succeed idempotently, SHALL leave exactly one state record, and SHALL preserve favorite, tags, collections, highlights, feedback, analysis evidence, and every field not named by this resource.

#### Scenario: Repeated mark-read preserves other user content

- **WHEN** the owner puts `read` twice for an accepted analysis that is favorite and belongs to a collection
- **THEN** both calls return `read`, one state record remains, and favorite and collection membership are unchanged

#### Scenario: Foreign and absent analyses are indistinguishable

- **WHEN** a principal puts read state for another tenant's analysis identifier and for a nonexistent identifier
- **THEN** both calls return the same scoped not-found error and change no state

### Requirement: Library capabilities reflect dependency availability

`GET /v1/capabilities` SHALL use the closed names `library.search` and `library.read_state`. A name SHALL appear only when its Platform route is implemented, the caller is authorized, and the last bounded dependency observation says the session/database path and required Knowledge surface are available. A request racing with a later dependency failure SHALL return a stable retryable unavailable error rather than stale or fabricated data.

#### Scenario: Knowledge becomes unavailable

- **WHEN** the last Knowledge health observation changes from available to unavailable
- **THEN** both library capability names disappear and a library request returns a retryable unavailable error

### Requirement: Telegram commands adapt the public contract without owning library state

For an authorized user in a private chat, `/search <query>` SHALL request the first five all-state matches, `/unread` SHALL request the first five unread recency results, and `/read <opaque-token>` SHALL replace one token-bound analysis state with `read`. Search queries SHALL contain 1 through 256 Unicode scalar values after trimming. `/unread` SHALL accept no argument. `/read` SHALL accept only one 64-character URL-safe opaque token. No command SHALL call Knowledge directly or create a Telegram-owned library projection, search history, or read state; only the bounded rendered reply required by the existing durable outbound queue MAY retain title and snippet text until normal outbound retention removes it.

#### Scenario: Search and unread map to distinct public queries

- **WHEN** an authorized private-chat user sends `/search recovery` and later `/unread`
- **THEN** Telegram issues a five-item query for `recovery` with no state filter and a five-item blank query filtered to `unread`, both through Platform

#### Scenario: Invalid command shape has no domain effect

- **WHEN** the user sends an empty or oversized `/search`, `/unread now`, or `/read` without one valid opaque token
- **THEN** Telegram returns bounded usage guidance and sends no library query or mutation

### Requirement: Telegram result and read authority is bounded and private

Telegram SHALL render one escaped HTML message that is shorter than 4096 Unicode scalar values, contains at most five results, limits each rendered title to 160 and snippet to 320 Unicode scalar values, and omits absent snippets or scores rather than inventing them. When `library.read_state` is available, each unread result SHALL receive a 15-minute, single-use, single-purpose token bound to the bot, Telegram actor, internal user, and private chat; when it is absent the result SHALL carry no read token. The token SHALL carry no analysis identifier, query, title, snippet, or tenant data. A foreign, malformed, expired, or consumed token SHALL release no action and SHALL receive the same safe expired-action guidance.

#### Scenario: Forwarded read token grants no authority

- **WHEN** another user or chat presents a live token copied from a search result
- **THEN** no Platform mutation occurs, the token remains unavailable to that foreign scope, and the response reveals no target fact

#### Scenario: Hostile result content is inert and bounded

- **WHEN** a title and snippet contain Telegram HTML metacharacters and lengths beyond the rendering budget
- **THEN** the queued reply contains escaped, deterministically truncated text within the Bot API limit and no active injected markup

### Requirement: Telegram reports authoritative and uncertain outcomes truthfully

Telegram SHALL claim `read` only after Platform returns the authoritative state. It MAY retry the idempotent PUT within a finite timeout and attempt bound. Scoped absence SHALL render a stable item-unavailable response; absent capability or upstream unavailability SHALL render a retryable feature-unavailable response; exhaustion after a request may have reached Platform SHALL render an outcome-unknown response directing the user to rerun `/unread`. Query text, titles, snippets, tokens, Telegram identifiers, tenant identifiers, and analysis identifiers SHALL NOT appear in ordinary logs or metric labels.

#### Scenario: Uncertain mark-read claims no success

- **WHEN** every bounded mutation attempt loses the response after sending the request
- **THEN** Telegram does not say the item was marked read and tells the user to check with `/unread`

#### Scenario: Successful read is acknowledged once

- **WHEN** Platform returns authoritative `read` for a valid token and the same token is presented again
- **THEN** one success reply is queued for the winning presentation and the replay performs no mutation

### Requirement: Fleet rollout is additive and integration-tested

Knowledge SHALL deploy its additive result/filter/mutation support before Platform exposes the public routes and capability names; Telegram SHALL deploy after Platform. Workspace integration SHALL use real service processes and disposable PostgreSQL data with a synthetic Bot API to prove search, unread filtering, idempotent read state, token scope denial, and capability disappearance on Knowledge failure. Rollback SHALL proceed Telegram, Platform, Knowledge and SHALL retain valid Knowledge read-state rows.

#### Scenario: Composed command flow changes authoritative state

- **WHEN** the composed profile seeds one read and two unread tenant-owned analyses, exercises `/search`, `/unread`, and a returned `/read` token, then repeats `/unread`
- **THEN** the Bot API recording shows bounded search/unread replies, Knowledge reports exactly one newly read analysis, and the final unread reply omits that analysis without changing its favorite state
