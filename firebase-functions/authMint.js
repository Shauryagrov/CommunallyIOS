/**
 * Mints Firebase Auth custom tokens so Firestore/Storage rules can use request.auth.uid.
 * UID matches the app's User.id (Google "sub" or Apple "sub" from verified ID tokens).
 */
const functions = require('firebase-functions');
const admin = require('firebase-admin');
const crypto = require('crypto');
const cors = require('cors')({origin: true});
const {OAuth2Client} = require('google-auth-library');
const jose = require('jose');
const appleAuth = require('./appleAuth');

const APPLE_JWKS = jose.createRemoteJWKSet(
    new URL('https://appleid.apple.com/auth/keys'),
);

/**
 * POST /mintCustomAuthToken
 * Body: { "provider": "google", "idToken": "<Google ID token>" }
 *    or { "provider": "apple", "identityToken": "<Apple JWT>" }
 *
 * Env: GOOGLE_IOS_CLIENT_ID (required for Google), APPLE_CLIENT_ID (bundle id, required for Apple)
 */
exports.mintCustomAuthToken = functions
  .runWith({ secrets: ['APPLE_CLIENT_ID', 'APPLE_TEAM_ID', 'APPLE_KEY_ID', 'APPLE_PRIVATE_KEY', 'GOOGLE_IOS_CLIENT_ID'] })
  .https.onRequest(async (req, res) => {
  cors(req, res, async () => {
    try {
      if (req.method !== 'POST') {
        res.status(405).json({error: 'Method not allowed'});
        return;
      }

      const body = req.body || {};
      const provider = body.provider;
      let uid;

      if (provider === 'google') {
        const idToken = body.idToken;
        if (!idToken || typeof idToken !== 'string') {
          res.status(400).json({error: 'Missing idToken'});
          return;
        }
        const clientId = process.env.GOOGLE_IOS_CLIENT_ID;
        if (!clientId) {
          console.error('mintCustomAuthToken: GOOGLE_IOS_CLIENT_ID is not set');
          res.status(500).json({error: 'Server configuration error'});
          return;
        }
        const client = new OAuth2Client(clientId);
        const ticket = await client.verifyIdToken({
          idToken,
          audience: clientId,
        });
        const sub = ticket.getPayload().sub;
        if (!sub) {
          res.status(401).json({error: 'Invalid Google token'});
          return;
        }
        uid = sub;
      } else if (provider === 'apple') {
        const identityToken = body.identityToken;
        const rawNonce = body.rawNonce;
        if (!identityToken || typeof identityToken !== 'string') {
          res.status(400).json({error: 'Missing identityToken'});
          return;
        }
        // Nonce verification — prevents replay attacks. Apple identity
        // tokens are bearer credentials valid for ~10 minutes. Without
        // nonce binding, an attacker who intercepts a token (debug
        // build HAR, leaked logs, MitM on a misconfigured device) can
        // replay it to mint a Firebase custom token as the victim —
        // full account takeover. Nonce binding makes each sign-in
        // attempt one-time: iOS generates a random nonce, hashes it,
        // includes the hash in the Apple Sign-In request, and Apple
        // embeds the hash in the identity token. The iOS app then
        // sends the RAW nonce to this endpoint and we verify
        // SHA256(rawNonce) matches the token's nonce claim.
        if (!rawNonce || typeof rawNonce !== 'string') {
          res.status(400).json({error: 'Missing rawNonce — Apple Sign-In must include a nonce'});
          return;
        }
        const audience = process.env.APPLE_CLIENT_ID;
        if (!audience) {
          console.error('mintCustomAuthToken: APPLE_CLIENT_ID is not set');
          res.status(500).json({error: 'Server configuration error'});
          return;
        }
        const {payload} = await jose.jwtVerify(identityToken, APPLE_JWKS, {
          issuer: 'https://appleid.apple.com',
          audience: audience,
        });
        const sub = payload.sub;
        if (!sub || typeof sub !== 'string') {
          res.status(401).json({error: 'Invalid Apple token'});
          return;
        }
        // Verify the nonce claim matches SHA256(rawNonce). Apple stores
        // it lowercase hex in the JWT `nonce` claim.
        const tokenNonce = payload.nonce;
        if (!tokenNonce || typeof tokenNonce !== 'string') {
          console.warn(`mintCustomAuthToken: Apple identity token has no nonce claim — refusing.`);
          res.status(401).json({error: 'Apple identity token missing nonce — re-sign in'});
          return;
        }
        const expectedHash = crypto.createHash('sha256')
            .update(rawNonce, 'utf8')
            .digest('hex');
        if (expectedHash !== tokenNonce.toLowerCase()) {
          console.warn(`mintCustomAuthToken: nonce mismatch (token=${tokenNonce}, expected=${expectedHash})`);
          res.status(401).json({error: 'Nonce verification failed — possible replay attack'});
          return;
        }
        uid = sub;

        // Sign in with Apple revocation prep — required for App Store
        // Guideline 5.1.1(v). Apple's /auth/revoke takes a refresh token,
        // not the identity token we just verified, so we exchange the
        // one-time authorization code from the iOS credential for a
        // refresh token and stash it in the server-only private
        // subcollection. deleteUserAccount reads it back to revoke.
        //
        // The authorizationCode is sent on FIRST sign-in only (Apple
        // doesn't re-issue it on subsequent sign-ins of the same user
        // to the same app). If we already have a stored refresh token
        // for this uid, the iOS app won't send a new code and we skip.
        // If Apple keys aren't configured yet, exchange is a no-op.
        const authorizationCode = body.authorizationCode;
        if (authorizationCode && typeof authorizationCode === 'string') {
          const refreshToken = await appleAuth.exchangeAuthCodeForRefreshToken(authorizationCode);
          if (refreshToken) {
            try {
              await admin.firestore()
                  .collection('users').doc(uid)
                  .collection('private').doc('apple')
                  .set({
                    refreshToken,
                    updatedAt: admin.firestore.FieldValue.serverTimestamp(),
                  }, {merge: true});
            } catch (storeErr) {
              // Storage failure is non-fatal — don't block sign-in.
              console.warn(`mintCustomAuthToken: failed to store Apple refresh token: ${storeErr.message}`);
            }
          }
        }
      } else {
        res.status(400).json({error: 'provider must be "google" or "apple"'});
        return;
      }

      const token = await admin.auth().createCustomToken(uid);
      res.json({token, uid});
    } catch (error) {
      console.error('mintCustomAuthToken error:', error);
      res.status(401).json({error: error.message || 'Token verification failed'});
    }
  });
});
