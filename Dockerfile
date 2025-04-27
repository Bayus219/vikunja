# syntax=docker/dockerfile:1@sha256:4c68376a702446fc3c79af22de146a148bc3367e73c25a5803d453b6b3f722fb

# Stage 1: Frontend build (unchanged)
FROM --platform=$BUILDPLATFORM node:22.15.0-alpine@sha256:ad1aedbcc1b0575074a91ac146d6956476c1f9985994810e4ee02efd932a68fd AS frontendbuilder

WORKDIR /build
ENV PNPM_CACHE_FOLDER=.cache/pnpm/
ENV PUPPETEER_SKIP_DOWNLOAD=true
ENV CYPRESS_INSTALL_BINARY=0

COPY frontend/ ./
RUN npm install -g corepack && corepack enable && \
      pnpm install && \
      pnpm run build

# Stage 2: API build (modified)
FROM --platform=$BUILDPLATFORM ghcr.io/techknowlogick/xgo:go-1.23.x@sha256:46a34792b019ee60cb16d0f2ec464dbd69fde843e485203c4f65258bde4fe7e2 AS apibuilder

# Install Mage and Git (required for cloning)
RUN go install github.com/magefile/mage@latest && \
    mv /go/bin/mage /usr/local/go/bin && \
    apt-get update && apt-get install -y git

WORKDIR /go/src/code.vikunja.io/api

# Clone Vikunja with full Git history instead of copying
RUN git clone https://github.com/go-vikunja/api.git . && \
    git submodule update --init --recursive

# Copy frontend assets
COPY --from=frontendbuilder /build/dist ./frontend/dist

# Version handling (fallback if Git isn't available)
ARG TARGETOS TARGETARCH TARGETVARIANT RELEASE_VERSION
ENV RELEASE_VERSION=${RELEASE_VERSION:-$(git describe --tags --always || echo "v0.0.0-dev")}

ENV GOPROXY=https://goproxy.kolaente.de
RUN export PATH=$PATH:$GOPATH/bin && \
    mage build:clean && \
    mage release:xgo "${TARGETOS}/${TARGETARCH}/${TARGETVARIANT}"

# Stage 3: Final image (unchanged)
FROM scratch
LABEL org.opencontainers.image.authors='maintainers@vikunja.io'
LABEL org.opencontainers.image.url='https://vikunja.io'
LABEL org.opencontainers.image.documentation='https://vikunja.io/docs'
LABEL org.opencontainers.image.source='https://code.vikunja.io/vikunja'
LABEL org.opencontainers.image.licenses='AGPLv3'
LABEL org.opencontainers.image.title='Vikunja'

WORKDIR /app/vikunja
ENTRYPOINT [ "/app/vikunja/vikunja" ]
EXPOSE 3456
USER 1000

ENV VIKUNJA_SERVICE_ROOTPATH=/app/vikunja/
ENV VIKUNJA_DATABASE_PATH=/db/vikunja.db

COPY --from=apibuilder /build/vikunja-* vikunja
COPY --from=apibuilder /etc/ssl/certs/ca-certificates.crt /etc/ssl/certs/
