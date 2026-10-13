## ADDED Requirements

### Requirement: The Telegram progress stream is not cut by the whole-call timeout

The Telegram Platform client SHALL keep its whole-call timeout for every request and response call and SHALL follow `GET /v1/operations/{id}/events` with a second client that has a connect timeout equal to the configured Platform timeout, a read timeout `PLATFORM_STREAM_IDLE_TIMEOUT` of 45 seconds (three of Platform's 15 second keep-alives) and no total timeout. A stream with no byte for 45 seconds SHALL end as a clean close, and resumption with `Last-Event-ID` SHALL be unchanged. The Bot API file download SHALL keep its own whole-call timeout.

#### Scenario: An operation outlives the whole-call timeout

- **WHEN** a PDF capture stays queued for 32 seconds because the extractor is stopped and started again
- **THEN** the dispatcher follows the operation over at most two requests to `/v1/operations/{id}/events`, logs no `follow_frame_failed`, and the completion edit arrives, verified by the dispatcher tests of `ratatoskr-telegram` against a loopback server and by flow F3 of the native smoke when it is run

#### Scenario: A server goes silent

- **WHEN** the stream sends no byte for the idle timeout
- **THEN** it ends as a clean close
