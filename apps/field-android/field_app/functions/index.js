
const { onCall, HttpsError } = require("firebase-functions/v2/https");
const { initializeApp } = require("firebase-admin/app");
const { getAuth } = require("firebase-admin/auth");
const { getFirestore, FieldValue } = require("firebase-admin/firestore");

initializeApp();

const db = getFirestore();
const auth = getAuth();

exports.createCrewAccount = onCall(async (request) => {
  // Only an authenticated administrator can create accounts.
  if (!request.auth || request.auth.token.admin !== true) {
    throw new HttpsError(
      "permission-denied",
      "Only the Municipal Board administrator can create accounts."
    );
  }

  const municipalId = String(request.data.municipalId || "")
    .trim()
    .toUpperCase();
  const fullName = String(request.data.fullName || "").trim();
  const password = String(request.data.password || "");

  if (!/^[A-Z0-9-]{3,30}$/.test(municipalId)) {
    throw new HttpsError(
      "invalid-argument",
      "Municipal ID must contain 3-30 letters, numbers, or hyphens."
    );
  }

  if (fullName.length < 2 || fullName.length > 100) {
    throw new HttpsError("invalid-argument", "Enter a valid full name.");
  }

  if (password.length < 8) {
    throw new HttpsError(
      "invalid-argument",
      "Password must be at least 8 characters."
    );
  }

  const email =
    `${municipalId.toLowerCase()}@crew.municipal.local`;
  const idRef = db.collection("municipalIds").doc(municipalId);

  try {
    // Reserve this Municipal ID so it cannot be assigned twice.
    await db.runTransaction(async (transaction) => {
      const existing = await transaction.get(idRef);

      if (existing.exists) {
        throw new HttpsError(
          "already-exists",
          "This Municipal ID is already assigned."
        );
      }

      transaction.create(idRef, {
        municipalId,
        status: "creating",
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

      await db.collection("users").doc(user.uid).set({
        municipalId,
        fullName,
        accessBlocked: false,
        createdAt: FieldValue.serverTimestamp(),
      });

      await idRef.set({
        municipalId,
        uid: user.uid,
        status: "active",
        createdAt: FieldValue.serverTimestamp(),
      });
    } catch (error) {
      // Clean up partial creation if an operation fails.
      if (user) {
        await auth.deleteUser(user.uid).catch(() => {});
        await db.collection("users").doc(user.uid).delete().catch(() => {});
      }

      await idRef.delete().catch(() => {});
      throw error;
    }

    return {
      success: true,
      municipalId,
      message: "Crew account created successfully.",
    };
  } catch (error) {
    if (error instanceof HttpsError) throw error;

    if (error.code === "auth/email-already-exists") {
      throw new HttpsError(
        "already-exists",
        "This Municipal ID already has an account."
      );
    }

    console.error("createCrewAccount failed:", error);
    throw new HttpsError("internal", "Could not create crew account.");
  }
});
