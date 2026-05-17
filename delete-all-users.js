const admin = require('firebase-admin');
const serviceAccount = require('./serviceAccountKey.json');

admin.initializeApp({
  credential: admin.credential.cert(serviceAccount)
});

const db = admin.firestore();

async function deleteAllUsers() {
  console.log('🗑️ Deleting all users from Firestore...');
  
  const usersSnapshot = await db.collection('users').get();
  
  if (usersSnapshot.empty) {
    console.log('ℹ️ No users found in Firebase');
    return;
  }
  
  const batch = db.batch();
  usersSnapshot.docs.forEach((doc) => {
    batch.delete(doc.ref);
  });
  
  await batch.commit();
  console.log(`✅ Deleted ${usersSnapshot.docs.length} users from Firebase`);
}

deleteAllUsers()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error('❌ Error:', error);
    process.exit(1);
  });
