# ---- Build stage ----
FROM oven/bun:1 AS build

ARG CAPROVER_GIT_COMMIT_SHA=${CAPROVER_GIT_COMMIT_SHA}
ARG CLAUDE_CODE_OAUTH_TOKEN=${CLAUDE_CODE_OAUTH_TOKEN}
ARG MERIDIAN_API_KEY=${MERIDIAN_API_KEY}

WORKDIR /app
COPY package.json bun.lock* ./
RUN bun install --frozen-lockfile

COPY tsconfig.json* ./
COPY bin/ ./bin/
COPY src/ ./src/
RUN rm -rf dist && bun build bin/cli.ts src/proxy/server.ts --outdir dist --target node --splitting --external @anthropic-ai/claude-agent-sdk --external libsql --entry-naming '[name].js'

# ---- Runtime stage ----
FROM node:22-alpine

# Per CapRover docs pattern: ARG + ENV to surface build-args as runtime env vars.
# This bakes values into the image layers — acceptable for private registries.
ARG CAPROVER_GIT_COMMIT_SHA=${CAPROVER_GIT_COMMIT_SHA}
ARG CLAUDE_CODE_OAUTH_TOKEN=${CLAUDE_CODE_OAUTH_TOKEN}
ARG MERIDIAN_API_KEY=${MERIDIAN_API_KEY}

ENV GIT_COMMIT_SHA=${CAPROVER_GIT_COMMIT_SHA} \
    CLAUDE_CODE_OAUTH_TOKEN=${CLAUDE_CODE_OAUTH_TOKEN} \
    MERIDIAN_API_KEY=${MERIDIAN_API_KEY}

RUN deluser --remove-home node 2>/dev/null; \
    adduser -D -u 1000 claude \
    && mkdir -p /home/claude/.claude /app/bin/shims \
    && chown -R claude:claude /home/claude /app

WORKDIR /app

COPY --from=build --chown=claude:claude /app/node_modules ./node_modules
COPY --from=build --chown=claude:claude /app/dist ./dist
COPY --from=build --chown=claude:claude /app/package.json ./

RUN printf '#!/bin/sh\nexec node /app/node_modules/@anthropic-ai/claude-agent-sdk/cli.js "$@"\n' > /app/bin/shims/claude \
    && chmod +x /app/bin/shims/claude
ENV PATH="/app/bin/shims:$PATH"

RUN echo "=== claude CLI smoke test ===" \
    && (claude --version || true) \
    && echo "--- auth status ---" \
    && (claude auth status || true) \
    && echo "=== end smoke test ==="

COPY --chown=claude:claude bin/docker-entrypoint.sh bin/claude-proxy-supervisor.sh ./bin/
RUN apk add --no-cache su-exec dos2unix \
    && dos2unix ./bin/docker-entrypoint.sh ./bin/claude-proxy-supervisor.sh \
    && chmod +x ./bin/docker-entrypoint.sh ./bin/claude-proxy-supervisor.sh

EXPOSE 3456

HEALTHCHECK --interval=30s --timeout=5s --retries=3 \
    CMD node -e "fetch('http://127.0.0.1:3456/health').then(r=>process.exit(r.ok?0:1)).catch(()=>process.exit(1))"

ENV CLAUDE_PROXY_PASSTHROUGH=1 \
    CLAUDE_PROXY_HOST=0.0.0.0 \
    IS_SANDBOX=1
ENTRYPOINT ["./bin/docker-entrypoint.sh"]
CMD ["./bin/claude-proxy-supervisor.sh"]
