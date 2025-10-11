require('dotenv').config();
const express = require('express');
const multer = require('multer');
const AWS = require('aws-sdk');
const { Pool } = require('pg');
const { v4: uuidv4 } = require('uuid');
const cors = require('cors');

const app = express();
app.use(express.json());
app.use(cors());

const REGION = process.env.REGION;
const S3_BUCKET_PRIMARY = process.env.S3_BUCKET_PRIMARY;
const S3_BUCKET_SECONDARY = process.env.S3_BUCKET_SECONDARY;
const DB_SECRET_NAME = process.env.DB_SECRET_NAME;

AWS.config.update({ region: REGION });
const secretsManager = new AWS.SecretsManager({ region: REGION });
const s3 = new AWS.S3();

// Multer setup
const upload = multer({ storage: multer.memoryStorage() });

let dbCredsCache = null;
let writerPool = null;
let readerPool = null;

// --------------------------
// Fetch Secrets from AWS
// --------------------------
async function fetchSecrets() {
  const secret = await secretsManager.getSecretValue({ SecretId: DB_SECRET_NAME }).promise();
  if (!secret || !secret.SecretString) throw new Error("DB secret not found or empty");
  dbCredsCache = JSON.parse(secret.SecretString);
  console.log("🔑 Secrets fetched successfully");
  return dbCredsCache;
}

// --------------------------
// Initialize DB Connections
// --------------------------
async function initDbConnections() {
  const creds = dbCredsCache || await fetchSecrets();

  writerPool = new Pool({
    host: creds.primary_cluster_writer_endpoint,
    user: creds.username,
    password: creds.password,
    database: creds.dbname,
    port: 5432,
  });

  readerPool = new Pool({
    host: creds.secondary_cluster_endpoint || creds.primary_cluster_writer_endpoint,
    user: creds.username,
    password: creds.password,
    database: creds.dbname,
    port: 5432,
  });

  console.log(`✅ DB connections ready (Writer: ${creds.primary_cluster_writer_endpoint})`);
}

// --------------------------
// Helper DB Query Functions
// --------------------------
async function runWriterQuery(query, params) {
  try {
    return await writerPool.query(query, params);
  } catch (err) {
    console.error("❌ Writer DB error:", err.message);
    console.log("🔄 Refreshing secrets and retrying writer query...");
    await fetchSecrets();
    await initDbConnections();
    return writerPool.query(query, params); // retry once with new creds
  }
}

async function runReaderQuery(query, params) {
  try {
    return await readerPool.query(query, params);
  } catch (err) {
    console.error("⚠️ Reader DB error:", err.message);
    console.log("🔄 Refreshing secrets and retrying reader query...");
    await fetchSecrets();
    await initDbConnections();
    return readerPool.query(query, params); // retry once with new creds
  }
}

// --------------------------
// Initialize App
// --------------------------
async function initApp() {
  try {
    await fetchSecrets();
    await initDbConnections();

    const createTableQuery = `
      CREATE TABLE IF NOT EXISTS media (
        id UUID PRIMARY KEY,
        filename TEXT NOT NULL,
        s3_key TEXT NOT NULL,
        region TEXT,
        created_at TIMESTAMP DEFAULT NOW()
      );
    `;
    await runWriterQuery(createTableQuery);
    console.log('✅ Media table ready.');

    // -------- ROUTES --------
    app.get('/health', (req, res) => res.send(`✅ Healthy - Region: ${REGION}`));

    // Upload media (WRITE)
    app.post('/media', upload.single('file'), async (req, res) => {
      try {
        const fileKey = `${uuidv4()}-${req.file.originalname}`;
        await s3.putObject({
          Bucket: S3_BUCKET_PRIMARY,
          Key: fileKey,
          Body: req.file.buffer,
          ContentType: req.file.mimetype,
        }).promise();

        const result = await runWriterQuery(
          'INSERT INTO media(id, filename, s3_key, region) VALUES($1, $2, $3, $4) RETURNING *',
          [uuidv4(), req.file.originalname, fileKey, REGION]
        );

        res.json({ message: '✅ File uploaded successfully', data: result.rows[0] });
      } catch (err) {
        console.error('❌ Upload failed:', err);
        res.status(500).json({ error: 'Upload failed' });
      }
    });

    // Fetch metadata (READ)
    app.get('/media', async (req, res) => {
      try {
        const result = await runReaderQuery('SELECT * FROM media ORDER BY created_at DESC');
        res.json(result.rows);
      } catch (err) {
        console.error('❌ Fetch media failed:', err);
        res.status(500).json({ error: 'Failed to fetch media' });
      }
    });

    // Download media (READ)
    app.get('/media/:key', async (req, res) => {
      try {
        const key = req.params.key;
        const localBucket = REGION === 'us-east-1' ? S3_BUCKET_PRIMARY : S3_BUCKET_SECONDARY;

        const data = await s3.getObject({ Bucket: localBucket, Key: key }).promise();
        res.setHeader('Content-Type', data.ContentType);
        res.send(data.Body);
      } catch (err) {
        console.error('❌ File not found:', err);
        res.status(404).json({ error: 'File not found' });
      }
    });

    // Start Server
    const PORT = process.env.PORT || 5000;
    app.listen(PORT, () => {
      console.log(`🚀 Server running in ${REGION} region on port ${PORT}`);
    });

  } catch (err) {
    console.error("❌ App initialization failed:", err);
    process.exit(1);
  }
}

initApp();
