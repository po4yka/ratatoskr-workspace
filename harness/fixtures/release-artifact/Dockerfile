# The self-test fixture of `.github/workflows/reusable-release-artifact.yml`.
#
# It has the same `export` stage contract as a service repository's Dockerfile, and exports one real
# aarch64 binary linked against Debian 12's glibc, so the workflow's build, check and SBOM steps run
# end to end in seconds. `ci.yml` calls the workflow with `publish: false`, so nothing is pushed.
FROM debian:12-slim@sha256:7c7b2c966bc9ee8cedfeef67e0e279108992c77681fa595db4a9d65c06ccc587 AS builder
RUN cp /bin/true /fixture-ok

FROM scratch AS export
COPY --from=builder /fixture-ok /
