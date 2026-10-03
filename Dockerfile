# Dearth Hub image (SPEC §14.6): the Dart Hub + the Flutter web app it serves.
#
#   tool/build_all.sh --hub-image        # builds dist/web, then this image
#   docker build -t dearth-hub .         # uses whatever is in dist/web (may be empty → API only)
ARG DART_VERSION=3.13.2

# ── 1. Hub build (pure Dart workspace subset; no Flutter SDK needed) ─────────
FROM dart:${DART_VERSION} AS hub-build
RUN apt-get update && apt-get install -y --no-install-recommends build-essential && rm -rf /var/lib/apt/lists/*
WORKDIR /src
COPY analysis_options.yaml ./
COPY packages/dearth_core packages/dearth_core
COPY packages/dearth_integrations packages/dearth_integrations
COPY hub/dearth_hub hub/dearth_hub
RUN printf 'name: dearth_hub_build\npublish_to: none\nenvironment:\n  sdk: ^3.13.0\nworkspace:\n  - packages/dearth_core\n  - packages/dearth_integrations\n  - hub/dearth_hub\n' > pubspec.yaml \
 && dart pub get \
 && cd hub/dearth_hub && dart build cli -o /out

# ── 2. Runtime ────────────────────────────────────────────────────────────────
FROM debian:bookworm-slim
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
 && mkdir -p /data /app/web && chown dearth:dearth /data
COPY --from=hub-build /out/bundle /app
# dist/ always exists (dist/.keep); dist/web is the Flutter web build when present.
COPY dist/ /tmp/dist/
RUN if [ -f /tmp/dist/web/index.html ]; then cp -r /tmp/dist/web/. /app/web/; fi && rm -rf /tmp/dist
ENV DEARTH_DATA_DIR=/data \
    DEARTH_WEB_DIR=/app/web \
    DEARTH_PORT=8080
USER dearth
EXPOSE 8080
VOLUME ["/data"]
HEALTHCHECK --interval=30s --timeout=5s --start-period=20s --retries=3 CMD ["/app/bin/dearth_hub", "healthcheck"]
ENTRYPOINT ["/app/bin/dearth_hub"]
CMD ["serve"]
