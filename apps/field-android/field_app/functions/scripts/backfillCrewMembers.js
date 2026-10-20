'use strict';

const {initializeApp, getApps} = require('firebase-admin/app');
const {getFirestore} = require('firebase-admin/firestore');
if (!getApps().length) initializeApp();
const db = getFirestore();
const {buildCrewMembers, normalizeUids} = require('../index');

(async () => {
  const tasks = await db.collection('tasks').get();
  let updated = 0;
  for (const task of tasks.docs) {
    const uids = normalizeUids(task.data().assignedToUid);
    if (!Array.isArray(task.data().assignedToUid)) continue;
    const members = await buildCrewMembers(uids);
    if (JSON.stringify(task.data().crewMembers ?? []) !== JSON.stringify(members)) {
      await task.ref.update({crewMembers: members});
      updated++;
    }
  }
  console.log(`Updated ${updated} of ${tasks.size} tasks.`);
})().catch((e) => {console.error(e); process.exitCode = 1;});
