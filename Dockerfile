FROM node:20.12.1-buster-slim AS builder

WORKDIR /app

COPY package.json ./

RUN npm install

COPY . ./

RUN chown node /app

USER node

EXPOSE $PORT

CMD [ "node", "index.js" ]
