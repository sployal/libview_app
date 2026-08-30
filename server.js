require('dotenv').config();

const fs = require('fs');
const path = require('path');
const https = require('https');
const express = require('express');
const cors = require('cors');
const multer = require('multer');
const { google } = require('googleapis');
const { Readable } = require('stream');
const admin = require('firebase-admin');
const { registerAiRoutes } = require('./ai_chat');
const { registerMediaRoutes } = require('./media server.js');
const { registerContactRoutes } = require('./contact');

// =========================================================================
// config
// =========================================================================

// Engineering Drive layout is derived from the Edupal root only
// (ROOT_FOLDER_ID or EDUPAL_FOLDER_ID). On startup the server looks for
// the Engineering course folder and its year/semester subfolders on Drive,
// creates any that are missing, then writes the IDs to Firestore. It also
// finds or creates an "updates" folder under the Edupal root for APKs.
const EDUPAL_FOLDER_ID =
  process.env.EDUPAL_FOLDER_ID || process.env.ROOT_FOLDER_ID || '';
const SYSTEM_ADMIN_EMAIL = (
  process.env.SYSTEM_ADMIN_EMAIL ||
  'muigaid91@gmail.com'
).toLowerCase();

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
  EDUPAL_FOLDER_ID,
  ADMIN_UIDS,

  // Public Drive API keys — used only for listing/reading and downloads,
  // same split as the Flutter app. Writes stay on OAuth.
  GOOGLE_DRIVE_API_KEY: process.env.GOOGLE_DRIVE_API_KEY || '',
  GOOGLE_DRIVE_DOWNLOAD_API_KEY: process.env.GOOGLE_DRIVE_DOWNLOAD_API_KEY || '',
};

// =========================================================================
// firebaseAdmin.js  (initialized early so Firestore is available to drive.js)
// =========================================================================

admin.initializeApp({
  credential: admin.credential.cert(require(path.resolve(CONFIG.FIREBASE_SA_KEY_PATH))),
});

const firestore = admin.firestore();

const extraSemesterIds = new Set();

async function syncEngineeringCourseToFirestore() {
  if (!CONFIG.EDUPAL_FOLDER_ID) {
    console.warn(
      'Skipping Engineering Drive sync: set ROOT_FOLDER_ID (or EDUPAL_FOLDER_ID) in .env.'
    );
    return;
  }
  if (!driveIsConfigured()) {
    console.warn('Skipping Engineering Drive sync: Drive OAuth is not configured yet.');
    return;
  }

  const structure = await ensureCourseStructure('Engineering', 5);
  const updatesFolderId = await ensureUpdatesFolder();
  const payload = {
    name: 'Engineering',
    years: 5,
    sample_admission_number: 'EB24/46271/20',
    admission_prefix: 'EB24',
    drive_folder_id: structure.courseFolderId,
    updatesFolderId,
    semesters: structure.semesters,
    updated_at: admin.firestore.FieldValue.serverTimestamp(),
  };

  await firestore.collection('courses').doc('engineering').set(payload, { merge: true });
  await firestore.collection('config').doc('googleDriveFolders').set(
    {
      edupalFolderId: CONFIG.EDUPAL_FOLDER_ID,
      engineeringCourseFolderId: structure.courseFolderId,
      updatesFolderId,
      semesterFolderIds: Object.fromEntries(
        Object.entries(structure.semesters).map(([key, value]) => [key, value.folderId])
      ),
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    },
    { merge: true }
  );
  console.log('Synced Engineering Drive folder IDs to Firestore (courses/engineering).');
}

async function ensureUpdatesFolder() {
  const edupalId = await resolveEdupalFolderId();
  const rootFolders = await listChildFolders(edupalId);
  const folder = await findOrCreateNamedFolder('updates', edupalId, rootFolders);
  if (folder.created) {
    console.log(`Created Drive folder "updates" under Edupal root (${folder.id}).`);
  } else {
    console.log(`Using existing Drive folder "updates" (${folder.id}).`);
  }
  return folder.id;
}

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

