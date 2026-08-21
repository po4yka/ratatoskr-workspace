# Stored bytes across repositories

## Purpose

Defines how services exchange durable artifact references while preserving byte integrity and
service ownership without introducing a shared blob service.

## Requirements

### Requirement: A blob is named by a reference, not served by a service

A service that stores bytes outside its database SHALL make them reachable to another service by
publishing a `BlobRef`, carrying the owning service, a content digest with its algorithm, the media
type and the byte length. No repository SHALL provide a blob storage service, and no contract SHALL
require one.

#### Scenario: one service hands a stored artifact to another

- **WHEN** an extracting service stores a fetched page and publishes an event referencing it
- **THEN** the event carries a `BlobRef` and not the bytes, and a consumer resolves the reference
  without calling an API belonging to a blob service

#### Scenario: the digest identifies the bytes

- **WHEN** a consumer resolves a `BlobRef` and hashes what it read
- **THEN** the digest matches the one in the reference, or the consumer treats the artifact as
  missing rather than as changed

### Requirement: The owning service owns the bytes

Each service SHALL write its own blobs, under a content-addressed path of its own on the deployment
target's durable device, and SHALL NOT write into another service's. The control plane SHALL own no
blobs at all.

#### Scenario: the control plane stores no extracted content

- **WHEN** a change proposes storing a document, a summary or an embedding in the control plane
- **THEN** the change is refused, because the control plane does not own extracted content

#### Scenario: a blob outlives the event that announced it

- **WHEN** the event announcing a blob has aged out of the bus
- **THEN** the blob is still readable by its reference, because its lifetime belongs to the owning
  service and not to the message
