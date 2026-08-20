require('dotenv').config();

const path = require('path');
const express = require('express');
const cors = require('cors');
const multer = require('multer');
const { google } = require('googleapis');
const { Readable } = require('stream');
const admin = require('firebase-admin');

// =========================================================================
// config
// =========================================================================

// These must match the semesterFolderIds map in your Flutter app
// (semesters_screen.dart). Only folders that are direct children of
// one of these IDs are treated as valid upload/create targets.
//
// IMPORTANT: once you move folders (or start using a different owning
// account), the IDs below must be updated to match the *current*
// location of those folders.
const SEMESTER_FOLDER_IDS = new Set([
  '18YgdYz4ErI9yJHn2Gx1UoaVqZ7YECSFz', // year1_sem1
  '13sB0aRpu0xjtScMoJbtlSHcWvbr1gvbp', // year1_sem2
  '12RdiiGAfWsJPR9Q9fFf7Pi6p-g51sd1C', // year2_sem1
  '1_50Uj07FIcQY_KTQaFExtFpRnFi4C_G6', // year2_sem2
  '1jAJiVWsNEAcz6GSVLluxBeMGTTiALv6d', // year3_sem1
  '16K6uo5lRlS4s93lO8bZ1UkVQ5ywbZCnF', // year3_sem2
  '1-vulmlL7rswowcYWgl0y9DHw3o1hdnmx', // year4_sem1
  '15W3I9I9Dqwt3JKjNy8a9fDBCc6V0qjxf', // year4_sem2
  '18oNF6Xm4NV6oPnpZTJVBCPDqrxlWm6vE', // year5_sem1
  '1VXL_RjzzO8QxDj1JY3eANLXP-38v-FiX', // year5_sem2
]);

const ADMIN_UIDS = new Set(
  (process.env.ADMIN_UIDS || '')
    .split(',')
    .map((s) => s.trim())
    .filter(Boolean)
);

const CONFIG = {
  PORT: parseInt(process.env.PORT || '3000', 10),
  ALLOWED_ORIGINS: (process.env.ALLOWED_ORIGINS || '*').split(',').map((s) => s.trim()),

  // --- Google OAuth2 (replaces the old service-account key) ---
  // Client ID/secret/redirect stay as env vars (they're not secrets that
  // change at runtime). The refresh token itself is NOT read from env
  // anymore — it's stored in and loaded from Firestore. See loadRefreshToken().
  GOOGLE_OAUTH_CLIENT_ID: process.env.GOOGLE_OAUTH_CLIENT_ID,
  GOOGLE_OAUTH_CLIENT_SECRET: process.env.GOOGLE_OAUTH_CLIENT_SECRET,
  GOOGLE_OAUTH_REDIRECT_URI: process.env.GOOGLE_OAUTH_REDIRECT_URI, // e.g. https://edupal-backend.onrender.com/auth/google/callback

  // Optional shared secret to protect the /auth/google entry point so
  // random visitors can't kick off the consent flow against your app.
  AUTH_SETUP_SECRET: process.env.AUTH_SETUP_SECRET || null,

  FIREBASE_SA_KEY_PATH: process.env.FIREBASE_SA_KEY_PATH || './secrets/firebase-service-account.json',
  MAX_UPLOAD_BYTES: parseInt(process.env.MAX_UPLOAD_BYTES || `${20 * 1024 * 1024}`, 10),
  SEMESTER_FOLDER_IDS,
  ADMIN_UIDS,
};

// =========================================================================
// firebaseAdmin.js  (initialized early so Firestore is available to drive.js)
// =========================================================================

admin.initializeApp({
  credential: admin.credential.cert(require(path.resolve(CONFIG.FIREBASE_SA_KEY_PATH))),
});

const firestore = admin.firestore();

// Where the refresh token lives in Firestore, instead of an env var.
// A single document under a "config" collection.
const OAUTH_DOC_REF = firestore.collection('config').doc('googleDriveOAuth');

async function saveRefreshToken(refreshToken) {
  await OAUTH_DOC_REF.set(
    {
      refreshToken,
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    },
    { merge: true }
  );
}

async function loadRefreshToken() {
  try {
    const snap = await OAUTH_DOC_REF.get();
    if (!snap.exists) return null;
    return snap.data().refreshToken || null;
  } catch (err) {
    console.error('Failed to load refresh token from Firestore:', err.message);
    return null;
  }
}

// =========================================================================
// drive.js  (OAuth2 client instead of a service account)
// =========================================================================

