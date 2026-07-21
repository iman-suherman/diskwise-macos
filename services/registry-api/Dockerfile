# DiskWise registry API — Express + Firestore/GCS for Cloud Run.
FROM node:20-alpine AS deps
WORKDIR /app
COPY package.json package-lock.json* ./
RUN npm ci --omit=dev 2>/dev/null || npm install --omit=dev

FROM node:20-alpine AS runner
WORKDIR /app
ENV NODE_ENV=production
ENV PORT=8080
RUN addgroup --system --gid 1001 nodejs \
  && adduser --system --uid 1001 registry
COPY --from=deps /app/node_modules ./node_modules
COPY package.json ./
COPY src ./src
USER registry
EXPOSE 8080
CMD ["node", "src/server.js"]