const DRIVE_SCOPES = [
  'https://www.googleapis.com/auth/drive',
  // HTTPS send for /contact. Render free instances block SMTP 25/465/587.
  'https://www.googleapis.com/auth/gmail.send',
];

const oauth2Client = new google.auth.OAuth2(
  CONFIG.GOOGLE_OAUTH_CLIENT_ID,
  CONFIG.GOOGLE_OAUTH_CLIENT_SECRET,
  CONFIG.GOOGLE_OAUTH_REDIRECT_URI
);

const drive = google.drive({ version: 'v3', auth: oauth2Client });
const publicDrive = google.drive({ version: 'v3' });

// Tracks whether we've successfully loaded/set a refresh token onto
// oauth2Client, so routes can fail fast with a clear message instead of
// a confusing Drive error when the token isn't ready yet.
let driveReady = false;

function driveIsConfigured() {
  return driveReady;
}

function driveReadIsConfigured() {
  return Boolean(CONFIG.GOOGLE_DRIVE_API_KEY);
}

function driveDownloadIsConfigured() {
  return Boolean(CONFIG.GOOGLE_DRIVE_DOWNLOAD_API_KEY);
}

function driveReadKey() {
  if (!CONFIG.GOOGLE_DRIVE_API_KEY) {
    throw new Error('GOOGLE_DRIVE_API_KEY is missing from .env');
  }
  return CONFIG.GOOGLE_DRIVE_API_KEY;
}

