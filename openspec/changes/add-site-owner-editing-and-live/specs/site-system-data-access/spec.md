# Spec Delta

## Purpose

Defines how a site reads the owner's library and knowledge search, and the limits that keep that
data inside the owner's own session.

## ADDED Requirements

### Requirement: A site reads the library only as its owner

`GET /v1/sites/{site}/library` with `library.read` SHALL return the same item shape, bounds and read
state as `GET /v1/library/search` returns for the same user and the same parameters. The
`site_owner` session's user SHALL be the only tenant authority. A tenant selector in the request
SHALL fail as an invalid request before Knowledge is queried.

#### Scenario: The same query through both routes

- **WHEN** the owner runs `q=durable&limit=5&offset=0` through `/v1/library/search` with the primary session and through `/v1/sites/{site}/library` with the site session
- **THEN** both responses hold the same items in the same order with the same read state
- **Test:** `ratatoskr-platform` `crates/public-api/tests/site_library.rs::site_library_equals_primary_library`

#### Scenario: A tenant selector

- **WHEN** a site session adds a `tenant` parameter to `/v1/sites/{site}/library`
- **THEN** Platform returns the invalid-request error and Knowledge receives no query
- **Test:** `ratatoskr-platform` `crates/public-api/tests/site_library.rs::tenant_selector_is_invalid_before_knowledge`

### Requirement: Knowledge search from a site is the owner's search

`GET /v1/sites/{site}/knowledge/search` with `knowledge.search` SHALL search only content that the
session's user owns, with the bounds of the library search: a query of at most 512 Unicode scalar
values and a `limit` from 1 through 100. It SHALL NOT be reachable by an anonymous caller, whatever
the manifest declares.

#### Scenario: Another user's content

- **WHEN** another user owns a document that matches the query better than any of the owner's documents
- **THEN** the site's result holds only the owner's documents, and its page facts are the same as in a database without the other user's document
- **Test:** `ratatoskr-workspace` `integration/run-site-owner-editing.sh` step `knowledge_search_holds_only_owner_documents`

#### Scenario: Knowledge is unavailable

- **WHEN** Knowledge does not answer within its budget
- **THEN** Platform returns the stable retryable unavailable error and no partial result
- **Test:** `ratatoskr-platform` `crates/public-api/tests/site_library.rs::knowledge_timeout_is_retryable_unavailable`
