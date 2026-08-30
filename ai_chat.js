const axios = require('axios');

const INVOKE_URL = 'https://integrate.api.nvidia.com/v1/chat/completions';
const SYSTEM_PROMPT =
  'You are Edupal AI, a helpful university study assistant. ' +
  'Answer clearly and concisely. Help with coursework, exam prep, ' +
  'explanations, summaries, diagrams in images, and study planning. ' +
  'If a question is outside academics, still be helpful but keep a study-focused tone.';

function toNvidiaMessages(clientMessages) {
  const out = [{ role: 'system', content: SYSTEM_PROMPT }];

  for (const msg of clientMessages) {
    if (!msg || typeof msg !== 'object') continue;

    const role =
      msg.role === 'assistant' || msg.role === 'model' ? 'assistant' : 'user';
    const text = String(msg.content ?? msg.text ?? '').trim();
    const imageBase64 = typeof msg.imageBase64 === 'string' ? msg.imageBase64.trim() : '';
    const imageMime = typeof msg.imageMime === 'string' && msg.imageMime
      ? msg.imageMime
      : 'image/jpeg';

    if (imageBase64) {
      const url = imageBase64.startsWith('data:')
        ? imageBase64
        : `data:${imageMime};base64,${imageBase64}`;
      out.push({
        role,
        content: [
          { type: 'image_url', image_url: { url } },
          { type: 'text', text: text || 'What is in this image?' },
        ],
      });
    } else if (text) {
      out.push({ role, content: text });
    }
  }

  return out;
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

function registerAiRoutes(app, { requireAuth }) {
  app.post('/ai/chat', requireAuth, async (req, res) => {
    const apiKey = process.env.NVIDIA_API_KEY;
    const model = process.env.NVIDIA_AI_MODEL;
    if (!apiKey || !model) {
      return res.status(503).json({
        error: `AI is not configured (missing ${!apiKey ? 'NVIDIA_API_KEY' : 'NVIDIA_AI_MODEL'})`,
      });
    }

    const messages = Array.isArray(req.body?.messages) ? req.body.messages : [];
    const nvidiaMessages = toNvidiaMessages(messages);
    const hasUserTurn = nvidiaMessages.some((m) => m.role === 'user');
    if (!hasUserTurn) {
      return res.status(400).json({ error: 'A user message is required' });
    }

    const payload = {
      messages: nvidiaMessages,
      model,
      frequency_penalty: 0,
      max_tokens: 1024,
      presence_penalty: 0,
      stream: false,
      temperature: 0.7,
      top_p: 1,
    };

    try {
      const response = await axios.post(INVOKE_URL, payload, {
        headers: {
          Authorization: `Bearer ${apiKey}`,
          Accept: 'application/json',
          'Content-Type': 'application/json',
        },
        timeout: 120000,
      });

      const reply = extractReply(response.data);
      if (!reply) {
        return res.status(502).json({ error: 'Empty response from AI' });
      }

      res.json({ reply });
    } catch (error) {
      const status = error.response?.status || 500;
      const nvidiaError = error.response?.data;
      console.error('AI chat failed:', nvidiaError || error.message);
      res.status(status >= 400 && status < 600 ? status : 500).json({
        error:
          nvidiaError?.error?.message ||
          nvidiaError?.message ||
          error.message ||
          'AI request failed',
      });
    }
  });
}

module.exports = { registerAiRoutes };
