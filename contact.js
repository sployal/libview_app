const { google } = require('googleapis');

const EMAIL_RE = /^[^\s@]+@[^\s@]+\.[^\s@]+$/;
const MAX_NAME = 120;
const MAX_SUBJECT = 160;
const MAX_MESSAGE = 4000;
const RATE_WINDOW_MS = 15 * 60 * 1000;
const RATE_MAX = 5;

const recentByIp = new Map();

function contactToEmail() {
  return (
    process.env.CONTACT_EMAIL ||
    process.env.SYSTEM_ADMIN_EMAIL ||
    ''
  ).trim();
}

function escapeHtml(value) {
  return String(value)
    .replace(/&/g, '&amp;')
    .replace(/</g, '&lt;')
    .replace(/>/g, '&gt;')
    .replace(/"/g, '&quot;');
}

function clientIp(req) {
  const forwarded = req.headers['x-forwarded-for'];
  if (typeof forwarded === 'string' && forwarded.trim()) {
    return forwarded.split(',')[0].trim();
  }
  return req.ip || req.socket?.remoteAddress || 'unknown';
}

function isRateLimited(ip) {
  const now = Date.now();
  const stamps = (recentByIp.get(ip) || []).filter((t) => now - t < RATE_WINDOW_MS);
  if (stamps.length >= RATE_MAX) {
    recentByIp.set(ip, stamps);
    return true;
  }
  stamps.push(now);
  recentByIp.set(ip, stamps);
  return false;
}

function encodeSubject(subject) {
  if (/^[\x20-\x7E]*$/.test(subject)) return subject;
  return `=?UTF-8?B?${Buffer.from(subject, 'utf8').toString('base64')}?=`;
}

function gmailRawMessage({ from, to, replyTo, subject, html }) {
  const mime = [
    `From: ${from}`,
    `To: ${to}`,
    `Reply-To: ${replyTo}`,
    `Subject: ${encodeSubject(subject)}`,
    'MIME-Version: 1.0',
    'Content-Type: text/html; charset=utf-8',
    '',
    html,
  ].join('\r\n');
  return Buffer.from(mime)
    .toString('base64')
    .replace(/\+/g, '-')
    .replace(/\//g, '_')
    .replace(/=+$/, '');
}

async function sendViaGmailApi(oauth2Client, mail) {
  if (!oauth2Client?.credentials?.refresh_token && !oauth2Client?.credentials?.access_token) {
    return false;
  }
  const gmail = google.gmail({ version: 'v1', auth: oauth2Client });
  await gmail.users.messages.send({
    userId: 'me',
    requestBody: { raw: gmailRawMessage(mail) },
  });
  return true;
}

function registerContactRoutes(app, { oauth2Client } = {}) {
  console.log('[contact] mail config', {
    contactEmail: Boolean(contactToEmail()),
    gmailOauth: Boolean(oauth2Client),
  });

  app.post('/contact', async (req, res) => {
    console.log('[contact] POST received');
    try {
      if (typeof req.body?.website === 'string' && req.body.website.trim()) {
        return res.json({ ok: true });
      }

      const ip = clientIp(req);
      if (isRateLimited(ip)) {
        return res.status(429).json({ error: 'Please wait a few minutes before sending another message.' });
      }

      const name = String(req.body?.name ?? '').trim();
      const email = String(req.body?.email ?? '').trim();
      const subject = String(req.body?.subject ?? '').trim();
      const message = String(req.body?.message ?? '').trim();

      if (!name || name.length > MAX_NAME) {
        return res.status(400).json({ error: 'Please enter your name.' });
      }
      if (!EMAIL_RE.test(email) || email.length > 200) {
        return res.status(400).json({ error: 'Please enter a valid email address.' });
      }
      if (subject.length > MAX_SUBJECT) {
        return res.status(400).json({ error: 'Subject is too long.' });
      }
      if (!message || message.length > MAX_MESSAGE) {
        return res.status(400).json({ error: 'Please write a message (up to 4000 characters).' });
      }

      const to = contactToEmail();
      if (!to) {
        console.error('[contact] CONTACT_EMAIL (or SYSTEM_ADMIN_EMAIL) is empty.');
        return res.status(503).json({ error: 'Could not send your message. Please try again later.' });
      }

      const topic = subject || 'General inquiry';
      const htmlMessage = escapeHtml(message).replace(/\n/g, '<br>');
      const mail = {
        from: `"Edupal" <${to}>`,
        to,
        replyTo: `"${name.replace(/"/g, '')}" <${email}>`,
        subject: `[Edupal inquiry] ${topic}`,
        html: `
          <p><strong>Name:</strong> ${escapeHtml(name)}</p>
          <p><strong>Email:</strong> ${escapeHtml(email)}</p>
          <p><strong>Subject:</strong> ${escapeHtml(topic)}</p>
          <p>${htmlMessage}</p>
        `,
      };

      const sent = await sendViaGmailApi(oauth2Client, mail);
      if (sent) {
        console.log('[contact] sent via Gmail API');
        return res.json({ ok: true });
      }

      console.error(
        '[contact] Gmail OAuth is not ready. Visit /auth/google so the backend token includes gmail.send.'
      );
      return res.status(503).json({ error: 'Could not send your message. Please try again later.' });
    } catch (err) {
      console.error('[contact] Gmail API send failed:', err.message || err);
      if (String(err.message || '').includes('insufficient') || err.code === 403) {
        console.error(
          '[contact] Re-authorize Google with gmail.send: visit /auth/google on this backend.'
        );
      }
      return res.status(500).json({ error: 'Could not send your message. Please try again later.' });
    }
  });
}

module.exports = { registerContactRoutes };
