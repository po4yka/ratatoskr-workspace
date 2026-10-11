## MODIFIED Requirements

### Requirement: Provider permalink hosts agree across the extension, Platform and the services

Platform's capture routing SHALL accept the four Threads hosts `threads.net`, `www.threads.net`, `threads.com` and `www.threads.com`, and the browser extension SHALL route the four Threads hosts and all six X hosts (`x.com`, `www.x.com`, `mobile.x.com`, `twitter.com`, `www.twitter.com`, `mobile.twitter.com`) to their provider lanes. The path grammar is one table that the extension, the services and, for hosts, Platform follow: X `^/[A-Za-z0-9_]{1,15}/status/[0-9]{1,19}/?$` on the six X hosts; Instagram `^/(?:[^/]+/)?(?:p|reel|reels|tv)/[A-Za-z0-9_-]{1,64}/?$` on `instagram.com` and `www.instagram.com`; Threads `^/@[A-Za-z0-9._]{1,30}/post/[A-Za-z0-9_-]{1,128}/?$` on the four Threads hosts. The extension's routes SHALL use exactly these expressions and accept the boundary lengths (19 digits, a 30 character handle) and refuse the first length beyond (20 digits, 31 characters, a 129 character code), so that it never promises a lane for an input the lane refuses. The X service is looser than the X expression (any handle, `statuses` as well as `status`), and the extension is the stricter side on purpose; the Instagram service accepts more hosts and any username segment. Platform's host check is unchanged, and the Threads service keeps canonicalizing to `www.threads.net`.

#### Scenario: A Threads permalink on the current domain

- **WHEN** a user submits a `threads.com` permalink
- **THEN** Platform dispatches it to the Threads lane instead of the generic extractor, verified by `crates/public-api/tests/capture.rs` in `ratatoskr-platform`

#### Scenario: A twenty-digit status id

- **WHEN** the extension sees an X status whose id has 20 digits
- **THEN** it does not route it to the X lane, and a capture of that URL through Platform without a `social` member is dispatched to the generic extractor, verified by the routing tests of `ratatoskr-browser-extension` and flow F5 of the native smoke when it is run

## ADDED Requirements

### Requirement: X can trust an operator-supplied CA and a terminal capture is terminal

X SHALL read `RATATOSKR__PUBLIC_CAPTURE__EXTRA_CA_FILE`, an optional absolute path to a PEM file whose certificates are added to the trust anchors of the public-capture client in addition to the platform verifier. The key applies to that client only, is validated at load (absolute, readable, at least one certificate), and its absence changes nothing. Instagram and Threads keep their allow-listed Meta endpoints and get no such key. A capture that ended terminally SHALL leave `next_attempt_at` at or before `reported_at`, so a finished capture never reads as a pending retry.

#### Scenario: A fake X API behind a throwaway CA

- **WHEN** X runs with `API_BASE_URL` pointing at an HTTPS fake and `EXTRA_CA_FILE` naming its CA
- **THEN** a capture of a public post succeeds and publishes one `social.source.captured` fact, and without the key the same capture ends `failed` with `social.source.unavailable` once, verified by the public-capture tests of `ratatoskr-x` and flow F5 of the native smoke when it is run

#### Scenario: A finished capture

- **WHEN** a capture ends `unavailable`
- **THEN** its `next_attempt_at` is not in the future, verified by `crates/x-sync/tests/public_capture/outcomes.rs` in `ratatoskr-x`
