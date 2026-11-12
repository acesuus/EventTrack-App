// Adds sample BSCS 4th-year students and their attendance to the existing
// "GENERAL ASSEMBLY" event, for demos. The event itself is never changed.
// Uses the locally signed-in Firebase CLI account.
//   node scripts/seed-sample.cjs           add or refresh the sample data
//   node scripts/seed-sample.cjs --delete  remove it again
const path = require('node:path');
const npmRoot = require('node:child_process').execSync('npm root -g').toString().trim();
const cli = path.join(npmRoot, 'firebase-tools/lib');
const project = 'event-track-46f63';
const db = `projects/${project}/databases/(default)/documents`;

const eventId = 'XXgKci9MdJ6GLne1zMja'; // GENERAL ASSEMBLY, created in the admin app

// [name, studentId, status, minutes from start at time in, left venue, came back]. No time in = Absent.
// Kert-Ace Ombion is the real account 202380358@psu.palawan.edu.ph; the other IDs are made up.
const students = [
  ['Kert-Ace Ombion', '2023-8-0358', 'Present', -8],
  ['Samir Araah', '2023-0-0001', 'Present', -12],
  ['Ralph Angelo Badang', '2023-0-0002', 'Present', -5],
  ['John Russel Cabailo', '2023-0-0003', 'Late', 24],
  ['Jon Richmond Vitug', '2023-0-0004', 'Present', 5],
  ['Edrian Bantog', '2023-0-0005', 'Partial', -2, 40, 80],
  ['Ruzz Romil Serra', '2023-0-0006', 'Late', 31],
  ['Marlon Murillo', '2023-0-0007', 'Present', 10],
  ['Datu Lachica', '2023-0-0008', 'Absent'],
];
// Must match AttendancePolicy.pointsFor.
const points = (s, base) => (s === 'Present' ? base : ['Late', 'Partial'].includes(s) ? Math.round(base / 2) : 0);

const value = (v) => {
  if (v === null) return { nullValue: null };
  if (v instanceof Date) return { timestampValue: v.toISOString() };
  if (typeof v === 'boolean') return { booleanValue: v };
  if (Number.isInteger(v)) return { integerValue: String(v) };
  if (typeof v === 'number') return { doubleValue: v };
  if (typeof v === 'string') return { stringValue: v };
  if (Array.isArray(v)) return { arrayValue: { values: v.map(value) } };
  return { mapValue: { fields: Object.fromEntries(Object.entries(v).map(([k, x]) => [k, value(x)])) } };
};

function sampleDocs(event) {
  const start = new Date(event.startTime.timestampValue);
  const end = new Date(event.endTime.timestampValue);
  const base = Number(event.basePoints?.integerValue ?? 10);
  const title = event.title.stringValue.trim();
  const at = (minutes) => new Date(start.getTime() + minutes * 60000);
  const docs = {};
  for (const [name, studentId, status, timeIn, left, back] of students) {
    docs[`students/${studentId}`] = { studentId, name, program: 'BSCS', yearBlock: '4-A', sample: true };
    if (timeIn === undefined) continue;
    const sessions = left
      ? [{ timeIn: at(timeIn), timeOut: at(left) }, { timeIn: at(back), timeOut: end }]
      : [{ timeIn: at(timeIn), timeOut: end }];
    docs[`attendance/${studentId}_${eventId}`] = {
      schemaVersion: 4,
      studentId,
      eventId,
      eventTitle: title,
      eventName: title,
      eventType: event.eventType?.stringValue ?? 'type2_continuous',
      initialStatus: status === 'Partial' ? 'Present' : status,
      status,
      timeIn: at(timeIn),
      timeOut: end,
      totalOutsideSeconds: left ? (back - left) * 60 : 0,
      sessions,
      lastVerified: end,
      pointsAwarded: points(status, base),
      sample: true,
    };
  }
  return docs;
}

(async () => {
  const remove = process.argv.includes('--delete');
  await require(path.join(cli, 'requireAuth')).requireAuth({
    project, ...require(path.join(cli, 'auth')).getGlobalDefaultAccount(),
  });
  const { Client } = require(path.join(cli, 'apiv2'));
  const api = new Client({ urlPrefix: 'https://firestore.googleapis.com', apiVersion: 'v1' });
  const quiet = { skipLog: { body: true, resBody: true } };
  const event = (await api.get(`/${db}/events/${eventId}`, quiet)).body.fields;
  const writes = Object.entries(sampleDocs(event)).map(([p, data]) => remove
    ? { delete: `${db}/${p}` }
    : { update: { name: `${db}/${p}`, fields: value(data).mapValue.fields } });
  await api.post(`/${db}:commit`, { writes }, quiet);
  console.log(`${remove ? 'Deleted' : 'Wrote'} ${writes.length} sample documents.`);
})().catch((e) => { console.error(e.message || e); process.exit(1); });
