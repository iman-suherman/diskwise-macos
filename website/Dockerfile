FROM node:20-slim AS builder
WORKDIR /app

COPY package.json package-lock.json* ./
RUN npm config set fetch-retries 5 \
	&& npm config set fetch-retry-factor 2 \
	&& npm config set fetch-retry-mintimeout 10000 \
	&& npm config set fetch-retry-maxtimeout 120000 \
	&& npm config set prefer-online true \
	&& i=1 \
	&& until [ "$i" -gt 4 ]; do \
		npm ci --no-audit --no-fund && break; \
		echo "npm ci failed (attempt $i/4), retrying in $((i * 5))s..."; \
		sleep $((i * 5)); \
		i=$((i + 1)); \
	done \
	&& [ "$i" -le 4 ]

COPY . .
ENV NEXT_TELEMETRY_DISABLED=1
ENV DOCKER_BUILD=1
ARG NEXT_PUBLIC_REGISTRY_API_URL=https://diskwise-registry.suherman.net
ARG NEXT_PUBLIC_APP_ID=diskwise-macos
ARG NEXT_PUBLIC_DOWNLOAD_BASE_URL=https://diskwise-download.suherman.net/downloads
ENV NEXT_PUBLIC_REGISTRY_API_URL=$NEXT_PUBLIC_REGISTRY_API_URL
ENV NEXT_PUBLIC_APP_ID=$NEXT_PUBLIC_APP_ID
ENV NEXT_PUBLIC_DOWNLOAD_BASE_URL=$NEXT_PUBLIC_DOWNLOAD_BASE_URL
ENV NODE_ENV=production

RUN npm run build

FROM node:20-slim AS runner
WORKDIR /app

ENV NODE_ENV=production
ENV PORT=8080
ENV HOSTNAME=0.0.0.0

COPY --from=builder /app/public ./public
COPY --from=builder /app/.next/standalone ./
COPY --from=builder /app/.next/static ./.next/static

EXPOSE 8080
CMD ["node", "server.js"]
