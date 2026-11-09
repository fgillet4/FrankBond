import Fastify from 'fastify';
import cors from '@fastify/cors';
import pg from 'pg';
import jwt from 'jsonwebtoken';

const { Pool } = pg;

function requiredEnv(name) {
    const value = process.env[name];
    if (!value) throw new Error(`${name} env var is required`);
    return value;
}

const JWT_SECRET = requiredEnv('JWT_SECRET');
const PORT = parseInt(process.env.PORT || '3010');

const pool = new Pool({
  host: 'localhost',
  port: 5433,
  database: 'frankbond',
  user: 'postgres',
  password: 'postgres',
});

const fastify = Fastify({ logger: true });

await fastify.register(cors, {
  origin: [
    'https://frankbond.frankstation.org',
    'http://localhost:5178',
    'http://localhost:5180',
  ],
  credentials: true,
  methods: ['GET', 'POST', 'PUT', 'DELETE', 'OPTIONS'],
});

// Auth middleware
function verifyToken(request, reply) {
  const auth = request.headers.authorization;
  if (!auth || !auth.startsWith('Bearer ')) {
    reply.status(401).send({ error: 'Missing token' });
    return null;
  }
  try {
    const payload = jwt.verify(auth.slice(7), JWT_SECRET);
    return payload;
  } catch {
    reply.status(401).send({ error: 'Invalid token' });
    return null;
  }
}

fastify.get('/api/health', async () => ({ ok: true }));

// List all structures for the authenticated user
fastify.get('/api/structures', async (request, reply) => {
  const user = verifyToken(request, reply);
  if (!user) return;

  const result = await pool.query(
    'SELECT id, name, thumbnail, created_at, updated_at FROM structures WHERE user_id = $1 ORDER BY updated_at DESC',
    [user.userId]
  );
  return result.rows;
});

// Get a single structure (with full data)
fastify.get('/api/structures/:id', async (request, reply) => {
  const user = verifyToken(request, reply);
  if (!user) return;

  const result = await pool.query(
    'SELECT * FROM structures WHERE id = $1 AND user_id = $2',
    [request.params.id, user.userId]
  );
  if (result.rows.length === 0) {
    reply.status(404).send({ error: 'Not found' });
    return;
  }
  return result.rows[0];
});

// Save a new structure
fastify.post('/api/structures', async (request, reply) => {
  const user = verifyToken(request, reply);
  if (!user) return;

  const { name, data, thumbnail } = request.body;
  if (!data) {
    reply.status(400).send({ error: 'data is required' });
    return;
  }

  const result = await pool.query(
    `INSERT INTO structures (user_id, name, data, thumbnail)
     VALUES ($1, $2, $3, $4)
     RETURNING *`,
    [user.userId, name || 'Untitled', JSON.stringify(data), thumbnail || null]
  );
  reply.status(201).send(result.rows[0]);
});

// Update a structure
fastify.put('/api/structures/:id', async (request, reply) => {
  const user = verifyToken(request, reply);
  if (!user) return;

  const { name, data, thumbnail } = request.body;

  const result = await pool.query(
    `UPDATE structures
     SET name = COALESCE($1, name),
         data = COALESCE($2, data),
         thumbnail = COALESCE($3, thumbnail),
         updated_at = NOW()
     WHERE id = $4 AND user_id = $5
     RETURNING *`,
    [name, data ? JSON.stringify(data) : null, thumbnail || null, request.params.id, user.userId]
  );
  if (result.rows.length === 0) {
    reply.status(404).send({ error: 'Not found' });
    return;
  }
  return result.rows[0];
});

// Delete a structure
fastify.delete('/api/structures/:id', async (request, reply) => {
  const user = verifyToken(request, reply);
  if (!user) return;

  const result = await pool.query(
    'DELETE FROM structures WHERE id = $1 AND user_id = $2 RETURNING id',
    [request.params.id, user.userId]
  );
  if (result.rows.length === 0) {
    reply.status(404).send({ error: 'Not found' });
    return;
  }
  return { deleted: true };
});

await fastify.listen({ port: PORT, host: '127.0.0.1' });
console.log(`FrankBond API running on port ${PORT}`);
