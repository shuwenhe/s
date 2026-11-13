import { proxy, methodNotAllowed, withoutBody } from '../../../lib/proxy.ts';
export const runtime = 'nodejs';
export const dynamic = 'force-dynamic';
export function GET(request: Request) { return proxy(request, 'GET'); }
export function POST(request: Request) { return proxy(request, 'POST'); }
export async function HEAD(request: Request) { return withoutBody(await GET(request)); }
function unsupported() { return methodNotAllowed('GET, HEAD, POST'); }
export const PUT = unsupported;
export const DELETE = unsupported;
export const PATCH = unsupported;
export const OPTIONS = unsupported;
