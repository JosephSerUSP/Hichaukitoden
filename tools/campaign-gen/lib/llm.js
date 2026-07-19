// Minimal OpenAI-compatible chat client (OpenRouter, DeepSeek direct, or any
// other compatible endpoint -- provider is pure config). No SDK: one fetch.
// Streams the completion (onChunk gets each text delta for live console
// output) and reports token usage; OpenRouter additionally returns real USD
// cost when usage.include is requested -- other providers just omit it.
'use strict';

async function chat({ baseUrl, apiKey, model, temperature, messages, onChunk, maxRetries = 3 }) {
    let lastErr;
    for (let attempt = 1; attempt <= maxRetries; attempt++) {
        try {
            const res = await fetch(`${baseUrl}/chat/completions`, {
                method: 'POST',
                headers: {
                    'Content-Type': 'application/json',
                    'Authorization': `Bearer ${apiKey}`,
                },
                body: JSON.stringify({
                    model, temperature, messages,
                    stream: true,
                    usage: { include: true },
                }),
            });
            if (res.status === 429 || res.status >= 500) {
                lastErr = new Error(`HTTP ${res.status}: ${await res.text()}`);
                await new Promise(r => setTimeout(r, attempt * 5000));
                continue;
            }
            if (!res.ok) {
                throw new Error(`HTTP ${res.status}: ${await res.text()}`);
            }

            // SSE stream: lines of "data: {json}", terminated by "data: [DONE]".
            const decoder = new TextDecoder();
            let buffer = '';
            let content = '';
            let usage = null;
            for await (const raw of res.body) {
                buffer += decoder.decode(raw, { stream: true });
                let nl;
                while ((nl = buffer.indexOf('\n')) !== -1) {
                    const line = buffer.slice(0, nl).trim();
                    buffer = buffer.slice(nl + 1);
                    if (!line.startsWith('data:')) continue;
                    const payload = line.slice(5).trim();
                    if (payload === '[DONE]') continue;
                    let evt;
                    try { evt = JSON.parse(payload); } catch { continue; }
                    const delta = evt.choices && evt.choices[0] && evt.choices[0].delta
                        && evt.choices[0].delta.content;
                    if (delta) {
                        content += delta;
                        if (onChunk) onChunk(delta);
                    }
                    if (evt.usage) usage = evt.usage;
                }
            }
            if (!content) throw new Error('empty completion (streamed nothing)');
            return { content, usage };
        } catch (err) {
            lastErr = err;
            if (attempt < maxRetries) await new Promise(r => setTimeout(r, attempt * 5000));
        }
    }
    throw lastErr;
}

// Models wrap JSON in prose or code fences more often than not; extract the
// first top-level JSON value rather than trusting the whole reply to parse.
function extractJson(text) {
    const fenced = text.match(/```(?:json)?\s*([\s\S]*?)```/);
    const candidate = fenced ? fenced[1] : text;
    const start = candidate.search(/[[{]/);
    if (start === -1) throw new Error('no JSON found in model reply');
    // Walk to the matching close bracket of the first opener.
    const open = candidate[start];
    const close = open === '{' ? '}' : ']';
    let depth = 0, inStr = false, esc = false;
    for (let i = start; i < candidate.length; i++) {
        const c = candidate[i];
        if (esc) { esc = false; continue; }
        if (c === '\\') { esc = true; continue; }
        if (c === '"') { inStr = !inStr; continue; }
        if (inStr) continue;
        if (c === open) depth++;
        else if (c === close) {
            depth--;
            if (depth === 0) return JSON.parse(candidate.slice(start, i + 1));
        }
    }
    throw new Error('unbalanced JSON in model reply');
}

module.exports = { chat, extractJson };
