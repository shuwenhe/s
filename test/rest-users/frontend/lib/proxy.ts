// This proxy performs transport only. Validation, persistence and user rules live in S.
const REQUEST_LIMIT = 65_536;
const RESPONSE_LIMIT = 1_048_576;
const TIMEOUT_MS = 10_000;
class LimitError extends Error {}
function problem(status: number, code: string, message: string): Response {
  return Response.json({ error: { code, message } }, { status });
}
async function boundedBody(body: ReadableStream<Uint8Array> | null, maximum: number, signal: AbortSignal): Promise<Uint8Array> {
  if (!body) return new Uint8Array();
  const reader = body.getReader();
  const chunks: Uint8Array[] = [];
  let size = 0;
  const aborted = new Promise<never>((_, reject) => {
    signal.addEventListener('abort', () => { void reader.cancel().catch(() => {}); reject(new Error('timeout')); }, { once: true });
  });
  try {
    while (true) {
      const { done, value } = await Promise.race([reader.read(), aborted]);
      if (done) break;
      size += value.byteLength;
      if (size > maximum) throw new LimitError('body too large');
      chunks.push(value);
    }
  } catch (error) {
    void reader.cancel().catch(() => {});
    throw error;
  } finally {
    reader.releaseLock();
  }
  const result = new Uint8Array(size);
  let position = 0;
  for (const chunk of chunks) { result.set(chunk, position); position += chunk.byteLength; }
  return result;
}
export async function proxy(request: Request, method: 'GET' | 'POST' | 'PUT' | 'DELETE', id?: string): Promise<Response> {
  if (id !== undefined && !/^[A-Za-z0-9_-]{1,128}$/.test(id)) return problem(400, 'invalid_id', 'Invalid user ID.');
  let origin: URL;
  try {
    origin = new URL(process.env.S_API_ORIGIN || 'http://127.0.0.1:8080');
    if (!['http:', 'https:'].includes(origin.protocol) || origin.username || origin.password || origin.pathname !== '/' || origin.search || origin.hash) throw new Error('invalid origin');
  } catch { return problem(502, 'configuration_error', 'The API origin is not configured correctly.'); }
  const controller = new AbortController();
  const timeout = setTimeout(() => controller.abort(), TIMEOUT_MS);
  try {
    let body: Uint8Array | undefined;
    if (method === 'POST' || method === 'PUT') {
      const declared = request.headers.get('content-length');
      if (declared !== null && (!/^\d+$/.test(declared) || Number(declared) > REQUEST_LIMIT)) return problem(413, 'request_too_large', 'Request exceeds 65536 bytes.');
      try { body = await boundedBody(request.body, REQUEST_LIMIT, controller.signal); }
      catch (error) { if (error instanceof LimitError) return problem(413, 'request_too_large', 'Request exceeds 65536 bytes.'); throw error; }
    }
    const target = new URL(`/api/users${id === undefined ? '' : `/${encodeURIComponent(id)}`}`, origin);
    // Query parameters remain data; only the configured origin and fixed route
    // select the upstream. S owns query and request media-type validation.
    target.search = new URL(request.url).search;
    const requestHeaders = new Headers({ accept: 'application/json' });
    const contentType = request.headers.get('content-type');
    if (contentType !== null) requestHeaders.set('content-type', contentType);
    const upstream = await fetch(target, {
      method, body: body as BodyInit | undefined, headers: requestHeaders,
      redirect: 'manual', cache: 'no-store', signal: controller.signal,
    });
    if (upstream.status >= 300 && upstream.status < 400) { void upstream.body?.cancel(); return problem(502, 'upstream_redirect', 'The API returned an unexpected redirect.'); }
    const responseHeaders = new Headers({ 'content-type': 'application/json; charset=utf-8', 'cache-control': 'no-store' });
    const allow = upstream.headers.get('allow');
    if (allow && allow.length <= 128 && /^[A-Z]+(?:[ \t]*,[ \t]*[A-Z]+)*$/.test(allow)) responseHeaders.set('allow', allow);
    if (upstream.status === 204) return new Response(null, { status: 204, headers: responseHeaders });
    const response = await boundedBody(upstream.body, RESPONSE_LIMIT, controller.signal);
    return new Response(response as BodyInit, { status: upstream.status, headers: responseHeaders });
  } catch (error) {
    if (error instanceof LimitError) return problem(502, 'response_too_large', 'The API response exceeded 1048576 bytes.');
    return problem(controller.signal.aborted ? 504 : 502, 'upstream_unavailable', controller.signal.aborted ? 'The API request timed out.' : 'The S API is unavailable.');
  } finally { clearTimeout(timeout); }
}
export function methodNotAllowed(allow: string): Response {
  return Response.json({ error: { code: 'method', message: 'method not allowed' } }, { status: 405, headers: { allow } });
}
export async function withoutBody(response: Response): Promise<Response> {
  const headers = new Headers(response.headers);
  const bytes = await response.arrayBuffer();
  headers.set('content-length', String(bytes.byteLength));
  return new Response(null, { status: response.status, headers });
}
