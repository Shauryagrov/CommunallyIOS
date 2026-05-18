//
// userStatsTrigger.js
//
// Firestore-triggered Cloud Function. Recomputes /userStats/{userId}
// whenever a rating involving that user is created, updated, or
// deleted.
//
// Replaces the previous client-side write path. Per
// firestore.rules:177-180, any signed-in user could overwrite anyone
// else's stats — fake 5.0 ratings, sabotage competitors. With this
// trigger in place, `userStats` becomes server-only and the rule
// changes to `allow write: if false`.
//

const functions = require('firebase-functions');
const admin = require('firebase-admin');

exports.recomputeUserStatsOnRatingWrite = functions
  .runWith({ memory: '256MB', timeoutSeconds: 60 })
  .firestore.document('ratings/{ratingId}')
  .onWrite(async (change, context) => {
    const before = change.before.exists ? change.before.data() : null;
    const after = change.after.exists ? change.after.data() : null;

    // A rating change can affect up to two users:
    //   * On create/update: `after.ratedUserId`
    //   * On delete: `before.ratedUserId`
    //   * On the (rare) edit that re-targets the rating: both
    // Recompute for every affected user so a stale row never lingers.
    const affected = new Set();
    if (before && before.ratedUserId) affected.add(before.ratedUserId);
    if (after && after.ratedUserId) affected.add(after.ratedUserId);
    if (affected.size === 0) return null;

    const db = admin.firestore();
    for (const userId of affected) {
      await recomputeStatsFor(db, userId);
    }
    return null;
  });

async function recomputeStatsFor(db, userId) {
  const snap = await db.collection('ratings')
    .where('ratedUserId', '==', userId)
    .get();

  if (snap.empty) {
    // Last rating for this user was deleted. Removing the stats doc
    // lets the iOS "new user starts at 4.0" default apply again.
    await db.collection('userStats').doc(userId).delete().catch(() => {});
    return;
  }

  let total = 0;
  let sum = 0;
  const buckets = { 1: 0, 2: 0, 3: 0, 4: 0, 5: 0 };

  snap.docs.forEach((doc) => {
    const score = Number(doc.data().score) || 0;
    if (score <= 0) return;
    total += 1;
    sum += score;
    // Match iOS's `Int(rating.score)` (truncation toward zero) for
    // bucket assignment so client-side and server-side counts agree.
    const bucket = Math.floor(score);
    if (bucket >= 1 && bucket <= 5) buckets[bucket] += 1;
  });

  await db.collection('userStats').doc(userId).set({
    totalRatings: total,
    averageScore: total > 0 ? sum / total : 0,
    fiveStarCount: buckets[5],
    fourStarCount: buckets[4],
    threeStarCount: buckets[3],
    twoStarCount: buckets[2],
    oneStarCount: buckets[1],
    lastUpdated: admin.firestore.FieldValue.serverTimestamp(),
  }, { merge: true });
}
