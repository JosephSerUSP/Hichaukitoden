// Minimal LLM client supporting OpenAI-compatible endpoints (OpenRouter, DeepSeek
// direct, or any compatible endpoint) and Google Gemini. No SDK: plain fetch.
// Streams the completion (onChunk gets each text delta for live console output)
// and reports token usage; OpenRouter additionally returns real USD cost when
// usage.include is requested -- other providers just omit it.
'use strict';

// ---------------------------------------------------------------------------
// OpenAI-compatible chat (OpenRouter, DeepSeek, etc.)
// ---------------------------------------------------------------------------
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

// ---------------------------------------------------------------------------
// Google Gemini chat (non-OpenAI-compatible; uses its own streaming API)
// ---------------------------------------------------------------------------
async function geminiChat({ apiKey, model, temperature, messages, onChunk, maxRetries = 3 }) {
    // Convert the OpenAI-style message list into Gemini's "contents" format.
    // Gemini uses: { contents: [{ role: "user"|"model", parts: [{text: "..."}] }] }
    // The system message is passed as system_instruction.
    let systemInstruction = null;
    const contents = [];
    for (const msg of messages) {
        if (msg.role === 'system') {
            systemInstruction = msg.content;
            continue;
        }
        contents.push({
            role: msg.role === 'assistant' ? 'model' : 'user',
            parts: [{ text: msg.content }],
        });
    }

    const body = {
        contents,
        generationConfig: {
            temperature: temperature || 0.7,
        },
    };
    if (systemInstruction) {
        body.systemInstruction = { parts: [{ text: systemInstruction }] };
    }

    let lastErr;
    for (let attempt = 1; attempt <= maxRetries; attempt++) {
        try {
            // Gemini streaming API:
            // POST https://generativelanguage.googleapis.com/v1beta/models/{model}:streamGenerateContent?alt=sse
            // Key goes in a header rather than the query string so it doesn't end up in logs/proxies.
            const url = `https://generativelanguage.googleapis.com/v1beta/models/${model}:streamGenerateContent?alt=sse`;
            const res = await fetch(url, {
                method: 'POST',
                headers: { 'Content-Type': 'application/json', 'x-goog-api-key': apiKey },
                body: JSON.stringify(body),
            });
            if (res.status === 429 || res.status >= 500) {
                lastErr = new Error(`HTTP ${res.status}: ${await res.text()}`);
                await new Promise(r => setTimeout(r, attempt * 5000));
                continue;
            }
            if (!res.ok) {
                throw new Error(`HTTP ${res.status}: ${await res.text()}`);
            }

            // Gemini SSE: lines of "data: {json}", may include promptFeedback and candidates.
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
                    if (!payload) continue;
                    let evt;
                    try { evt = JSON.parse(payload); } catch { continue; }
                    // Skip promptFeedback messages (they have no candidates)
                    if (evt.promptFeedback && !evt.candidates) continue;
                    const candidate = evt.candidates && evt.candidates[0];
                    if (candidate) {
                        const text = candidate.content && candidate.content.parts
                            && candidate.content.parts.map(p => p.text || '').join('');
                        if (text) {
                            content += text;
                            if (onChunk) onChunk(text);
                        }
                        // Finish reason: STOP, MAX_TOKENS, SAFETY, etc.
                        if (candidate.finishReason && candidate.finishReason !== 'STOP') {
                            // Non-stop finish is unusual for text gen; log a warning.
                            console.warn(`  Gemini finish_reason: ${candidate.finishReason}`);
                        }
                    }
                    // Gemini returns usageMetadata on the final (or only) chunk.
                    if (evt.usageMetadata) {
                        usage = {
                            prompt_tokens: evt.usageMetadata.promptTokenCount || 0,
                            completion_tokens: evt.usageMetadata.candidatesTokenCount || 0,
                            // Gemini's totalTokenCount is read-only; no cost info.
                        };
                    }
                }
            }
            if (!content) throw new Error('empty completion (Gemini returned nothing)');
            return { content, usage };
        } catch (err) {
            lastErr = err;
            if (attempt < maxRetries) await new Promise(r => setTimeout(r, attempt * 5000));
        }
    }
    throw lastErr;
}

// ---------------------------------------------------------------------------
// Auto-dispatch: routes to the right chat function based on provider type.
// ---------------------------------------------------------------------------
async function chatForProvider({ providerType, baseUrl, apiKey, model, temperature, messages, onChunk, maxRetries }) {
    if (providerType === 'gemini') {
        return geminiChat({ apiKey, model, temperature, messages, onChunk, maxRetries });
    }
    // Default: OpenAI-compatible
    return chat({ baseUrl, apiKey, model, temperature, messages, onChunk, maxRetries });
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

module.exports = { chat, geminiChat, chatForProvider, extractJson };
