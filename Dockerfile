# Dearth Hub image (SPEC §14.6): the Dart Hub + the Flutter web app it serves.
#
#   tool/build_all.sh --hub-image        # builds dist/web, then this image
#   docker build -t dearth-hub .         # uses whatever is in dist/web (may be empty → API only)
ARG DART_VERSION=3.13.5
# Docker's official images, pulled from AWS's public copy: CI runners share
# addresses, and Docker Hub's anonymous pull limit failed builds (429).
ARG REGISTRY=public.ecr.aws/docker/library

# ── 1. Hub build (pure Dart workspace subset; no Flutter SDK needed) ─────────
FROM ${REGISTRY}/dart:${DART_VERSION} AS hub-build
RUN apt-get update && apt-get install -y --no-install-recommends build-essential && rm -rf /var/lib/apt/lists/*
WORKDIR /src
COPY analysis_options.yaml ./
COPY packages/dearth_core packages/dearth_core
COPY packages/dearth_integrations packages/dearth_integrations
COPY hub/dearth_hub hub/dearth_hub
# The workspace subset the Hub needs (CI's Hub jobs use the same file).
COPY hub/pubspec.workspace.yaml pubspec.yaml
RUN dart pub get \
 && cd hub/dearth_hub && dart build cli -o /out

# ── 2. Runtime ────────────────────────────────────────────────────────────────
FROM ${REGISTRY}/debian:trixie-slim
ARG VERSION=dev
LABEL org.opencontainers.image.title="Dearth Hub" \
      org.opencontainers.image.description="Family command center hub: sync, integrations, photos, web app" \
      org.opencontainers.image.source="https://github.com/robertzas/dearth" \
      org.opencontainers.image.licenses="AGPL-3.0-only" \
      org.opencontainers.image.version="${VERSION}"
RUN apt-get update \
 && apt-get install -y --no-install-recommends ca-certificates tzdata libvips-tools \
 && rm -rf /var/lib/apt/lists/* \
 && useradd --system --uid 10001 --home-dir /data --shell /usr/sbin/nologin dearth \
 && mkdir -p /data && chown dearth:dearth /data
COPY --from=hub-build /out/bundle /app
# dist/ always exists (dist/.keep); dist/web, the Flutter web build, lands in
# /app/web when present (.dockerignore keeps the rest of dist/ out). Without
# it the Hub serves the API only.
COPY dist/ /app/
# The release version (CI passes a semantic version): the Hub reports it
# and compares it with GitHub's latest release (SPEC §15.3).
ENV DEARTH_VERSION=${VERSION} \
    DEARTH_DATA_DIR=/data \
    DEARTH_WEB_DIR=/app/web \
    DEARTH_PORT=8080
USER dearth
EXPOSE 8080
VOLUME ["/data"]
HEALTHCHECK --interval=30s --timeout=5s --start-period=20s --retries=3 CMD ["/app/bin/dearth_hub", "healthcheck"]
ENTRYPOINT ["/app/bin/dearth_hub"]
CMD ["serve"]
