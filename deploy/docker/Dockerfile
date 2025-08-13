FROM denoland/deno:1.37.0

WORKDIR /app

# Copy dependency files
COPY deno.json .
COPY frontend/package.json frontend/

# Install frontend dependencies
RUN cd frontend && npm install

# Copy source code
COPY . .

# Build frontend
RUN cd frontend && npm run build

EXPOSE 3000

CMD ["deno", "run", "--allow-net", "--allow-read", "--allow-write", "--allow-env", "backend/server.js"]
