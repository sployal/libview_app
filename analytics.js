const path = require('path');

const FILE_TYPES = ['video', 'audio', 'image', 'pdf', 'word', 'excel', 'ppt', 'other'];
const DOCUMENT_TYPES = ['pdf', 'word', 'excel', 'ppt'];
const VIDEO_EXT = new Set([
  'mp4', 'm4v', 'mov', 'avi', 'mkv', 'webm', '3gp', '3g2', 'wmv', 'flv',
  'mpeg', 'mpg', 'ts', 'm2ts', 'mts', 'ogv', 'asf', 'vob', 'f4v',
]);
const AUDIO_EXT = new Set([
  'mp3', 'wav', 'aac', 'm4a', 'flac', 'ogg', 'oga', 'opus', 'wma',
  'aiff', 'aif', 'amr', 'mid', 'midi', 'caf', 'weba',
]);
const IMAGE_EXT = new Set([
  'jpg', 'jpeg', 'png', 'gif', 'webp', 'bmp', 'heic', 'heif', 'svg', 'tif', 'tiff',
]);
const WORD_EXT = new Set(['doc', 'docx', 'rtf', 'odt']);
const EXCEL_EXT = new Set(['xls', 'xlsx', 'csv', 'ods']);
const PPT_EXT = new Set(['ppt', 'pptx', 'pps', 'odp']);
const LAST_SEEN_MS = 10 * 60 * 1000;
const CATALOG_MS = 5 * 60 * 1000;
const MONTH_NAMES = [
  'January', 'February', 'March', 'April', 'May', 'June',
  'July', 'August', 'September', 'October', 'November', 'December',
];

