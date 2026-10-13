## MODIFIED Requirements

### Requirement: Provider permalink hosts agree across the extension, Platform and the services

Platform's capture routing SHALL accept the four Threads hosts `threads.net`, `www.threads.net`, `threads.com` and `www.threads.com`, and the browser extension SHALL route the four Threads hosts and all six X hosts (`x.com`, `www.x.com`, `mobile.x.com`, `twitter.com`, `www.twitter.com`, `mobile.twitter.com`) to their provider lanes. The path grammar is one table that the extension, the services and, for hosts, Platform follow: X `^/[A-Za-z0-9_]{1,15}/status/[0-9]{1,19}/?$` on the six X hosts; Instagram `^/(?:[^/]+/)?(?:p|reel|reels|tv)/[A-Za-z0-9_-]{1,64}/?$` on `instagram.com` and `www.instagram.com`; Threads `^/@[A-Za-z0-9._]{1,30}/post/[A-Za-z0-9_-]{1,128}/?$` on the four Threads hosts. The extension's routes SHALL use exactly these expressions and accept the boundary lengths (19 digits, a 30 character handle) and refuse the first length beyond (20 digits, 31 characters, a 129 character code), so that it never promises a lane for an input the lane refuses. The X service is looser than the X expression (any handle, `statuses` as well as `status`), and the extension is the stricter side on purpose; the Instagram service accepts more hosts and any username segment. Platform's host check is unchanged, and the Threads service keeps canonicalizing to `www.threads.net`. The Threads service SHALL apply the ASCII and percent-escape checks to the authority and the path only: the query and the fragment are discarded, never validated and never part of the canonical form, the 2048 character cap still bounds the whole raw input, and the original input is kept byte for byte. A handle or a path that holds a `%` or a non-ASCII byte is still refused with the same typed errors.

#### Scenario: A Threads permalink on the current domain

- **WHEN** a user submits a `threads.com` permalink
- **THEN** Platform dispatches it to the Threads lane instead of the generic extractor, verified by `crates/public-api/tests/capture.rs` in `ratatoskr-platform`

#### Scenario: A twitter.com permalink in the extension

- **WHEN** the extension sees a `twitter.com` status permalink
- **THEN** it routes it to the X lane

#### Scenario: A twenty-digit status id

- **WHEN** the extension sees an X status whose id has 20 digits
- **THEN** it does not route it to the X lane, and a capture of that URL through Platform without a `social` member is dispatched to the generic extractor, verified by the routing tests of `ratatoskr-browser-extension` and flow F5 of the native smoke when it is run

#### Scenario: A shared Threads link with an escaped tracking parameter

- **WHEN** a user captures `https://www.threads.net/@user/post/abc?xmt=a%3Db`, or a link whose query holds a non-ASCII byte
- **THEN** the Threads lane records a capture for `https://www.threads.net/@user/post/abc` instead of failing the operation at intake, verified by the permalink and capture tests of `ratatoskr-threads` and flow F5 of the native smoke when it is run

#### Scenario: An escape in the path

- **WHEN** a permalink holds `%41` in the handle or a non-ASCII handle
- **THEN** it is refused with the same typed errors as before
