#!/bin/bash

# Chemical Drawing App - Project Setup Script
# Creates the complete file structure with empty files and basic configurations

set -e

PROJECT_NAME="chemical-drawing-app"
echo "🧪 Setting up Chemical Drawing App project structure..."

# Create main project directory
mkdir -p "$PROJECT_NAME"
cd "$PROJECT_NAME"

# Create directory structure
echo "📁 Creating directory structure..."

# Root directories
mkdir -p frontend/src/lib/components
mkdir -p frontend/src/lib/stores
mkdir -p frontend/src/lib/utils
mkdir -p frontend/src/lib/drawing
mkdir -p frontend/src/routes/api/molecules
mkdir -p frontend/src/routes/api/export
mkdir -p frontend/static
mkdir -p backend/routes
mkdir -p backend/services
mkdir -p backend/utils
mkdir -p deploy/docker
mkdir -p deploy/aws
mkdir -p docs

# Create root configuration files
echo "⚙️ Creating configuration files..."

# deno.json
cat > deno.json << 'EOF'
{
  "compilerOptions": {
    "allowJs": true,
    "lib": ["deno.window"],
    "strict": true
  },
  "imports": {
    "express": "npm:express@4.18.2",
    "redis": "npm:redis@4.6.7",
    "aws-sdk": "npm:aws-sdk@2.1400.0",
    "cors": "npm:cors@2.8.5",
    "helmet": "npm:helmet@7.0.0",
    "dotenv": "npm:dotenv@16.0.3"
  },
  "tasks": {
    "dev:frontend": "cd frontend && npm run dev",
    "dev:backend": "deno run --allow-net --allow-read --allow-write --allow-env backend/server.js",
    "build": "cd frontend && npm run build",
    "test": "deno test --allow-all",
    "deploy": "./deploy/deploy.sh"
  },
  "permissions": {
    "allow-net": true,
    "allow-read": true,
    "allow-write": true,
    "allow-env": true
  }
}
EOF

# package.json for frontend
cat > frontend/package.json << 'EOF'
{
  "name": "chemical-drawing-frontend",
  "version": "1.0.0",
  "private": true,
  "scripts": {
    "dev": "vite dev",
    "build": "vite build",
    "preview": "vite preview",
    "check": "svelte-kit sync && svelte-check --tsconfig ./tsconfig.json",
    "check:watch": "svelte-kit sync && svelte-check --tsconfig ./tsconfig.json --watch"
  },
  "devDependencies": {
    "@sveltejs/adapter-auto": "^2.0.0",
    "@sveltejs/kit": "^1.20.4",
    "autoprefixer": "^10.4.14",
    "postcss": "^8.4.24",
    "svelte": "^4.0.5",
    "svelte-check": "^3.4.3",
    "tailwindcss": "^3.3.0",
    "tslib": "^2.4.1",
    "typescript": "^5.0.0",
    "vite": "^4.4.2"
  },
  "type": "module"
}
EOF

# Tailwind config
cat > tailwind.config.js << 'EOF'
/** @type {import('tailwindcss').Config} */
export default {
  content: ['./frontend/src/**/*.{html,js,svelte,ts}'],
  theme: {
    extend: {
      colors: {
        // Chemical element colors
        carbon: '#000000',
        oxygen: '#ff0d0d',
        nitrogen: '#3050f8',
        sulfur: '#ffff30',
        phosphorus: '#ff8000',
        fluorine: '#90e050',
        chlorine: '#1ff01f',
        bromine: '#a62929',
        iodine: '#940094',
      },
    },
  },
  plugins: [],
}
EOF

# Vite config
cat > frontend/vite.config.js << 'EOF'
import { sveltekit } from '@sveltejs/kit/vite';
import { defineConfig } from 'vite';

export default defineConfig({
  plugins: [sveltekit()],
  server: {
    proxy: {
      '/api': {
        target: 'http://localhost:3000',
        changeOrigin: true
      }
    }
  }
});
EOF

