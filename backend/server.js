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
let s3 = new AWS.S3();

const upload = multer({ storage: multer.memoryStorage() });

let AppConfig = null;
let dbPool = null;

let lastFetchTime = 0;
const SECRET_CACHE_TTL_MS = 5 * 60 * 1000; // 5 minutes

// -----------------------------------------------------
// Fetch Secrets (cached with optional force refresh)
// -----------------------------------------------------
async function fetchSecrets(force = false) {
  const now = Date.now();
  if (!force && AppConfig && now - lastFetchTime < SECRET_CACHE_TTL_MS) {
    return AppConfig;
  }

  console.log('🔐 Fetching latest secrets from AWS...');
  const secret = await secretsManager.getSecretValue({ SecretId: APP_SECRET_NAME }).promise();
  if (!secret || !secret.SecretString) throw new Error("Secret not found or empty");

  const newConfig = JSON.parse(secret.SecretString);
  lastFetchTime = now;

  // If bucket or DB changed, handle it gracefully
  if (AppConfig) {
    const bucketChanged = AppConfig.main_s3_bucket !== newConfig.main_s3_bucket;
    const dbChanged =
      AppConfig.db_password !== newConfig.db_password ||
      AppConfig.db_global_cluster_endpoint !== newConfig.db_global_cluster_endpoint ||
      AppConfig.db_primary_cluster_endpoint !== newConfig.db_primary_cluster_endpoint ||
      AppConfig.db_secondary_cluster_endpoint !== newConfig.db_secondary_cluster_endpoint;

    if (bucketChanged) {
      console.log('🪣 S3 bucket configuration changed, updating S3 client...');
      s3 = new AWS.S3(); // reinit client (same region but safe)
    }

    if (dbChanged) {
      console.log('⚙️ DB credentials or endpoints changed, refreshing DB connections...');
      AppConfig = newConfig;
      await initDbConnections();
    }
  }

  AppConfig = newConfig;
  return AppConfig;
}

// -----------------------------------------------------
// Initialize Database Connections
// -----------------------------------------------------
async function initDbConnections() {
  const creds = await fetchSecrets(true);

  // Close existing pools if any
  if (dbPool) await dbPool.end().catch(() => {});


  dbPool = new Pool({
    host: creds.db_global_cluster_endpoint,
    user: creds.db_username,
    password: creds.db_password,
    database: creds.db_name,
    port: 5432,
  });



  console.log('✅ Database connections ready');
}

// -----------------------------------------------------
// Background Secrets Refresher
// -----------------------------------------------------
function startSecretRefresher() {
  setInterval(async () => {
    try {
      console.log('🔄 Periodic secrets refresh...');
      await fetchSecrets(true);
    } catch (err) {
      console.error('❌ Secrets refresh failed:', err.message);
    }
  }, 5 * 60 * 1000); // every 5 minutes
}

// -----------------------------------------------------
// DB Query Wrappers
// -----------------------------------------------------
async function runQuery(query, params) {
  try {
    return await dbPool.query(query, params);
  } catch (err) {
    console.error('❌ DB error:', err.message);
    await initDbConnections();
    return dbPool.query(query, params);
  }
}



// -----------------------------------------------------
// Initialize App
// -----------------------------------------------------
async function initApp() {
  try {
    await fetchSecrets(true);
    await initDbConnections();
    startSecretRefresher();

    // Ensure table exists
    await runQuery(`
      CREATE TABLE IF NOT EXISTS media (
        id UUID PRIMARY KEY,
        filename TEXT NOT NULL,
        s3_key TEXT NOT NULL,
        region TEXT,
        created_at TIMESTAMP DEFAULT NOW()
      );
    `);

    console.log('✅ Media table verified');

    // Health
    app.get('/health', (req, res) => res.send(`✅ Healthy - Region: ${REGION}`));

    // Upload
    app.post('/api/media', upload.single('file'), async (req, res) => {
      try {
        if (!req.file) return res.status(400).json({ error: 'No file provided' });

        const id = uuidv4();
        const fileKey = `${id}-${req.file.originalname}`;

        await s3
          .putObject({
            Bucket: AppConfig.main_s3_bucket,
            Key: fileKey,
            Body: req.file.buffer,
            ContentType: req.file.mimetype,
          })
          .promise();

        const result = await runQuery(
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
            created_at: result.rows[0].created_at,
          },
        });
      } catch (err) {
        console.error('❌ Upload failed:', err);
        res.status(500).json({ error: 'Upload failed' });
      }
    });

    // List
    app.get('/api/media', async (req, res) => {
      try {
        const result = await runQuery('SELECT * FROM media ORDER BY created_at DESC');
        const media = result.rows.map((m) => ({
          id: m.id,
          filename: m.filename,
          url: `${AppConfig.cloudfront_url}/${m.s3_key}`,
          created_at: m.created_at,
        }));
        res.json({ count: media.length, media });
      } catch (err) {
        console.error('❌ Fetch media failed:', err);
        res.status(500).json({ error: 'Failed to fetch media' });
      }
    });

    // Start Server
    const PORT = process.env.PORT || 5000;
    app.listen(PORT, () => console.log(`🚀 Running in ${REGION} on port ${PORT}`));
  } catch (err) {
    console.error('❌ App init failed:', err);
    process.exit(1);
  }
}

initApp();
