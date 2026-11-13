import { proxy, methodNotAllowed, withoutBody } from '../../../../lib/proxy.ts';
export const runtime = 'nodejs';
export const dynamic = 'force-dynamic';
type Context = { params: Promise<{ id: string }> };
export async function GET(request: Request, context: Context) { return proxy(request, 'GET', (await context.params).id); }
export async function PUT(request: Request, context: Context) { return proxy(request, 'PUT', (await context.params).id); }
export async function DELETE(request: Request, context: Context) { return proxy(request, 'DELETE', (await context.params).id); }
export async function HEAD(request: Request, context: Context) { return withoutBody(await GET(request, context)); }
function unsupported() { return methodNotAllowed('GET, HEAD, PUT, DELETE'); }
export const POST = unsupported;
export const PATCH = unsupported;
export const OPTIONS = unsupported;
