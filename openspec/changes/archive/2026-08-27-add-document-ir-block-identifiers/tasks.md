## 1. Contracts implementation

- [x] 1.1 Add a failing stable serialized block-identifier contract test.
- [x] 1.2 Implement typed block IDs and uniqueness validation; merged as `4929b96`.
- [x] 1.3 Add multi-byte Document IR anchor evidence.
- [x] 1.4 Confirm Unicode-scalar anchor validation in the Knowledge consumer.

## 2. Workspace agreement

- [x] 2.1 Validate this cross-repository proposal, design, and specification.

## 3. Knowledge consumer

- [x] 3.1 Add failing anchor validation coverage after the Contracts change.
- [x] 3.2 Implement source-revision-bound highlight persistence; merged as `9608eea`.

## 4. Extractor producer

- [x] 4.1 Add failing emitted-block-ID coverage.
- [x] 4.2 Allocate deterministic distinct IDs; merged as `4ade491`.

## 5. Integration and publication

- [x] 5.1 Verify Contracts serialization, Extractor emission, and Knowledge validation through the component fixtures and gates.
- [x] 5.2 Verify integrated child SHAs, run component compatibility gates, and record rollback as reverting the respective child commits against recreated development schema.
