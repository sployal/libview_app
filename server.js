require('dotenv').config();

const path = require('path');
const express = require('express');
const cors = require('cors');
const multer = require('multer');
const { google } = require('googleapis');
const { Readable } = require('stream');
const admin = require('firebase-admin');
const { registerAiRoutes } = require('./ai_chat');

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

// Semester folders created for additional courses (loaded from Firestore).
const extraSemesterFolderIds = new Set();
const SUPER_ADMIN_EMAIL = (process.env.SUPER_ADMIN_EMAIL || 'muigaid91@gmail.com').toLowerCase();

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

const extraSemesterIds = new Set();

async function loadSemesterIdsFromFirestore() {
  try {
    const snapshot = await firestore.collection('courses').get();
    snapshot.forEach((doc) => {
      const semesters = doc.data().semesters || {};
      Object.values(semesters).forEach((semester) => {
        const id = semester && semester.folderId;
        if (typeof id === 'string' && id) extraSemesterIds.add(id);
      });
    });
  } catch (err) {
    console.error('Failed to load course semester folders from Firestore:', err.message);
  }
}

function rememberSemesterFolderId(folderId) {
  if (typeof folderId === 'string' && folderId) {
    extraSemesterIds.add(folderId);
  }
}

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
    valid = isFolder && parents.some((p) => isSemesterFolder(p));
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

function isSemesterFolder(folderId) {
  return typeof folderId === 'string' &&
    (CONFIG.SEMESTER_FOLDER_IDS.has(folderId) || extraSemesterIds.has(folderId));
}

// New unit folders are created directly under a semester folder.
// Nested folders can still be created inside an existing unit folder.
async function isValidCreateParent(folderId) {
  return isSemesterFolder(folderId) || (await isValidSubjectFolder(folderId));
}

async function createFolder(folderName, parentFolderId, { cacheAsSubject = true } = {}) {
  const safeName = sanitizeFileName(folderName);
  const res = await drive.files.create({
    requestBody: {
      name: safeName,
      mimeType: 'application/vnd.google-apps.folder',
      parents: [parentFolderId],
    },
    fields: 'id, name',
    supportsAllDrives: true,
  });
  if (cacheAsSubject) {
    validationCache.set(res.data.id, { valid: true, at: Date.now() });
  }
  return res.data;
}

async function resolveEdupalFolderId() {
  if (process.env.EDUPAL_FOLDER_ID) {
    return process.env.EDUPAL_FOLDER_ID;
  }

  const semesterId = [...CONFIG.SEMESTER_FOLDER_IDS][0];
  if (!semesterId) {
    throw new Error('No known semester folder to locate Edupal from');
  }

  const semester = await drive.files.get({
    fileId: semesterId,
    fields: 'parents',
    supportsAllDrives: true,
  });
  const courseFolderId = (semester.data.parents || [])[0];
  if (!courseFolderId) {
    throw new Error('Could not find the Engineering course folder');
  }

  const courseFolder = await drive.files.get({
    fileId: courseFolderId,
    fields: 'parents',
    supportsAllDrives: true,
  });
  const edupalId = (courseFolder.data.parents || [])[0];
  if (!edupalId) {
    throw new Error('Could not find the Edupal Drive folder');
  }
  return edupalId;
}

async function createCourseStructure(courseName, years) {
  const edupalId = await resolveEdupalFolderId();
  const courseFolder = await createFolder(courseName, edupalId, {
    cacheAsSubject: false,
  });

  const semesters = {};
  for (let year = 1; year <= years; year += 1) {
    for (let sem = 1; sem <= 2; sem += 1) {
      const key = `year${year}_sem${sem}`;
      const driveName = `year ${year} sem ${sem}`;
      const folder = await createFolder(driveName, courseFolder.id, {
        cacheAsSubject: false,
      });
      rememberSemesterFolderId(folder.id);
      semesters[key] = {
        folderId: folder.id,
        name: `Year ${year} - Semester ${sem}`,
        driveName,
      };
    }
  }

  return {
    courseFolderId: courseFolder.id,
    courseFolderName: courseFolder.name,
    semesters,
  };
}

async function isCourseFolderUnderEdupal(folderId) {
  if (!folderId || typeof folderId !== 'string') return false;
  if (isSemesterFolder(folderId)) return false;

  try {
    const edupalId = await resolveEdupalFolderId();
    if (folderId === edupalId) return false;

    const res = await drive.files.get({
      fileId: folderId,
      fields: 'id, mimeType, parents',
      supportsAllDrives: true,
    });
    const isFolder = res.data.mimeType === 'application/vnd.google-apps.folder';
    const parents = res.data.parents || [];
    return Boolean(isFolder && parents.includes(edupalId));
  } catch (err) {
    return false;
  }
}

async function resolveCourseFolderId(folderId) {
  if (await isCourseFolderUnderEdupal(folderId)) return folderId;

  try {
    const res = await drive.files.get({
      fileId: folderId,
      fields: 'id, parents',
      supportsAllDrives: true,
    });
    const parent = (res.data.parents || [])[0];
    if (parent && (await isCourseFolderUnderEdupal(parent))) return parent;
  } catch (err) {
    return null;
  }
  return null;
}

