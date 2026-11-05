// Explicit project guard; backup is the default. Reset requires a completed backup.
const fs = require('node:fs');
const path = require('node:path');
const crypto = require('node:crypto');
const project = 'event-track-46f63';
const cli = path.join(process.env.APPDATA, 'npm/node_modules/firebase-tools/lib');
const { Client } = require(path.join(cli, 'apiv2'));
const mode = process.argv[2] || 'backup';
const quiet = { skipLog: { body: true, resBody: true } };
const firestore = new Client({ urlPrefix: 'https://firestore.googleapis.com', apiVersion: 'v1' });
const auth = new Client({ urlPrefix: 'https://identitytoolkit.googleapis.com', apiVersion: 'v1' });

async function collectionIds(parent) {
  const ids = [];
  let pageToken;
  do {
    const r = await firestore.post(`/${parent}:listCollectionIds`, { pageSize: 1000, ...(pageToken ? { pageToken } : {}) }, { ...quiet });
    ids.push(...(r.body.collectionIds || []));
    pageToken = r.body.nextPageToken;
  } while (pageToken);
  return ids;
}

async function scanCollection(parent, id, documents) {
  let pageToken;
  do {
    const query = new URLSearchParams({ pageSize: '1000', showMissing: 'true' });
    if (pageToken) query.set('pageToken', pageToken);
    const r = await firestore.get(`/${parent}/${encodeURIComponent(id)}?${query}`, { ...quiet });
    const docs = r.body.documents || [];
    for (let i = 0; i < docs.length; i += 8) {
      await Promise.all(docs.slice(i, i + 8).map(async (doc) => {
        if (doc.createTime || doc.updateTime) documents.push(doc);
        for (const child of await collectionIds(doc.name)) {
          await scanCollection(doc.name, child, documents);
        }
      }));
    }
    pageToken = r.body.nextPageToken;
  } while (pageToken);
}

async function scanFirestore() {
  const r = await firestore.get(`/projects/${project}/databases`, { ...quiet });
  const databases = [];
  for (const db of r.body.databases || []) {
    const documents = [];
    const root = `${db.name}/documents`;
    const collections = await collectionIds(root);
    for (const id of collections) await scanCollection(root, id, documents);
    databases.push({ name: db.name, collections, documents });
    console.log(`Firestore ${db.name.split('/').pop()}: ${documents.length} documents across ${collections.length} root collections.`);
  }
  return databases;
}

async function users() {
  const all = [];
  let pageToken;
  do {
    const query = new URLSearchParams({ maxResults: '1000' });
    if (pageToken) query.set('nextPageToken', pageToken);
    const r = await auth.get(`/projects/${project}/accounts:batchGet?${query}`, { ...quiet });
    all.push(...(r.body.users || []));
    pageToken = r.body.nextPageToken;
  } while (pageToken);
  return all;
}

function writeJson(filename, data) {
  fs.writeFileSync(filename, JSON.stringify(data, null, 2), { flag: 'wx', mode: 0o600 });
}

(async () => {
  if (!['backup', 'reset', 'verify'].includes(mode)) throw Error('Expected backup, reset, or verify.');
  await require(path.join(cli, 'requireAuth')).requireAuth({
    project, ...require(path.join(cli, 'auth')).getGlobalDefaultAccount(),
  });
  if (mode === 'backup') {
    const databases = await scanFirestore();
    const accounts = await users();
    console.log(`Authentication: ${accounts.length} accounts.`);
    const dir = path.resolve('firebase-backups', `reset-${new Date().toISOString().replace(/[:.]/g, '-')}`);
    fs.mkdirSync(dir, { recursive: true });
    writeJson(path.join(dir, 'firestore.json'), { project, databases });
    writeJson(path.join(dir, 'auth-users.json'), { project, users: accounts });
    const configApi = new Client({ urlPrefix: 'https://identitytoolkit.googleapis.com', apiVersion: 'v2' });
    let configBackedUp = false;
    try {
      const config = await configApi.get(`/projects/${project}/config`, { ...quiet });
      writeJson(path.join(dir, 'auth-config.json'), config.body);
      configBackedUp = true;
    } catch {
      console.log('Auth configuration could not be exported; account data is backed up.');
    }
    const manifest = { project, createdAt: new Date().toISOString(), configBackedUp,
      documentCount: databases.reduce((n, db) => n + db.documents.length, 0),
      accountCount: accounts.length, hashes: {} };
    for (const file of ['firestore.json', 'auth-users.json']) {
      manifest.hashes[file] = crypto.createHash('sha256').update(fs.readFileSync(path.join(dir, file))).digest('hex');
    }
    writeJson(path.join(dir, 'manifest.json'), manifest);
    console.log(`Backup complete: ${dir}`);
    return;
  }
  if (mode === 'reset') {
    if (process.argv[4] !== project) throw Error('Explicit matching project argument required.');
    const dir = path.resolve(process.argv[3] || '');
    const manifest = JSON.parse(fs.readFileSync(path.join(dir, 'manifest.json')));
    if (manifest.project !== project) throw Error('Backup project mismatch.');
    for (const [file, hash] of Object.entries(manifest.hashes)) {
      if (crypto.createHash('sha256').update(fs.readFileSync(path.join(dir, file))).digest('hex') !== hash) throw Error('Backup checksum mismatch.');
    }
    const data = JSON.parse(fs.readFileSync(path.join(dir, 'firestore.json')));
    const accounts = JSON.parse(fs.readFileSync(path.join(dir, 'auth-users.json')));
    if (data.project !== project || accounts.project !== project) throw Error('Backup data project mismatch.');
    // Delete only the backed-up versions; concurrent edits abort rather than lose unbacked data.
    for (const db of data.databases) {
      if (!db.name.startsWith(`projects/${project}/databases/`)) throw Error('Database project mismatch.');
      for (let i = 0; i < db.documents.length; i += 200) {
        const batch = db.documents.slice(i, i + 200);
        const writes = batch.map(doc => {
          if (!doc.name.startsWith(`${db.name}/documents/`)) throw Error('Document project mismatch.');
          return { delete: doc.name, currentDocument: { updateTime: doc.updateTime } };
        });
        await firestore.post(`/${db.name}/documents:commit`, { writes }, { ...quiet });
        console.log(`Deleted ${batch.length} backed-up Firestore documents.`);
      }
    }
    for (let i = 0; i < accounts.users.length; i += 1000) {
      const batch = accounts.users.slice(i, i + 1000);
      const r = await auth.post(`/projects/${project}/accounts:batchDelete`, {
        localIds: batch.map(user => user.localId), force: true,
      }, { ...quiet });
      if (r.body.errors?.length) throw Error(`Authentication deletion had ${r.body.errors.length} errors.`);
      console.log(`Deleted ${batch.length} backed-up login accounts.`);
    }
  }
  const databases = await scanFirestore();
  const accounts = await users();
  const remaining = databases.reduce((n, db) => n + db.documents.length, 0);
  console.log(`Verification: ${remaining} Firestore documents; ${accounts.length} login accounts.`);
  if (remaining || accounts.length) throw Error('Reset incomplete; records remain.');
})().catch(error => {
  console.error(error.message);
  if (error.original?.message) console.error(error.original.message);
  if (error.original?.code) console.error(`Network code: ${error.original.code}`);
  process.exitCode = 1;
});
