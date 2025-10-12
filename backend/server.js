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
const APP_SECRET_NAME = process.env.APP_SECRET_NAME;


AWS.config.update({ region: REGION });
const secretsManager = new AWS.SecretsManager({ region: REGION });
const s3 = new AWS.S3();

const upload = multer({ storage: multer.memoryStorage() });

let AppConfig = null;
let writerPool = null;
let readerPool = null;

// --------------------------
// Fetch Secrets from AWS
// --------------------------
async function fetchSecrets() {
  const secret = await secretsManager.getSecretValue({ SecretId: APP_SECRET_NAME }).promise();
  if (!secret || !secret.SecretString) throw new Error("DB secret not found or empty");
  AppConfig = JSON.parse(secret.SecretString);
  console.log("🔑 Secrets fetched successfully");
  return AppConfig;
}

// --------------------------
// Initialize DB Connections
// --------------------------
async function initDbConnections() {
  const creds = AppConfig || await fetchSecrets();

  writerPool = new Pool({
    host: creds.db_primary_cluster_endpoint,
    user: creds.db_username,
    password: creds.db_password,
    database: creds.db_name,
    port: 5432,
  });

  readerPool = new Pool({
    host: REGION === 'us-east-1'
      ? creds.db_primary_cluster_endpoint
      : creds.db_secondary_cluster_endpoint,
     user: creds.db_username,
    password: creds.db_password,
    database: creds.db_name,
    port: 5432,
  });

  console.log(`✅ DB connections established`);
}

// --------------------------
// Helper DB Query Functions
// --------------------------
async function runWriterQuery(query, params) {
  try {
    return await writerPool.query(query, params);
  } catch (err) {
    console.error("❌ Writer DB error:", err.message);
    await fetchSecrets();
    await initDbConnections();
    return writerPool.query(query, params);
  }
}

async function runReaderQuery(query, params) {
  try {
    return await readerPool.query(query, params);
  } catch (err) {
    console.error("⚠️ Reader DB error:", err.message);
    await fetchSecrets();
    await initDbConnections();
    return readerPool.query(query, params);
  }
}

// --------------------------
// Initialize App
// --------------------------
async function initApp() {
  try {
    await fetchSecrets();
    await initDbConnections();

    // DB table
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

    // --------------------------
    // POST /api/media — Upload
    // --------------------------
    app.post('/api/media', upload.single('file'), async (req, res) => {
      try {
        if (!req.file) return res.status(400).json({ error: "No file provided" });

        const id = uuidv4();
        const fileKey = `${id}-${req.file.originalname}`;

        // Upload to primary bucket
        await s3.putObject({
          Bucket: AppConfig.main_s3_bucket,
          Key: fileKey,
          Body: req.file.buffer,
          ContentType: req.file.mimetype,
        }).promise();

        const result = await runWriterQuery(
          `INSERT INTO media(id, filename, s3_key, region) VALUES($1, $2, $3, $4) RETURNING *`,
          [id, req.file.originalname, fileKey, REGION]
        );

        const url = `${AppConfig.cloudfront_url}/${fileKey}`;

        res.status(201).json({
          message: '✅ File uploaded successfully',
          media: {
            id,
            filename: req.file.originalname,
            url,
            created_at: result.rows[0].created_at
          }
        });
      } catch (err) {
        console.error('❌ Upload failed:', err);
        res.status(500).json({ error: 'Upload failed' });
      }
    });

    // --------------------------
    // GET /api/media — List all
    // --------------------------
    app.get('/api/media', async (req, res) => {
      try {
        const result = await runReaderQuery('SELECT * FROM media ORDER BY created_at DESC');
        const media = result.rows.map(m => ({
          id: m.id,
          filename: m.filename,
          url: `${AppConfig.cloudfront_url}/${m.s3_key}`,
          created_at: m.created_at
        }));
        res.json({ count: media.length, media });
      } catch (err) {
        console.error('❌ Fetch media failed:', err);
        res.status(500).json({ error: 'Failed to fetch media' });
      }
    });



    // Start Server
    const PORT = process.env.PORT || 5000;
    app.listen(PORT, () => {
      console.log(`🚀 Content Service running in ${REGION} on port ${PORT}`);

    });

  } catch (err) {
    console.error("❌ App initialization failed:", err);
    process.exit(1);
  }
}

initApp();
