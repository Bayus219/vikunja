# syntax=docker/dockerfile:1

# Stage 1: Frontend build (MUST complete successfully)
FROM --platform=$BUILDPLATFORM node:22.15.0-alpine AS frontendbuilder
WORKDIR /build
ENV PNPM_CACHE_FOLDER=.cache/pnpm/
ENV PUPPETEER_SKIP_DOWNLOAD=true
ENV CYPRESS_INSTALL_BINARY=0

# Copy ONLY frontend files for clean build
COPY frontend/package.json frontend/pnpm-lock.yaml ./ 
RUN npm install -g corepack && corepack enable && \
    pnpm install && \
    pnpm run build

# Stage 2: API build
FROM --platform=$BUILDPLATFORM golang:1.23 AS apibuilder

# Install build tools
RUN go install github.com/magefile/mage@latest

WORKDIR /src
# Clone Vikunja properly (with Git history)
RUN git clone https://github.com/go-vikunja/api.git . && \
    git submodule update --init --recursive

# Copy frontend assets from frontend builder
COPY --from=frontendbuilder /build/dist ./frontend/dist

# Version fallback
ARG RELEASE_VERSION
ENV RELEASE_VERSION=${RELEASE_VERSION:-$(git describe --tags --always || echo "v0.0.0-dev")}

# Build
RUN mage build:clean && \
    mage release

# Stage 3: Final image
FROM alpine:latest
WORKDIR /app/vikunja
COPY --from=apibuilder /src/vikunja .
COPY --from=apibuilder /etc/ssl/certs/ca-certificates.crt /etc/ssl/certs/

EXPOSE 3456
USER 1000:1000
ENTRYPOINT ["/app/vikunja/vikunja"]
