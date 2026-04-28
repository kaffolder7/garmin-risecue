FROM node:22-alpine

WORKDIR /app

ENV NODE_ENV=production
ENV HOST=0.0.0.0
ENV PORT=8787

COPY package.json package-lock.json ./
RUN npm ci --omit=dev

COPY endpoint ./endpoint

EXPOSE 8787
CMD ["node", "endpoint/server.mjs"]

