'use client';
import { useCallback, useEffect, useState, type FormEvent } from 'react';
type User = { id: string; name: string; email: string; age: number | null };
type Form = { name: string; email: string; age: string };
const empty: Form = { name: '', email: '', age: '' };
async function api<T>(path: string, method = 'GET', body?: unknown): Promise<T> {
 const response = await fetch(path, { method, headers: { 'content-type': 'application/json' }, body: body === undefined ? undefined : JSON.stringify(body), cache: 'no-store' });
 if (response.status === 204) return undefined as T;
 let data;
 try { data = await response.json(); } catch { throw new Error(`The server returned an unreadable response (${response.status}).`); }
 if (!response.ok) throw new Error(data?.error?.message || `Request failed (${response.status}).`);
 return data as T;
}
export default function Page() {
 const [users, setUsers] = useState<User[]>([]);
 const [form, setForm] = useState<Form>(empty);
 const [editing, setEditing] = useState<string | null>(null);
 const [error, setError] = useState('');
 const [notice, setNotice] = useState('');
 const [loading, setLoading] = useState(true);
 const [busy, setBusy] = useState(false);
 const load = useCallback(async () => {
  setLoading(true);
  try { const result = await api<{users: User[]}>('/api/users'); setUsers(result.users); }
  catch (error) { setError(error instanceof Error ? error.message : 'Could not load users.'); }
  finally { setLoading(false); }
 }, []);
 useEffect(() => { void load(); }, [load]);
 async function save(event: FormEvent<HTMLFormElement>) {
  event.preventDefault(); setBusy(true); setError(''); setNotice('');
  try {
   await api<User>(editing ? `/api/users/${encodeURIComponent(editing)}` : '/api/users', editing ? 'PUT' : 'POST', { name: form.name, email: form.email, age: form.age === '' ? null : Number(form.age) });
   setNotice(editing ? 'Changes saved.' : 'User created.'); setForm(empty); setEditing(null); await load();
  } catch (error) { setError(error instanceof Error ? error.message : 'Could not save user.'); }
  finally { setBusy(false); }
 }
 async function edit(id: string) {
  setBusy(true); setError(''); setNotice('');
  try { const user = await api<User>(`/api/users/${encodeURIComponent(id)}`); setEditing(id); setForm({name:user.name,email:user.email,age:user.age === null ? '' : String(user.age)}); }
  catch (error) { setError(error instanceof Error ? error.message : 'Could not open user.'); }
  finally { setBusy(false); }
 }
 async function remove(user: User) {
  if (!window.confirm(`Delete ${user.name}?`)) return;
  setBusy(true); setError(''); setNotice('');
  try {
   await api<void>(`/api/users/${encodeURIComponent(user.id)}`, 'DELETE');
   if (editing === user.id) { setEditing(null); setForm(empty); }
   setNotice('User deleted.'); await load();
  } catch (error) { setError(error instanceof Error ? error.message : 'Could not delete user.'); }
  finally { setBusy(false); }
 }
 return <main>
  <nav><a className="brand" href="/">s<span>.</span> <b>PEOPLE</b></a><span className="tag">S REST API / NEXT.JS</span></nav>
  <header><p className="eyebrow">A LITTLE MORE HUMAN</p><h1>Good people.<br/><span>One place.</span></h1><p className="intro">Keep your directory simple. Add someone new,<br className="desktop"/> update the details, and get on with your day.</p></header>
  {error && <div role="alert" className="message error">{error}</div>}
  {notice && <div role="status" className="message success">{notice}</div>}
  <section className="workspace">
   <div className="directory"><div className="section-title"><div><span className="eyebrow">YOUR DIRECTORY</span><h2>Everyone <span className="count">{users.length}</span></h2></div><button className="quiet" disabled={loading || busy} onClick={() => {setError(''); void load();}}>↻ Refresh</button></div>
    {loading ? <p role="status" className="empty">Loading your people…</p> : users.length === 0 ? <div className="empty"><span className="empty-symbol">+</span><h3>A fresh start.</h3><p>Add your first person using the form.</p></div> : <ul className="people">{users.map(user => <li key={user.id}><span aria-hidden="true" className="avatar">{user.name.slice(0,1).toUpperCase()}</span><div className="details"><strong>{user.name}</strong><span>{user.email}</span><small>{user.age === null ? 'Age not provided' : `${user.age} years old`}</small></div><div className="actions"><button disabled={busy} onClick={() => void edit(user.id)} aria-label={`Edit ${user.name}`}>Edit</button><button disabled={busy} onClick={() => void remove(user)} aria-label={`Delete ${user.name}`} className="delete">Delete</button></div></li>)}</ul>}
   </div>
   <aside><span className="eyebrow">{editing ? 'A QUICK UPDATE' : 'MAKE AN INTRODUCTION'}</span><h2>{editing ? 'Edit person' : 'Add a person'}<span className="accent">↗</span></h2><p className="form-note">{editing ? 'Keep their details up to date.' : 'Every directory begins with a name.'}</p>
    <form onSubmit={save}><label>Full name<input name="name" required maxLength={200} autoComplete="name" placeholder="Ada Lovelace" value={form.name} onChange={e=>setForm({...form,name:e.target.value})}/></label><label>Email address<input name="email" type="email" required maxLength={320} autoComplete="email" placeholder="ada@example.com" value={form.email} onChange={e=>setForm({...form,email:e.target.value})}/></label><label>Age <span className="optional">optional</span><input name="age" type="number" min="0" max="150" step="1" placeholder="—" value={form.age} onChange={e=>setForm({...form,age:e.target.value})}/></label><button className="primary" disabled={busy} type="submit">{busy ? 'Working…' : editing ? 'Save changes' : 'Add person'} <span>→</span></button>{editing && <button type="button" className="cancel" disabled={busy} onClick={()=>{setEditing(null);setForm(empty);}}>Cancel editing</button>}</form>
   </aside>
  </section><footer><span>Small directory. Real connections.</span><span>Built with S + Next.js</span></footer>
 </main>;
}