# PostCSS config
cat > frontend/postcss.config.js << 'EOF'
export default {
  plugins: {
    tailwindcss: {},
    autoprefixer: {},
  },
}
EOF

# SvelteKit config
cat > frontend/svelte.config.js << 'EOF'
import adapter from '@sveltejs/adapter-auto';

/** @type {import('@sveltejs/kit').Config} */
const config = {
  kit: {
    adapter: adapter()
  }
};

export default config;
EOF

# TypeScript config for frontend
cat > frontend/tsconfig.json << 'EOF'
{
  "extends": "./.svelte-kit/tsconfig.json",
  "compilerOptions": {
    "allowJs": true,
    "checkJs": true,
    "esModuleInterop": true,
    "forceConsistentCasingInFileNames": true,
    "resolveJsonModule": true,
    "skipLibCheck": true,
    "sourceMap": true,
    "strict": true
  }
}
EOF

# Environment files
cat > .env.example << 'EOF'
# Server Configuration
NODE_ENV=development
PORT=3000
FRONTEND_URL=http://localhost:5173

# Redis Configuration
REDIS_HOST=localhost
REDIS_PORT=6379
REDIS_PASSWORD=

# AWS Configuration
AWS_ACCESS_KEY_ID=your_access_key
AWS_SECRET_ACCESS_KEY=your_secret_key
AWS_REGION=us-east-1
AWS_S3_BUCKET=chemical-drawing-files

# Session Configuration
SESSION_SECRET=your_session_secret_here
EOF

touch .env

# .gitignore
cat > .gitignore << 'EOF'
# Dependencies
node_modules/
.npm

# Environment variables
.env
.env.local
.env.production

# Build outputs
frontend/build/
frontend/.svelte-kit/
dist/
*.log

# OS generated files
.DS_Store
.DS_Store?
._*
.Spotlight-V100
.Trashes
ehthumbs.db
Thumbs.db

# IDE files
.vscode/
.idea/
*.swp
*.swo

# Deno
.deno/

# AWS
.aws/

# Temporary files
tmp/
temp/
EOF

# Create empty frontend files
echo "📄 Creating frontend files..."

# Main layout
touch frontend/src/app.html
touch frontend/src/routes/+layout.svelte
touch frontend/src/routes/+page.svelte

# Components
touch frontend/src/lib/components/Toolbar.svelte
touch frontend/src/lib/components/Canvas.svelte
touch frontend/src/lib/components/PropertyPanel.svelte
touch frontend/src/lib/components/Grid.svelte
touch frontend/src/lib/components/MenuBar.svelte

# Stores
touch frontend/src/lib/stores/drawing.js
touch frontend/src/lib/stores/tools.js
touch frontend/src/lib/stores/ui.js

# Utils
touch frontend/src/lib/utils/chemistry.js
touch frontend/src/lib/utils/geometry.js
touch frontend/src/lib/utils/serialization.js
touch frontend/src/lib/utils/validation.js

# Drawing engine
touch frontend/src/lib/drawing/DrawingEngine.js
touch frontend/src/lib/drawing/BondRenderer.js
touch frontend/src/lib/drawing/AtomRenderer.js
touch frontend/src/lib/drawing/GridSystem.js

# API routes
touch frontend/src/routes/api/molecules/+server.js
touch frontend/src/routes/api/export/+server.js

# CSS
cat > frontend/src/app.css << 'EOF'
@tailwind base;
@tailwind components;
@tailwind utilities;

@layer base {
  html {
    font-family: system-ui, sans-serif;
  }
  
  body {
    @apply bg-gray-50;
  }
}

@layer components {
  .toolbar-button {
    @apply px-3 py-2 rounded-lg border border-gray-300 bg-white hover:bg-gray-50 active:bg-gray-100 transition-colors;
  }
  
  .toolbar-button.active {
    @apply bg-blue-500 text-white border-blue-500;
  }
  
  .canvas-container {
    @apply relative overflow-hidden bg-white border border-gray-300 rounded-lg;
  }
}
EOF

