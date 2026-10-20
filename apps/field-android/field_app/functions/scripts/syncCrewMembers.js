'use strict';
// Spark-plan task snapshot sync. Run only from a trusted administrator's computer.
// Uses Application Default Credentials; never embed credentials in the Flutter app.
const { initializeApp, getApps } = require('firebase-admin/app');
const { getFirestore } = require('firebase-admin/firestore');
if (!getApps().length) initializeApp();
const db = getFirestore();
const projectId = process.env.GOOGLE_CLOUD_PROJECT || process.env.GCLOUD_PROJECT;
if (!projectId) {
  console.error('Set GOOGLE_CLOUD_PROJECT to your Firebase project ID.');
  process.exit(1);
}
const target = process.argv[2];
const uniqueUids = value => Array.isArray(value)
  ? [...new Set(value.filter(x => typeof x === 'string' && x.trim()))]
  : [];
async function syncTask(doc) {
  const task = doc.data();
  const uids = uniqueUids(task.assignedToUid);
  if (!Array.isArray(task.assignedToUid)) {
    console.log(`SKIP ${doc.id}: assignedToUid is not an array`);
    return false;
  }
  const members = await Promise.all(uids.map(async uid => {
    const userSnap = await db.collection('users').doc(uid).get();
    if (!userSnap.exists) throw Error(`Missing users/${uid} for task ${doc.id}`);
    const user = userSnap.data();
    const municipalId = String(user.municipalId || '').trim();
    if (!municipalId) throw Error(`Missing municipalId for users/${uid}`);
    const municipalSnap = await db.collection('municipalIds').doc(municipalId).get();
    if (!municipalSnap.exists || municipalSnap.data().uid !== uid) {
      throw Error(`Mismatched municipalIds/${municipalId} for UID ${uid}`);
    }
    return {
      uid,
      municipalId,
      name: String(user.fullName || 'Crew member').trim(),
      phone: String(municipalSnap.data().contact || '').trim(),
      role: 'Crew Member',
    };
  }));
  // Guard against reassignment during the lookup. Firestore rules prevent crew from
  // updating crewMembers; only trusted admin credentials can write these snapshots.
  let updated = false;
  await db.runTransaction(async tx => {
    const latest = await tx.get(doc.ref);
    if (!latest.exists) return;
    if (JSON.stringify(uniqueUids(latest.data().assignedToUid)) !== JSON.stringify(uids)) {
      throw Error(`Assignment changed while syncing ${doc.id}; retry.`);
    }
    if (JSON.stringify(latest.data().crewMembers || []) === JSON.stringify(members)) return;
    tx.update(doc.ref, { crewMembers: members });
    updated = true;
  });
  console.log(`${updated ? 'UPDATED' : 'UNCHANGED'} ${doc.id}: ${members.length} crew members`);
  return updated;
}
(async () => {
  if (target && target !== '--all') {
    const doc = await db.collection('tasks').doc(target).get();
    if (!doc.exists) throw Error(`No tasks/${target} document exists`);
    await syncTask(doc);
  } else {
    const snapshot = await db.collection('tasks').get();
    for (const doc of snapshot.docs) await syncTask(doc);
  }
})().catch(err => { console.error(err); process.exitCode = 1; });
