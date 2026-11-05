// Uses the locally installed Firebase CLI and its signed-in account.
// Tests proposed rules without deploying them or modifying documents.
const path = require('node:path');
const fs = require('node:fs');
const cli = process.env.FIREBASE_TOOLS_LIB || path.join(process.env.APPDATA, 'npm/node_modules/firebase-tools/lib');
const project = 'event-track-46f63';

(async () => {
  await require(path.join(cli, 'requireAuth')).requireAuth({
    project, ...require(path.join(cli, 'auth')).getGlobalDefaultAccount(),
  });
  const { Client } = require(path.join(cli, 'apiv2'));
  const api = new Client({urlPrefix: 'https://firebaserules.googleapis.com', apiVersion: 'v1'});
  const tests = [];
  for (const auth of [null, {uid: 'ordinary', token: {}}, {uid: 'ordinary', token: {admin: false}}, {uid: 'admin', token: {admin: true}}]) {
    for (const document of ['students/demo', 'settings/schoolYear', 'events/demo']) {
      for (const method of ['get', 'list', 'create', 'update', 'delete']) {
        const allowed = (document.startsWith('events/') && ['get', 'list'].includes(method)) || auth?.token.admin === true;
        tests.push({expectation: allowed ? 'ALLOW' : 'DENY',
          request: {path: '/databases/(default)/documents/' + document, method, auth, resource: {data: {}}},
          resource: {data: {}},
        });
      }
    }
    tests.push({expectation: 'ALLOW', request: {
      path: '/databases/(default)/documents/users/demo', method: 'get', auth,
    }, resource: {data: {studentId: 'demo'}}});
    tests.push({expectation: 'ALLOW', request: {
      path: '/databases/(default)/documents/attendance/demo', method: 'create', auth,
      resource: {data: {studentId: 'demo', eventId: 'demo', status: 'Present', timeIn: null}},
    }});
  }
  const response = await api.post(`/projects/${project}:test`, {
    source: {files: [{name: 'firestore.rules', content: fs.readFileSync('firestore.rules', 'utf8')}]},
    testSuite: {testCases: tests},
  }, {skipLog: {body: true, resBody: true}});
  const failures = response.body.testResults?.filter(result => result.state !== 'SUCCESS') || [];
  if (response.body.issues?.some(issue => issue.severity === 'ERROR') ||
      response.body.testResults?.length !== tests.length || failures.length) {
    throw Error(JSON.stringify({issues: response.body.issues, failures}));
  }
  console.log(`${tests.length} access-rule tests passed (no documents modified).`);
})().catch(error => {console.error(error.message); process.exitCode = 1;});
