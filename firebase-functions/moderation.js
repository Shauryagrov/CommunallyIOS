//
// moderation.js
//
// Image moderation Cloud Function. Triggered on every Storage object
// finalize, calls Cloud Vision SafeSearch, and deletes anything flagged
// for adult content, violence, or strongly racy material. Every flag is
// audit-logged to Firestore `moderationEvents` for human review.
//
// One-time setup before deploy:
//   gcloud services enable vision.googleapis.com --project=communally-a4cb3
//
// Cost: ~$1.50 per 1,000 images (Vision SafeSearch pricing tier 1).
//

const functions = require('firebase-functions');
const admin = require('firebase-admin');
const vision = require('@google-cloud/vision');

const visionClient = new vision.ImageAnnotatorClient();

// Vision returns one of: UNKNOWN, VERY_UNLIKELY, UNLIKELY, POSSIBLE,
// LIKELY, VERY_LIKELY. LIKELY+ is treated as a positive signal.
const POSITIVE = new Set(['LIKELY', 'VERY_LIKELY']);

/**
 * Decide whether an image fails moderation for a teen marketplace. Errs
 * on the side of false-positives — losing a legit photo is acceptable;
 * publishing anything that could constitute child-safety harm is not.
 */
function isFlagged(safeSearch) {
  if (!safeSearch) return false;
  if (POSITIVE.has(safeSearch.adult)) return true;
  if (POSITIVE.has(safeSearch.violence)) return true;
  // `racy` registers on swimsuit / lingerie / suggestive poses. Only the
  // strongest signal triggers a delete so legit profile selfies aren't
  // collateral damage.
  if (safeSearch.racy === 'VERY_LIKELY') return true;
  return false;
}

exports.moderateUploadedImage = functions
  .runWith({ memory: '512MB', timeoutSeconds: 60 })
  .storage.object()
  .onFinalize(async (object) => {
    const { bucket, name, contentType, metadata } = object;

    // Only inspect images. Video/audio/PDFs flow through other paths.
    if (!name || !contentType || !contentType.startsWith('image/')) {
      return null;
    }

    // Server-side bypass for assets we know are safe (default avatars,
    // app-shipped banner images uploaded by admin tooling). Client SDK
    // uploads can't set arbitrary metadata keys, so this can't be
    // forged from iOS.
    if (metadata && metadata.skipModeration === 'true') {
      return null;
    }

    const gcsUri = `gs://${bucket}/${name}`;

    let safeSearch;
    try {
      const [result] = await visionClient.safeSearchDetection(gcsUri);
      safeSearch = result.safeSearchAnnotation;
    } catch (err) {
      // Fail-closed: when Vision is unreachable we'd rather lose the
      // upload than leave unchecked content in the bucket. Apple's child
      // safety reviewers and 18 U.S.C. § 2258A both presume the platform
      // has actually inspected what it serves.
      console.error(`[moderation] Vision API failed for ${name}:`, err);
      try {
        await admin.storage().bucket(bucket).file(name).delete();
      } catch (delErr) {
        console.error(`[moderation] fail-closed delete failed for ${name}:`, delErr);
      }
      return null;
    }

    if (!isFlagged(safeSearch)) {
      return null;
    }

    // Flagged. Delete the object first so it can't be served, then
    // audit-log. Errors on either branch are swallowed so a transient
    // Firestore outage doesn't cause the function to retry indefinitely
    // and re-delete an already-gone object.
    try {
      await admin.storage().bucket(bucket).file(name).delete();
    } catch (err) {
      console.error(`[moderation] delete failed for ${name}:`, err);
    }

    try {
      await admin.firestore().collection('moderationEvents').add({
        type: 'image_safesearch_flagged',
        bucket,
        path: name,
        contentType,
        // iOS attaches `uid` to upload metadata; null-safe for older
        // clients that don't set it yet.
        uploaderUid: (metadata && metadata.uid) || null,
        adult: safeSearch.adult,
        violence: safeSearch.violence,
        racy: safeSearch.racy,
        medical: safeSearch.medical,
        spoof: safeSearch.spoof,
        action: 'deleted',
        createdAt: admin.firestore.FieldValue.serverTimestamp(),
      });
    } catch (err) {
      console.error(`[moderation] audit log failed for ${name}:`, err);
    }

    console.warn(`[moderation] FLAGGED + DELETED: ${name}`, safeSearch);

    // TODO(pre-public-launch): NCMEC CyberTipline reporting for CSAM.
    // 18 U.S.C. § 2258A requires service providers to report once they
    // have "actual knowledge." SafeSearch's adult flag is broad — for
    // CSAM-specific detection wire PhotoDNA or NCMEC Hash Sharing API.
    return null;
  });
