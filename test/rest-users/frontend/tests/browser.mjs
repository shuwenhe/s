import assert from 'node:assert/strict';
import { randomUUID } from 'node:crypto';

const supplied = process.env.NEXT_BASE_URL;
if (!supplied) {
  console.error('BLOCKED: NEXT_BASE_URL is required; start the real Next.js and S/MySQL services first.');
  process.exit(2);
}
let base;
try {
  base = new URL(supplied);
  if (!['http:', 'https:'].includes(base.protocol) || base.pathname !== '/' || base.username || base.password || base.search || base.hash) throw new Error('expected a bare HTTP(S) origin');
} catch (error) {
  console.error(`BLOCKED: invalid NEXT_BASE_URL: ${error.message}`);
  process.exit(2);
}
process.env.PLAYWRIGHT_BROWSERS_PATH ||= '/tmp/s-rest-playwright';
let chromium;
try { ({ chromium } = await import('playwright')); }
catch (error) { console.error(`BLOCKED: Playwright unavailable: ${error.message}`); process.exit(2); }
let browser;
try { browser = await chromium.launch({ headless: true }); }
catch (error) { console.error(`BLOCKED: Chromium unavailable in ${process.env.PLAYWRIGHT_BROWSERS_PATH}: ${error.message}`); process.exit(2); }

const email = `browser-${randomUUID()}@s-rest.invalid`;
const initialName = '张三 Browser';
const editedName = '李四';
let createdId;
const ownIds = new Set();
let deleted = false;
let failed = false;
const observed = [];
const pageErrors = [];
const page = await browser.newPage();
page.setDefaultTimeout(20_000);
page.on('pageerror', error => pageErrors.push(error.message));
page.on('dialog', dialog => dialog.accept());
page.on('response', async response => {
  if (response.request().method() !== 'POST' || response.status() !== 201 || new URL(response.url()).pathname !== '/api/users') return;
  try { const user = await response.json(); if (user.email === email && typeof user.id === 'string') ownIds.add(user.id); } catch { /* Main assertions report invalid responses. */ }
});
function responseFor(method, pathname, status) {
  const pending = page.waitForResponse(response => {
    const url = new URL(response.url());
    return url.origin === base.origin && url.pathname === pathname && response.request().method() === method && response.status() === status;
  });
  void pending.catch(() => {});
  return pending;
}
async function record(response, method, status) {
  assert.equal(response.status(), status);
  assert.equal(response.request().method(), method);
  const payload = status === 204 ? undefined : await response.json();
  observed.push(`${method} ${new URL(response.url()).pathname} ${status}`);
  return payload;
}
async function visibleText(locator, expected) {
  await locator.filter({ hasText: expected }).waitFor({ state: 'visible' });
}
async function fill(name, age) {
  await page.getByRole('textbox', { name: 'Full name', exact: true }).fill(name);
  await page.getByRole('textbox', { name: 'Email address', exact: true }).fill(email);
  await page.getByRole('spinbutton', { name: 'Age optional', exact: true }).fill(String(age));
}
try {
  const listing = responseFor('GET', '/api/users', 200);
  await page.goto(base.href, { waitUntil: 'domcontentloaded' });
  const list = await record(await listing, 'GET', 200);
  assert.ok(Array.isArray(list.users), 'GET collection must return users');
  await page.getByRole('heading', { name: /Good people\./ }).waitFor({ state: 'visible' });

  await fill(initialName, 26);
  const creating = responseFor('POST', '/api/users', 201);
  await page.getByRole('button', { name: 'Add person', exact: false }).click();
  const created = await record(await creating, 'POST', 201);
  assert.equal(typeof created.id, 'string');
  assert.ok(created.id.length > 0);
  createdId = created.id;
  ownIds.add(createdId);
  assert.equal(created.name, initialName);
  assert.equal(created.email, email);
  assert.equal(created.age, 26);
  await visibleText(page.getByRole('status'), 'User created.');
  let row = page.getByRole('listitem').filter({ hasText: email });
  await visibleText(row, initialName);

  const reading = responseFor('GET', `/api/users/${encodeURIComponent(createdId)}`, 200);
  await row.getByRole('button', { name: `Edit ${initialName}`, exact: true }).click();
  const read = await record(await reading, 'GET', 200);
  assert.equal(read.id, createdId);
  assert.equal(read.name, initialName);
  await page.getByRole('heading', { name: 'Edit person', exact: false }).waitFor({ state: 'visible' });
  await fill(editedName, 37);
  const updating = responseFor('PUT', `/api/users/${encodeURIComponent(createdId)}`, 200);
  await page.getByRole('button', { name: 'Save changes', exact: false }).click();
  const updated = await record(await updating, 'PUT', 200);
  assert.equal(updated.id, createdId);
  assert.equal(updated.name, editedName);
  assert.equal(updated.email, email);
  assert.equal(updated.age, 37);
  await visibleText(page.getByRole('status'), 'Changes saved.');
  row = page.getByRole('listitem').filter({ hasText: email });
  await visibleText(row, editedName);
  await visibleText(row, '37 years old');

  await fill('Duplicate Browser', 40);
  const duplicateResponse = responseFor('POST', '/api/users', 409);
  await page.getByRole('button', { name: 'Add person', exact: false }).click();
  const duplicate = await record(await duplicateResponse, 'POST', 409);
  assert.equal(typeof duplicate.error?.code, 'string');
  assert.equal(typeof duplicate.error?.message, 'string');
  assert.ok(duplicate.error.message.length > 0);
  await visibleText(page.getByRole('alert'), duplicate.error.message);
  assert.equal(await row.count(), 1, 'duplicate rejection must not create a second row');

  const deleting = responseFor('DELETE', `/api/users/${encodeURIComponent(createdId)}`, 204);
  await row.getByRole('button', { name: `Delete ${editedName}`, exact: true }).click();
  const removed = await deleting;
  await record(removed, 'DELETE', 204);
  assert.equal(await removed.text(), '');
  deleted = true;
  ownIds.delete(createdId);
  await visibleText(page.getByRole('status'), 'User deleted.');
  await row.waitFor({ state: 'detached' });
  assert.deepEqual(pageErrors, [], 'hydrated React page raised browser errors');
  for (const request of observed) console.log(request);
  console.log(`browser: PASS — hydrated React CRUD, Unicode, duplicate 409, empty 204; test email ${email}`);
} catch (error) {
  failed = true;
  console.error(`browser: FAIL — ${error.stack || error}`);
} finally {
  if (createdId && !deleted) ownIds.add(createdId);
  for (const ownId of ownIds) {
    try {
      const result = await fetch(new URL(`/api/users/${encodeURIComponent(ownId)}`, base), { method: 'DELETE', signal: AbortSignal.timeout(10_000) });
      if (![204, 404].includes(result.status)) throw new Error(`cleanup returned ${result.status}: ${await result.text()}`);
      console.log(`cleanup: deleted own test user ${ownId}`);
    } catch (error) { failed = true; console.error(`cleanup: FAIL — ${error.message}`); }
  }
  await browser.close();
}
if (failed) process.exitCode = 1;
