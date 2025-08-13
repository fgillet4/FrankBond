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
