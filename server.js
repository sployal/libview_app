require('dotenv').config();

const fs = require('fs');
const path = require('path');
const crypto = require('crypto');
const https = require('https');
const express = require('express');
const cors = require('cors');
const multer = require('multer');
const { google } = require('googleapis');
const { Readable } = require('stream');
const admin = require('firebase-admin');
const { registerAiRoutes } = require('./ai_chat');
const { registerMediaRoutes, deleteProfileAvatar } = require('./media server.js');
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
const SYSTEM_ADMIN_EMAIL = String(process.env.SYSTEM_ADMIN_EMAIL || '')
  .trim()
  .toLowerCase();
const GOOGLE_DRIVE_EMAIL = String(process.env.GOOGLE_DRIVE_EMAIL || '')
  .trim()
  .toLowerCase();

const ADMIN_UIDS = new Set(
  (process.env.ADMIN_UIDS || '')
    .split(',')
    .map((s) => s.trim())
    .filter(Boolean)
);

const CONFIG = {
  PORT: parseInt(process.env.PORT || '3000', 10),
  ALLOWED_ORIGINS: (process.env.ALLOWED_ORIGINS || 'https://edupal-web.vercel.app')
    .split(',')
    .map((s) => s.trim().replace(/\/$/, ''))
    .filter(Boolean),

  // --- Google OAuth2 (replaces the old service-account key) ---
  // Client ID/secret/redirect stay as env vars (they're not secrets that
  // change at runtime). The refresh token itself is NOT read from env
  // anymore — it's stored in and loaded from Firestore. See loadRefreshToken().
  GOOGLE_OAUTH_CLIENT_ID: process.env.GOOGLE_OAUTH_CLIENT_ID,
  GOOGLE_OAUTH_CLIENT_SECRET: process.env.GOOGLE_OAUTH_CLIENT_SECRET,
  GOOGLE_OAUTH_REDIRECT_URI: process.env.GOOGLE_OAUTH_REDIRECT_URI, // e.g. https://edupal-backend.onrender.com/auth/google/callback
  // Only this Google account's OAuth token is accepted for Drive.
  GOOGLE_DRIVE_EMAIL,

  // Optional shared secret to protect the /auth/google entry point so
  // random visitors can't kick off the consent flow against your app.
  AUTH_SETUP_SECRET: process.env.AUTH_SETUP_SECRET || null,

  FIREBASE_SA_KEY_PATH: process.env.FIREBASE_SA_KEY_PATH || './secrets/firebase-service-account.json',
  MAX_UPLOAD_BYTES: parseInt(process.env.MAX_UPLOAD_BYTES || `${200 * 1024 * 1024}`, 10),
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
const clientWorkspaceIds = new Set();
const clientResolveCache = new Map();
let clientsRootFolderId = '';

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

function rememberClientWorkspaceId(folderId) {
  if (typeof folderId === 'string' && folderId) {
    clientWorkspaceIds.add(folderId);
  }
}

function forgetClientWorkspaceId(folderId) {
  if (typeof folderId === 'string' && folderId) {
    clientWorkspaceIds.delete(folderId);
    clientResolveCache.clear();
  }
}

async function loadClientWorkspaceIdsFromFirestore() {
  try {
    const snapshot = await firestore.collection('clients').get();
    snapshot.forEach((doc) => {
      const id = doc.data().drive_folder_id;
      if (typeof id === 'string' && id) clientWorkspaceIds.add(id);
    });
  } catch (err) {
    console.error('Failed to load client workspace folders from Firestore:', err.message);
  }
}

function isClientWorkspaceFolder(folderId) {
  return typeof folderId === 'string' && clientWorkspaceIds.has(folderId);
}

async function ensureClientsRootFolder() {
  const edupalId = await resolveEdupalFolderId();
  const rootFolders = await listChildFolders(edupalId);
  const folder = await findOrCreateNamedFolder('clients', edupalId, rootFolders);
  clientsRootFolderId = folder.id;
  if (folder.created) {
    console.log(`Created Drive folder "clients" under Edupal root (${folder.id}).`);
  }
  await firestore.collection('config').doc('googleDriveFolders').set(
    {
      clientsFolderId: folder.id,
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    },
    { merge: true }
  );
  return folder.id;
}

async function createClientWorkspaceFolder(name) {
  const rootId = await ensureClientsRootFolder();
  const children = await listChildFolders(rootId);
  const folder = await findOrCreateNamedFolder(name, rootId, children);
  rememberClientWorkspaceId(folder.id);
  return {
    folderId: folder.id,
    name: folder.name,
    created: folder.created,
    clientsRootId: rootId,
  };
}

async function resolveClientWorkspaceId(folderId) {
  if (!folderId || typeof folderId !== 'string') return null;
  if (isClientWorkspaceFolder(folderId)) return folderId;

  const cached = clientResolveCache.get(folderId);
  if (cached && Date.now() - cached.at < CACHE_TTL_MS) {
    return cached.workspaceId;
  }

  let current = folderId;
  const seen = new Set();
  let workspaceId = null;
  try {
    while (current && !seen.has(current)) {
      seen.add(current);
      if (isClientWorkspaceFolder(current)) {
        workspaceId = current;
        break;
      }
      if (current === CONFIG.EDUPAL_FOLDER_ID || current === clientsRootFolderId) {
        break;
      }
      const meta = await drive.files.get({
        fileId: current,
        fields: 'id, parents',
        supportsAllDrives: true,
      });
      current = (meta.data.parents || [])[0] || '';
    }
  } catch (err) {
    workspaceId = null;
  }

  clientResolveCache.set(folderId, { workspaceId, at: Date.now() });
  return workspaceId;
}

function isConfiguredSystemAdminEmail(email) {
  return Boolean(SYSTEM_ADMIN_EMAIL) && String(email || '').trim().toLowerCase() === SYSTEM_ADMIN_EMAIL;
}

const promotedSystemAdminUids = new Set();

async function ensureEnvSystemAdminRole(user) {
  if (!SYSTEM_ADMIN_EMAIL || !user?.uid) return;
  if (!isConfiguredSystemAdminEmail(user.email)) return;
  if (promotedSystemAdminUids.has(user.uid)) return;

  const ref = firestore.collection('profiles').doc(user.uid);
  const snap = await ref.get();
  const data = snap.data() || {};
  const role = String(data.role || '').toLowerCase();
  if (role !== 'system_admin') {
    await ref.set(
      {
        email: SYSTEM_ADMIN_EMAIL,
        role: 'system_admin',
        updated_at: admin.firestore.FieldValue.serverTimestamp(),
      },
      { merge: true },
    );
  }
  promotedSystemAdminUids.add(user.uid);
}

async function promoteEnvSystemAdminOnStartup() {
  if (!SYSTEM_ADMIN_EMAIL) {
    console.warn('SYSTEM_ADMIN_EMAIL is not set in .env — no account will be auto-promoted to system admin.');
    return;
  }
  try {
    const authUser = await admin.auth().getUserByEmail(SYSTEM_ADMIN_EMAIL);
    await ensureEnvSystemAdminRole({ uid: authUser.uid, email: authUser.email });
    console.log(`Ensured system_admin role for ${SYSTEM_ADMIN_EMAIL}`);
  } catch (err) {
    if (err.code === 'auth/user-not-found') {
      console.warn(
        `SYSTEM_ADMIN_EMAIL ${SYSTEM_ADMIN_EMAIL} has no Firebase Auth user yet. They will be promoted on first sign-in.`,
      );
      return;
    }
    console.warn('Could not auto-promote system admin:', err.message);
  }
}

async function isSystemAdminUser(user) {
  const email = String(user?.email || '').toLowerCase();
  if (isConfiguredSystemAdminEmail(email)) return true;
  if (CONFIG.ADMIN_UIDS.size > 0 && CONFIG.ADMIN_UIDS.has(user.uid)) return true;
  try {
    const snap = await firestore.collection('profiles').doc(user.uid).get();
    const role = String(snap.data()?.role || '').toLowerCase();
    return role === 'system_admin';
  } catch (err) {
    return false;
  }
}

async function clientWorkspaceAllowsUser(workspaceFolderId, user) {
  if (!workspaceFolderId || !user?.uid) return false;
  if (await isSystemAdminUser(user)) return true;

  const snapshot = await firestore
    .collection('clients')
    .where('drive_folder_id', '==', workspaceFolderId)
    .limit(1)
    .get();
  if (snapshot.empty) return false;

  const doc = snapshot.docs[0];
  const data = doc.data() || {};
  if (data.suspended === true) return false;
  if (data.owner_uid === user.uid) return true;
  const members = Array.isArray(data.member_uids) ? data.member_uids : [];
  if (members.includes(user.uid)) return true;

  const profile = await firestore.collection('profiles').doc(user.uid).get();
  return String(profile.data()?.client_id || '') === doc.id;
}

async function userCanWriteClientFolder(user, folderId) {
  const workspaceId = await resolveClientWorkspaceId(folderId);
  if (!workspaceId) return false;
  return clientWorkspaceAllowsUser(workspaceId, user);
}

const FOLDER_LOCKS = () => firestore.collection('folder_locks');
const FOLDER_PASSWORD_MIN = 4;
const FOLDER_PASSWORD_MAX = 64;
const FOLDER_LOCK_SCRYPT_KEYLEN = 32;

function normalizeFolderPassword(value) {
  if (typeof value !== 'string') return '';
  return value;
}

function folderPasswordLengthOk(password) {
  const length = [...password].length;
  return length >= FOLDER_PASSWORD_MIN && length <= FOLDER_PASSWORD_MAX;
}

function scryptFolderPassword(password, salt) {
  return new Promise((resolve, reject) => {
    crypto.scrypt(password, salt, FOLDER_LOCK_SCRYPT_KEYLEN, { N: 16384, r: 8, p: 1 }, (err, derived) => {
      if (err) return reject(err);
      resolve(derived);
    });
  });
}

async function hashFolderPassword(password) {
  const salt = crypto.randomBytes(16);
  const hash = await scryptFolderPassword(password, salt);
  return {
    salt: salt.toString('base64'),
    hash: hash.toString('base64'),
  };
}

async function folderPasswordMatches(record, password) {
  if (!record?.salt || !record?.hash) return false;
  try {
    const salt = Buffer.from(record.salt, 'base64');
    const expected = Buffer.from(record.hash, 'base64');
    const derived = await scryptFolderPassword(password, salt);
    if (expected.length !== derived.length) return false;
    return crypto.timingSafeEqual(expected, derived);
  } catch (_) {
    return false;
  }
}

async function forgetFolderLock(folderId) {
  if (!folderId) return;
  try {
    await FOLDER_LOCKS().doc(folderId).delete();
  } catch (_) {}
}

async function assertLockableClientFolder(user, folderId) {
  if (!folderId || typeof folderId !== 'string') {
    return { ok: false, status: 400, error: 'Folder not found' };
  }
  if (isClientWorkspaceFolder(folderId)) {
    return { ok: false, status: 403, error: 'The workspace root cannot be locked' };
  }
  const allowed = await userCanWriteClientFolder(user, folderId);
  if (!allowed) {
    return { ok: false, status: 403, error: 'You do not have permission.' };
  }
  const workspaceId = await resolveClientWorkspaceId(folderId);
  if (!workspaceId) {
    return { ok: false, status: 403, error: 'You do not have permission.' };
  }
  return { ok: true, workspaceId };
}

const DEFAULT_CLIENT_STORAGE_LIMIT = 1024 * 1024 * 1024;

async function assertClientStorageAllows(folderId, incomingBytes) {
  const workspaceId = await resolveClientWorkspaceId(folderId);
  if (!workspaceId) return { ok: true };

  const snapshot = await firestore
    .collection('clients')
    .where('drive_folder_id', '==', workspaceId)
    .limit(1)
    .get();
  if (snapshot.empty) return { ok: true };

  const raw = Number(snapshot.docs[0].data().storage_limit_bytes);
  const limit =
    Number.isFinite(raw) && raw > 0 ? raw : DEFAULT_CLIENT_STORAGE_LIMIT;
  const used = await sumFolderBytes(workspaceId);
  if (used + incomingBytes > limit) {
    return { ok: false, used, limit };
  }
  return { ok: true, used, limit };
}

// Where the refresh token lives in Firestore, instead of an env var.
// A single document under a "config" collection.
const OAUTH_DOC_REF = firestore.collection('config').doc('googleDriveOAuth');
const REFRESH_TOKEN_TTL_DAYS = 7;
const REFRESH_TOKEN_TTL_MS = REFRESH_TOKEN_TTL_DAYS * 24 * 60 * 60 * 1000;

function firestoreTimeToMs(value) {
  if (!value) return null;
  if (typeof value.toMillis === 'function') return value.toMillis();
  if (value instanceof Date) return value.getTime();
  if (typeof value === 'string') {
    const parsed = Date.parse(value);
    return Number.isFinite(parsed) ? parsed : null;
  }
  if (typeof value._seconds === 'number') {
    return value._seconds * 1000 + Math.floor((value._nanoseconds || 0) / 1e6);
  }
  return null;
}

function firestoreTimeToIso(value) {
  const ms = firestoreTimeToMs(value);
  return ms == null ? null : new Date(ms).toISOString();
}

async function saveRefreshToken(refreshToken) {
  const now = admin.firestore.Timestamp.now();
  const expiresAt = admin.firestore.Timestamp.fromMillis(
    now.toMillis() + REFRESH_TOKEN_TTL_MS
  );
  await OAUTH_DOC_REF.set(
    {
      refreshToken,
      updatedAt: now,
      expiresAt,
      ttlDays: REFRESH_TOKEN_TTL_DAYS,
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

function oauthStatusFromData(data) {
  const stored = Boolean(data && data.refreshToken);
  if (!stored) {
    return {
      stored: false,
      expired: false,
      daysLeft: null,
      updatedAt: null,
      expiresAt: null,
      ttlDays: REFRESH_TOKEN_TTL_DAYS,
    };
  }

  const updatedAtMs = firestoreTimeToMs(data.updatedAt);
  const expiresAtMs =
    firestoreTimeToMs(data.expiresAt) ??
    (updatedAtMs == null ? null : updatedAtMs + REFRESH_TOKEN_TTL_MS);
  const remainingMs = expiresAtMs == null ? null : expiresAtMs - Date.now();
  const expired = remainingMs != null && remainingMs <= 0;
  const daysLeft =
    remainingMs == null
      ? null
      : remainingMs <= 0
        ? 0
        : Math.ceil(remainingMs / (24 * 60 * 60 * 1000));

  return {
    stored: true,
    expired,
    daysLeft,
    updatedAt: firestoreTimeToIso(data.updatedAt),
    expiresAt: expiresAtMs == null ? null : new Date(expiresAtMs).toISOString(),
    ttlDays: Number(data.ttlDays) || REFRESH_TOKEN_TTL_DAYS,
  };
}

async function loadOAuthStatus() {
  const snap = await OAUTH_DOC_REF.get();
  if (!snap.exists) return oauthStatusFromData(null);
  const data = snap.data() || {};
  const status = oauthStatusFromData(data);
  if (status.stored && !data.expiresAt && status.expiresAt) {
    try {
      await OAUTH_DOC_REF.set(
        {
          expiresAt: admin.firestore.Timestamp.fromDate(new Date(status.expiresAt)),
          ttlDays: REFRESH_TOKEN_TTL_DAYS,
        },
        { merge: true }
      );
    } catch (err) {
      console.warn('Could not backfill OAuth expiry fields:', err.message);
    }
  }
  return status;
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

async function fetchAuthorizedDriveEmail() {
  const about = await drive.about.get({
    fields: 'user(emailAddress,displayName)',
  });
  return String(about.data.user?.emailAddress || '').trim().toLowerCase();
}

async function restorePreviousDriveAuth() {
  oauth2Client.setCredentials({});
  driveReady = false;
  await initDriveAuth();
}

async function applyDriveOAuthTokens(tokens) {
  if (!tokens?.refresh_token) {
    return { ok: false, reason: 'missing_token' };
  }

  if (!CONFIG.GOOGLE_DRIVE_EMAIL) {
    console.error('GOOGLE_DRIVE_EMAIL is not set — refusing to save a Drive OAuth token.');
    return { ok: false, reason: 'email_not_configured' };
  }

  oauth2Client.setCredentials(tokens);

  let accountEmail = '';
  try {
    accountEmail = await fetchAuthorizedDriveEmail();
  } catch (err) {
    console.error('Could not read Drive account email from OAuth token:', err.message);
    await restorePreviousDriveAuth();
    return { ok: false, reason: 'email_check_failed' };
  }

  if (accountEmail !== CONFIG.GOOGLE_DRIVE_EMAIL) {
    console.warn(
      `Rejected Drive OAuth for ${accountEmail || '(unknown)'} — expected ${CONFIG.GOOGLE_DRIVE_EMAIL}.`
    );
    await restorePreviousDriveAuth();
    return {
      ok: false,
      reason: 'wrong_account',
      email: accountEmail,
      expected: CONFIG.GOOGLE_DRIVE_EMAIL,
    };
  }

  await saveRefreshToken(tokens.refresh_token);
  driveReady = true;

  try {
    await syncEngineeringCourseToFirestore();
    await loadSemesterIdsFromFirestore();
    await ensureClientsRootFolder();
    await loadClientWorkspaceIdsFromFirestore();
  } catch (err) {
    console.error('Failed to sync Engineering Drive folders after OAuth:', err.message);
  }

  console.log(
    `Google Drive OAuth refresh token saved for ${accountEmail} (config/googleDriveOAuth).`
  );
  return { ok: true, email: accountEmail };
}

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
  if (!refreshToken) {
    driveReady = false;
    return;
  }

  oauth2Client.setCredentials({ refresh_token: refreshToken });

  if (CONFIG.GOOGLE_DRIVE_EMAIL) {
    try {
      const accountEmail = await fetchAuthorizedDriveEmail();
      if (accountEmail && accountEmail !== CONFIG.GOOGLE_DRIVE_EMAIL) {
        console.error(
          `Stored Drive token belongs to ${accountEmail}, expected ${CONFIG.GOOGLE_DRIVE_EMAIL}. ` +
            'Drive writes are disabled until /auth/google is completed with the correct account.'
        );
        oauth2Client.setCredentials({});
        driveReady = false;
        return;
      }
    } catch (err) {
      console.warn('Could not verify stored Drive account email:', err.message);
    }
  } else {
    console.warn('GOOGLE_DRIVE_EMAIL is not set — /auth/google will not save a new token.');
  }

  driveReady = true;
}

const CACHE_TTL_MS = 10 * 60 * 1000;

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

async function isValidSubjectFolder(folderId) {
  return typeof folderId === 'string' && folderId.length > 0;
}

function parseDriveDateTime(value) {
  if (value == null || value === '') return undefined;
  if (typeof value === 'number' && Number.isFinite(value)) {
    const ms = value < 10_000_000_000 ? value * 1000 : value;
    const date = new Date(ms);
    if (Number.isNaN(date.getTime())) return undefined;
    const min = Date.UTC(1980, 0, 1);
    const max = Date.now() + 24 * 60 * 60 * 1000;
    if (date.getTime() < min || date.getTime() > max) return undefined;
    return date.toISOString();
  }
  if (typeof value !== 'string') return undefined;
  const trimmed = value.trim();
  if (!trimmed) return undefined;
  if (/^-?\d+(\.\d+)?$/.test(trimmed)) {
    return parseDriveDateTime(Number(trimmed));
  }
  const date = new Date(trimmed);
  if (Number.isNaN(date.getTime())) return undefined;
  const min = Date.UTC(1980, 0, 1);
  const max = Date.now() + 24 * 60 * 60 * 1000;
  if (date.getTime() < min || date.getTime() > max) return undefined;
  return date.toISOString();
}

async function uploadFile({
  fileName,
  buffer,
  folderId,
  uploadedBy,
  mimeType,
  modifiedTime,
}) {
  const safeName = sanitizeFileName(fileName);
  const uploadedAt = new Date().toISOString();
  const originalModified = parseDriveDateTime(modifiedTime);
  const mime = mimeType || mimeFromFileName(safeName);
  const requestBody = {
    name: safeName,
    parents: [folderId],
    properties: { uploadedAt },
    appProperties: uploadedBy ? { uploadedBy } : undefined,
  };
  if (originalModified) {
    // Drive rejects modifiedTime earlier than createdTime. Pin both to the
    // phone's file date (same as the Drive app), and keep the real upload
    // instant in properties.uploadedAt for the Edupal UI.
    requestBody.createdTime = originalModified;
    requestBody.modifiedTime = originalModified;
  }

  const created = await drive.files.create({
    requestBody,
    fields: 'id',
    supportsAllDrives: true,
  });
  const fileId = created.data?.id;
  if (!fileId) {
    throw new Error('Drive did not return a file id');
  }

  await drive.files.update({
    fileId,
    media: {
      mimeType: mime,
      body: Readable.from(buffer),
    },
    supportsAllDrives: true,
  });

  if (originalModified) {
    await drive.files.update({
      fileId,
      requestBody: { modifiedTime: originalModified },
      supportsAllDrives: true,
    });
  }

  const res = await drive.files.get({
    fileId,
    fields: 'id, name, webViewLink, size, createdTime, modifiedTime, properties',
    supportsAllDrives: true,
  });
  return {
    ...res.data,
    uploadedAt: res.data.properties?.uploadedAt || uploadedAt,
  };
}

function isSemesterFolder(folderId) {
  return typeof folderId === 'string' && extraSemesterIds.has(folderId);
}

// New unit folders are created directly under a semester folder.
// Nested folders can still be created inside an existing unit folder.
async function isValidCreateParent(folderId) {
  return isSemesterFolder(folderId) || (await isValidSubjectFolder(folderId));
}

async function createFolder(folderName, parentFolderId) {
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
  return res.data;
}

function normalizeFolderName(name) {
  return String(name || '')
    .toLowerCase()
    .replace(/[^a-z0-9]/g, '');
}

function androidNameKey(name) {
  const cleaned = String(name || '')
    .trim()
    .replace(/[\/\\:*?"<>|\x00-\x1f]/g, '_')
    .slice(0, 200)
    .replace(/[. ]+$/g, '');
  return cleaned.toLowerCase();
}

function keysMatch(left, right, keyOf) {
  const a = keyOf(left);
  const b = keyOf(right);
  if (!a || !b) {
    return String(left || '').trim().toLowerCase() === String(right || '').trim().toLowerCase();
  }
  return a === b;
}

function fileNamesClash(left, right) {
  return keysMatch(left, right, androidNameKey);
}

function folderNamesClash(left, right) {
  if (fileNamesClash(left, right)) return true;
  return keysMatch(left, right, normalizeFolderName);
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

  const created = await createFolder(name, parentId);
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

function childNamesClash(existingName, existingMime, wantedName, wantedIsFolder) {
  const existingIsFolder = existingMime === FOLDER_MIME;
  if (existingIsFolder || wantedIsFolder) {
    return folderNamesClash(existingName, wantedName);
  }
  return fileNamesClash(existingName, wantedName);
}

async function listChildItems(parentId) {
  const items = [];
  let pageToken;
  do {
    const res = await drive.files.list({
      q: `'${parentId}' in parents and trashed = false`,
      fields: 'nextPageToken, files(id, name, mimeType)',
      pageSize: 100,
      pageToken,
      supportsAllDrives: true,
      includeItemsFromAllDrives: true,
    });
    items.push(...(res.data.files || []));
    pageToken = res.data.nextPageToken;
  } while (pageToken);
  return items;
}

async function nameTakenInFolder(parentId, name, { ignoreId, isFolder } = {}) {
  const siblings = await listChildItems(parentId);
  return siblings.some((item) => {
    if (ignoreId && item.id === ignoreId) return false;
    return childNamesClash(item.name, item.mimeType, name, Boolean(isFolder));
  });
}

function asListedDriveItem(item) {
  return {
    id: item.id,
    name: item.name,
    mimeType: item.mimeType,
    size: item.size,
    modifiedTime: item.modifiedTime,
    createdTime: item.createdTime,
    uploadedAt: item.properties?.uploadedAt || item.createdTime,
    webViewLink: item.webViewLink,
    thumbnailLink: item.thumbnailLink,
    fileCount: item.fileCount,
  };
}

async function listDirectChildren(parentId, { apiKey } = {}) {
  const client = apiKey ? publicDrive : drive;
  const files = [];
  let pageToken;
  do {
    const res = await client.files.list({
      q: `'${parentId}' in parents and trashed = false`,
      fields: 'nextPageToken, files(id, name, mimeType, size, modifiedTime, createdTime, webViewLink, thumbnailLink, properties)',
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
}

// A file/folder may be deleted only if it lives under a known semester
// folder: either it *is* a subject folder (parent is a semester ID), or
// it sits inside a valid subject folder.
async function isManagedFromParents(parents) {
  if ((parents || []).some((p) => isSemesterFolder(p) || isClientWorkspaceFolder(p))) {
    return true;
  }
  for (const parent of parents || []) {
    if (await isValidSubjectFolder(parent)) return true;
    if (await resolveClientWorkspaceId(parent)) return true;
  }
  return false;
}

async function isManagedItem(fileId) {
  if (!fileId || typeof fileId !== 'string') return false;

  try {
    const res = await drive.files.get({
      fileId,
      fields: 'id, parents',
      supportsAllDrives: true,
    });
    return isManagedFromParents(res.data.parents || []);
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
    mp4: 'video/mp4',
    m4v: 'video/mp4',
    mov: 'video/quicktime',
    avi: 'video/x-msvideo',
    mkv: 'video/x-matroska',
    webm: 'video/webm',
    '3gp': 'video/3gpp',
    '3g2': 'video/3gpp2',
    wmv: 'video/x-ms-wmv',
    flv: 'video/x-flv',
    mpeg: 'video/mpeg',
    mpg: 'video/mpeg',
    ts: 'video/mp2t',
    m2ts: 'video/mp2t',
    mts: 'video/mp2t',
    ogv: 'video/ogg',
    asf: 'video/x-ms-asf',
    vob: 'video/dvd',
    f4v: 'video/x-f4v',
    mp3: 'audio/mpeg',
    wav: 'audio/wav',
    aac: 'audio/aac',
    m4a: 'audio/mp4',
    flac: 'audio/flac',
    ogg: 'audio/ogg',
    oga: 'audio/ogg',
    opus: 'audio/opus',
    wma: 'audio/x-ms-wma',
    aiff: 'audio/aiff',
    aif: 'audio/aiff',
    amr: 'audio/amr',
    mid: 'audio/midi',
    midi: 'audio/midi',
    caf: 'audio/x-caf',
    weba: 'audio/webm',
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
    console.warn('Auth rejected: missing Bearer token');
    return res.status(401).json({ error: 'Please sign in again.' });
  }

  try {
    const decoded = await admin.auth().verifyIdToken(token);
    req.user = decoded;
    try {
      await ensureEnvSystemAdminRole(decoded);
    } catch (err) {
      console.warn('Could not promote system admin profile:', err.message);
    }
    next();
  } catch (err) {
    console.error('Token verification failed:', err.message);
    res.status(401).json({ error: 'Please sign in again.' });
  }
}

// Use after requireAuth. Restricts a route to UIDs listed in ADMIN_UIDS.
// If ADMIN_UIDS is empty, this allows any signed-in user through —
// tighten this before you ship if that's not what you want.
function requireAdmin(req, res, next) {
  if (CONFIG.ADMIN_UIDS.size === 0 || CONFIG.ADMIN_UIDS.has(req.user.uid)) {
    return next();
  }
  console.warn(`Admin check failed for uid ${req.user.uid}`);
  res.status(403).json({ error: 'You do not have permission.' });
}

function requireSystemAdmin(req, res, next) {
  isSystemAdminUser(req.user)
    .then((allowed) => {
      if (allowed) return next();
      console.warn(`System admin check failed for uid ${req.user.uid}`);
      return res.status(403).json({ error: 'You do not have permission.' });
    })
    .catch((err) => {
      console.error('System admin check failed:', err.message);
      return res.status(403).json({ error: 'You do not have permission.' });
    });
}

// =========================================================================
// server.js
// =========================================================================

const app = express();

function normalizeOrigin(origin) {
  return String(origin || '').trim().replace(/\/$/, '');
}

function isAllowedOrigin(origin) {
  if (!origin) return true;
  if (CONFIG.ALLOWED_ORIGINS.includes('*')) return true;
  return CONFIG.ALLOWED_ORIGINS.includes(normalizeOrigin(origin));
}

function isOriginExemptPath(path) {
  return (
    path === '/health' ||
    path === '/auth/google' ||
    path === '/auth/google/callback'
  );
}

app.use(
  cors({
    origin(origin, callback) {
      if (isAllowedOrigin(origin)) {
        callback(null, true);
        return;
      }
      callback(null, false);
    },
    // Let the web app read the download filename from Content-Disposition.
    exposedHeaders: ['Content-Disposition', 'Content-Type'],
  })
);

app.use((req, res, next) => {
  if (isOriginExemptPath(req.path)) return next();
  const origin = req.headers.origin;
  if (isAllowedOrigin(origin)) return next();
  console.warn(`Blocked request from origin ${origin} ${req.method} ${req.path}`);
  return res.status(403).json({ error: 'Origin not allowed' });
});

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
    console.warn('Drive storage rejected: Drive OAuth is not configured');
    return res.status(503).json({ error: 'Could not load storage' });
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
    res.status(500).json({ error: 'Could not load storage' });
  }
});

app.get('/drive-oauth-status', requireAuth, requireSystemAdmin, async (req, res) => {
  try {
    const status = await loadOAuthStatus();
    res.json(status);
  } catch (e) {
    console.error('Drive OAuth status query failed:', e);
    res.status(500).json({ error: 'Could not load token status' });
  }
});

// --- One-time OAuth2 setup routes ---------------------------------------
//
// These exist ONLY to generate a refresh token once. After you've
// captured the refresh token and saved it as GOOGLE_OAUTH_REFRESH_TOKEN
// in your .env / Render environment variables, you should remove these
// two routes (or at minimum keep AUTH_SETUP_SECRET set so randoms can't
// trigger the consent flow against your app).

function escapeHtml(value) {
  return String(value)
    .replace(/&/g, '&amp;')
    .replace(/</g, '&lt;')
    .replace(/>/g, '&gt;')
    .replace(/"/g, '&quot;');
}

function oauthResultPage({ status, title, message }) {
  const allowed = new Set([
    'success',
    'failed',
    'missing_token',
    'wrong_account',
    'email_not_configured',
  ]);
  const safeStatus = allowed.has(status) ? status : 'failed';
  const safeTitle = escapeHtml(title || 'Authorization');
  const safeMessage = escapeHtml(message || '');
  return `<!DOCTYPE html>
<html lang="en" data-edupal-oauth="${safeStatus}">
<head>
  <meta charset="utf-8" />
  <meta name="viewport" content="width=device-width, initial-scale=1" />
  <title>${safeTitle}</title>
  <style>
    body { margin: 0; min-height: 100vh; display: flex; align-items: center; justify-content: center;
      font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif;
      background: #0f172a; color: #f8fafc; padding: 24px; }
    .card { max-width: 420px; text-align: center; }
    h1 { font-size: 22px; margin: 0 0 12px; }
    p { margin: 0; color: #94a3b8; line-height: 1.5; }
  </style>
</head>
<body data-edupal-oauth="${safeStatus}">
  <div class="card">
    <h1>${safeTitle}</h1>
    <p>${safeMessage}</p>
  </div>
</body>
</html>`;
}

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
    ...(CONFIG.GOOGLE_DRIVE_EMAIL ? { login_hint: CONFIG.GOOGLE_DRIVE_EMAIL } : {}),
  });

  res.redirect(url);
});

app.get('/auth/google/callback', async (req, res) => {
  const { code, error } = req.query;

  if (error) {
    return res.status(400).send(oauthResultPage({
      status: 'failed',
      title: 'Authorization failed',
      message: String(error),
    }));
  }
  if (!code) {
    return res.status(400).send(oauthResultPage({
      status: 'failed',
      title: 'Authorization failed',
      message: 'Missing authorization code. Close this screen and try again.',
    }));
  }

  try {
    const { tokens } = await oauth2Client.getToken(code);
    const applied = await applyDriveOAuthTokens(tokens);
    if (!applied.ok) {
      if (applied.reason === 'wrong_account') {
        return res.status(403).send(oauthResultPage({
          status: 'wrong_account',
          title: 'Wrong Google account',
          message:
            `This server only accepts Drive access from ${applied.expected}. ` +
            `You signed in as ${applied.email || 'a different account'}. ` +
            'Close this screen and authorize with the configured Drive email.',
        }));
      }
      if (applied.reason === 'email_not_configured') {
        return res.status(500).send(oauthResultPage({
          status: 'email_not_configured',
          title: 'Drive email not configured',
          message: 'Set GOOGLE_DRIVE_EMAIL in the server .env, then try again.',
        }));
      }
      if (applied.reason === 'email_check_failed') {
        return res.status(500).send(oauthResultPage({
          status: 'failed',
          title: 'Could not verify account',
          message: 'The token was received but the Drive account email could not be read. Try again.',
        }));
      }
      return res.status(200).send(oauthResultPage({
        status: 'missing_token',
        title: 'No refresh token',
        message:
          'Google did not return a refresh token. Remove this app at myaccount.google.com/permissions, then try again.',
      }));
    }

    res.send(oauthResultPage({
      status: 'success',
      title: 'Drive connected',
      message: `Access has been saved for ${applied.email || CONFIG.GOOGLE_DRIVE_EMAIL}. You can return to Edupal.`,
    }));
  } catch (e) {
    console.error('Token exchange failed:', e);
    res.status(500).send(oauthResultPage({
      status: 'failed',
      title: 'Token exchange failed',
      message: 'Check server logs, then try again.',
    }));
  }
});

// --- Upload a file into a subject folder --------------------------------

app.post('/upload', requireAuth, (req, res) => {
  if (!driveIsConfigured()) {
    console.warn('Upload rejected: Drive OAuth is not configured');
    return res.status(503).json({ error: 'File upload failed' });
  }

  upload.single('file')(req, res, async (err) => {
    if (err) {
      console.error('Upload rejected:', err.message);
      return res.status(400).json({ error: 'File upload failed' });
    }
    if (!req.file) {
      console.warn('Upload rejected: missing file field');
      return res.status(400).json({ error: 'File upload failed' });
    }

    const { folderId } = req.body;
    const subjectOk = await isValidSubjectFolder(folderId);
    const clientOk = !subjectOk && (await userCanWriteClientFolder(req.user, folderId));
    if (!subjectOk && !clientOk) {
      console.warn(`Upload rejected: invalid folder ${folderId || '(empty)'}`);
      return res.status(403).json({ error: 'File upload failed' });
    }
    if (clientOk && isClientWorkspaceFolder(folderId)) {
      console.warn(`Upload rejected: client workspace root ${folderId}`);
      return res.status(403).json({ error: 'File upload failed' });
    }
    if (clientOk) {
      const quota = await assertClientStorageAllows(
        folderId,
        req.file.size || req.file.buffer.length
      );
      if (!quota.ok) {
        console.warn(
          `Upload rejected: client storage limit used=${quota.used} limit=${quota.limit}`
        );
        return res.status(403).json({
          error: 'Storage limit exceeded',
          usedBytes: quota.used,
          limitBytes: quota.limit,
        });
      }
    }

    try {
      const safeName = sanitizeFileName(req.file.originalname);
      if (await nameTakenInFolder(folderId, safeName, { isFolder: false })) {
        return res.status(409).json({ error: 'A file with that name already exists' });
      }

      const result = await uploadFile({
        fileName: req.file.originalname,
        buffer: req.file.buffer,
        folderId,
        uploadedBy: req.user.uid,
        mimeType: mimeFromFileName(req.file.originalname, req.file.mimetype),
        modifiedTime: req.body?.modifiedMs || req.body?.modifiedTime,
      });
      res.json(result);
    } catch (e) {
      console.error('Upload failed:', e);
      res.status(500).json({ error: 'File upload failed' });
    }
  });
});

// --- Create a folder within a subject folder ---------------------------

app.post('/folders', requireAuth, async (req, res) => {
  if (!driveIsConfigured()) {
    console.warn('Folder create rejected: Drive OAuth is not configured');
    return res.status(503).json({ error: 'Could not create the folder' });
  }

  const { name, parentFolderId } = req.body;

  if (!name || typeof name !== 'string' || !name.trim()) {
    console.warn('Folder create rejected: empty name');
    return res.status(400).json({ error: 'Could not create the folder' });
  }
  const semesterParentOk = await isValidCreateParent(parentFolderId);
  const clientParentOk =
    !semesterParentOk && (await userCanWriteClientFolder(req.user, parentFolderId));
  if (!semesterParentOk && !clientParentOk) {
    console.warn(`Folder create rejected: invalid parent ${parentFolderId || '(empty)'}`);
    return res.status(403).json({ error: 'Could not create the folder' });
  }

  try {
    const safeName = sanitizeFileName(name);
    if (await nameTakenInFolder(parentFolderId, safeName, { isFolder: true })) {
      return res.status(409).json({ error: 'A folder with that name already exists' });
    }

    const folder = await createFolder(name, parentFolderId);
    res.json(folder);
  } catch (e) {
    console.error('Folder creation failed:', e);
    res.status(500).json({ error: 'Could not create the folder' });
  }
});

// --- Create a course folder under Edupal with year/semester subfolders ---

app.post('/course-structure', requireAuth, requireSystemAdmin, async (req, res) => {
  if (!driveIsConfigured()) {
    console.warn('Course structure rejected: Drive OAuth is not configured');
    return res.status(503).json({ error: 'Could not create the course' });
  }

  const { name, years } = req.body || {};
  const yearCount = Number(years);

  if (!name || typeof name !== 'string' || !name.trim()) {
    console.warn('Course structure rejected: empty name');
    return res.status(400).json({ error: 'Could not create the course' });
  }
  if (!Number.isInteger(yearCount) || yearCount < 1 || yearCount > 10) {
    console.warn(`Course structure rejected: invalid years ${years}`);
    return res.status(400).json({ error: 'Could not create the course' });
  }

  try {
    const structure = await createCourseStructure(name.trim(), yearCount);
    res.json(structure);
  } catch (e) {
    console.error('Course structure creation failed:', e);
    res.status(500).json({ error: 'Could not create the course' });
  }
});

// --- Create a client workspace folder under Edupal/clients (system admin) ---

app.post('/client-workspace', requireAuth, requireSystemAdmin, async (req, res) => {
  if (!driveIsConfigured()) {
    console.warn('Client workspace rejected: Drive OAuth is not configured');
    return res.status(503).json({ error: 'Could not create the client workspace' });
  }

  const { name } = req.body || {};
  if (!name || typeof name !== 'string' || !name.trim()) {
    console.warn('Client workspace rejected: empty name');
    return res.status(400).json({ error: 'Could not create the client workspace' });
  }

  try {
    const workspace = await createClientWorkspaceFolder(name.trim());
    res.json(workspace);
  } catch (e) {
    console.error('Client workspace creation failed:', e);
    res.status(500).json({ error: 'Could not create the client workspace' });
  }
});

app.patch('/client-workspace/:folderId', requireAuth, requireSystemAdmin, async (req, res) => {
  if (!driveIsConfigured()) {
    console.warn('Client rename rejected: Drive OAuth is not configured');
    return res.status(503).json({ error: 'Rename failed' });
  }

  const { folderId } = req.params;
  const { name } = req.body || {};
  if (!folderId || !isClientWorkspaceFolder(folderId)) {
    console.warn(`Client rename rejected: invalid folder ${folderId || '(empty)'}`);
    return res.status(403).json({ error: 'Rename failed' });
  }
  if (!name || typeof name !== 'string' || !name.trim()) {
    console.warn('Client rename rejected: empty name');
    return res.status(400).json({ error: 'Rename failed' });
  }

  try {
    const result = await renameItem(folderId, name.trim());
    res.json(result);
  } catch (e) {
    console.error('Client workspace rename failed:', e);
    res.status(500).json({ error: 'Rename failed' });
  }
});

app.delete('/client-workspace/:folderId', requireAuth, requireSystemAdmin, async (req, res) => {
  if (!driveIsConfigured()) {
    console.warn('Client delete rejected: Drive OAuth is not configured');
    return res.status(503).json({ error: 'Delete failed' });
  }

  const { folderId } = req.params;
  if (!folderId || !isClientWorkspaceFolder(folderId)) {
    console.warn(`Client delete rejected: invalid folder ${folderId || '(empty)'}`);
    return res.status(403).json({ error: 'Delete failed' });
  }

  try {
    await deleteItem(folderId);
    forgetClientWorkspaceId(folderId);
    res.json({ deleted: true, folderId });
  } catch (e) {
    console.error('Client workspace delete failed:', e);
    res.status(500).json({ error: 'Delete failed' });
  }
});

// --- Rename the main course folder under Edupal (system admin) ------------

app.patch('/course-folder/:folderId', requireAuth, requireSystemAdmin, async (req, res) => {
  if (!driveIsConfigured()) {
    console.warn('Course rename rejected: Drive OAuth is not configured');
    return res.status(503).json({ error: 'Rename failed' });
  }

  const { folderId } = req.params;
  const { name } = req.body || {};

  if (!folderId) {
    console.warn('Course rename rejected: missing folderId');
    return res.status(400).json({ error: 'Rename failed' });
  }
  if (!name || typeof name !== 'string' || !name.trim()) {
    console.warn('Course rename rejected: empty name');
    return res.status(400).json({ error: 'Rename failed' });
  }

  const courseFolderId = await resolveCourseFolderId(folderId);
  if (!courseFolderId) {
    console.warn(`Course rename rejected: invalid folder ${folderId}`);
    return res.status(403).json({ error: 'Rename failed' });
  }

  try {
    const result = await renameItem(courseFolderId, name.trim());
    res.json(result);
  } catch (e) {
    console.error('Course folder rename failed:', e);
    res.status(500).json({ error: 'Rename failed' });
  }
});

// --- Delete the course folder and all nested Drive folders (system admin) --

app.delete('/course-folder/:folderId', requireAuth, requireSystemAdmin, async (req, res) => {
  if (!driveIsConfigured()) {
    console.warn('Course delete rejected: Drive OAuth is not configured');
    return res.status(503).json({ error: 'Delete failed' });
  }

  const { folderId } = req.params;
  if (!folderId) {
    console.warn('Course delete rejected: missing folderId');
    return res.status(400).json({ error: 'Delete failed' });
  }

  const courseFolderId = await resolveCourseFolderId(folderId);
  if (!courseFolderId) {
    console.warn(`Course delete rejected: invalid folder ${folderId}`);
    return res.status(403).json({ error: 'Delete failed' });
  }

  try {
    await forgetCourseSemesterIds(courseFolderId);
    await deleteItem(courseFolderId);
    res.json({ deleted: true, courseFolderId });
  } catch (e) {
    console.error('Course folder delete failed:', e);
    res.status(500).json({ error: 'Delete failed' });
  }
});

function googlePhotoFromAuthUser(user) {
  const providers = user.providerData || [];
  const google = providers.find((p) => p.providerId === 'google.com');
  const url = (google && google.photoURL) || user.photoURL || '';
  return String(url).trim();
}

app.get('/users/auth-photos', requireAuth, requireSystemAdmin, async (req, res) => {
  try {
    const photos = {};
    let pageToken;
    do {
      const result = await admin.auth().listUsers(1000, pageToken);
      for (const user of result.users) {
        const url = googlePhotoFromAuthUser(user);
        if (url) photos[user.uid] = url;
      }
      pageToken = result.pageToken;
    } while (pageToken);
    res.json({ photos });
  } catch (e) {
    console.error('Auth photo list failed:', e);
    res.status(500).json({ error: 'Could not load user photos' });
  }
});

// --- Delete a user profile + Firebase Auth account (system admin) ---------

app.delete('/users/:uid', requireAuth, requireSystemAdmin, async (req, res) => {
  const uid = String(req.params.uid || '').trim();
  if (!uid) {
    return res.status(400).json({ error: 'Delete failed' });
  }
  if (uid === req.user.uid) {
    return res.status(400).json({ error: 'You cannot delete your own account.' });
  }

  try {
    const snap = await firestore.collection('profiles').doc(uid).get();
    const profileEmail = String(snap.data()?.email || '').toLowerCase();

    let authEmail = '';
    try {
      const authUser = await admin.auth().getUser(uid);
      authEmail = String(authUser.email || '').toLowerCase();
    } catch (err) {
      if (err.code !== 'auth/user-not-found') throw err;
    }

    if (
      isConfiguredSystemAdminEmail(profileEmail) ||
      isConfiguredSystemAdminEmail(authEmail)
    ) {
      return res.status(403).json({ error: 'This account cannot be deleted.' });
    }

    try {
      await admin.auth().deleteUser(uid);
    } catch (err) {
      if (err.code !== 'auth/user-not-found') throw err;
    }

    await deleteProfileAvatar(snap.data());
    await firestore.collection('profiles').doc(uid).delete();
    res.json({ deleted: true, uid });
  } catch (e) {
    console.error('User delete failed:', e);
    res.status(500).json({ error: 'Delete failed' });
  }
});

// --- Rename a file or folder (admin-only by default) --------------------

// Drive thumbnailLink URLs expire and often 403 in the browser. Proxy them
// through the backend so folder cards can show real file previews.
app.get('/files/:fileId/thumbnail', requireAuth, async (req, res) => {
  if (!driveIsConfigured() && !driveReadIsConfigured()) {
    console.warn('Thumbnail rejected: Drive is not configured');
    return res.status(503).json({ error: 'Could not load preview' });
  }

  const { fileId } = req.params;
  if (!fileId) {
    console.warn('Thumbnail rejected: missing fileId');
    return res.status(400).json({ error: 'Could not load preview' });
  }

  try {
    let thumbnailLink = '';
    if (driveIsConfigured()) {
      try {
        const meta = await drive.files.get({
          fileId,
          fields: 'thumbnailLink,hasThumbnail',
          supportsAllDrives: true,
        });
        thumbnailLink = meta.data.thumbnailLink || '';
      } catch (err) {
        console.warn(`OAuth thumbnail meta failed for ${fileId}:`, err.message);
      }
    }
    if (!thumbnailLink && driveReadIsConfigured()) {
      const meta = await driveGetMeta(fileId, 'thumbnailLink,hasThumbnail', driveReadKey());
      thumbnailLink = meta.thumbnailLink || '';
    }
    if (!thumbnailLink) {
      console.warn(`Thumbnail missing for ${fileId}`);
      return res.status(404).json({ error: 'Could not load preview' });
    }

    const url = thumbnailLink.replace(/=s\d+/, '=s400');
    const thumbRes = await fetch(url);
    if (!thumbRes.ok) {
      console.error(`Thumbnail fetch failed for ${fileId}:`, thumbRes.status);
      return res.status(thumbRes.status).json({ error: 'Could not load preview' });
    }

    const contentType = thumbRes.headers.get('content-type') || 'image/jpeg';
    res.setHeader('Content-Type', contentType);
    res.setHeader('Cache-Control', 'private, max-age=3600');
    res.send(Buffer.from(await thumbRes.arrayBuffer()));
  } catch (e) {
    console.error('Thumbnail failed:', e);
    res.status(500).json({ error: 'Could not load preview' });
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
  if (!driveIsConfigured() && !driveDownloadIsConfigured()) {
    console.warn('Download rejected: Drive is not configured');
    return res.status(503).json({ error: 'Download failed' });
  }

  const { fileId } = req.params;
  if (!fileId) {
    console.warn('Download rejected: missing fileId');
    return res.status(400).json({ error: 'Download failed' });
  }

  const apiKey = driveDownloadIsConfigured() ? driveDownloadKey() : '';
  const range = req.headers.range;

  try {
    if (!(await isManagedItem(fileId))) {
      console.warn(`Download rejected: unmanaged file ${fileId}`);
      return res.status(403).json({ error: 'Download failed' });
    }

    let meta;
    if (driveIsConfigured()) {
      const got = await drive.files.get({
        fileId,
        fields: 'id, name, mimeType, size, webContentLink, exportLinks',
        supportsAllDrives: true,
      });
      meta = got.data;
    } else {
      meta = await driveGetMeta(
        fileId,
        'id, name, mimeType, size, webContentLink, exportLinks',
        apiKey
      );
    }

    const sourceMime = meta.mimeType || 'application/octet-stream';
    const sourceName = meta.name || 'download';
    const isGoogleApp = sourceMime.startsWith('application/vnd.google-apps.');
    const isMedia =
      sourceMime.startsWith('video/') || sourceMime.startsWith('audio/');

    let downloadMime = sourceMime;
    let downloadName = sourceName;
    if (isGoogleApp) {
      const exported = googleExportFor(sourceMime, sourceName);
      downloadMime = exported.mime;
      downloadName = exported.name;
    }

    const disposition = isMedia
      ? `inline; filename="${sanitizeFileName(downloadName).replace(/"/g, '')}"`
      : contentDispositionAttachment(downloadName);

    if (driveIsConfigured() && !isGoogleApp) {
      try {
        const opts = { responseType: 'stream' };
        if (range) opts.headers = { Range: range };
        const driveRes = await drive.files.get(
          { fileId, alt: 'media', supportsAllDrives: true },
          opts
        );
        const status = driveRes.status || (range ? 206 : 200);
        res.status(status);
        res.setHeader('Content-Type', downloadMime);
        res.setHeader('Content-Disposition', disposition);
        res.setHeader('Accept-Ranges', 'bytes');
        res.setHeader('Cache-Control', 'private, no-store');
        const headers = driveRes.headers || {};
        if (headers['content-range']) {
          res.setHeader('Content-Range', headers['content-range']);
        }
        if (headers['content-length']) {
          res.setHeader('Content-Length', headers['content-length']);
        } else if (!range && meta.size) {
          res.setHeader('Content-Length', String(meta.size));
        }
        driveRes.data.on('error', (error) => {
          console.error('Download stream failed:', error);
          if (!res.headersSent) {
            res.status(500).json({ error: 'Download failed' });
          } else {
            res.destroy(error);
          }
        });
        driveRes.data.pipe(res);
        return;
      } catch (err) {
        console.warn(`OAuth media stream failed for ${fileId}:`, err.message);
      }
    }

    const downloadUrl = downloadUrlFromMeta(meta, apiKey, downloadMime);
    if (!downloadUrl) {
      console.warn(`Download rejected: no URL for ${fileId} mime=${sourceMime}`);
      return res.status(400).json({ error: 'Download failed' });
    }

    const upstreamHeaders = {};
    if (range) upstreamHeaders.Range = range;
    let fileRes = await fetch(downloadUrl, {
      redirect: 'follow',
      headers: upstreamHeaders,
    });
    const mediaUrl = driveMediaUrl(fileId, apiKey);
    if (!fileRes.ok && !isGoogleApp && downloadUrl !== mediaUrl) {
      fileRes = await fetch(mediaUrl, {
        redirect: 'follow',
        headers: upstreamHeaders,
      });
    }
    if (!fileRes.ok) {
      console.error('Download upstream failed:', fileRes.status, await fileRes.text().catch(() => ''));
      return res.status(fileRes.status === 404 ? 404 : 502).json({ error: 'Download failed' });
    }

    res.status(fileRes.status === 206 ? 206 : 200);
    res.setHeader('Content-Type', downloadMime);
    res.setHeader('Content-Disposition', disposition);
    res.setHeader('Accept-Ranges', 'bytes');
    const contentRange = fileRes.headers.get('content-range');
    if (contentRange) res.setHeader('Content-Range', contentRange);
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
      res.status(500).json({ error: 'Download failed' });
    }
  }
});

// --- Rename a file or folder (admin-only by default) --------------------

app.patch('/files/:fileId', requireAuth, requireAdmin, async (req, res) => {
  if (!driveIsConfigured()) {
    console.warn('Rename rejected: Drive OAuth is not configured');
    return res.status(503).json({ error: 'Rename failed' });
  }

  const { fileId } = req.params;
  const { name } = req.body || {};

  if (!fileId) {
    console.warn('Rename rejected: missing fileId');
    return res.status(400).json({ error: 'Rename failed' });
  }
  if (!name || typeof name !== 'string' || !name.trim()) {
    console.warn('Rename rejected: empty name');
    return res.status(400).json({ error: 'Rename failed' });
  }
  if (isSemesterFolder(fileId) || isClientWorkspaceFolder(fileId)) {
    console.warn(`Rename rejected: protected folder ${fileId}`);
    return res.status(403).json({ error: 'Rename failed' });
  }
  if (!(await isManagedItem(fileId))) {
    console.warn(`Rename rejected: unmanaged file ${fileId}`);
    return res.status(403).json({ error: 'Rename failed' });
  }

  try {
    const current = await drive.files.get({
      fileId,
      fields: 'id, name, mimeType, parents',
      supportsAllDrives: true,
    });
    const safeName = sanitizeFileName(name);
    const isFolder = current.data.mimeType === FOLDER_MIME;
    const parents = current.data.parents || [];
    for (const parentId of parents) {
      if (await nameTakenInFolder(parentId, safeName, { ignoreId: fileId, isFolder })) {
        return res.status(409).json({
          error: isFolder
            ? 'A folder with that name already exists'
            : 'A file with that name already exists',
        });
      }
    }

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
    console.warn('Delete rejected: Drive OAuth is not configured');
    return res.status(503).json({ error: 'Delete failed' });
  }

  const { fileId } = req.params;
  if (!fileId) {
    console.warn('Delete rejected: missing fileId');
    return res.status(400).json({ error: 'Delete failed' });
  }
  if (isSemesterFolder(fileId) || isClientWorkspaceFolder(fileId)) {
    console.warn(`Delete rejected: protected folder ${fileId}`);
    return res.status(403).json({ error: 'Delete failed' });
  }
  if (!(await isManagedItem(fileId))) {
    console.warn(`Delete rejected: unmanaged file ${fileId}`);
    return res.status(403).json({ error: 'Delete failed' });
  }

  try {
    await deleteItem(fileId);
    await forgetFolderLock(fileId);
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

app.get('/client-folder-locks', requireAuth, async (req, res) => {
  const workspaceFolderId = String(req.query.workspaceFolderId || '');
  if (!(await userCanWriteClientFolder(req.user, workspaceFolderId))) {
    return res.status(403).json({ error: 'Could not load folder locks' });
  }
  const workspaceId = await resolveClientWorkspaceId(workspaceFolderId);
  if (!workspaceId) {
    return res.status(403).json({ error: 'Could not load folder locks' });
  }
  try {
    const snap = await FOLDER_LOCKS().where('workspaceId', '==', workspaceId).get();
    res.json({ folderIds: snap.docs.map((doc) => doc.id) });
  } catch (e) {
    console.error('Folder lock list failed:', e);
    res.status(500).json({ error: 'Could not load folder locks' });
  }
});

app.post('/client-folders/:folderId/lock', requireAuth, async (req, res) => {
  const { folderId } = req.params;
  const password = normalizeFolderPassword(req.body?.password);
  const access = await assertLockableClientFolder(req.user, folderId);
  if (!access.ok) {
    return res.status(access.status).json({ error: access.error });
  }
  if (!folderPasswordLengthOk(password)) {
    return res.status(400).json({
      error: `Password must be ${FOLDER_PASSWORD_MIN}–${FOLDER_PASSWORD_MAX} characters`,
    });
  }

  try {
    const existing = await FOLDER_LOCKS().doc(folderId).get();
    if (existing.exists) {
      return res.status(409).json({ error: 'This folder is already locked' });
    }
    const hashed = await hashFolderPassword(password);
    await FOLDER_LOCKS().doc(folderId).set({
      workspaceId: access.workspaceId,
      salt: hashed.salt,
      hash: hashed.hash,
      lockedBy: req.user.uid,
      lockedAt: admin.firestore.FieldValue.serverTimestamp(),
    });
    res.json({ locked: true, folderId });
  } catch (e) {
    console.error('Folder lock failed:', e);
    res.status(500).json({ error: 'Could not lock this folder' });
  }
});

app.post('/client-folders/:folderId/unlock', requireAuth, async (req, res) => {
  const { folderId } = req.params;
  const password = normalizeFolderPassword(req.body?.password);
  const removeLock = req.body?.remove === true || req.body?.remove === 'true';
  const access = await assertLockableClientFolder(req.user, folderId);
  if (!access.ok) {
    return res.status(access.status).json({ error: access.error });
  }

  try {
    const snap = await FOLDER_LOCKS().doc(folderId).get();
    if (!snap.exists) {
      return res.json({ locked: false, folderId, unlocked: true });
    }
    if (!password) {
      return res.status(400).json({ error: 'Enter the folder password' });
    }
    if (!(await folderPasswordMatches(snap.data(), password))) {
      return res.status(403).json({ error: 'Incorrect password' });
    }
    if (removeLock) {
      await FOLDER_LOCKS().doc(folderId).delete();
      return res.json({ locked: false, folderId, unlocked: true });
    }
    res.json({ locked: true, folderId, unlocked: true });
  } catch (e) {
    console.error('Folder unlock check failed:', e);
    res.status(500).json({ error: 'Could not unlock this folder' });
  }
});

app.get('/folders/:folderId', requireAuth, async (req, res) => {
  if (!driveReadIsConfigured()) {
    console.warn('Folder list rejected: GOOGLE_DRIVE_API_KEY is missing');
    return res.status(503).json({ error: 'Could not load this folder' });
  }

  const { folderId } = req.params;
  if (!folderId) {
    console.warn('Folder list rejected: missing folderId');
    return res.status(400).json({ error: 'Could not load this folder' });
  }

  const apiKey = driveReadKey();
  const semesterOk =
    isSemesterFolder(folderId) || (await isValidSubjectFolder(folderId));
  const clientOk = !semesterOk && (await userCanWriteClientFolder(req.user, folderId));
  if (!semesterOk && !clientOk) {
    console.warn(`Folder list rejected: invalid folder ${folderId}`);
    return res.status(403).json({ error: 'Could not load this folder' });
  }

  try {
    const children = await listDirectChildren(folderId, { apiKey });
    const folders = [];
    const files = [];
    for (const item of children) {
      const listed = asListedDriveItem(item);
      if (item.mimeType === FOLDER_MIME) folders.push(listed);
      else files.push(listed);
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
    res.status(500).json({ error: 'Could not load this folder' });
  }
});

// --- AI chat (NVIDIA Llama vision) --------------------------------------

registerAiRoutes(app, { requireAuth });
registerMediaRoutes(app, { requireAuth, requireSystemAdmin, upload });
registerContactRoutes(app, { oauth2Client });

// --- Fallback error handler --------------------------------------------

app.use((err, req, res, next) => {
  console.error('[express]', err.message || err);
  res.status(500).json({ error: 'Something went wrong.' });
});

initDriveAuth().then(async () => {
  try {
    await syncEngineeringCourseToFirestore();
  } catch (err) {
    console.error('Failed to sync Engineering Drive folders to Firestore:', err.message);
  }
  await loadSemesterIdsFromFirestore();
  try {
    await ensureClientsRootFolder();
  } catch (err) {
    console.error('Failed to ensure Edupal/clients folder:', err.message);
  }
  await loadClientWorkspaceIdsFromFirestore();
  await promoteEnvSystemAdminOnStartup();
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