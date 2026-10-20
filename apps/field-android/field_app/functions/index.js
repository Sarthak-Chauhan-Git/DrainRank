'use strict';

const { onCall, HttpsError } = require('firebase-functions/v2/https');
const { onDocumentWritten } = require('firebase-functions/v2/firestore');
const { initializeApp } = require('firebase-admin/app');
const { getAuth } = require('firebase-admin/auth');
const { getFirestore, FieldValue } = require('firebase-admin/firestore');

initializeApp();

const db = getFirestore();
const auth = getAuth();

// Existing function: preserved from your current index.js.
exports.createCrewAccount = onCall(async (request) => {
  if (!request.auth || request.auth.token.admin !== true) {
    throw new HttpsError(
      'permission-denied',
      'Only the Municipal Board administrator can create accounts.'
    );
  }

  const municipalId = String(request.data.municipalId || '')
    .trim()
    .toUpperCase();
  const fullName = String(request.data.fullName || '').trim();
  const password = String(request.data.password || '');

  if (!/^[A-Z0-9-]{3,30}$/.test(municipalId)) {
    throw new HttpsError(
      'invalid-argument',
      'Municipal ID must contain 3-30 letters, numbers, or hyphens.'
    );
  }
  if (fullName.length < 2 || fullName.length > 100) {
    throw new HttpsError('invalid-argument', 'Enter a valid full name.');
  }
  if (password.length < 8) {
    throw new HttpsError(
      'invalid-argument',
      'Password must be at least 8 characters.'
    );
  }

  const email = `${municipalId.toLowerCase()}@crew.municipal.local`;
  const idRef = db.collection('municipalIds').doc(municipalId);

  try {
    await db.runTransaction(async (transaction) => {
      const existing = await transaction.get(idRef);
      if (existing.exists) {
        throw new HttpsError(
          'already-exists',
          'This Municipal ID is already assigned.'
        );
      }
      transaction.create(idRef, {
        municipalId,
        status: 'creating',
        createdAt: FieldValue.serverTimestamp(),
      });
    });

    let user;
    try {
      user = await auth.createUser({
        email,
        password,
        displayName: fullName,
        disabled: false,
      });

      await db.collection('users').doc(user.uid).set({
        municipalId,
        fullName,
        accessBlocked: false,
        createdAt: FieldValue.serverTimestamp(),
      });

      await idRef.set({
        municipalId,
        uid: user.uid,
        status: 'active',
        createdAt: FieldValue.serverTimestamp(),
      });
    } catch (error) {
      if (user) {
        await auth.deleteUser(user.uid).catch(() => {});
        await db.collection('users').doc(user.uid).delete().catch(() => {});
      }
      await idRef.delete().catch(() => {});
      throw error;
    }

    return {
      success: true,
      municipalId,
      message: 'Crew account created successfully.',
    };
  } catch (error) {
    if (error instanceof HttpsError) throw error;
    if (error.code === 'auth/email-already-exists') {
      throw new HttpsError(
        'already-exists',
        'This Municipal ID already has an account.'
      );
    }
    console.error('createCrewAccount failed:', error);
    throw new HttpsError('internal', 'Could not create crew account.');
  }
});

// New helper: collect members from the assigned Firebase Auth UIDs.
function normalizeUids(value) {
  return Array.isArray(value)
    ? [...new Set(value.filter((uid) => typeof uid === 'string' && uid.length > 0))]
    : [];
}

async function buildCrewMembers(uids) {
  return Promise.all(uids.map(async (uid) => {
    const profileDoc = await db.collection('users').doc(uid).get();
    const profile = profileDoc.exists ? profileDoc.data() : {};
    const municipalId = typeof profile.municipalId === 'string'
      ? profile.municipalId.trim()
      : '';
    const municipalDoc = municipalId
      ? await db.collection('municipalIds').doc(municipalId).get()
      : null;
    const municipal = municipalDoc && municipalDoc.exists ? municipalDoc.data() : {};
    const matchesUid = municipal.uid === uid;

    return {
      uid,
      name: typeof profile.fullName === 'string' && profile.fullName.trim()
        ? profile.fullName.trim()
        : 'Crew member',
      phone: matchesUid && typeof municipal.contact === 'string'
        ? municipal.contact.trim()
        : '',
      role: 'Crew Member',
      municipalId,
    };
  }));
}

// New function: keep task crewMembers in sync whenever a task is written.
exports.syncTaskCrewMembers = onDocumentWritten(
  { document: 'tasks/{taskId}', region: 'asia-south2' },
  async (event) => {
    if (!event.data?.after?.exists) return;
    const initial = event.data.after.data();
    if (!Array.isArray(initial.assignedToUid)) return;
    const requested = normalizeUids(initial.assignedToUid);
    const members = await buildCrewMembers(requested);
    const taskRef = db.collection('tasks').doc(event.params.taskId);

    await db.runTransaction(async (tx) => {
      const latest = await tx.get(taskRef);
      if (!latest.exists) return;
      const data = latest.data();
      if (JSON.stringify(normalizeUids(data.assignedToUid)) !== JSON.stringify(requested)) return;
      if (JSON.stringify(data.crewMembers ?? []) === JSON.stringify(members)) return;
      tx.update(taskRef, { crewMembers: members });
    });
  }
);

// Helpers used by the one-time backfill script.
module.exports.buildCrewMembers = buildCrewMembers;
module.exports.normalizeUids = normalizeUids;