async function forgetCourseSemesterIds(courseFolderId) {
  try {
    const res = await drive.files.list({
      q: `'${courseFolderId}' in parents and trashed = false`,
      fields: 'files(id)',
      supportsAllDrives: true,
      includeItemsFromAllDrives: true,
    });
    for (const file of res.data.files || []) {
      extraSemesterIds.delete(file.id);
    }
  } catch (err) {
    console.error('Could not forget semester folder IDs:', err.message);
  }
}

async function renameItem(fileId, newName) {
  const res = await drive.files.update({
    fileId,
    requestBody: { name: sanitizeFileName(newName) },
    fields: 'id, name',
    supportsAllDrives: true,
  });
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
    if (parents.some((p) => isSemesterFolder(p))) {
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

function requireSuperAdmin(req, res, next) {
  const email = (req.user.email || '').toLowerCase();
  if (email === SUPER_ADMIN_EMAIL) return next();
  if (CONFIG.ADMIN_UIDS.size > 0 && CONFIG.ADMIN_UIDS.has(req.user.uid)) {
    return next();
  }
  return res.status(403).json({ error: 'Super admin privileges required' });
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
app.use(express.json({ limit: '12mb' }));

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
  if (!(await isValidCreateParent(parentFolderId))) {
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

// --- Create a course folder under Edupal with year/semester subfolders ---

app.post('/course-structure', requireAuth, requireSuperAdmin, async (req, res) => {
  if (!driveIsConfigured()) {
    return res.status(503).json({ error: 'Drive is not configured yet. Complete the OAuth setup first.' });
  }

  const { name, years } = req.body || {};
  const yearCount = Number(years);

  if (!name || typeof name !== 'string' || !name.trim()) {
    return res.status(400).json({ error: 'A non-empty course "name" is required' });
  }
  if (!Number.isInteger(yearCount) || yearCount < 1 || yearCount > 10) {
    return res.status(400).json({ error: 'years must be an integer between 1 and 10' });
  }

  try {
    const structure = await createCourseStructure(name.trim(), yearCount);
    res.json(structure);
  } catch (e) {
    console.error('Course structure creation failed:', e);
    res.status(500).json({ error: e.message || 'Failed to create course folders' });
  }
});

// --- Rename the main course folder under Edupal (super admin) ------------

app.patch('/course-folder/:folderId', requireAuth, requireSuperAdmin, async (req, res) => {
  if (!driveIsConfigured()) {
    return res.status(503).json({ error: 'Drive is not configured yet. Complete the OAuth setup first.' });
  }

  const { folderId } = req.params;
  const { name } = req.body || {};

  if (!folderId) {
    return res.status(400).json({ error: 'A folder ID is required' });
  }
  if (!name || typeof name !== 'string' || !name.trim()) {
    return res.status(400).json({ error: 'A non-empty "name" is required' });
  }

  const courseFolderId = await resolveCourseFolderId(folderId);
  if (!courseFolderId) {
    return res.status(403).json({ error: 'Invalid or unauthorized course folder' });
  }

  try {
    const result = await renameItem(courseFolderId, name.trim());
    res.json(result);
  } catch (e) {
    console.error('Course folder rename failed:', e);
    res.status(500).json({ error: 'Failed to rename the course folder' });
  }
});

// --- Delete the course folder and all nested Drive folders (super admin) --

app.delete('/course-folder/:folderId', requireAuth, requireSuperAdmin, async (req, res) => {
  if (!driveIsConfigured()) {
    return res.status(503).json({ error: 'Drive is not configured yet. Complete the OAuth setup first.' });
  }

  const { folderId } = req.params;
  if (!folderId) {
    return res.status(400).json({ error: 'A folder ID is required' });
  }

  const courseFolderId = await resolveCourseFolderId(folderId);
  if (!courseFolderId) {
    return res.status(403).json({ error: 'Invalid or unauthorized course folder' });
  }

  try {
    await forgetCourseSemesterIds(courseFolderId);
    await deleteItem(courseFolderId);
    res.json({ deleted: true, courseFolderId });
  } catch (e) {
    console.error('Course folder delete failed:', e);
    res.status(500).json({ error: 'Failed to delete the course Drive folders' });
  }
});

// --- Rename a file or folder (admin-only by default) --------------------

app.patch('/files/:fileId', requireAuth, requireAdmin, async (req, res) => {
  if (!driveIsConfigured()) {
    return res.status(503).json({ error: 'Drive is not configured yet. Complete the OAuth setup first.' });
  }

  const { fileId } = req.params;
  const { name } = req.body || {};

  if (!fileId) {
    return res.status(400).json({ error: 'A file ID is required' });
  }
  if (!name || typeof name !== 'string' || !name.trim()) {
    return res.status(400).json({ error: 'A non-empty "name" is required' });
  }
  if (isSemesterFolder(fileId)) {
    return res.status(403).json({ error: 'Semester folders cannot be renamed' });
  }
  if (!(await isManagedItem(fileId))) {
    return res.status(403).json({ error: 'Invalid or unauthorized file' });
  }

  try {
    const result = await renameItem(fileId, name);
    res.json(result);
  } catch (e) {
    console.error('Rename failed:', e);
    res.status(500).json({ error: 'Rename failed' });
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

// --- AI chat (NVIDIA Llama vision) --------------------------------------

registerAiRoutes(app, { requireAuth });

// --- Fallback error handler --------------------------------------------

app.use((err, req, res, next) => {
  console.error(err);
  res.status(500).json({ error: 'Unexpected server error' });
});

initDriveAuth().then(async () => {
  await loadSemesterIdsFromFirestore();
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