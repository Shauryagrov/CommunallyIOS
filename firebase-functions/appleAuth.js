/**
 * Sign in with Apple — token exchange + revocation.
 *
 * Apple's App Store Review Guideline 5.1.1(v) requires that when a user
 * deletes their account, any tokens issued by Sign in with Apple are also
 * revoked. The revoke endpoint takes a refresh token, not the identity token
 * the iOS app uses for sign-in — so we have to exchange the one-time
 * `authorizationCode` returned by ASAuthorizationAppleIDCredential for a
 * refresh token, store it, and present it at delete time.
 *
 * Configuration (set as Firebase Functions env / secrets):
 *   APPLE_CLIENT_ID    iOS bundle id (e.g. "shaurlabs.Communally") — same
 *                      value used by mintCustomAuthToken for audience check.
 *   APPLE_TEAM_ID      10-char Apple Developer team id (Developer portal
 *                      → Membership).
 *   APPLE_KEY_ID       10-char key id from the .p8 you generated in
 *                      Certificates → Keys → "Sign In with Apple".
 *   APPLE_PRIVATE_KEY  Contents of the .p8 file (the PEM block including
 *                      "-----BEGIN PRIVATE KEY-----" lines, newlines and
 *                      all). Store as a Firebase secret, not in .env.
 *
 * If any of these are missing, exchange + revoke degrade to no-ops with a
 * warning. Sign-in still works (it only needs APPLE_CLIENT_ID for the
 * identity-token audience check); only the post-deletion revoke is skipped.
 */

const jose = require('jose');

const APPLE_TOKEN_URL = 'https://appleid.apple.com/auth/token';
const APPLE_REVOKE_URL = 'https://appleid.apple.com/auth/revoke';

const isConfigured = () => Boolean(
    process.env.APPLE_CLIENT_ID
    && process.env.APPLE_TEAM_ID
    && process.env.APPLE_KEY_ID
    && process.env.APPLE_PRIVATE_KEY,
);

/**
 * Builds the JWT Apple expects as `client_secret` on /auth/token and
 * /auth/revoke. ES256, signed with the .p8 private key, kid = APPLE_KEY_ID,
 * iss = team id, sub = bundle id, aud = appleid.apple.com.
 *
 * Apple allows expiries up to 6 months; we use 5 minutes because the JWT
 * is generated per-request and never stored.
 */
async function buildClientSecret() {
  const privateKeyPem = process.env.APPLE_PRIVATE_KEY.replace(/\\n/g, '\n');
  const privateKey = await jose.importPKCS8(privateKeyPem, 'ES256');
  const now = Math.floor(Date.now() / 1000);
  return await new jose.SignJWT({})
      .setProtectedHeader({alg: 'ES256', kid: process.env.APPLE_KEY_ID})
      .setIssuer(process.env.APPLE_TEAM_ID)
      .setIssuedAt(now)
      .setExpirationTime(now + 5 * 60)
      .setAudience('https://appleid.apple.com')
      .setSubject(process.env.APPLE_CLIENT_ID)
      .sign(privateKey);
}

/**
 * Exchange the one-time `authorizationCode` from Sign in with Apple for a
 * refresh token. Returns `null` if Apple keys aren't configured (sign-in
 * still works without revoke) or if the exchange fails — failures are
 * logged but never thrown so they don't break the sign-in user flow.
 */
async function exchangeAuthCodeForRefreshToken(authorizationCode) {
  if (!isConfigured()) {
    console.warn('appleAuth: skipping auth-code exchange — Apple secrets not configured');
    return null;
  }
  if (!authorizationCode || typeof authorizationCode !== 'string') {
    return null;
  }
  try {
    const clientSecret = await buildClientSecret();
    const body = new URLSearchParams({
      client_id: process.env.APPLE_CLIENT_ID,
      client_secret: clientSecret,
      code: authorizationCode,
      grant_type: 'authorization_code',
    });
    const resp = await fetch(APPLE_TOKEN_URL, {
      method: 'POST',
      headers: {'Content-Type': 'application/x-www-form-urlencoded'},
      body,
    });
    const text = await resp.text();
    if (!resp.ok) {
      console.warn(`appleAuth: /auth/token HTTP ${resp.status}: ${text}`);
      return null;
    }
    const data = JSON.parse(text);
    return data.refresh_token || null;
  } catch (e) {
    console.warn(`appleAuth: auth-code exchange failed: ${e.message}`);
    return null;
  }
}

/**
 * Revoke a stored Apple refresh token. Called from deleteUserAccount to
 * satisfy Guideline 5.1.1(v). Returns true on success, false on any
 * failure (including missing config) — caller logs but does not abort
 * deletion, because letting the rest of the cleanup proceed is more
 * important than this single Apple API call.
 */
async function revokeRefreshToken(refreshToken) {
  if (!isConfigured()) {
    console.warn('appleAuth: skipping token revoke — Apple secrets not configured');
    return false;
  }
  if (!refreshToken || typeof refreshToken !== 'string') return false;
  try {
    const clientSecret = await buildClientSecret();
    const body = new URLSearchParams({
      client_id: process.env.APPLE_CLIENT_ID,
      client_secret: clientSecret,
      token: refreshToken,
      token_type_hint: 'refresh_token',
    });
    const resp = await fetch(APPLE_REVOKE_URL, {
      method: 'POST',
      headers: {'Content-Type': 'application/x-www-form-urlencoded'},
      body,
    });
    if (!resp.ok) {
      const text = await resp.text();
      console.warn(`appleAuth: /auth/revoke HTTP ${resp.status}: ${text}`);
      return false;
    }
    return true;
  } catch (e) {
    console.warn(`appleAuth: token revoke failed: ${e.message}`);
    return false;
  }
}

module.exports = {
  isConfigured,
  exchangeAuthCodeForRefreshToken,
  revokeRefreshToken,
};