const DRIVE_SCOPES = ['https://www.googleapis.com/auth/drive'];

const oauth2Client = new google.auth.OAuth2(
  CONFIG.GOOGLE_OAUTH_CLIENT_ID,
  CONFIG.GOOGLE_OAUTH_CLIENT_SECRET,
  CONFIG.GOOGLE_OAUTH_REDIRECT_URI
);

const drive = google.drive({ version: 'v3', auth: oauth2Client });

// Tracks whether we've successfully loaded/set a refresh token onto
// oauth2Client, so routes can fail fast with a clear message instead of
// a confusing Drive error when the token isn't ready yet.
let driveReady = false;

function driveIsConfigured() {
  return driveReady;
}

// Called once at startup, and again right after the one-time OAuth
// callback succeeds, so a redeploy is never required.
async function initDriveAuth() {
  const refreshToken = await loadRefreshToken();
  if (refreshToken) {
    oauth2Client.setCredentials({ refresh_token: refreshToken });
    driveReady = true;
  } else {
    driveReady = false;
  }
}

// In-memory cache so repeated uploads to the same folder don't each
// cost an extra Drive API call. Entries expire after 10 minutes.
const validationCache = new Map();
const CACHE_TTL_MS = 10 * 60 * 1000;

// Confirms `folderId` is a real folder whose parent is one of our
// known semester folders (i.e. it's a legitimate subject folder,
// not an arbitrary ID the client made up).
async function isValidSubjectFolder(folderId) {
  if (!folderId || typeof folderId !== 'string') return false;

  const cached = validationCache.get(folderId);
  if (cached && Date.now() - cached.at < CACHE_TTL_MS) {
    return cached.valid;
  }

  let valid = false;
  try {
    const res = await drive.files.get({
      fileId: folderId,
      fields: 'id, mimeType, parents',
      supportsAllDrives: true,
    });
    const isFolder = res.data.mimeType === 'application/vnd.google-apps.folder';
    const parents = res.data.parents || [];
    valid = isFolder && parents.some((p) => CONFIG.SEMESTER_FOLDER_IDS.has(p));
  } catch (err) {
    valid = false; // not found, not accessible, or transient error — fail closed
  }

  validationCache.set(folderId, { valid, at: Date.now() });
  return valid;
}

async function uploadFile({ fileName, buffer, folderId, uploadedBy, mimeType }) {
  const safeName = sanitizeFileName(fileName);
  const res = await drive.files.create({
    requestBody: {
      name: safeName,
      parents: [folderId],
      appProperties: uploadedBy ? { uploadedBy } : undefined,
    },
    media: {
      mimeType: mimeType || mimeFromFileName(safeName),
      body: Readable.from(buffer),
    },
    fields: 'id, name, webViewLink, size, createdTime',
    supportsAllDrives: true,
  });
  return res.data;
}

async function createFolder(folderName, parentFolderId) {
  const res = await drive.files.create({
    requestBody: {
      name: folderName.trim(),
      mimeType: 'application/vnd.google-apps.folder',
      parents: [parentFolderId],
    },
    fields: 'id, name',
    supportsAllDrives: true,
  });
  // A newly created folder under a valid subject folder is itself a
  // valid target for further nested uploads/creates — cache that.
  validationCache.set(res.data.id, { valid: true, at: Date.now() });
  return res.data;
}

async function deleteItem(fileId) {
  await drive.files.delete({
    fileId,
    supportsAllDrives: true,
  });
  validationCache.delete(fileId);
}

// A file/folder may be deleted only if it lives under a known semester
// folder: either it *is* a subject folder (parent is a semester ID), or
// it sits inside a valid subject folder.
async function isManagedItem(fileId) {
  if (!fileId || typeof fileId !== 'string') return false;

  try {
    const res = await drive.files.get({
      fileId,
      fields: 'id, parents',
      supportsAllDrives: true,
    });
    const parents = res.data.parents || [];
    if (parents.some((p) => CONFIG.SEMESTER_FOLDER_IDS.has(p))) {
      return true;
    }
    for (const parent of parents) {
      if (await isValidSubjectFolder(parent)) return true;
    }
    return false;
  } catch (err) {
    return false;
  }
}

