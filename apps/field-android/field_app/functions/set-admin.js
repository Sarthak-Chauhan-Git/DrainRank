
const { initializeApp, applicationDefault } = require("firebase-admin/app");
const { getAuth } = require("firebase-admin/auth");

initializeApp({
  credential: applicationDefault(),
});

async function main() {
  const uid = process.argv[2];

  if (!uid) {
    console.error("Usage: node set-admin.js FIREBASE_AUTH_UID");
    process.exitCode = 1;
    return;
  }

  await getAuth().setCustomUserClaims(uid, { admin: true });
  console.log("Admin permission assigned successfully.");
}

main().catch((error) => {
  console.error("Failed to assign admin permission:", error.message);
  process.exitCode = 1;
});
