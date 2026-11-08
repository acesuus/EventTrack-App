const path = require('node:path');
const fs = require('node:fs');
const project = 'event-track-46f63';
const email = process.env.EVENTTRACK_ADMIN_EMAIL;
const password = process.env.EVENTTRACK_ADMIN_PASSWORD;
const npmRoot = require('node:child_process').execSync('npm root -g').toString().trim();
const cli = path.join(npmRoot, 'firebase-tools/lib');

(async () => {
  if (!email || !password) throw Error('Set EVENTTRACK_ADMIN_EMAIL and EVENTTRACK_ADMIN_PASSWORD.');
  const config = JSON.parse(fs.readFileSync('android/app/google-services.json', 'utf8'));
  if (config.project_info.project_id !== project) throw Error('Firebase project mismatch.');
  await require(path.join(cli, 'requireAuth')).requireAuth({
    project, ...require(path.join(cli, 'auth')).getGlobalDefaultAccount(),
  });
  const { Client } = require(path.join(cli, 'apiv2'));
  const api = new Client({ urlPrefix: 'https://identitytoolkit.googleapis.com', apiVersion: 'v1' });
  const quiet = () => ({ skipLog: { body: true, resBody: true } });
  const lookup = await api.post(`/projects/${project}/accounts:lookup`, { email: [email] }, quiet());
  let user = lookup.body.users?.[0];
  if (!user) {
    const created = await api.post(`/projects/${project}/accounts`, {
      email, password, displayName: 'Administrator',
    }, quiet());
    user = created.body;
  }
  const claims = { ...JSON.parse(user.customAttributes || '{}'), admin: true };
  await api.post(`/projects/${project}/accounts:update`, {
    localId: user.localId, password, customAttributes: JSON.stringify(claims), disabled: false,
  }, quiet());

  // Exercise the same password sign-in and admin claim check as the Flutter app.
  const publicApi = new Client({ urlPrefix: 'https://identitytoolkit.googleapis.com', apiVersion: 'v1', auth: false });
  const key = config.client[0].api_key[0].current_key;
  const session = await publicApi.post(`/accounts:signInWithPassword?key=${encodeURIComponent(key)}`, {
    email, password, returnSecureToken: true,
  }, quiet());
  const token = JSON.parse(Buffer.from(session.body.idToken.split('.')[1], 'base64url').toString('utf8'));
  if (token.admin !== true || token.aud !== project || token.email !== email) throw Error('Admin sign-in verification failed.');
  console.log(`Administrator ready: ${email}. Password sign-in and administrator access verified.`);
})().catch(error => { console.error(error.message); process.exitCode = 1; });