function createAnalytics({ firestore, admin, drive, resolveClientWorkspaceId }) {
  const increment = (value) => admin.firestore.FieldValue.increment(value);
  const timestamp = () => admin.firestore.FieldValue.serverTimestamp();
  const lastSeenCache = new Map();
  const folderOwnerCache = new Map();
  let catalog = { at: 0, courses: [], clients: [], folderToOwner: new Map() };

  function nairobiKey(date = new Date()) {
    return new Intl.DateTimeFormat('en-CA', {
      timeZone: 'Africa/Nairobi',
      year: 'numeric',
      month: '2-digit',
      day: '2-digit',
    }).format(date);
  }

  function nairobiParts(date = new Date()) {
    const parts = new Intl.DateTimeFormat('en-US', {
      timeZone: 'Africa/Nairobi',
      year: 'numeric',
      month: '2-digit',
      day: '2-digit',
    }).formatToParts(date);
    const get = (type) => {
      const part = parts.find((item) => item.type === type);
      return part ? Number(part.value) : 0;
    };
    return { year: get('year'), month: get('month'), day: get('day') };
  }

  function nairobiDate(key, endOfDay = false) {
    return new Date(`${key}T${endOfDay ? '23:59:59.999' : '00:00:00'}+03:00`);
  }

  function daysInMonth(year, month) {
    return new Date(year, month, 0).getDate();
  }

  function asDate(value) {
    if (!value) return null;
    if (typeof value.toDate === 'function') return value.toDate();
    if (typeof value._seconds === 'number') return new Date(value._seconds * 1000);
    if (typeof value.seconds === 'number') return new Date(value.seconds * 1000);
    const date = new Date(value);
    return Number.isNaN(date.getTime()) ? null : date;
  }

  function inRange(date, start, end) {
    if (!date) return false;
    if (start && date < start) return false;
    if (end && date > end) return false;
    return true;
  }

  function num(value) {
    const parsed = Number(value);
    return Number.isFinite(parsed) ? parsed : 0;
  }

  function safeField(value, fallback = 'other') {
    const cleaned = String(value || fallback)
      .trim()
      .replace(/[./[\]]/g, '_')
      .slice(0, 80);
    return cleaned || fallback;
  }

  function admissionPrefix(value) {
    const trimmed = String(value || '').trim().toUpperCase();
    if (!trimmed) return '';
    const slash = trimmed.search(/[\\/]/);
    return (slash >= 0 ? trimmed.slice(0, slash) : trimmed).trim();
  }

  function clientPlatform(req) {
    const header = String(
      req.headers['x-client-platform'] ||
        req.query?.platform ||
        req.body?.platform ||
        '',
    ).toLowerCase();
    if (header === 'web' || header === 'mobile') return header;
    const ua = String(req.headers['user-agent'] || '').toLowerCase();
    if (
      ua.includes('dart') ||
      ua.includes('okhttp') ||
      ua.includes('edupal-mobile') ||
      ua.includes('flutter')
    ) {
      return 'mobile';
    }
    return 'web';
  }

  function classifyFile(name, mimeType) {
    const mime = String(mimeType || '').toLowerCase();
    const ext = path.extname(name || '').slice(1).toLowerCase();

    if (mime.startsWith('video/') || VIDEO_EXT.has(ext)) return 'video';
    if (mime.startsWith('audio/') || AUDIO_EXT.has(ext)) return 'audio';
    if (mime.startsWith('image/') || IMAGE_EXT.has(ext)) return 'image';
    if (mime === 'application/pdf' || ext === 'pdf') return 'pdf';
    if (
      WORD_EXT.has(ext) ||
      mime.includes('wordprocessing') ||
      mime === 'application/msword' ||
      mime.includes('google-apps.document')
    ) {
      return 'word';
    }
    if (
      EXCEL_EXT.has(ext) ||
      mime.includes('spreadsheet') ||
      mime.includes('ms-excel')
    ) {
      return 'excel';
    }
    if (
      PPT_EXT.has(ext) ||
      mime.includes('presentation') ||
      mime.includes('ms-powerpoint')
    ) {
      return 'ppt';
    }
    return 'other';
  }

  function isMediaType(fileType) {
    return fileType === 'video' || fileType === 'audio';
  }

  function playbackKind(event) {
    const kind = event?.kind;
    if (kind !== 'download') return kind;
    if (event.saved || event.intent === 'download' || event.source === 'save') {
      return 'download';
    }
    const type = FILE_TYPES.includes(event.fileType)
      ? event.fileType
      : classifyFile(event.fileName, event.mimeType);
    return isMediaType(type) ? 'stream' : 'download';
  }

  function normalizeMediaPlays(bucket) {
    if (!bucket?.types) return bucket;
    bucket.bytesStreamed = num(bucket.bytesStreamed);
    const usesStreamBytes =
      bucket.bytesStreamed > 0 ||
      ['video', 'audio'].some((type) => num(bucket.types[type]?.bytesStreamed) > 0);
    if (usesStreamBytes) return bucket;
    for (const type of ['video', 'audio']) {
      const stats = bucket.types[type];
      if (!stats) continue;
      const extra = num(stats.downloads);
      const leftover = num(stats.bytesDownloaded);
      if (extra) {
        stats.streams = num(stats.streams) + extra;
        stats.downloads = 0;
        bucket.streams = num(bucket.streams) + extra;
        bucket.downloads = Math.max(0, num(bucket.downloads) - extra);
      }
      if (!leftover) continue;
      stats.bytesStreamed = num(stats.bytesStreamed) + leftover;
      stats.bytesDownloaded = 0;
      bucket.bytesStreamed += leftover;
      bucket.bytesDownloaded = Math.max(0, num(bucket.bytesDownloaded) - leftover);
    }
    return bucket;
  }

  function emptyTypes() {
    return Object.fromEntries(
      FILE_TYPES.map((type) => [
        type,
        { uploads: 0, downloads: 0, streams: 0, bytesUploaded: 0, bytesDownloaded: 0, bytesStreamed: 0 },
      ]),
    );
  }

  function emptyBucket() {
    return {
      uploads: 0,
      downloads: 0,
      streams: 0,
      bytesUploaded: 0,
      bytesDownloaded: 0,
      bytesStreamed: 0,
      activeUsers: 0,
      types: emptyTypes(),
      courses: {},
      clients: {},
      other: { uploads: 0, downloads: 0, streams: 0, bytesUploaded: 0, bytesDownloaded: 0, bytesStreamed: 0 },
    };
  }

  function mergeOwnerMap(raw) {
    const out = {};
    if (!raw || typeof raw !== 'object') return out;
    for (const [id, value] of Object.entries(raw)) {
      if (!value || typeof value !== 'object') continue;
      out[id] = {
        uploads: num(value.uploads),
        downloads: num(value.downloads),
        streams: num(value.streams),
        bytesUploaded: num(value.bytesUploaded),
        bytesDownloaded: num(value.bytesDownloaded),
        bytesStreamed: num(value.bytesStreamed),
      };
    }
    return out;
  }

  function setDeep(target, parts, value) {
    let current = target;
    for (let i = 0; i < parts.length - 1; i += 1) {
      const key = parts[i];
      if (!current[key] || typeof current[key] !== 'object') current[key] = {};
      current = current[key];
    }
    current[parts[parts.length - 1]] = value;
  }

  function readPrefixed(data, prefix) {
    if (!data || typeof data !== 'object') return {};
    const nested = data[prefix];
    if (nested && typeof nested === 'object' && !Array.isArray(nested)) {
      return nested;
    }
    const out = {};
    const start = `${prefix}.`;
    for (const [key, value] of Object.entries(data)) {
      if (!key.startsWith(start)) continue;
      setDeep(out, key.slice(start.length).split('.'), value);
    }
    return out;
  }

  function extractBucket(data, prefix) {
    const src = readPrefixed(data, prefix);
    const types = emptyTypes();
    const rawTypes = src.types && typeof src.types === 'object' ? src.types : {};
    for (const type of FILE_TYPES) {
      const item = rawTypes[type] || {};
      types[type] = {
        uploads: num(item.uploads),
        downloads: num(item.downloads),
        streams: num(item.streams),
        bytesUploaded: num(item.bytesUploaded),
        bytesDownloaded: num(item.bytesDownloaded),
        bytesStreamed: num(item.bytesStreamed),
      };
    }
    const bucket = {
      uploads: num(src.uploads),
      downloads: num(src.downloads),
      streams: num(src.streams),
      bytesUploaded: num(src.bytesUploaded),
      bytesDownloaded: num(src.bytesDownloaded),
      bytesStreamed: num(src.bytesStreamed),
      activeUsers: num(src.activeUsers),
      types,
      courses: mergeOwnerMap(src.courses),
      clients: mergeOwnerMap(src.clients),
      other: {
        uploads: num(src.other?.uploads),
        downloads: num(src.other?.downloads),
        streams: num(src.other?.streams),
        bytesUploaded: num(src.other?.bytesUploaded),
        bytesDownloaded: num(src.other?.bytesDownloaded),
        bytesStreamed: num(src.other?.bytesStreamed),
      },
    };
    return normalizeMediaPlays(bucket);
  }

  function emptyOwnerStats() {
    return {
      uploads: 0,
      downloads: 0,
      streams: 0,
      bytesUploaded: 0,
      bytesDownloaded: 0,
      bytesStreamed: 0,
    };
  }

  function emptyAiStats() {
    return {
      requests: 0,
      promptTokens: 0,
      completionTokens: 0,
      totalTokens: 0,
    };
  }

  function isAiStatsShape(value) {
    return Boolean(
      value &&
        typeof value === 'object' &&
        !Array.isArray(value) &&
        ('requests' in value ||
          'promptTokens' in value ||
          'completionTokens' in value ||
          'totalTokens' in value),
    );
  }

  function mergeAiStats(value) {
    const out = emptyAiStats();
    if (!value || typeof value !== 'object') return out;
    out.requests = num(value.requests);
    out.promptTokens = num(value.promptTokens);
    out.completionTokens = num(value.completionTokens);
    out.totalTokens = num(value.totalTokens);
    if (!out.totalTokens) out.totalTokens = out.promptTokens + out.completionTokens;
    return out;
  }

  function addAiStats(target, value) {
    const stats = mergeAiStats(value);
    target.requests += stats.requests;
    target.promptTokens += stats.promptTokens;
    target.completionTokens += stats.completionTokens;
    target.totalTokens += stats.totalTokens;
    return target;
  }

  function mergeAiOwnerMap(raw) {
    const out = {};
    if (!raw || typeof raw !== 'object') return out;
    for (const [id, value] of Object.entries(raw)) {
      if (!isAiStatsShape(value)) continue;
      const stats = mergeAiStats(value);
      if (stats.requests || stats.totalTokens) out[id] = stats;
    }
    return out;
  }

  function aggregateAiMap(raw) {
    if (isAiStatsShape(raw)) return mergeAiStats(raw);
    const out = emptyAiStats();
    if (!raw || typeof raw !== 'object') return out;
    for (const value of Object.values(raw)) {
      addAiStats(out, value);
    }
    return out;
  }

  function extractAi(data, prefix) {
    const src = readPrefixed(data, prefix);
    const ai = src.ai && typeof src.ai === 'object' ? src.ai : {};
    const courses = mergeAiOwnerMap(ai.courses);
    const clients = aggregateAiMap(ai.clients);
    const other = mergeAiStats(ai.other);
    const totals = mergeAiStats(ai);
    if (!totals.requests && !totals.totalTokens) {
      Object.values(courses).forEach((stats) => addAiStats(totals, stats));
      addAiStats(totals, clients);
      addAiStats(totals, other);
    }
    return { ...totals, courses, clients, other };
  }

  function aiIncrements(platform, owner, usage) {
    const updates = {};
    const prompt = Math.max(0, Math.round(num(usage?.promptTokens)));
    const completion = Math.max(0, Math.round(num(usage?.completionTokens)));
    const total = Math.max(
      0,
      Math.round(num(usage?.totalTokens) || prompt + completion),
    );
    const ownerPath =
      owner.kind === 'course'
        ? `courses.${safeField(owner.id, 'course')}`
        : owner.kind === 'client'
          ? 'clients'
          : 'other';

    for (const prefix of [platform, 'all']) {
      updates[`${prefix}.ai.requests`] = increment(1);
      updates[`${prefix}.ai.promptTokens`] = increment(prompt);
      updates[`${prefix}.ai.completionTokens`] = increment(completion);
      updates[`${prefix}.ai.totalTokens`] = increment(total);
      updates[`${prefix}.ai.${ownerPath}.requests`] = increment(1);
      updates[`${prefix}.ai.${ownerPath}.promptTokens`] = increment(prompt);
      updates[`${prefix}.ai.${ownerPath}.completionTokens`] = increment(completion);
      updates[`${prefix}.ai.${ownerPath}.totalTokens`] = increment(total);
    }

    if (owner.kind === 'course') {
      updates[`courseNames.${safeField(owner.id, 'course')}`] = owner.name || owner.id;
    }
    return updates;
  }

  function applyEventToBucket(bucket, event) {
    const kind = playbackKind(event);
    if (kind !== 'upload' && kind !== 'download' && kind !== 'stream') return;
    const count = countField(kind);
    const traffic = bytesField(kind);
    const bytes = num(event.sizeBytes);
    const type = FILE_TYPES.includes(event.fileType) ? event.fileType : 'other';
    bucket[count] = num(bucket[count]) + 1;
    bucket[traffic] = num(bucket[traffic]) + bytes;
    bucket.types[type][count] = num(bucket.types[type][count]) + 1;
    bucket.types[type][traffic] = num(bucket.types[type][traffic]) + bytes;

    const ownerKind = event.ownerKind || 'other';
    const ownerId = String(event.ownerId || 'other');
    if (ownerKind === 'course') {
      if (!bucket.courses[ownerId]) bucket.courses[ownerId] = emptyOwnerStats();
      bucket.courses[ownerId][count] += 1;
      bucket.courses[ownerId][traffic] += bytes;
    } else if (ownerKind === 'client') {
      if (!bucket.clients[ownerId]) bucket.clients[ownerId] = emptyOwnerStats();
      bucket.clients[ownerId][count] += 1;
      bucket.clients[ownerId][traffic] += bytes;
    } else {
      bucket.other[count] += 1;
      bucket.other[traffic] += bytes;
    }
  }

  function bucketHasTraffic(bucket) {
    return Boolean(
      bucket &&
        (bucket.uploads ||
          bucket.downloads ||
          bucket.streams ||
          bucket.bytesUploaded ||
          bucket.bytesDownloaded ||
          bucket.bytesStreamed),
    );
  }

  async function patchRollup(ref, extra, incrementMap) {
    const extraPayload = { ...extra, updatedAt: timestamp() };
    try {
      await ref.update({ ...incrementMap, ...extraPayload });
    } catch (err) {
      const missing =
        err.code === 5 ||
        err.code === 'not-found' ||
        /no document|NOT_FOUND/i.test(String(err.message || ''));
      if (!missing) throw err;
      await ref.set(extraPayload, { merge: true });
      await ref.update(incrementMap);
    }
  }

  function countField(kind) {
    if (kind === 'stream') return 'streams';
    if (kind === 'upload') return 'uploads';
    return 'downloads';
  }

  function bytesField(kind) {
    if (kind === 'upload') return 'bytesUploaded';
    if (kind === 'stream') return 'bytesStreamed';
    return 'bytesDownloaded';
  }

  function usageIncrements(platform, fileType, owner, bytes, kind) {
    const updates = {};
    const count = countField(kind);
    const traffic = bytesField(kind);
    const ownerPath =
      owner.kind === 'client'
        ? `clients.${safeField(owner.id, 'client')}`
        : owner.kind === 'course'
          ? `courses.${safeField(owner.id, 'course')}`
          : 'other';

    for (const prefix of [platform, 'all']) {
      updates[`${prefix}.${count}`] = increment(1);
      updates[`${prefix}.${traffic}`] = increment(bytes);
      updates[`${prefix}.types.${fileType}.${count}`] = increment(1);
      updates[`${prefix}.types.${fileType}.${traffic}`] = increment(bytes);
      updates[`${prefix}.${ownerPath}.${count}`] = increment(1);
      updates[`${prefix}.${ownerPath}.${traffic}`] = increment(bytes);
    }

    if (owner.kind === 'course') {
      updates[`courseNames.${safeField(owner.id, 'course')}`] = owner.name || owner.id;
    } else if (owner.kind === 'client') {
      updates[`clientNames.${safeField(owner.id, 'client')}`] = owner.name || owner.id;
    }
    return updates;
  }

  async function getCatalog() {
    if (Date.now() - catalog.at < CATALOG_MS && catalog.courses.length) {
      return catalog;
    }

    const [courseSnap, clientSnap] = await Promise.all([
      firestore.collection('courses').get(),
      firestore.collection('clients').get(),
    ]);

    const courses = [];
    const clients = [];
    const folderToOwner = new Map();

    courseSnap.forEach((doc) => {
      const data = doc.data() || {};
      const course = {
        id: doc.id,
        name: String(data.name || doc.id).trim() || doc.id,
        admissionPrefix: admissionPrefix(data.admission_prefix || data.sample_admission_number),
        driveFolderId: String(data.drive_folder_id || ''),
      };
      courses.push(course);
      if (course.driveFolderId) {
        folderToOwner.set(course.driveFolderId, {
          kind: 'course',
          id: course.id,
          name: course.name,
        });
      }
      const semesters = data.semesters || {};
      Object.values(semesters).forEach((semester) => {
        const folderId = semester && semester.folderId;
        if (typeof folderId === 'string' && folderId) {
          folderToOwner.set(folderId, { kind: 'course', id: course.id, name: course.name });
        }
      });
    });

    clientSnap.forEach((doc) => {
      const data = doc.data() || {};
      const client = {
        id: doc.id,
        name: String(data.name || doc.id).trim() || doc.id,
        driveFolderId: String(data.drive_folder_id || ''),
      };
      clients.push(client);
      if (client.driveFolderId) {
        folderToOwner.set(client.driveFolderId, {
          kind: 'client',
          id: client.id,
          name: client.name,
        });
      }
    });

    catalog = { at: Date.now(), courses, clients, folderToOwner };
    return catalog;
  }

  function matchUserCourse(profile, loaded) {
    const role = String(profile?.role || '').toLowerCase();
    if (role === 'client') {
      const client = loaded.clients.find((item) => item.id === profile.client_id);
      return {
        kind: 'client',
        id: client?.id || String(profile.client_id || 'client'),
        name: client?.name || 'Client',
      };
    }

    const prefix = admissionPrefix(profile?.admission_number);
    if (!prefix) {
      return { kind: 'other', id: 'unassigned', name: 'Unassigned' };
    }
    const course = loaded.courses.find((item) => item.admissionPrefix === prefix);
    if (!course) {
      return { kind: 'other', id: 'unassigned', name: 'Unassigned' };
    }
    return { kind: 'course', id: course.id, name: course.name };
  }

  async function resolveOwnerFromFolder(folderId) {
    if (!folderId) return { kind: 'other', id: 'other', name: 'Unassigned' };
    const cached = folderOwnerCache.get(folderId);
    if (cached && Date.now() - cached.at < CATALOG_MS) return cached.owner;

    const loaded = await getCatalog();
    if (loaded.folderToOwner.has(folderId)) {
      const owner = loaded.folderToOwner.get(folderId);
      folderOwnerCache.set(folderId, { at: Date.now(), owner });
      return owner;
    }

    if (typeof resolveClientWorkspaceId === 'function') {
      try {
        const workspaceId = await resolveClientWorkspaceId(folderId);
        if (workspaceId) {
          const client = loaded.clients.find((item) => item.driveFolderId === workspaceId);
          const owner = client
            ? { kind: 'client', id: client.id, name: client.name }
            : { kind: 'client', id: workspaceId, name: 'Client' };
          folderOwnerCache.set(folderId, { at: Date.now(), owner });
          return owner;
        }
      } catch (_) {
        // Fall through to Drive parent walk.
      }
    }

    if (drive) {
      let current = folderId;
      const seen = new Set();
      for (let i = 0; i < 8 && current && !seen.has(current); i += 1) {
        seen.add(current);
        if (loaded.folderToOwner.has(current)) {
          const owner = loaded.folderToOwner.get(current);
          folderOwnerCache.set(folderId, { at: Date.now(), owner });
          return owner;
        }
        try {
          const res = await drive.files.get({
            fileId: current,
            fields: 'id, parents',
            supportsAllDrives: true,
          });
          current = (res.data.parents || [])[0] || '';
        } catch (_) {
          break;
        }
      }
    }

    const owner = { kind: 'other', id: 'other', name: 'Unassigned' };
    folderOwnerCache.set(folderId, { at: Date.now(), owner });
    return owner;
  }

  async function loadProfile(uid) {
    if (!uid) return {};
    try {
      const snap = await firestore.collection('profiles').doc(uid).get();
      return snap.data() || {};
    } catch (_) {
      return {};
    }
  }

  async function recordUsage({
    req,
    kind,
    fileId,
    fileName,
    mimeType,
    sizeBytes,
    folderId,
    profile,
    saved,
  }) {
    const uid = req.user?.uid;
    if (!uid || !kind) return;

    const platform = clientPlatform(req);
    const bytes = Math.max(0, Math.round(num(sizeBytes)));
    const fileType = classifyFile(fileName, mimeType);
    const dateKey = nairobiKey();
    const monthKey = dateKey.slice(0, 7);
    const yearKey = dateKey.slice(0, 4);
    const loaded = await getCatalog();
    const userProfile = profile || (await loadProfile(uid));
    const userCourse = matchUserCourse(userProfile, loaded);
    let owner = await resolveOwnerFromFolder(folderId);
    if (owner.id === 'other' || owner.id === 'unassigned') {
      owner = userCourse;
    }

    if (kind === 'stream') {
      const streamRef = firestore
        .collection('analytics_stream_dedup')
        .doc(`${dateKey}_${uid}_${fileId || fileName || 'unknown'}`);
      const existing = await streamRef.get();
      if (existing.exists) return;
      await streamRef.set({
        uid,
        fileId: fileId || '',
        date: dateKey,
        at: timestamp(),
      });
    }

    const displayName =
      String(userProfile.full_name || '').trim() ||
      String(userProfile.username || '').trim() ||
      String(req.user.email || '').trim() ||
      'User';

    await firestore.collection('analytics_events').add({
      kind,
      platform,
      uid,
      email: String(req.user.email || userProfile.email || ''),
      name: displayName,
      role: String(userProfile.role || ''),
      fileId: fileId || '',
      fileType,
      sizeBytes: bytes,
      folderId: folderId || '',
      ownerKind: owner.kind,
      ownerId: owner.id,
      ownerName: owner.name,
      saved: Boolean(saved),
      createdAt: timestamp(),
      date: dateKey,
    });

    await Promise.all([
      patchRollup(
        firestore.collection('analytics_daily').doc(dateKey),
        { date: dateKey },
        usageIncrements(platform, fileType, owner, bytes, kind),
      ),
      patchRollup(
        firestore.collection('analytics_monthly').doc(monthKey),
        { month: monthKey },
        usageIncrements(platform, fileType, owner, bytes, kind),
      ),
      patchRollup(
        firestore.collection('analytics_yearly').doc(yearKey),
        { year: yearKey },
        usageIncrements(platform, fileType, owner, bytes, kind),
      ),
      patchRollup(
        firestore.collection('analytics_totals').doc('all'),
        {},
        usageIncrements(platform, fileType, owner, bytes, kind),
      ),
      patchRollup(
        firestore.collection('analytics_users').doc(uid),
        {
          name: displayName,
          email: String(req.user.email || userProfile.email || ''),
          role: String(userProfile.role || ''),
          ownerId: owner.id,
          ownerName: owner.name,
          lastPlatform: platform,
        },
        {
          [`${platform}.${countField(kind)}`]: increment(1),
          [`${platform}.${bytesField(kind)}`]: increment(bytes),
          [`all.${countField(kind)}`]: increment(1),
          [`all.${bytesField(kind)}`]: increment(bytes),
        },
      ),
    ]);
  }

  async function recordAiUsage({ req, usage }) {
    const uid = req?.user?.uid;
    if (!uid) return;

    try {
      const platform = clientPlatform(req);
      const dateKey = nairobiKey();
      const monthKey = dateKey.slice(0, 7);
      const yearKey = dateKey.slice(0, 4);
      const loaded = await getCatalog();
      const userProfile = await loadProfile(uid);
      const owner = matchUserCourse(userProfile, loaded);
      const increments = aiIncrements(platform, owner, usage);

      await Promise.all([
        patchRollup(
          firestore.collection('analytics_daily').doc(dateKey),
          { date: dateKey },
          increments,
        ),
        patchRollup(
          firestore.collection('analytics_monthly').doc(monthKey),
          { month: monthKey },
          increments,
        ),
        patchRollup(
          firestore.collection('analytics_yearly').doc(yearKey),
          { year: yearKey },
          increments,
        ),
        patchRollup(
          firestore.collection('analytics_totals').doc('all'),
          {},
          increments,
        ),
      ]);
    } catch (err) {
      console.warn('Could not record AI analytics:', err.message);
    }
  }

  async function touchLastSeen(req) {
    const uid = req.user?.uid;
    if (!uid) return;
    const now = Date.now();
    const previous = lastSeenCache.get(uid) || 0;
    if (now - previous < LAST_SEEN_MS) return;
    lastSeenCache.set(uid, now);

    const platform = clientPlatform(req);
    const dateKey = nairobiKey();
    const monthKey = dateKey.slice(0, 7);
    const yearKey = dateKey.slice(0, 4);

    firestore
      .collection('profiles')
      .doc(uid)
      .set(
        {
          last_seen_at: timestamp(),
          last_platform: platform,
        },
        { merge: true },
      )
      .catch((err) => {
        console.warn('Could not update last seen:', err.message);
      });

    const actorRef = firestore
      .collection('analytics_daily')
      .doc(dateKey)
      .collection('actors')
      .doc(uid);

    actorRef
      .get()
      .then(async (snap) => {
        const data = snap.data() || {};
        const platforms = data.platforms && typeof data.platforms === 'object' ? data.platforms : {};
        const firstToday = !snap.exists;
        const firstOnPlatform = !platforms[platform];
        if (!firstToday && !firstOnPlatform) {
          await actorRef.set({ lastAt: timestamp() }, { merge: true });
          return;
        }

        await actorRef.set(
          {
            platforms: { ...platforms, [platform]: true },
            lastAt: timestamp(),
          },
          { merge: true },
        );

        const presenceIncrements = {
          ...(firstOnPlatform ? { [`${platform}.activeUsers`]: increment(1) } : {}),
          ...(firstToday ? { 'all.activeUsers': increment(1) } : {}),
        };
        await Promise.all([
          patchRollup(
            firestore.collection('analytics_daily').doc(dateKey),
            { date: dateKey },
            presenceIncrements,
          ),
          patchRollup(
            firestore.collection('analytics_monthly').doc(monthKey),
            { month: monthKey },
            presenceIncrements,
          ),
          patchRollup(
            firestore.collection('analytics_yearly').doc(yearKey),
            { year: yearKey },
            presenceIncrements,
          ),
        ]);
      })
      .catch((err) => {
        console.warn('Could not record daily presence:', err.message);
      });
  }

  async function recordUploadFromRequest(req, { folderId, result } = {}) {
    try {
      await recordUsage({
        req,
        kind: 'upload',
        fileId: result?.id,
        fileName: result?.name || req.file?.originalname,
        mimeType: result?.mimeType || req.file?.mimetype,
        sizeBytes: result?.size || req.file?.size || req.file?.buffer?.length,
        folderId,
      });
    } catch (err) {
      console.warn('Could not record upload analytics:', err.message);
    }
  }

  async function recordDownloadFromRequest(req, {
    fileId,
    fileName,
    mimeType,
    sizeBytes,
    folderId,
    isRange,
    forceDownload,
  } = {}) {
    try {
      const media = isMediaType(classifyFile(fileName, mimeType));
      await recordUsage({
        req,
        kind: forceDownload ? 'download' : (media || isRange ? 'stream' : 'download'),
        fileId,
        fileName,
        mimeType,
        sizeBytes,
        folderId,
        saved: Boolean(forceDownload),
      });
    } catch (err) {
      console.warn('Could not record download analytics:', err.message);
    }
  }

  function periodMeta(kind, year, month) {
    const now = nairobiParts();
    const selectedYear = Number(year) || now.year;
    const selectedMonth = Math.min(12, Math.max(1, Number(month) || now.month));

    if (kind === 'year') {
      const start = nairobiDate(`${selectedYear}-01-01`);
      const end = nairobiDate(`${selectedYear}-12-31`, true);
      return {
        kind: 'year',
        year: selectedYear,
        month: null,
        label: String(selectedYear),
        start,
        end,
      };
    }

    if (kind === 'month') {
      const last = daysInMonth(selectedYear, selectedMonth);
      const start = nairobiDate(
        `${selectedYear}-${String(selectedMonth).padStart(2, '0')}-01`,
      );
      const end = nairobiDate(
        `${selectedYear}-${String(selectedMonth).padStart(2, '0')}-${String(last).padStart(2, '0')}`,
        true,
      );
      return {
        kind: 'month',
        year: selectedYear,
        month: selectedMonth,
        label: `${MONTH_NAMES[selectedMonth - 1]} ${selectedYear}`,
        start,
        end,
      };
    }

    return {
      kind: 'all',
      year: now.year,
      month: now.month,
      label: 'All time',
      start: null,
      end: new Date(),
    };
  }

  function ownerRowsFromBucket(bucket, names, kind) {
    const rows = [];
    const source = kind === 'client' ? bucket.clients : bucket.courses;
    for (const [id, stats] of Object.entries(source || {})) {
      rows.push({
        id,
        name: names[id] || id,
        kind,
        uploads: num(stats.uploads),
        downloads: num(stats.downloads),
        streams: num(stats.streams),
        bytesUploaded: num(stats.bytesUploaded),
        bytesDownloaded: num(stats.bytesDownloaded),
        bytesStreamed: num(stats.bytesStreamed),
      });
    }
    if (kind === 'course' && bucket.other) {
      const unused =
        num(bucket.other.uploads) +
        num(bucket.other.downloads) +
        num(bucket.other.streams) +
        num(bucket.other.bytesUploaded) +
        num(bucket.other.bytesDownloaded) +
        num(bucket.other.bytesStreamed);
      if (unused > 0) {
        rows.push({
          id: 'unassigned',
          name: 'Unassigned',
          kind: 'other',
          uploads: num(bucket.other.uploads),
          downloads: num(bucket.other.downloads),
          streams: num(bucket.other.streams),
          bytesUploaded: num(bucket.other.bytesUploaded),
          bytesDownloaded: num(bucket.other.bytesDownloaded),
          bytesStreamed: num(bucket.other.bytesStreamed),
        });
      }
    }
    rows.sort(
      (a, b) =>
        b.bytesUploaded + b.bytesDownloaded - (a.bytesUploaded + a.bytesDownloaded),
    );
    return rows;
  }

  function pushAiRow(rows, id, name, kind, stats) {
    const item = mergeAiStats(stats);
    if (!item.requests && !item.totalTokens) return;
    rows.push({
      id,
      name,
      kind,
      requests: item.requests,
      promptTokens: item.promptTokens,
      completionTokens: item.completionTokens,
      totalTokens: item.totalTokens,
    });
  }

  function aiOwnerRows(ai, names) {
    const rows = [];
    for (const [id, stats] of Object.entries(ai.courses || {})) {
      pushAiRow(rows, id, names[id] || id, 'course', stats);
    }
    pushAiRow(rows, 'clients', 'Clients', 'client', ai.clients);
    pushAiRow(rows, 'unassigned', 'Unassigned', 'other', ai.other);
    rows.sort((a, b) => b.totalTokens - a.totalTokens || b.requests - a.requests);
    return rows;
  }

  function typeRows(bucket) {
    return FILE_TYPES.map((id) => {
      const stats = bucket.types[id] || emptyTypes()[id];
      return {
        id,
        name: id === 'ppt' ? 'PowerPoint' : id[0].toUpperCase() + id.slice(1),
        group: DOCUMENT_TYPES.includes(id) ? 'document' : id === 'other' ? 'other' : 'media',
        uploads: num(stats.uploads),
        downloads: num(stats.downloads),
        streams: num(stats.streams),
        bytesUploaded: num(stats.bytesUploaded),
        bytesDownloaded: num(stats.bytesDownloaded),
        bytesStreamed: num(stats.bytesStreamed),
      };
    });
  }

  function roleLabel(role) {
    const labels = {
      student: 'Students',
      class_rep: 'Class reps',
      assistant_class_rep: 'Asst. class reps',
      lecturer: 'Lecturers',
      admin: 'Admins',
      system_admin: 'System admins',
      super_admin: 'System admins',
      client: 'Clients',
    };
    return labels[role] || role || 'Other';
  }

  async function buildAnalytics({ period, year, month, platform }) {
    const prefix = platform === 'mobile' || platform === 'web' ? platform : 'all';
    const meta = periodMeta(period, year, month);
    const loaded = await getCatalog();

    let rollupSource = {};
    let mobileSource = {};
    let webSource = {};
    const series = [];

    if (meta.kind === 'all') {
      const snap = await firestore.collection('analytics_totals').doc('all').get();
      rollupSource = snap.data() || {};
      const yearsSnap = await firestore.collection('analytics_yearly').get();
      yearsSnap.docs
        .sort((a, b) => a.id.localeCompare(b.id))
        .forEach((doc) => {
          const bucket = extractBucket(doc.data(), prefix);
          series.push({
            label: doc.id,
            uploads: bucket.uploads,
            downloads: bucket.downloads,
            streams: bucket.streams,
            bytesUploaded: bucket.bytesUploaded,
            bytesDownloaded: bucket.bytesDownloaded,
            bytesStreamed: bucket.bytesStreamed,
            activeUsers: bucket.activeUsers,
          });
        });
    } else if (meta.kind === 'year') {
      const snap = await firestore
        .collection('analytics_yearly')
        .doc(String(meta.year))
        .get();
      rollupSource = snap.data() || {};
      const monthReads = await Promise.all(
        Array.from({ length: 12 }, (_, index) => {
          const key = `${meta.year}-${String(index + 1).padStart(2, '0')}`;
          return firestore.collection('analytics_monthly').doc(key).get();
        }),
      );
      monthReads.forEach((doc, index) => {
        const bucket = extractBucket(doc.data(), prefix);
        series.push({
          label: MONTH_NAMES[index].slice(0, 3),
          uploads: bucket.uploads,
          downloads: bucket.downloads,
          streams: bucket.streams,
          bytesUploaded: bucket.bytesUploaded,
          bytesDownloaded: bucket.bytesDownloaded,
          bytesStreamed: bucket.bytesStreamed,
          activeUsers: bucket.activeUsers,
        });
      });
    } else {
      const monthKey = `${meta.year}-${String(meta.month).padStart(2, '0')}`;
      const snap = await firestore.collection('analytics_monthly').doc(monthKey).get();
      rollupSource = snap.data() || {};
      const last = daysInMonth(meta.year, meta.month);
      const dayReads = await Promise.all(
        Array.from({ length: last }, (_, index) => {
          const key = `${monthKey}-${String(index + 1).padStart(2, '0')}`;
          return firestore.collection('analytics_daily').doc(key).get();
        }),
      );
      dayReads.forEach((doc, index) => {
        const bucket = extractBucket(doc.data(), prefix);
        series.push({
          label: String(index + 1),
          uploads: bucket.uploads,
          downloads: bucket.downloads,
          streams: bucket.streams,
          bytesUploaded: bucket.bytesUploaded,
          bytesDownloaded: bucket.bytesDownloaded,
          bytesStreamed: bucket.bytesStreamed,
          activeUsers: bucket.activeUsers,
        });
      });
    }

    let rollup = extractBucket(rollupSource, prefix);
    mobileSource = extractBucket(rollupSource, 'mobile');
    webSource = extractBucket(rollupSource, 'web');

    const profilesSnap = await firestore.collection('profiles').get();
    const courseUserCounts = new Map();
    const roleCounts = new Map();
    let activeUsers = 0;
    let newUsers = 0;
    let mobileActive = 0;
    let webActive = 0;

    profilesSnap.forEach((doc) => {
      const data = doc.data() || {};
      const owner = matchUserCourse(data, loaded);
      const lastSeen = asDate(data.last_seen_at);
      const created = asDate(data.created_at);
      const lastPlatform = String(data.last_platform || '');
      const platformOk = prefix === 'all' || lastPlatform === prefix;
      const isActive = inRange(lastSeen, meta.start, meta.end) && platformOk;
      const isNew = inRange(created, meta.start, meta.end);
      if (isNew) newUsers += 1;
      if (inRange(lastSeen, meta.start, meta.end)) {
        if (lastPlatform === 'web') webActive += 1;
        else if (lastPlatform === 'mobile') mobileActive += 1;
      }

      if (isActive) {
        activeUsers += 1;
        const key = `${owner.kind}:${owner.id}`;
        const current = courseUserCounts.get(key) || {
          id: owner.id,
          name: owner.name,
          kind: owner.kind,
          users: 0,
          newUsers: 0,
        };
        current.users += 1;
        if (isNew) current.newUsers += 1;
        courseUserCounts.set(key, current);

        const role = String(data.role || 'student').toLowerCase();
        const roleKey = role === 'super_admin' ? 'system_admin' : role;
        roleCounts.set(roleKey, (roleCounts.get(roleKey) || 0) + 1);
      }
    });

    const names = {
      ...(rollupSource.courseNames || {}),
      ...(rollupSource.clientNames || {}),
    };
    loaded.courses.forEach((course) => {
      names[course.id] = course.name;
    });
    loaded.clients.forEach((client) => {
      names[client.id] = client.name;
    });

    const topMaps = { uploads: new Map(), downloads: new Map(), streams: new Map() };
    const eventTotals = {
      all: emptyBucket(),
      mobile: emptyBucket(),
      web: emptyBucket(),
    };
    const seriesFromEvents = new Map();
    try {
      let query = firestore.collection('analytics_events').orderBy('createdAt', 'desc');
      if (meta.start) query = query.where('createdAt', '>=', meta.start);
      if (meta.end) query = query.where('createdAt', '<=', meta.end);
      const eventsSnap = await query.limit(2000).get();
      eventsSnap.forEach((doc) => {
        const event = doc.data() || {};
        const eventPlatform = event.platform === 'web' ? 'web' : 'mobile';
        if (prefix !== 'all' && eventPlatform !== prefix) return;
        applyEventToBucket(eventTotals.all, event);
        applyEventToBucket(eventTotals[eventPlatform], event);

        const eventDate =
          event.date ||
          (asDate(event.createdAt) ? nairobiKey(asDate(event.createdAt)) : '');
        let seriesLabel = '';
        if (eventDate && meta.kind === 'all') seriesLabel = eventDate.slice(0, 4);
        else if (eventDate && meta.kind === 'year') {
          const monthNumber = Number(eventDate.slice(5, 7));
          seriesLabel = MONTH_NAMES[monthNumber - 1]
            ? MONTH_NAMES[monthNumber - 1].slice(0, 3)
            : '';
        } else if (eventDate) {
          seriesLabel = String(Number(eventDate.slice(8, 10)));
        }
        if (seriesLabel) {
          if (!seriesFromEvents.has(seriesLabel)) {
            seriesFromEvents.set(seriesLabel, emptyBucket());
          }
          applyEventToBucket(seriesFromEvents.get(seriesLabel), event);
        }

        const kind = playbackKind(event);
        if (kind !== 'upload' && kind !== 'download' && kind !== 'stream') return;
        const bucket =
          kind === 'upload'
            ? topMaps.uploads
            : kind === 'stream'
              ? topMaps.streams
              : topMaps.downloads;
        const type = FILE_TYPES.includes(event.fileType)
          ? event.fileType
          : classifyFile(event.fileName, event.mimeType);
        const fileType = FILE_TYPES.includes(type) ? type : 'other';
        const current = bucket.get(event.uid) || {
          uid: event.uid,
          name: event.name || 'User',
          courseName: event.ownerName || '',
          count: 0,
          bytes: 0,
          types: {},
          video: 0,
          audio: 0,
        };
        current.count += 1;
        current.bytes += num(event.sizeBytes);
        current.types[fileType] = num(current.types[fileType]) + 1;
        if (kind === 'stream') {
          if (fileType === 'video') current.video += 1;
          else if (fileType === 'audio') current.audio += 1;
        }
        bucket.set(event.uid, current);
        if (event.ownerName && !names[event.ownerId]) {
          names[event.ownerId] = event.ownerName;
        }
      });
    } catch (err) {
      console.warn('Analytics events query failed:', err.message);
    }

    if (bucketHasTraffic(eventTotals.all)) {
      rollup = eventTotals.all;
      mobileSource = eventTotals.mobile;
      webSource = eventTotals.web;
      if (seriesFromEvents.size) {
        const mapped = series.map((point) => {
          const fromEvent = seriesFromEvents.get(point.label);
          if (!fromEvent) {
            return {
              ...point,
              uploads: 0,
              downloads: 0,
              streams: 0,
              bytesUploaded: 0,
              bytesDownloaded: 0,
              bytesStreamed: 0,
            };
          }
          return {
            ...point,
            uploads: fromEvent.uploads,
            downloads: fromEvent.downloads,
            streams: fromEvent.streams,
            bytesUploaded: fromEvent.bytesUploaded,
            bytesDownloaded: fromEvent.bytesDownloaded,
            bytesStreamed: fromEvent.bytesStreamed,
          };
        });
        if (mapped.some((point) => point.uploads || point.downloads || point.streams || point.bytesUploaded || point.bytesDownloaded || point.bytesStreamed)) {
          series.length = 0;
          series.push(...mapped);
        } else if (meta.kind === 'all') {
          series.length = 0;
          Array.from(seriesFromEvents.keys())
            .sort()
            .forEach((label) => {
              const fromEvent = seriesFromEvents.get(label);
              series.push({
                label,
                uploads: fromEvent.uploads,
                downloads: fromEvent.downloads,
                streams: fromEvent.streams,
                bytesUploaded: fromEvent.bytesUploaded,
                bytesDownloaded: fromEvent.bytesDownloaded,
                bytesStreamed: fromEvent.bytesStreamed,
                activeUsers: fromEvent.activeUsers,
              });
            });
        }
      }
    }

    const typeCounts = (types) => {
      const out = {};
      for (const type of FILE_TYPES) {
        const count = num(types?.[type]);
        if (count > 0) out[type] = count;
      }
      return out;
    };
    const toTop = (map, { includePlays = false } = {}) =>
      Array.from(map.values())
        .sort((a, b) => b.count - a.count || b.bytes - a.bytes)
        .slice(0, 10)
        .map((item) => ({
          uid: item.uid,
          name: item.name,
          courseName: item.courseName,
          count: item.count,
          bytes: item.bytes,
          types: typeCounts(item.types),
          ...(includePlays
            ? { video: num(item.video), audio: num(item.audio) }
            : {}),
        }));

    const yearsSnap = await firestore.collection('analytics_yearly').get();
    const availableYears = new Set(yearsSnap.docs.map((doc) => Number(doc.id)).filter(Boolean));
    availableYears.add(nairobiParts().year);

    const ai = extractAi(rollupSource, prefix);
    const avgUpload = rollup.uploads > 0 ? Math.round(rollup.bytesUploaded / rollup.uploads) : 0;
    const downloadBytes = FILE_TYPES.filter((type) => !isMediaType(type)).reduce(
      (sum, type) => sum + num(rollup.types[type]?.bytesDownloaded),
      0,
    );
    const avgDownload = rollup.downloads > 0 ? Math.round(downloadBytes / rollup.downloads) : 0;
    const fileTypeRows = typeRows(rollup);

    return {
      period: {
        kind: meta.kind,
        year: meta.year,
        month: meta.month,
        label: meta.label,
      },
      platform: prefix,
      availableYears: Array.from(availableYears).sort((a, b) => b - a),
      summary: {
        activeUsers,
        newUsers,
        uploads: rollup.uploads,
        downloads: rollup.downloads,
        streams: rollup.streams,
        bytesUploaded: rollup.bytesUploaded,
        bytesDownloaded: rollup.bytesDownloaded,
        bytesStreamed: rollup.bytesStreamed,
        avgUploadBytes: avgUpload,
        avgDownloadBytes: avgDownload,
      },
      platforms: {
        mobile: {
          activeUsers: mobileActive,
          uploads: mobileSource.uploads,
          downloads: mobileSource.downloads,
          streams: mobileSource.streams,
          bytesUploaded: mobileSource.bytesUploaded,
          bytesDownloaded: mobileSource.bytesDownloaded,
          bytesStreamed: mobileSource.bytesStreamed,
        },
        web: {
          activeUsers: webActive,
          uploads: webSource.uploads,
          downloads: webSource.downloads,
          streams: webSource.streams,
          bytesUploaded: webSource.bytesUploaded,
          bytesDownloaded: webSource.bytesDownloaded,
          bytesStreamed: webSource.bytesStreamed,
        },
      },
      activeUsersByCourse: Array.from(courseUserCounts.values()).sort(
        (a, b) => b.users - a.users,
      ),
      activeUsersByRole: Array.from(roleCounts.entries())
        .map(([id, users]) => ({ id, name: roleLabel(id), users }))
        .sort((a, b) => b.users - a.users),
      bandwidthByCourse: [
        ...ownerRowsFromBucket(rollup, names, 'course'),
        ...ownerRowsFromBucket(rollup, names, 'client'),
      ],
      fileTypes: fileTypeRows,
      documents: fileTypeRows.filter((row) => row.id === 'pdf' || row.id === 'word'),
      media: fileTypeRows.filter((row) => isMediaType(row.id)),
      series,
      topUploaders: toTop(topMaps.uploads),
      topDownloaders: toTop(topMaps.downloads),
      topPlayers: toTop(topMaps.streams, { includePlays: true }),
      ai: {
        requests: ai.requests,
        promptTokens: ai.promptTokens,
        completionTokens: ai.completionTokens,
        totalTokens: ai.totalTokens,
        byOwner: aiOwnerRows(ai, names),
      },
    };
  }

  function registerAnalyticsRoutes(app, { requireAuth, requireSystemAdmin }) {
    app.get('/analytics', requireAuth, requireSystemAdmin, async (req, res) => {
      try {
        const period = String(req.query.period || 'month').toLowerCase();
        const platform = String(req.query.platform || 'all').toLowerCase();
        const year = req.query.year;
        const month = req.query.month;
        const payload = await buildAnalytics({
          period: ['all', 'year', 'month'].includes(period) ? period : 'month',
          year,
          month,
          platform: ['mobile', 'web', 'all'].includes(platform) ? platform : 'all',
        });
        res.json(payload);
      } catch (err) {
        console.error('Analytics failed:', err);
        res.status(500).json({ error: 'Could not load analytics' });
      }
    });

    app.post('/events/download', requireAuth, async (req, res) => {
      const fileId = String(req.body?.fileId || '').trim();
      const fileName = String(req.body?.fileName || '').trim();
      if (!fileId && !fileName) {
        return res.status(400).json({ error: 'Missing file' });
      }
      await recordDownloadFromRequest(req, {
        fileId,
        fileName,
        mimeType: req.body?.mimeType,
        sizeBytes: req.body?.sizeBytes,
        folderId: req.body?.folderId,
        isRange: false,
        forceDownload: true,
      });
      res.json({ recorded: true });
    });

    app.post('/events/presence', requireAuth, async (req, res) => {
      lastSeenCache.delete(req.user.uid);
      await touchLastSeen(req);
      res.json({ recorded: true });
    });
  }

  return {
    registerAnalyticsRoutes,
    touchLastSeen,
    recordUploadFromRequest,
    recordDownloadFromRequest,
    recordAiUsage,
    clientPlatform,
  };
}

module.exports = { createAnalytics };
