
const {
  initializeApp,
  applicationDefault,
} = require("firebase-admin/app");

const { getAuth } = require("firebase-admin/auth");

const {
  getFirestore,
  FieldValue,
} = require("firebase-admin/firestore");

initializeApp({
  credential: applicationDefault(),
  projectId: "my-login-app-71981",
});

const auth = getAuth();
const db = getFirestore();

async function main() {
  const municipalId = (process.argv[2] || "")
    .trim()
    .toUpperCase();

  const fullName = (process.argv[3] || "").trim();
  const password = process.env.CREW_PASSWORD;

  // Validate Municipal ID
  if (!/^[A-Z0-9-]{3,30}$/.test(municipalId)) {
    throw new Error(
      "Municipal ID must contain 3-30 letters, numbers, or hyphens."
    );
  }

  // Validate name
  if (fullName.length < 2 || fullName.length > 100) {
    throw new Error("Enter a valid full name (2-100 characters).");
  }

  // Validate password
  if (!password || password.length < 8) {
    throw new Error(
      "Set CREW_PASSWORD to a password of at least 8 characters."
    );
  }

  const email =
    `${municipalId.toLowerCase()}@crew.municipal.local`;

  const idRef = db.collection("municipalIds").doc(municipalId);

  let user = null;
  let reservationCreated = false;

  try {
    // Reserve the Municipal ID so it cannot be assigned twice.
    await db.runTransaction(async (transaction) => {
      const existing = await transaction.get(idRef);

      if (existing.exists) {
        throw new Error("This Municipal ID is already assigned.");
      }

      transaction.create(idRef, {
        municipalId,
        status: "creating",
        createdAt: FieldValue.serverTimestamp(),
      });
    });

    reservationCreated = true;

    // Create Firebase Authentication account.
    user = await auth.createUser({
      email,
      password,
      displayName: fullName,
      disabled: false,
    });

    // Create the user's Firestore profile.
    await db.collection("users").doc(user.uid).set({
      municipalId,
      fullName,
      accessBlocked: false,
      createdAt: FieldValue.serverTimestamp(),
    });

    // Mark the Municipal ID as active.
    await idRef.set({
      municipalId,
      uid: user.uid,
      status: "active",
      createdAt: FieldValue.serverTimestamp(),
    });

    console.log("Crew account created successfully.");
    console.log(`Municipal ID: ${municipalId}`);
    console.log(`Crew name: ${fullName}`);
  } catch (error) {
    // Roll back resources created during this attempt.
    if (user) {
      await db.collection("users").doc(user.uid).delete().catch(() => {});
      await auth.deleteUser(user.uid).catch(() => {});
    }

    if (reservationCreated) {
      await idRef.delete().catch(() => {});
    }

    throw error;
  }
}

main().catch((error) => {
  console.error("Account creation failed:", error.message);
  process.exitCode = 1;
});