// Strips characters that are awkward in file names or could be used
// for path traversal — Drive doesn't have real paths, but this keeps
// names clean and avoids surprises in UIs that render them.
function sanitizeFileName(name) {
  const trimmed = (name || 'upload').trim();
  const cleaned = trimmed.replace(/[\/\\:*?"<>|\x00-\x1f]/g, '_');
  return cleaned.slice(0, 200) || 'upload';
}

function mimeFromFileName(name, fallback) {
  const ext = path.extname(name || '').slice(1).toLowerCase();
  const byExt = {
    pdf: 'application/pdf',
    doc: 'application/msword',
    docx: 'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
    ppt: 'application/vnd.ms-powerpoint',
    pps: 'application/vnd.ms-powerpoint',
    pptx: 'application/vnd.openxmlformats-officedocument.presentationml.presentation',
    xls: 'application/vnd.ms-excel',
    xlsx: 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
    jpg: 'image/jpeg',
    jpeg: 'image/jpeg',
    png: 'image/png',
    gif: 'image/gif',
    webp: 'image/webp',
    bmp: 'image/bmp',
    heic: 'image/heic',
    heif: 'image/heif',
    svg: 'image/svg+xml',
    tif: 'image/tiff',
    tiff: 'image/tiff',
    txt: 'text/plain',
    rtf: 'application/rtf',
  };
  return byExt[ext] || fallback || 'application/octet-stream';
}

// =========================================================================
// firebaseAuth.js
// =========================================================================

// Verifies the Firebase ID token sent as "Authorization: Bearer <token>".
// On success attaches req.user = { uid, email, ... } and calls next().
async function requireAuth(req, res, next) {
  const header = req.headers.authorization || '';
  const token = header.startsWith('Bearer ') ? header.slice(7) : null;

  if (!token) {
    return res.status(401).json({ error: 'Missing Authorization header' });
  }

  try {
    const decoded = await admin.auth().verifyIdToken(token);
    req.user = decoded;
    next();
  } catch (err) {
    console.error('Token verification failed:', err.message);
    res.status(401).json({ error: 'Invalid or expired token' });
  }
}

// Use after requireAuth. Restricts a route to UIDs listed in ADMIN_UIDS.
// If ADMIN_UIDS is empty, this allows any signed-in user through —
// tighten this before you ship if that's not what you want.
function requireAdmin(req, res, next) {
  if (CONFIG.ADMIN_UIDS.size === 0 || CONFIG.ADMIN_UIDS.has(req.user.uid)) {
    return next();
  }
  res.status(403).json({ error: 'Admin privileges required for this action' });
}

// =========================================================================
// server.js
// =========================================================================

const app = express();

app.use(
  cors({
    origin: CONFIG.ALLOWED_ORIGINS.includes('*') ? '*' : CONFIG.ALLOWED_ORIGINS,
  })
);
app.use(express.json());

const upload = multer({
  storage: multer.memoryStorage(),
  limits: { fileSize: CONFIG.MAX_UPLOAD_BYTES },
});

// --- Health check -----------------------------------------------------

app.get('/health', (req, res) => res.json({ ok: true, driveConfigured: driveIsConfigured() }));

// --- One-time OAuth2 setup routes ---------------------------------------
//
// These exist ONLY to generate a refresh token once. After you've
// captured the refresh token and saved it as GOOGLE_OAUTH_REFRESH_TOKEN
// in your .env / Render environment variables, you should remove these
// two routes (or at minimum keep AUTH_SETUP_SECRET set so randoms can't
// trigger the consent flow against your app).

app.get('/auth/google', (req, res) => {
  if (CONFIG.AUTH_SETUP_SECRET && req.query.secret !== CONFIG.AUTH_SETUP_SECRET) {
    return res.status(403).send('Forbidden');
  }
  if (!CONFIG.GOOGLE_OAUTH_CLIENT_ID || !CONFIG.GOOGLE_OAUTH_CLIENT_SECRET || !CONFIG.GOOGLE_OAUTH_REDIRECT_URI) {
    return res.status(500).send('OAuth client is not configured (missing env vars)');
  }

  const url = oauth2Client.generateAuthUrl({
    access_type: 'offline', // required to get a refresh_token back
    prompt: 'consent',      // forces Google to re-issue a refresh_token even on repeat auth
    scope: DRIVE_SCOPES,
  });

  res.redirect(url);
});

app.get('/auth/google/callback', async (req, res) => {
  const { code, error } = req.query;

  if (error) {
    return res.status(400).send(`Authorization failed: ${error}`);
  }
  if (!code) {
    return res.status(400).send('Missing "code" query parameter');
  }

  try {
    const { tokens } = await oauth2Client.getToken(code);

    if (!tokens.refresh_token) {
      return res
        .status(200)
        .send(
          'Signed in, but Google did not return a refresh_token (it only returns one the ' +
          'first time you consent, or when prompt=consent is used and any prior grant was ' +
          'revoked first). Go to https://myaccount.google.com/permissions, remove access for ' +
          'this app, then visit /auth/google again.'
        );
    }

    // Persist to Firestore so it survives restarts/redeploys and every
    // server instance (if you ever scale beyond one) can read it — no
    // manual copy-pasting into env vars required.
    await saveRefreshToken(tokens.refresh_token);

    // Wire it up immediately so this running server instance can use it
    // right away too, without waiting for a restart.
    oauth2Client.setCredentials(tokens);
    driveReady = true;

    console.log('Google Drive OAuth refresh token saved to Firestore (config/googleDriveOAuth).');

    res.send(
      'Success. Drive access has been authorized and saved. You can now remove or lock down ' +
      'the /auth/google and /auth/google/callback routes.'
    );
  } catch (e) {
    console.error('Token exchange failed:', e);
    res.status(500).send('Token exchange failed. Check server logs.');
  }
});

// --- Upload a file into a subject folder --------------------------------

app.post('/upload', requireAuth, (req, res) => {
  if (!driveIsConfigured()) {
    return res.status(503).json({ error: 'Drive is not configured yet. Complete the OAuth setup first.' });
  }

  upload.single('file')(req, res, async (err) => {
    if (err) {
      return res.status(400).json({ error: err.message });
    }
    if (!req.file) {
      return res.status(400).json({ error: 'A "file" field is required' });
    }

    const { folderId } = req.body;
    if (!(await isValidSubjectFolder(folderId))) {
      return res.status(403).json({ error: 'Invalid or unauthorized target folder' });
    }

    try {
      const result = await uploadFile({
        fileName: req.file.originalname,
        buffer: req.file.buffer,
        folderId,
        uploadedBy: req.user.uid,
        mimeType: mimeFromFileName(req.file.originalname, req.file.mimetype),
      });
      res.json(result);
    } catch (e) {
      console.error('Upload failed:', e);
      res.status(500).json({ error: 'Upload failed' });
    }
  });
});

// --- Create a folder within a subject folder ---------------------------

app.post('/folders', requireAuth, async (req, res) => {
  if (!driveIsConfigured()) {
    return res.status(503).json({ error: 'Drive is not configured yet. Complete the OAuth setup first.' });
  }

  const { name, parentFolderId } = req.body;

  if (!name || typeof name !== 'string' || !name.trim()) {
    return res.status(400).json({ error: 'A non-empty "name" is required' });
  }
  if (!(await isValidSubjectFolder(parentFolderId))) {
    return res.status(403).json({ error: 'Invalid or unauthorized parent folder' });
  }

  try {
    const folder = await createFolder(name, parentFolderId);
    res.json(folder);
  } catch (e) {
    console.error('Folder creation failed:', e);
    res.status(500).json({ error: 'Failed to create folder' });
  }
});

// --- Delete a file or folder (admin-only by default) --------------------

app.delete('/files/:fileId', requireAuth, requireAdmin, async (req, res) => {
  if (!driveIsConfigured()) {
    return res.status(503).json({ error: 'Drive is not configured yet. Complete the OAuth setup first.' });
  }

  const { fileId } = req.params;
  if (!fileId) {
    return res.status(400).json({ error: 'A file ID is required' });
  }
  if (!(await isManagedItem(fileId))) {
    return res.status(403).json({ error: 'Invalid or unauthorized file' });
  }

  try {
    await deleteItem(fileId);
    res.json({ deleted: true });
  } catch (e) {
    console.error('Delete failed:', e);
    res.status(500).json({ error: 'Delete failed' });
  }
});

// --- Fallback error handler --------------------------------------------

app.use((err, req, res, next) => {
  console.error(err);
  res.status(500).json({ error: 'Unexpected server error' });
});

initDriveAuth().then(() => {
  app.listen(CONFIG.PORT, () => {
    console.log(`Edupal backend listening on port ${CONFIG.PORT}`);
    if (!driveIsConfigured()) {
      console.log(
        `Drive is not configured yet. Visit /auth/google${CONFIG.AUTH_SETUP_SECRET ? '?secret=YOUR_SECRET' : ''} ` +
        `once to authorize — the refresh token will be saved to Firestore automatically.`
      );
    } else {
      console.log('Drive OAuth refresh token loaded from Firestore.');
    }
  });
});