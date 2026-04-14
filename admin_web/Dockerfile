FROM node:20-alpine AS build
WORKDIR /app

ARG VITE_API_BASE_URL=http://127.0.0.1:8000
ARG VITE_ADMIN_TOKEN=
ENV VITE_API_BASE_URL=$VITE_API_BASE_URL
ENV VITE_ADMIN_TOKEN=$VITE_ADMIN_TOKEN

COPY package.json package-lock.json ./
RUN npm install
COPY tsconfig.json tsconfig.node.json vite.config.ts index.html ./
COPY src ./src
RUN npm run build

FROM nginx:1.27-alpine
COPY --from=build /app/dist /usr/share/nginx/html
EXPOSE 80
CMD ["nginx", "-g", "daemon off;"]
