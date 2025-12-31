FROM node:18-alpine

WORKDIR /app

# Use strace for debugging the DNS resolution calls.
# RUN apk add --no-cache strace

COPY package*.json ./
RUN npm install

COPY . .

EXPOSE 3000

# CMD ["strace", "-f", "-e", "trace=network,openat", "node", "index.js"]
CMD ["node", "index.js"]

