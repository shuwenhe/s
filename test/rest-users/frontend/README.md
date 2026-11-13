# S users frontend

Requires Node.js 22.18+ (Node's built-in TypeScript stripping runs the transport tests).

```sh
npm ci
npm test
npm run typecheck
npm run build
S_API_ORIGIN=http://127.0.0.1:8080 npm start -- --port 3000
```

Open http://127.0.0.1:3000. The browser calls the same-origin Next.js
`/api/users` and `/api/users/:id` routes. They forward only to the configured
`S_API_ORIGIN` (default `http://127.0.0.1:8080`). No URL, path, query, cookie,
or authorization header supplied by a browser selects an upstream host.
Query strings and the provided Content-Type are forwarded as request data; S
validates them. Safe upstream Allow headers are preserved.
The S application owns all user validation and database operations.

POST/PUT bodies are read incrementally and rejected above 65536 bytes,
even without Content-Length. Upstream response bodies are bounded to 1 MiB.
Requests time out after ten seconds and upstream redirects are rejected.
The UI supports listing, reading for editing, creating, updating, and deleting
users, and renders errors returned by S. No database logic runs in Next.js.

For local development, use `npm run dev -- --port 3000`.

## Real browser CRUD verification

```sh
PLAYWRIGHT_BROWSERS_PATH=/tmp/s-rest-playwright npx playwright install chromium
NEXT_BASE_URL=http://127.0.0.1:3000 node tests/browser.mjs
```

Start the real S/MySQL application and production Next server before running.
The test drives hydrated React controls and checks the network responses for
list/read/create/update/delete, Unicode fields, duplicate-email 409 errors, and
empty 204 responses. It generates a unique `@s-rest.invalid` email and cleans
up only records it creates, including after an assertion failure. Missing
configuration or a missing browser reports `BLOCKED` and exits with code 2.