# Create empty backend files
echo "🖥️ Creating backend files..."

# Main server
touch backend/server.js

# Routes
touch backend/routes/molecules.js
touch backend/routes/reactions.js
touch backend/routes/export.js

# Services
touch backend/services/redis.js
touch backend/services/aws.js
touch backend/services/chemistry.js

# Utils
touch backend/utils/validation.js
touch backend/utils/helpers.js

# Create deployment files
echo "🚀 Creating deployment files..."

# Docker files
cat > deploy/docker/Dockerfile << 'EOF'
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
EOF

touch deploy/docker/docker-compose.yml
touch deploy/aws/cloudformation.yml
touch deploy/deploy.sh

# Create documentation files
echo "📚 Creating documentation files..."

touch docs/API.md
touch docs/DEVELOPMENT.md
touch docs/DEPLOYMENT.md

# Create README
cat > README.md << 'EOF'
# Chemical Bond Line Structure Drawing App

A web-based chemical drawing application for creating bond line structures and reaction pathways, similar to MolView but open-source and free.

## Features

- ✨ Intuitive drawing interface with hexagonal grid
- 🧪 Support for all common chemical bonds and functional groups
- 🎨 Color-coded atoms and functional groups
- 📁 Save/load drawings with cloud storage
- 📤 Export to PNG, SVG, MOL, and SMILES formats
- ⚡ Real-time validation and molecular formula calculation
- 📱 Responsive design for desktop and tablet

## Tech Stack

- Frontend: Svelte + SvelteKit + Tailwind CSS
- Backend: Express.js with Deno runtime
- Database: Redis for caching and sessions
- Cloud: AWS (S3, EC2/Lambda)
- Drawing: HTML5 Canvas with custom engine

## Quick Start

### Prerequisites
- Deno 1.30+
- Node.js 18+ (for frontend build tools)
- Redis server
- AWS account (for cloud features)

### Installation

1. Clone the repository
```bash
git clone <repo-url>
cd chemical-drawing-app
```

2. Install frontend dependencies
```bash
cd frontend
npm install
cd ..
```

3. Set up environment variables
```bash
cp .env.example .env
# Edit .env with your configuration
```

4. Start Redis server
```bash
redis-server
```

5. Run development servers
```bash
# Backend (terminal 1)
deno task dev:backend

# Frontend (terminal 2)
deno task dev:frontend
```

6. Open http://localhost:5173

## Development

See [DEVELOPMENT.md](docs/DEVELOPMENT.md) for detailed development instructions.

## API Documentation

See [API.md](docs/API.md) for API documentation.

## Deployment

See [DEPLOYMENT.md](docs/DEPLOYMENT.md) for deployment instructions.

## License

MIT License - see LICENSE file for details.
EOF

# Create LICENSE
cat > LICENSE << 'EOF'
MIT License

Copyright (c) 2024 Chemical Drawing App

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
EOF

# Make scripts executable
chmod +x deploy/deploy.sh

echo "✅ Project structure created successfully!"
echo ""
echo "📁 Created $PROJECT_NAME/ with the following structure:"
echo "   ├── frontend/          # Svelte frontend application"
echo "   ├── backend/           # Express.js API server"
echo "   ├── deploy/            # Deployment configurations"
echo "   ├── docs/              # Documentation"
echo "   ├── deno.json          # Deno configuration"
echo "   ├── tailwind.config.js # Tailwind CSS config"
echo "   ├── .env.example       # Environment variables template"
echo "   └── README.md          # Project documentation"
echo ""
echo "🚀 Next steps:"
echo "   1. cd $PROJECT_NAME"
echo "   2. cp .env.example .env"
echo "   3. Edit .env with your configuration"
echo "   4. cd frontend && npm install"
echo "   5. deno task dev:backend (in one terminal)"
echo "   6. deno task dev:frontend (in another terminal)"
echo ""
echo "Happy coding! 🧪✨"
