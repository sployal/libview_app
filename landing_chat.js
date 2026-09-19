/**
 * Public landing-page assistant. Isolated from /ai/chat (signed-in study AI)
 * and /contact (email). Can be mounted on the main Express app, or started
 * on its own with `node landing_chat.js`.
 */

const express = require('express');
const cors = require('cors');

const INVOKE_URL = 'https://integrate.api.nvidia.com/v1/chat/completions';
const MAX_MESSAGE = 800;
const MAX_HISTORY = 10;
const RATE_WINDOW_MS = 15 * 60 * 1000;
const RATE_MAX = 24;

const EDUPAL_KNOWLEDGE = `
Edupal is a campus academic workspace (web companion to the original campus mobile app).
It is designed for Chuka University students, courses, and class materials.

Who it is for
- Students whose course has been registered by a faculty representative or admin.
- Sign up uses email/password or Google. After Google, students may be asked once for full name and admission number.
- Use the official student admission number for the course.
- Invited workspace clients (for example faculty reps managing course files) complete a client profile instead of a student admission number.

What students can do after signing in
- Semester library: browse years, units, folders, notes, slides, and past papers the way the class organizes them.
- Preview files and download a local copy for offline use when campus Wi-Fi drops.
- AI study partner (inside the signed-in app): ask questions, attach a photo of a problem, keep conversations for later revision. That in-app AI is separate from this landing assistant.
- Focus timer on the home dashboard: start, pause, reset.
- Daily streak calendar for opening Edupal consistently.
- Todos for readings and deadlines, synced to the account.
- Notifications, profile, and downloads pages in the web app.

How to get started
1. Sign in as a student (email or Google).
2. Enter the admission number of your registered course.
3. Browse semesters and units, preview or download files, then use todos, the focus timer, streaks, and in-app AI from home.

Support
- Contact form on this landing page, or email edupalapp026@gmail.com.
- Questions about course setup, feedback, or requesting the mobile app can go through that contact email.

This assistant must:
- Answer only questions about Edupal, its features, sign-in, courses, campus use, and how to get help.
- If asked something unrelated, briefly say you only help with Edupal and suggest the contact form or email.
- Never invent prices, private student data, passwords, or unpublished admin tools.
- Never claim you can log the visitor in or fetch their files from this chat.
`.trim();

const SYSTEM_PROMPT =
  'You are Edupal Guide, a concise public assistant on the Edupal landing page. ' +
  'Speak in short, friendly paragraphs. Use the product facts below and do not contradict them.\n\n' +
  EDUPAL_KNOWLEDGE;

const recentByIp = new Map();

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

function extractReply(data) {
  const content = data?.choices?.[0]?.message?.content;
  if (typeof content === 'string') return content.trim();
  if (Array.isArray(content)) {
    return content
      .map((part) => (typeof part === 'string' ? part : part?.text || ''))
      .join('')
      .trim();
  }
  return '';
}

function normalizeMessages(raw) {
  const list = Array.isArray(raw) ? raw : [];
  const out = [];
  for (const msg of list.slice(-MAX_HISTORY)) {
    if (!msg || typeof msg !== 'object') continue;
    const role = msg.role === 'assistant' ? 'assistant' : 'user';
    const content = String(msg.content ?? msg.text ?? '').trim();
    if (!content || content.length > MAX_MESSAGE) continue;
    out.push({ role, content });
  }
  return out;
}

const FAQ_FALLBACKS = [
  {
    keys: ['what is', 'edupal', 'about', 'this app', 'platform'],
    reply:
      'Edupal is a campus academic workspace for Chuka University. After you sign in, you get semester files, an AI study partner, offline downloads, a focus timer, streaks, and todos in one place. This chat only explains the product — sign in to use the library and study tools.',
  },
  {
    keys: ['sign up', 'signup', 'account', 'who can', 'register', 'admission'],
    reply:
      'Students can create an account when their course has been registered by a faculty rep or admin. Use email or Google, then your official admission number. If Google asks for a name and admission number once, that completes your student profile.',
  },
  {
    keys: ['google'],
    reply:
      'Yes — you can sign in with Google. You may be asked for your full name and admission number once, then you go to home.',
  },
  {
    keys: ['download', 'offline', 'wifi', 'wi-fi'],
    reply:
      'Files you download are saved on this device so you can reopen them later, even without campus Wi-Fi.',
  },
  {
    keys: ['mobile', 'app', 'android', 'apk'],
    reply:
      'Edupal started as a campus mobile app; this site is the web companion. Sign in here for the same academic workspace, or email edupalapp026@gmail.com to request the mobile app.',
  },
  {
    keys: ['ai', 'chatbot', 'study'],
    reply:
      'Inside the signed-in app, Edupal includes an AI study partner: ask questions, attach a photo of a problem, and keep conversations. This landing chat only answers product questions. Coursework help starts after you sign in.',
  },
  {
    keys: ['contact', 'email', 'support', 'help'],
    reply:
      'Use the Contact section on this page, or write to edupalapp026@gmail.com for course setup, feedback, or questions.',
  },
  {
    keys: ['client', 'faculty', 'workspace'],
    reply:
      'Some people are invited as workspace clients to manage course materials. They finish a client profile instead of a student admission number. If you were invited by email, sign in with that address.',
  },
];

