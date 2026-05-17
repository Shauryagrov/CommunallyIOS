/**
 * One-time script: cancels all "accepted" applications older than 5 hours.
 * Run: GOOGLE_APPLICATION_CREDENTIALS=serviceAccount.json node fix-stuck-jobs.js
 * (or just: node fix-stuck-jobs.js  — if you're logged in via firebase CLI / gcloud)
 */

const admin = require('firebase-admin');

admin.initializeApp({ projectId: 'communally-a4cb3' });
const db = admin.firestore();

const FIVE_HOURS_MS = 5 * 60 * 60 * 1000;

async function main() {
    const snap = await db.collection('applications')
        .where('status', '==', 'accepted')
        .get();

    if (snap.empty) {
        console.log('No accepted applications found.');
        return;
    }

    const stale = [];
    snap.forEach(doc => {
        const data = doc.data();
        const acceptedAt = data.acceptedAt?.toDate?.() ?? null;
        const ageMs = acceptedAt ? Date.now() - acceptedAt.getTime() : Infinity;
        stale.push({ id: doc.id, title: data.opportunityTitleSnapshot ?? '?', applicant: data.applicantName ?? '?', ageHours: (ageMs / 3600000).toFixed(1), acceptedAt });
    });

    console.log('\nAccepted applications found:\n');
    stale.forEach((j, i) => console.log(`  [${i}] id=${j.id}  job="${j.title}"  applicant="${j.applicant}"  age=${j.ageHours}h`));

    const toCancel = stale.filter(j => parseFloat(j.ageHours) > 5);
    if (toCancel.length === 0) {
        console.log('\nNone older than 5 hours — nothing to cancel.');
        return;
    }

    console.log(`\nCancelling ${toCancel.length} stale job(s)...\n`);
    for (const job of toCancel) {
        await db.collection('applications').doc(job.id).update({ status: 'cancelled' });

        // Also reset the opportunity back to open so it can get new applicants
        const oppSnap = await db.collection('opportunities')
            .where('acceptedApplicantId', '==', null)
            .limit(1)
            .get(); // just a probe — we update by opportunityId below

        const appDoc = await db.collection('applications').doc(job.id).get();
        const opportunityId = appDoc.data()?.opportunityId;
        if (opportunityId) {
            await db.collection('opportunities').doc(opportunityId).update({
                status: 'open',
                acceptedApplicantId: admin.firestore.FieldValue.delete()
            }).catch(() => {}); // ok if opp is already gone
        }

        console.log(`  ✅ Cancelled: ${job.title} (${job.ageHours}h old)`);
    }

    console.log('\nDone.');
}

main().catch(err => {
    console.error('Error:', err.message);
    process.exit(1);
});
