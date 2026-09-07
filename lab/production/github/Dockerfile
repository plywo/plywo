FROM node:24-bookworm-slim

WORKDIR /app

COPY lab/production/github/package.json ./package.json
RUN npm install --omit=dev

COPY lab/production/github/emulator.mjs ./emulator.mjs
COPY lab/production/github/edge.mjs ./edge.mjs

CMD ["node", "emulator.mjs"]