function fallbackReply(text) {
  const q = text.toLowerCase();
  let best = FAQ_FALLBACKS[0];
  let score = 0;
  for (const item of FAQ_FALLBACKS) {
    const hits = item.keys.filter((k) => q.includes(k)).length;
    if (hits > score) {
      score = hits;
      best = item;
    }
  }
  if (score === 0) {
    return 'I can help with Edupal itself — sign-in, courses, files, downloads, the in-app study AI, and how to get support. Ask about one of those, or use the contact form / edupalapp026@gmail.com.';
  }
  return best.reply;
}

async function nvidiaReply(messages) {
  const apiKey = process.env.NVIDIA_API_KEY;
  if (!apiKey) return null;

  const payload = {
    messages: [{ role: 'system', content: SYSTEM_PROMPT }, ...messages],
    model: process.env.NVIDIA_LANDING_CHAT_MODEL || process.env.NVIDIA_AI_MODEL || 'meta/llama-3.2-90b-vision-instruct',
    frequency_penalty: 0,
    max_tokens: 420,
    presence_penalty: 0,
    stream: false,
    temperature: 0.4,
    top_p: 1,
  };

  const response = await fetch(INVOKE_URL, {
    method: 'POST',
    headers: {
      Authorization: `Bearer ${apiKey}`,
      Accept: 'application/json',
      'Content-Type': 'application/json',
    },
    body: JSON.stringify(payload),
    signal: AbortSignal.timeout(45000),
  });

  const data = await response.json().catch(() => ({}));
  if (!response.ok) {
    const err = new Error(data?.error?.message || data?.message || `NVIDIA ${response.status}`);
    err.status = response.status;
    throw err;
  }
  const reply = extractReply(data);
  if (!reply) {
    const err = new Error('Empty response from AI');
    err.status = 502;
    throw err;
  }
  return reply;
}

function registerLandingChatRoutes(app) {
  app.post('/landing-chat', async (req, res) => {
    try {
      const ip = clientIp(req);
      if (isRateLimited(ip)) {
        return res.status(429).json({ error: 'Please wait a moment before sending another question.' });
      }

      const messages = normalizeMessages(req.body?.messages);
      const lastUser = [...messages].reverse().find((m) => m.role === 'user');
      if (!lastUser) {
        return res.status(400).json({ error: 'Please type a question about Edupal.' });
      }
      if (String(req.body?.website ?? '').trim()) {
        return res.json({ reply: fallbackReply(lastUser.content) });
      }

      try {
        const reply = await nvidiaReply(messages);
        if (reply) return res.json({ reply });
      } catch (error) {
        console.error('[landing-chat] NVIDIA failed, using local answers:', error.message || error);
      }

      return res.json({ reply: fallbackReply(lastUser.content) });
    } catch (error) {
      console.error('[landing-chat]', error.message || error);
      return res.status(500).json({ error: 'Could not answer right now. Try again, or use the contact form.' });
    }
  });
}

function allowedOrigins() {
  return (process.env.ALLOWED_ORIGINS || 'https://edupal-web.vercel.app')
    .split(',')
    .map((s) => s.trim().replace(/\/$/, ''))
    .filter(Boolean);
}

function createLandingChatApp() {
  const app = express();
  const origins = allowedOrigins();
  app.use(
    cors({
      origin(origin, callback) {
        if (!origin || origins.includes('*') || origins.includes(origin.replace(/\/$/, ''))) {
          callback(null, true);
          return;
        }
        callback(null, false);
      },
    })
  );
  app.use(express.json({ limit: '32kb' }));
  app.get('/health', (_req, res) => res.json({ ok: true, service: 'landing-chat' }));
  registerLandingChatRoutes(app);
  return app;
}

if (require.main === module) {
  try {
    require('dotenv').config();
  } catch {
    /* optional when launched from the backend folder */
  }
  const port = parseInt(process.env.LANDING_CHAT_PORT || '3010', 10);
  createLandingChatApp().listen(port, () => {
    console.log(`Edupal landing chat listening on port ${port}`);
  });
}

module.exports = { registerLandingChatRoutes, createLandingChatApp };
