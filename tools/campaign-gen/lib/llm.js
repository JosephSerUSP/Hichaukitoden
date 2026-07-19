// Minimal OpenAI-compatible chat client (OpenRouter, DeepSeek direct, or any
// other compatible endpoint -- provider is pure config). No SDK: one fetch.
'use strict';

async function chat({ baseUrl, apiKey, model, temperature, messages, maxRetries = 3 }) {
    let lastErr;
    for (let attempt = 1; attempt <= maxRetries; attempt++) {
        try {
            const res = await fetch(`${baseUrl}/chat/completions`, {
                method: 'POST',
                headers: {
                    'Content-Type': 'application/json',
                    'Authorization': `Bearer ${apiKey}`,
                },
                body: JSON.stringify({ model, temperature, messages }),
            });
            if (res.status === 429 || res.status >= 500) {
                // Rate limit / transient upstream failure: back off and retry.
                lastErr = new Error(`HTTP ${res.status}: ${await res.text()}`);
                await new Promise(r => setTimeout(r, attempt * 5000));
                continue;
            }
            if (!res.ok) {
                throw new Error(`HTTP ${res.status}: ${await res.text()}`);
            }
            const body = await res.json();
            const content = body.choices && body.choices[0] && body.choices[0].message
                && body.choices[0].message.content;
            if (!content) throw new Error('empty completion: ' + JSON.stringify(body).slice(0, 400));
            return content;
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
