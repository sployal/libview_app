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
  GOOGLE_DRIVE_SA_KEY_PATH: process.env.GOOGLE_DRIVE_SA_KEY_PATH || './secrets/drive-service-account.json',
  FIREBASE_SA_KEY_PATH: process.env.FIREBASE_SA_KEY_PATH || './secrets/firebase-service-account.json',
  MAX_UPLOAD_BYTES: parseInt(process.env.MAX_UPLOAD_BYTES || `${20 * 1024 * 1024}`, 10),
  SEMESTER_FOLDER_IDS,
  ADMIN_UIDS,
};

// =========================================================================
// drive.js
// =========================================================================

const driveAuth = new google.auth.GoogleAuth({
  keyFile: path.resolve(CONFIG.GOOGLE_DRIVE_SA_KEY_PATH),
  scopes: ['https://www.googleapis.com/auth/drive'],
});

const drive = google.drive({ version: 'v3', auth: driveAuth });

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

admin.initializeApp({
  credential: admin.credential.cert(require(path.resolve(CONFIG.FIREBASE_SA_KEY_PATH))),
});

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

app.get('/health', (req, res) => res.json({ ok: true }));

// --- Upload a file into a subject folder --------------------------------

app.post('/upload', requireAuth, (req, res) => {
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
  try {
    await deleteItem(req.params.fileId);
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

app.listen(CONFIG.PORT, () => {
  console.log(`Edupal backend listening on port ${CONFIG.PORT}`);
});