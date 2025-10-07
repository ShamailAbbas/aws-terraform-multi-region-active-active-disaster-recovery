require('dotenv').config();
const express = require('express');
const multer = require('multer');
const AWS = require('aws-sdk');
const { Pool } = require('pg');
const { v4: uuidv4 } = require('uuid');
const cors = require('cors');




const app = express();
app.use(express.json());
// Enable CORS for all origins
app.use(cors());

// ---------- ENV VARIABLES ----------
const REGION = process.env.REGION
const DB_HOST = REGION=='us-east-1'?process.env.PRIMARY_DB_HOST:process.env.SECONDARY_DB_HOST;
const DB_USER = process.env.DB_USER;
const DB_PASSWORD = process.env.DB_PASSWORD;
const DB_NAME = process.env.DB_NAME;
const S3_BUCKET_PRIMARY = process.env.S3_BUCKET_PRIMARY;
const S3_BUCKET_LOCAL = REGION=='us-east-1'?process.env.S3_BUCKET_PRIMARY:process.env.S3_BUCKET_SECONDARY;
const DYNAMO_TABLE = process.env.DYNAMO_TABLE;

// ---------- POSTGRESQL POOL ----------
const pool = new Pool({
  host: DB_HOST,
  user: DB_USER,
  password: DB_PASSWORD,
  database: DB_NAME,
  port: 5432
});

// ---------- AWS CONFIG ----------
AWS.config.update({ region: REGION });
const s3 = new AWS.S3();
const dynamo = new AWS.DynamoDB.DocumentClient();

// ---------- MULTER SETUP ----------
const upload = multer({ storage: multer.memoryStorage() });

// ---------- AUTO-CREATE TABLE ----------
const createMediaTable = async () => {
  const query = `
    CREATE TABLE IF NOT EXISTS media (
      id UUID PRIMARY KEY,
      filename TEXT NOT NULL,
      s3_key TEXT NOT NULL,
      region TEXT,
      created_at TIMESTAMP DEFAULT NOW()
    );
  `;
  await pool.query(query);
  console.log('Media table is ready.');
};

// Initialize table before starting the server
createMediaTable().catch(err => {
  console.error('Error creating media table:', err);
  process.exit(1);
});

// ---------- ROUTES ----------

// Health Check
app.get('/health', (req, res) => {
  res.send(`Hello from ${REGION} region!`);
});

// --------- MEDIA CRUD ----------

// Upload media (write always to primary S3)
app.post('/media', upload.single('file'), async (req, res) => {
  try {
    const fileKey = `${uuidv4()}-${req.file.originalname}`;

    // Upload to primary S3
    await s3.putObject({
      Bucket: S3_BUCKET_PRIMARY,
      Key: fileKey,
      Body: req.file.buffer,
      ContentType: req.file.mimetype
    }).promise();

    // Store metadata in DB
    const result = await pool.query(
      'INSERT INTO media(id, filename, s3_key, region) VALUES($1, $2, $3, $4) RETURNING *',
      [uuidv4(), req.file.originalname, fileKey, REGION]
    );

    res.json({ message: 'File uploaded', data: result.rows[0] });
  } catch (err) {
    console.error(err);
    res.status(500).json({ error: 'Upload failed' });
  }
});

// Get media metadata
app.get('/media', async (req, res) => {
  try {
    const result = await pool.query('SELECT * FROM media');
    res.json(result.rows);
  } catch (err) {
    console.error(err);
    res.status(500).json({ error: 'Failed to fetch media' });
  }
});

// Download media (read from local S3)
app.get('/media/:key', async (req, res) => {
  try {
    const key = req.params.key;
    const data = await s3.getObject({
      Bucket: S3_BUCKET_LOCAL,
      Key: key
    }).promise();

    res.setHeader('Content-Type', data.ContentType);
    res.send(data.Body);
  } catch (err) {
    console.error(err);
    res.status(404).json({ error: 'File not found' });
  }
});

// DynamoDB session example
app.post('/session', async (req, res) => {
  const sessionId = uuidv4();
  await dynamo.put({
    TableName: DYNAMO_TABLE,
    Item: {
      sessionId,
      data: req.body
    }
  }).promise();
  res.json({ sessionId });
});

app.get('/session/:id', async (req, res) => {
  const sessionId = req.params.id;
  const result = await dynamo.get({
    TableName: DYNAMO_TABLE,
    Key: { sessionId }
  }).promise();
  res.json(result.Item);
});

// ---------- START SERVER ----------
const PORT = process.env.PORT || 5000;
app.listen(PORT, () => {
  console.log(`Server running in ${REGION} region on port ${PORT}`);
});