function driveDownloadKey() {
  if (!CONFIG.GOOGLE_DRIVE_DOWNLOAD_API_KEY) {
    throw new Error('GOOGLE_DRIVE_DOWNLOAD_API_KEY is missing from .env');
  }
  return CONFIG.GOOGLE_DRIVE_DOWNLOAD_API_KEY;
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
async function driveGetMeta(fileId, fields, apiKey) {
  const client = apiKey ? publicDrive : drive;
  const res = await client.files.get({
    fileId,
    fields,
    supportsAllDrives: true,
    ...(apiKey ? { key: apiKey } : {}),
  });
  return res.data;
}

async function isValidSubjectFolder(folderId, { apiKey } = {}) {
  if (!folderId || typeof folderId !== 'string') return false;

  const cached = validationCache.get(folderId);
  if (cached && Date.now() - cached.at < CACHE_TTL_MS) {
    return cached.valid;
  }

  let valid = false;
  try {
    const data = await driveGetMeta(folderId, 'id, mimeType, parents', apiKey);
    const isFolder = data.mimeType === 'application/vnd.google-apps.folder';
    const parents = data.parents || [];
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
  return typeof folderId === 'string' && extraSemesterIds.has(folderId);
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

function normalizeFolderName(name) {
  return String(name || '')
    .trim()
    .toLowerCase()
    .replace(/\s+/g, ' ');
}

async function listChildFolders(parentId) {
  const folders = [];
  let pageToken;
  do {
    const res = await drive.files.list({
      q: `'${parentId}' in parents and mimeType = 'application/vnd.google-apps.folder' and trashed = false`,
      fields: 'nextPageToken, files(id, name)',
      pageSize: 100,
      pageToken,
      supportsAllDrives: true,
      includeItemsFromAllDrives: true,
    });
    folders.push(...(res.data.files || []));
    pageToken = res.data.nextPageToken;
  } while (pageToken);
  return folders;
}

async function findOrCreateNamedFolder(name, parentId, existingFolders) {
  const wanted = normalizeFolderName(name);
  const existing = existingFolders.find((folder) => normalizeFolderName(folder.name) === wanted);
  if (existing) {
    return { id: existing.id, name: existing.name, created: false };
  }

  const created = await createFolder(name, parentId, { cacheAsSubject: false });
  existingFolders.push(created);
  return { id: created.id, name: created.name, created: true };
}

async function resolveEdupalFolderId() {
  if (!CONFIG.EDUPAL_FOLDER_ID) {
    throw new Error('ROOT_FOLDER_ID (or EDUPAL_FOLDER_ID) is not set');
  }
  return CONFIG.EDUPAL_FOLDER_ID;
}

const FOLDER_MIME = 'application/vnd.google-apps.folder';
const STORAGE_CACHE_TTL_MS = 5 * 60 * 1000;
let storageCache = { at: 0, data: null };

async function listDirectChildren(parentId, { apiKey } = {}) {
  const client = apiKey ? publicDrive : drive;
  const files = [];
  let pageToken;
  do {
    const res = await client.files.list({
      q: `'${parentId}' in parents and trashed = false`,
      fields: 'nextPageToken, files(id, name, mimeType, size, modifiedTime, webViewLink, thumbnailLink)',
      pageSize: 1000,
      pageToken,
      supportsAllDrives: true,
      includeItemsFromAllDrives: true,
      ...(apiKey ? { key: apiKey } : {}),
    });
    files.push(...(res.data.files || []));
    pageToken = res.data.nextPageToken;
  } while (pageToken);
  return files;
}

async function sumFolderBytes(folderId) {
  const children = await listDirectChildren(folderId);
  let bytes = 0;
  const subfolders = [];
  for (const file of children) {
    if (file.mimeType === FOLDER_MIME) {
      subfolders.push(file.id);
    } else {
      bytes += Number(file.size || 0);
    }
  }
  for (const id of subfolders) {
    bytes += await sumFolderBytes(id);
  }
  return bytes;
}

async function collectDriveStorage() {
  const about = await drive.about.get({
    fields: 'user(displayName,emailAddress),storageQuota',
  });
  const quota = about.data.storageQuota || {};
  const limit = quota.limit != null && quota.limit !== '' ? Number(quota.limit) : null;
  const usage = Number(quota.usage || 0);
  const usageInDrive = Number(quota.usageInDrive || 0);

  let root = null;
  let courses = [];
  let otherAccountBytes = usage;

  if (CONFIG.EDUPAL_FOLDER_ID) {
    const rootId = await resolveEdupalFolderId();
    const rootMeta = await drive.files.get({
      fileId: rootId,
      fields: 'id, name',
      supportsAllDrives: true,
    });
    const children = await listDirectChildren(rootId);
    let rootLooseBytes = 0;
    courses = [];
    for (const file of children) {
      if (file.mimeType === FOLDER_MIME) {
        const bytes = await sumFolderBytes(file.id);
        courses.push({
          folderId: file.id,
          name: file.name,
          bytes,
        });
      } else {
        rootLooseBytes += Number(file.size || 0);
      }
    }
    courses.sort((a, b) => b.bytes - a.bytes || a.name.localeCompare(b.name));
    const coursesBytes = courses.reduce((sum, course) => sum + course.bytes, 0);
    const rootBytes = coursesBytes + rootLooseBytes;
    otherAccountBytes = Math.max(0, usage - rootBytes);
    root = {
      folderId: rootId,
      name: rootMeta.data.name || 'Edupal',
      bytes: rootBytes,
      otherBytes: rootLooseBytes,
    };
  }

  return {
    account: {
      email: about.data.user?.emailAddress || '',
      displayName: about.data.user?.displayName || '',
      limitBytes: Number.isFinite(limit) ? limit : null,
      usageBytes: usage,
      usageInDriveBytes: usageInDrive,
    },
    root,
    courses,
    otherAccountBytes,
    computedAt: new Date().toISOString(),
  };
}

async function ensureCourseStructure(courseName, years) {
  const edupalId = await resolveEdupalFolderId();
  const rootFolders = await listChildFolders(edupalId);
  const courseFolder = await findOrCreateNamedFolder(courseName, edupalId, rootFolders);

  const semesterFolders = await listChildFolders(courseFolder.id);
  const semesters = {};
  for (let year = 1; year <= years; year += 1) {
    for (let sem = 1; sem <= 2; sem += 1) {
      const key = `year${year}_sem${sem}`;
      const driveName = `year ${year} sem ${sem}`;
      const folder = await findOrCreateNamedFolder(driveName, courseFolder.id, semesterFolders);
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

async function createCourseStructure(courseName, years) {
  return ensureCourseStructure(courseName, years);
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
async function isManagedFromParents(parents, { apiKey } = {}) {
  if ((parents || []).some((p) => isSemesterFolder(p))) {
    return true;
  }
  for (const parent of parents || []) {
    if (await isValidSubjectFolder(parent, { apiKey })) return true;
  }
  return false;
}

async function isManagedItem(fileId, { apiKey } = {}) {
  if (!fileId || typeof fileId !== 'string') return false;

  try {
    const data = await driveGetMeta(fileId, 'id, parents', apiKey);
    return isManagedFromParents(data.parents || [], { apiKey });
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

function requireSystemAdmin(req, res, next) {
  const email = (req.user.email || '').toLowerCase();
  if (email === SYSTEM_ADMIN_EMAIL) return next();
  if (CONFIG.ADMIN_UIDS.size > 0 && CONFIG.ADMIN_UIDS.has(req.user.uid)) {
    return next();
  }

  firestore
    .collection('profiles')
    .doc(req.user.uid)
    .get()
    .then((snap) => {
      const role = String(snap.data()?.role || '').toLowerCase();
      if (role === 'system_admin' || role === 'super_admin') return next();
      return res.status(403).json({ error: 'System admin privileges required' });
    })
    .catch((err) => {
      console.error('System admin check failed:', err.message);
      return res.status(403).json({ error: 'System admin privileges required' });
    });
}

// =========================================================================
// server.js
// =========================================================================

const app = express();

app.use(
  cors({
    origin: CONFIG.ALLOWED_ORIGINS.includes('*') ? '*' : CONFIG.ALLOWED_ORIGINS,
    // Let the web app read the download filename from Content-Disposition.
    exposedHeaders: ['Content-Disposition', 'Content-Type'],
  })
);
app.use(express.json({ limit: '12mb' }));

const upload = multer({
  storage: multer.memoryStorage(),
  limits: { fileSize: CONFIG.MAX_UPLOAD_BYTES },
});

// --- Health check -----------------------------------------------------

app.get('/health', (req, res) =>
  res.json({
    ok: true,
    driveConfigured: driveIsConfigured(),
    driveReadKeyConfigured: driveReadIsConfigured(),
    driveDownloadKeyConfigured: driveDownloadIsConfigured(),
  })
);

// Public Firebase *web* client config from web-service.json (same idea as
// google-services.json). Flutter never calls this. Additive only.
app.get('/firebase-config', (req, res) => {
  const candidates = [
    process.env.FIREBASE_WEB_CONFIG_PATH &&
      path.resolve(__dirname, process.env.FIREBASE_WEB_CONFIG_PATH),
    path.resolve(__dirname, 'secrets', 'web-service.json'),
  ].filter(Boolean);

  for (const file of candidates) {
    try {
      if (!fs.existsSync(file)) continue;
      const config = JSON.parse(fs.readFileSync(file, 'utf8'));
      if (!config?.apiKey || !config?.projectId) continue;
      return res.json(config);
    } catch (err) {
      console.error('Failed to read web-service.json:', err.message);
    }
  }

  return res.status(503).json({
    error: 'web-service.json was not found in the secrets folder',
  });
});

// --- Weather (OpenWeather; API key stays on the server) ---------------

const OPENWEATHER_API_KEY = process.env.OPENWEATHER_API_KEY || '';
const DEFAULT_WEATHER_LOCATION = {
  name: 'Chuka',
  country: 'KE',
  lat: -0.3333,
  lon: 37.65,
};
const weatherCache = new Map();
const WEATHER_CACHE_TTL_MS = 5 * 60 * 1000;

function httpsGetJson(url) {
  return new Promise((resolve, reject) => {
    https
      .get(url, (incoming) => {
        let raw = '';
        incoming.on('data', (chunk) => {
          raw += chunk;
        });
        incoming.on('end', () => {
          try {
            const json = JSON.parse(raw || '{}');
            if (incoming.statusCode >= 400) {
              const err = new Error(json.message || `OpenWeather ${incoming.statusCode}`);
              err.statusCode = incoming.statusCode;
              return reject(err);
            }
            resolve(json);
          } catch (err) {
            reject(err);
          }
        });
      })
      .on('error', reject);
  });
}

function cacheGet(key) {
  const hit = weatherCache.get(key);
  if (!hit) return null;
  if (Date.now() - hit.at > WEATHER_CACHE_TTL_MS) {
    weatherCache.delete(key);
    return null;
  }
  return hit.value;
}

function cacheSet(key, value) {
  weatherCache.set(key, { at: Date.now(), value });
}

function friendlyCondition(weather) {
  const main = String(weather?.main || '').toLowerCase();
  const icon = String(weather?.icon || '');
  const isDay = icon.endsWith('d');
  if (main === 'clear') return isDay ? 'Sunny' : 'Clear';
  if (main === 'clouds') return weather?.id === 801 ? 'Partly cloudy' : 'Cloudy';
  if (main === 'rain') return 'Rainy';
  if (main === 'drizzle') return 'Drizzle';
  if (main === 'thunderstorm') return 'Stormy';
  if (main === 'snow') return 'Snowy';
  if (main === 'mist' || main === 'fog' || main === 'haze' || main === 'smoke') {
    return 'Misty';
  }
  const description = String(weather?.description || '').trim();
  if (!description) return 'Unknown';
  return description.charAt(0).toUpperCase() + description.slice(1);
}

function requireOpenWeather(_req, res, next) {
  if (!OPENWEATHER_API_KEY) {
    return res.status(503).json({
      error: 'Weather is not configured. Set OPENWEATHER_API_KEY on the server.',
    });
  }
  return next();
}

app.get('/weather', requireAuth, requireOpenWeather, async (req, res) => {
  try {
    let lat = Number.parseFloat(String(req.query.lat || ''));
    let lon = Number.parseFloat(String(req.query.lon || ''));
    if (!Number.isFinite(lat) || !Number.isFinite(lon)) {
      lat = DEFAULT_WEATHER_LOCATION.lat;
      lon = DEFAULT_WEATHER_LOCATION.lon;
    }

    const cacheKey = `weather:${lat.toFixed(3)},${lon.toFixed(3)}`;
    const cached = cacheGet(cacheKey);
    if (cached) return res.json(cached);

    const url =
      'https://api.openweathermap.org/data/2.5/weather' +
      `?lat=${encodeURIComponent(lat)}&lon=${encodeURIComponent(lon)}` +
      `&units=metric&appid=${encodeURIComponent(OPENWEATHER_API_KEY)}`;
    const data = await httpsGetJson(url);
    const weather = (data.weather && data.weather[0]) || {};
    const payload = {
      city: data.name || DEFAULT_WEATHER_LOCATION.name,
      country: (data.sys && data.sys.country) || DEFAULT_WEATHER_LOCATION.country,
      lat: data.coord?.lat ?? lat,
      lon: data.coord?.lon ?? lon,
      tempC: Math.round(Number(data.main?.temp ?? 0)),
      condition: friendlyCondition(weather),
      icon: weather.icon || '01d',
    };
    cacheSet(cacheKey, payload);
    return res.json(payload);
  } catch (err) {
    console.error('Weather fetch failed:', err.message);
    return res.status(502).json({ error: 'Could not load weather right now.' });
  }
});

app.get('/weather/locations', requireAuth, requireOpenWeather, async (req, res) => {
  try {
    const query = String(req.query.q || '').trim();
    if (query.length < 2) {
      return res.json({
        locations: [
          {
            name: DEFAULT_WEATHER_LOCATION.name,
            country: DEFAULT_WEATHER_LOCATION.country,
            state: null,
            lat: DEFAULT_WEATHER_LOCATION.lat,
            lon: DEFAULT_WEATHER_LOCATION.lon,
          },
        ],
      });
    }

    const cacheKey = `geo:${query.toLowerCase()}`;
    const cached = cacheGet(cacheKey);
    if (cached) return res.json(cached);

    const url =
      'https://api.openweathermap.org/geo/1.0/direct' +
      `?q=${encodeURIComponent(query)}&limit=8&appid=${encodeURIComponent(OPENWEATHER_API_KEY)}`;
    const results = await httpsGetJson(url);
    const locations = (Array.isArray(results) ? results : []).map((item) => ({
      name: item.name,
      country: item.country || '',
      state: item.state || null,
      lat: item.lat,
      lon: item.lon,
    }));
    const payload = { locations };
    cacheSet(cacheKey, payload);
    return res.json(payload);
  } catch (err) {
    console.error('Weather location search failed:', err.message);
    return res.status(502).json({ error: 'Could not search locations right now.' });
  }
});

// --- Drive account quota + Edupal / course folder usage (system admin) ---

app.get('/drive-storage', requireAuth, requireSystemAdmin, async (req, res) => {
  if (!driveIsConfigured()) {
    return res.status(503).json({
      error: 'Drive is not configured yet. Complete the OAuth setup first.',
    });
  }

  try {
    const refresh = req.query.refresh === '1' || req.query.refresh === 'true';
    if (
      !refresh &&
      storageCache.data &&
      Date.now() - storageCache.at < STORAGE_CACHE_TTL_MS
    ) {
      return res.json({ ...storageCache.data, cached: true });
    }

    const data = await collectDriveStorage();
    storageCache = { at: Date.now(), data };
    res.json({ ...data, cached: false });
  } catch (e) {
    console.error('Drive storage query failed:', e);
    res.status(500).json({ error: e.message || 'Failed to load Drive storage' });
  }
});

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

    try {
      await syncEngineeringCourseToFirestore();
      await loadSemesterIdsFromFirestore();
    } catch (err) {
      console.error('Failed to sync Engineering Drive folders after OAuth:', err.message);
    }

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

app.post('/course-structure', requireAuth, requireSystemAdmin, async (req, res) => {
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

// --- Rename the main course folder under Edupal (system admin) ------------

app.patch('/course-folder/:folderId', requireAuth, requireSystemAdmin, async (req, res) => {
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

// --- Delete the course folder and all nested Drive folders (system admin) --

app.delete('/course-folder/:folderId', requireAuth, requireSystemAdmin, async (req, res) => {
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

// Drive thumbnailLink URLs expire and often 403 in the browser. Proxy them
// through the backend so folder cards can show real file previews.
app.get('/files/:fileId/thumbnail', requireAuth, async (req, res) => {
  if (!driveReadIsConfigured()) {
    return res.status(503).json({ error: 'GOOGLE_DRIVE_API_KEY is not configured.' });
  }

  const { fileId } = req.params;
  if (!fileId) {
    return res.status(400).json({ error: 'A file ID is required' });
  }

  try {
    const meta = await driveGetMeta(fileId, 'thumbnailLink,hasThumbnail', driveReadKey());
    const thumbnailLink = meta.thumbnailLink;
    if (!thumbnailLink) {
      return res.status(404).json({ error: 'No thumbnail' });
    }

    const url = thumbnailLink.replace(/=s\d+/, '=s400');
    const thumbRes = await fetch(url);
    if (!thumbRes.ok) {
      return res.status(thumbRes.status).json({ error: 'Thumbnail fetch failed' });
    }

    const contentType = thumbRes.headers.get('content-type') || 'image/jpeg';
    res.setHeader('Content-Type', contentType);
    res.setHeader('Cache-Control', 'private, max-age=3600');
    res.send(Buffer.from(await thumbRes.arrayBuffer()));
  } catch (e) {
    console.error('Thumbnail failed:', e);
    res.status(500).json({ error: 'Failed to load thumbnail' });
  }
});

// =========================================================================
// Web app — file download
// Signed-in students download unit files through this proxy using
// GOOGLE_DRIVE_DOWNLOAD_API_KEY (same key as the Flutter DownloadService).
// Native Google Docs/Sheets/Slides are exported first, then streamed.
// The Next.js Downloads page saves that blob locally (IndexedDB) and also
// triggers a browser save.
// =========================================================================

// Pick an export MIME type + filename when the Drive item is a Google Doc,
// Sheet, or Slide rather than an uploaded binary.
function googleExportFor(mimeType, fileName) {
  if (mimeType.includes('spreadsheet')) {
    return {
      mime: 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
      name: fileName.replace(/\.[^.]+$/, '') + '.xlsx',
    };
  }
  if (mimeType.includes('presentation')) {
    return {
      mime: 'application/vnd.openxmlformats-officedocument.presentationml.presentation',
      name: fileName.replace(/\.[^.]+$/, '') + '.pptx',
    };
  }
  if (mimeType.includes('document')) {
    return {
      mime: 'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
      name: fileName.replace(/\.[^.]+$/, '') + '.docx',
    };
  }
  return {
    mime: 'application/pdf',
    name: fileName.replace(/\.[^.]+$/, '') + '.pdf',
  };
}

function contentDispositionAttachment(fileName) {
  const safe = sanitizeFileName(fileName).replace(/"/g, '');
  return `attachment; filename="${safe}"; filename*=UTF-8''${encodeURIComponent(safe)}`;
}

function driveMediaUrl(fileId, apiKey) {
  const params = new URLSearchParams({
    alt: 'media',
    supportsAllDrives: 'true',
    key: apiKey,
  });
  return `https://www.googleapis.com/drive/v3/files/${encodeURIComponent(fileId)}?${params}`;
}

function driveExportUrl(fileId, mimeType, apiKey) {
  const params = new URLSearchParams({
    mimeType,
    key: apiKey,
  });
  return `https://www.googleapis.com/drive/v3/files/${encodeURIComponent(fileId)}/export?${params}`;
}

function downloadUrlFromMeta(meta, apiKey, exportMime) {
  const mime = meta.mimeType || '';
  if (mime.includes('google-apps')) {
    const links = meta.exportLinks || {};
    return links[exportMime] || driveExportUrl(meta.id, exportMime, apiKey);
  }
  if (meta.webContentLink) return meta.webContentLink;
  return driveMediaUrl(meta.id, apiKey);
}

app.get('/files/:fileId/download', requireAuth, async (req, res) => {
  if (!driveDownloadIsConfigured()) {
    return res.status(503).json({ error: 'GOOGLE_DRIVE_DOWNLOAD_API_KEY is not configured.' });
  }

  const { fileId } = req.params;
  if (!fileId) {
    return res.status(400).json({ error: 'A file ID is required' });
  }

  const apiKey = driveDownloadKey();

  try {
    const meta = await driveGetMeta(
      fileId,
      'id, name, mimeType, size, webContentLink, exportLinks, parents',
      apiKey
    );
    if (!(await isManagedFromParents(meta.parents || [], { apiKey }))) {
      return res.status(403).json({ error: 'Invalid or unauthorized file' });
    }

    const sourceMime = meta.mimeType || 'application/octet-stream';
    const sourceName = meta.name || 'download';
    const isGoogleApp = sourceMime.startsWith('application/vnd.google-apps.');

    let downloadMime = sourceMime;
    let downloadName = sourceName;
    if (isGoogleApp) {
      const exported = googleExportFor(sourceMime, sourceName);
      downloadMime = exported.mime;
      downloadName = exported.name;
    }

    const downloadUrl = downloadUrlFromMeta(meta, apiKey, downloadMime);
    if (!downloadUrl) {
      return res.status(400).json({ error: 'This file type cannot be downloaded' });
    }

    let fileRes = await fetch(downloadUrl, { redirect: 'follow' });
    const mediaUrl = driveMediaUrl(fileId, apiKey);
    if (!fileRes.ok && !isGoogleApp && downloadUrl !== mediaUrl) {
      fileRes = await fetch(mediaUrl, { redirect: 'follow' });
    }
    if (!fileRes.ok) {
      console.error('Download upstream failed:', fileRes.status, await fileRes.text().catch(() => ''));
      return res.status(fileRes.status === 404 ? 404 : 502).json({ error: 'Failed to download file' });
    }

    res.setHeader('Content-Type', downloadMime);
    res.setHeader('Content-Disposition', contentDispositionAttachment(downloadName));
    const length = fileRes.headers.get('content-length') || (!isGoogleApp && meta.size ? String(meta.size) : '');
    if (length) {
      res.setHeader('Content-Length', length);
    }
    res.setHeader('Cache-Control', 'private, no-store');

    if (!fileRes.body) {
      res.send(Buffer.from(await fileRes.arrayBuffer()));
      return;
    }

    const stream = Readable.fromWeb(fileRes.body);
    stream.on('error', (error) => {
      console.error('Download stream failed:', error);
      if (!res.headersSent) {
        res.status(500).json({ error: 'Download failed' });
      } else {
        res.destroy(error);
      }
    });
    stream.pipe(res);
  } catch (e) {
    console.error('Download failed:', e);
    if (!res.headersSent) {
      res.status(500).json({ error: 'Failed to download file' });
    }
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

// =========================================================================
// Web app (Next.js) — Drive listing
// Flutter lists Drive with GOOGLE_DRIVE_API_KEY. The web semester/unit
// screens call this authenticated route, which uses the same key. Writes
// (upload, create, rename, delete) stay on OAuth above.
// =========================================================================

app.get('/folders/:folderId', requireAuth, async (req, res) => {
  if (!driveReadIsConfigured()) {
    return res.status(503).json({ error: 'GOOGLE_DRIVE_API_KEY is not configured.' });
  }

  const { folderId } = req.params;
  if (!folderId) {
    return res.status(400).json({ error: 'A folder ID is required' });
  }

  const apiKey = driveReadKey();
  const allowed =
    isSemesterFolder(folderId) || (await isValidSubjectFolder(folderId, { apiKey }));
  if (!allowed) {
    return res.status(403).json({ error: 'Invalid or unauthorized folder' });
  }

  try {
    const children = await listDirectChildren(folderId, { apiKey });
    const folders = [];
    const files = [];
    for (const item of children) {
      if (item.mimeType === FOLDER_MIME) folders.push(item);
      else files.push(item);
    }

    if (String(req.query.counts || '') === '1') {
      await Promise.all(
        folders.map(async (folder) => {
          const inner = await listDirectChildren(folder.id, { apiKey });
          folder.fileCount = inner.filter((file) => file.mimeType !== FOLDER_MIME).length;
        })
      );
    }

    res.json({ folders, files });
  } catch (e) {
    console.error('Folder listing failed:', e);
    res.status(500).json({ error: 'Failed to list folder contents' });
  }
});

// --- AI chat (NVIDIA Llama vision) --------------------------------------

registerAiRoutes(app, { requireAuth });
registerMediaRoutes(app, { requireAuth, requireSystemAdmin, upload });
registerContactRoutes(app, { oauth2Client });

// --- Fallback error handler --------------------------------------------

app.use((err, req, res, next) => {
  console.error('[express]', err.message || err);
  res.status(500).json({ error: 'Unexpected server error' });
});

initDriveAuth().then(async () => {
  try {
    await syncEngineeringCourseToFirestore();
  } catch (err) {
    console.error('Failed to sync Engineering Drive folders to Firestore:', err.message);
  }
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
    if (!driveReadIsConfigured()) {
      console.warn('GOOGLE_DRIVE_API_KEY is missing — folder listing and thumbnails will fail.');
    }
    if (!driveDownloadIsConfigured()) {
      console.warn('GOOGLE_DRIVE_DOWNLOAD_API_KEY is missing — file downloads will fail.');
    }
  });
});