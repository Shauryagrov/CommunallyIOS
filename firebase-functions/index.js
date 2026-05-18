const functions = require('firebase-functions');
const admin = require('firebase-admin');
const fs = require('fs');
const path = require('path');
const crypto = require('crypto');

const envFilePath = path.join(__dirname, '.env');
if (fs.existsSync(envFilePath)) {
  const envContents = fs.readFileSync(envFilePath, 'utf8');
  envContents.split(/\r?\n/).forEach((line) => {
    const trimmedLine = line.trim();
    if (!trimmedLine || trimmedLine.startsWith('#')) {
      return;
    }

    const separatorIndex = trimmedLine.indexOf('=');
    if (separatorIndex === -1) {
      return;
    }

    const key = trimmedLine.slice(0, separatorIndex).trim();
    let value = trimmedLine.slice(separatorIndex + 1).trim();

    if (
      (value.startsWith('"') && value.endsWith('"')) ||
      (value.startsWith("'") && value.endsWith("'"))
    ) {
      value = value.slice(1, -1);
    }

    if (!process.env[key]) {
      process.env[key] = value;
    }
  });
}

// Read from local .env first; fall back to Firebase runtime config for deployed functions.
const runtimeCfg = (() => { try { return functions.config(); } catch (_) { return {}; } })();
const stripeSecretKey = process.env.STRIPE_SECRET_KEY || runtimeCfg.stripe?.secret_key;
const stripeWebhookSecret = process.env.STRIPE_WEBHOOK_SECRET || runtimeCfg.stripe?.webhook_secret;
const gmailEmail = process.env.GMAIL_EMAIL || runtimeCfg.gmail?.email || 'communally.app@gmail.com';
const gmailPassword = process.env.GMAIL_APP_PASSWORD || runtimeCfg.gmail?.app_password || 'your-app-password';

// Optional at cold start so auth-only deploys work; payment endpoints check before use.
const stripe = stripeSecretKey ? require('stripe')(stripeSecretKey) : null;

function paymentsEnabled(res) {
  if (!stripe) {
    res.status(503).json({
      error: 'Payment service not configured. Set STRIPE_SECRET_KEY for this project.',
    });
    return false;
  }
  return true;
}

// Force custom token signing to use the same runtime identity configured on the function.
// This avoids cross-service-account signBlob failures when IAM bindings are stale/mismatched.
const customTokenSignerServiceAccount =
  process.env.CUSTOM_TOKEN_SIGNER_SERVICE_ACCOUNT ||
  `${process.env.GCLOUD_PROJECT || process.env.GCP_PROJECT}@appspot.gserviceaccount.com`;

admin.initializeApp({
  serviceAccountId: customTokenSignerServiceAccount,
});

// CORS configuration for web requests
const cors = require('cors')({origin: true});

// Image moderation — Storage trigger lives in its own module. Required
// AFTER admin.initializeApp so the moderation function can use the
// already-initialized admin SDK.
exports.moderateUploadedImage = require('./moderation').moderateUploadedImage;

// userStats — Firestore trigger replaces the old client-side write
// path. With this deployed, firestore.rules tightens userStats to
// `allow write: if false`.
exports.recomputeUserStatsOnRatingWrite =
  require('./userStatsTrigger').recomputeUserStatsOnRatingWrite;

/**
 * Create a Stripe Payment Intent for hiring a worker
 * POST /create-payment-intent
 * Body: {
 *   amount: number (in cents),
 *   currency: string,
 *   hirerId: string,
 *   workerId: string,
 *   applicationId: string,
 *   description: string,
 *   jobAmount: number,
 *   platformFee: number,
 *   stripeFee: number
 * }
 */
exports.createPaymentIntent = functions.https.onRequest(async (req, res) => {
  cors(req, res, async () => {
    try {
      if (req.method !== 'POST') {
        res.status(405).json({error: 'Method not allowed'});
        return;
      }
      if (!paymentsEnabled(res)) return;

      const {
        currency,
        hirerId,
        workerId,
        applicationId,
        description,
        // Auth + server-side amount recompute below means the
        // client-supplied amount / jobAmount / platformFee / stripeFee
        // are NO LONGER trusted. They're read for telemetry only —
        // the canonical numbers come from the opportunity doc on
        // Firestore. Without this, a rooted client could send
        // `amount: 50` for a $500 job and charge 50 cents.
        idToken,
      } = req.body;

      if (!idToken || typeof idToken !== 'string') {
        res.status(400).json({error: 'Missing idToken'});
        return;
      }
      let decoded;
      try {
        decoded = await admin.auth().verifyIdToken(idToken);
      } catch (e) {
        res.status(401).json({error: 'Invalid or expired authentication'});
        return;
      }
      if (decoded.uid !== hirerId) {
        console.warn(`createPaymentIntent: caller ${decoded.uid} tried to pay as hirerId ${hirerId}`);
        res.status(403).json({error: 'Cannot create a payment on behalf of another hirer'});
        return;
      }
      if (!applicationId || typeof applicationId !== 'string') {
        res.status(400).json({error: 'Missing applicationId'});
        return;
      }

      const db = admin.firestore();

      // Load the application, then the opportunity. These two reads let
      // us (a) confirm this hirer actually owns the job being paid for,
      // (b) confirm the workerId matches the application's applicantId,
      // and (c) compute canonical fees server-side instead of trusting
      // the client.
      const appDoc = await db.collection('applications').doc(applicationId).get();
      if (!appDoc.exists) {
        res.status(404).json({error: 'Application not found'});
        return;
      }
      const appData = appDoc.data();
      if (appData.applicantId !== workerId) {
        res.status(400).json({error: 'Worker mismatch for this application'});
        return;
      }

      const oppId = appData.opportunityId;
      if (!oppId) {
        res.status(400).json({error: 'Application missing opportunityId'});
        return;
      }
      const oppDoc = await db.collection('opportunities').doc(oppId).get();
      if (!oppDoc.exists) {
        res.status(404).json({error: 'Opportunity not found'});
        return;
      }
      const oppData = oppDoc.data();
      if (oppData.hirerId !== hirerId) {
        console.warn(`createPaymentIntent: caller is not the hirer of opportunity ${oppId}`);
        res.status(403).json({error: 'Not the hirer of this opportunity'});
        return;
      }

      // Recompute fees from canonical source — opportunity.payAmount.
      // Mirrors StripeConfig.getPaymentBreakdown exactly:
      //   platformFee   = jobAmount * 0.05
      //   subtotal      = jobAmount + platformFee
      //   totalCharged  = (subtotal + 0.30) / (1 - 0.029)
      //   stripeFee     = totalCharged - subtotal
      const canonicalJobAmount = Number(oppData.payAmount);
      if (!isFinite(canonicalJobAmount) || canonicalJobAmount <= 0) {
        res.status(400).json({error: 'Opportunity has invalid pay amount'});
        return;
      }
      // Sanity floor/cap. Without these a hirer who can write payAmount
      // on their own opportunity can set 0.01 (Stripe rejects sub-$0.50
      // with an opaque 400) or 9_999_999_999 (DoS / accidental huge
      // charge). MIN_JOB_USD ensures totalCharged > $1 after fees;
      // MAX_JOB_USD caps the platform's max-loss exposure per single
      // PaymentIntent at $5000.
      const MIN_JOB_USD = 1;
      const MAX_JOB_USD = 5000;
      if (canonicalJobAmount < MIN_JOB_USD || canonicalJobAmount > MAX_JOB_USD) {
        res.status(400).json({
          error: `Job amount must be between $${MIN_JOB_USD} and $${MAX_JOB_USD}.`,
        });
        return;
      }
      const canonicalPlatformFee = canonicalJobAmount * 0.05;
      const canonicalSubtotal = canonicalJobAmount + canonicalPlatformFee;
      const canonicalTotal = (canonicalSubtotal + 0.30) / (1 - 0.029);
      const canonicalStripeFee = canonicalTotal - canonicalSubtotal;
      const canonicalAmountCents = Math.round(canonicalTotal * 100);

      // Duplicate-PI guard. iOS creates the payments doc BEFORE calling
      // this endpoint, so on a legitimate first attempt there will
      // already be one `.pending` doc for this application — that's
      // expected and must not be blocked. What we want to refuse is:
      //
      //   (a) A previous attempt that already has a real Stripe
      //       PaymentIntent attached (`stripePaymentIntentId` set) is
      //       still in flight (`.pending`/`.processing`/`.held`). If
      //       we let createPaymentIntent run, the user could capture
      //       two charges for one application — the older PI hasn't
      //       failed yet but a new one is being minted. We force them
      //       to wait or cancel the in-flight one.
      //
      //   (b) `.held` doc already exists — the webhook already flipped
      //       it, the charge is already captured. Block immediately.
      //
      // We also pin the Stripe PI creation with `idempotencyKey:
      // pi_${applicationId}` so even if a race slips past this query,
      // Stripe itself returns the same PaymentIntent rather than
      // minting a second one.
      const ACTIVE_STATUSES = ['pending', 'processing', 'held'];
      const existingActiveSnap = await db.collection('payments')
          .where('applicationId', '==', applicationId)
          .where('status', 'in', ACTIVE_STATUSES)
          .limit(10)
          .get();
      const blockingDoc = existingActiveSnap.docs.find((d) => {
        const data = d.data();
        // Held doc means a charge has already been captured — never
        // mint a second PI on top of that.
        if (data.status === 'held' || data.status === 'processing') return true;
        // Pending doc WITH an attached Stripe PI means a previous
        // attempt is mid-flight (Sheet still open, webhook not yet
        // fired). Don't double-mint.
        if (data.status === 'pending' && data.stripePaymentIntentId) return true;
        return false;
      });
      if (blockingDoc) {
        res.status(409).json({
          error: 'A payment is already in progress for this application. Wait for it to finish or cancel it before retrying.',
        });
        return;
      }

      console.log('Creating payment intent:', {
        currency,
        hirerId,
        workerId,
        applicationId,
        canonicalJobAmount,
        canonicalAmountCents,
      });

      // Get or create Stripe customer for hirer
      const hirerDoc = await db.collection('users').doc(hirerId).get();

      let customerId = hirerDoc.data()?.stripeCustomerId;

      if (!customerId) {
        const customer = await stripe.customers.create({
          metadata: {
            firebaseUID: hirerId,
            email: hirerDoc.data()?.email || '',
            name: hirerDoc.data()?.name || '',
          },
        });
        customerId = customer.id;

        // Save customer ID to Firestore
        await db.collection('users').doc(hirerId).update({
          stripeCustomerId: customerId,
        });
      }

      // Create ephemeral key for customer
      const ephemeralKey = await stripe.ephemeralKeys.create(
          {customer: customerId},
          {apiVersion: '2024-12-18.acacia'}
      );

      // Create payment intent on the platform account.
      // We intentionally do NOT set transfer_data here because the money should
      // stay held by the platform until the hirer confirms the job is complete.
      const paymentIntentParams = {
        amount: canonicalAmountCents,
        currency: currency || 'usd',
        customer: customerId,
        description: description || `Payment for ${oppData.title || 'opportunity'}`,
        metadata: {
          hirerId: hirerId,
          workerId: workerId,
          applicationId: applicationId,
          opportunityId: oppId,
          jobAmount: canonicalJobAmount.toString(),
          platformFee: canonicalPlatformFee.toFixed(2),
          stripeFee: canonicalStripeFee.toFixed(2),
        },
        automatic_payment_methods: {
          enabled: true,
        },
      };

      // Pin the PI by applicationId so a race past the duplicate-check
      // returns the SAME PaymentIntent rather than a second charge.
      const paymentIntent = await stripe.paymentIntents.create(
          paymentIntentParams,
          {idempotencyKey: `pi_${applicationId}`}
      );

      res.json({
        clientSecret: paymentIntent.client_secret,
        customerId: customerId,
        ephemeralKey: ephemeralKey.secret,
        paymentIntentId: paymentIntent.id,
        // Echo the canonical numbers back so the iOS app can verify the
        // user is paying what they expected to pay (defensive UX).
        canonicalAmountCents,
        canonicalJobAmount,
      });
    } catch (error) {
      // Log full Stripe error server-side, but DON'T echo error.message
      // to the client — Stripe SDK errors include request IDs, account
      // IDs and parameter hints that aid enumeration / abuse.
      console.error('Error creating payment intent:', error);
      res.status(500).json({error: 'Could not create payment. Please try again or contact support.'});
    }
  });
});

/**
 * Create a Stripe Connect Account for workers to receive payouts
 * POST /create-connect-account
 * Body: {
 *   userId: string,
 *   email: string,
 *   name: string,
 *   returnURL: string,
 *   refreshURL: string
 * }
 */
/**
 * Create a Stripe Identity VerificationSession (document + selfie).
 * POST /createIdentityVerificationSession
 * Body: { idToken: string } — Firebase Auth ID token; UID must match the user being verified.
 */
exports.createIdentityVerificationSession = functions.https.onRequest(async (req, res) => {
  cors(req, res, async () => {
    try {
      if (req.method !== 'POST') {
        res.status(405).json({error: 'Method not allowed'});
        return;
      }
      if (!paymentsEnabled(res)) return;

      const {idToken} = req.body || {};
      if (!idToken || typeof idToken !== 'string') {
        res.status(400).json({error: 'idToken is required'});
        return;
      }

      let decoded;
      try {
        decoded = await admin.auth().verifyIdToken(idToken);
      } catch (e) {
        console.error('createIdentityVerificationSession: invalid id token', e.message);
        res.status(401).json({error: 'Invalid or expired authentication'});
        return;
      }

      const uid = decoded.uid;

      const sessionParams = {
        type: 'document',
        metadata: {userId: uid},
        options: {
          document: {
            require_matching_selfie: true,
          },
        },
      };

      const session = await stripe.identity.verificationSessions.create(sessionParams);

      await admin.firestore().collection('users').doc(uid).set({
        stripeIdentityLastSessionId: session.id,
      }, {merge: true});

      res.json({
        clientSecret: session.client_secret,
        sessionId: session.id,
      });
    } catch (error) {
      console.error('Error creating identity verification session:', error);
      res.status(500).json({error: error.message || 'Identity session failed'});
    }
  });
});

exports.createConnectAccount = functions.https.onRequest(async (req, res) => {
  cors(req, res, async () => {
    try {
      if (req.method !== 'POST') {
        res.status(405).json({error: 'Method not allowed'});
        return;
      }
      if (!paymentsEnabled(res)) return;

      const {
        userId, email, name, returnURL, refreshURL,
        // Optional prefill fields — the iOS client now sends these so we can
        // skip Stripe's hosted "Business details" and "Your name" screens.
        firstName, lastName, dateOfBirth,
        // Auth: required since this endpoint writes a Stripe Connect
        // account ID onto a user doc. Without auth, an attacker could
        // pass `userId: <victim>` and their own email to overwrite the
        // victim's `stripeConnectAccountId` with an attacker-controlled
        // account — every future `releasePayment` would then wire the
        // victim's earnings to attacker's bank. AUTH IS CRITICAL HERE.
        idToken,
      } = req.body;

      if (!idToken || typeof idToken !== 'string') {
        res.status(400).json({error: 'Missing idToken'});
        return;
      }
      let decoded;
      try {
        decoded = await admin.auth().verifyIdToken(idToken);
      } catch (e) {
        res.status(401).json({error: 'Invalid or expired authentication'});
        return;
      }
      if (decoded.uid !== userId) {
        console.warn(`Connect account hijack attempt: caller ${decoded.uid} tried to create account for ${userId}`);
        res.status(403).json({error: 'Not authorized to create a Connect account for this user'});
        return;
      }

      console.log('Creating Connect account for:', {userId, email, name, firstName, lastName, hasDob: !!dateOfBirth});

      // Check if user already has Connect account
      const userRef = admin.firestore().collection('users').doc(userId);
      const userDoc = await userRef.get();

      let accountId = userDoc.exists ? userDoc.data()?.stripeConnectAccountId : null;

      // Validate the stored account ID still exists in Stripe — stale IDs
      // (e.g. created with broken keys before) will cause accountLinks.create
      // to fail with "account not connected to platform".
      if (accountId) {
        try {
          await stripe.accounts.retrieve(accountId);
        } catch (retrieveErr) {
          console.warn('Stored Connect account not found in Stripe, clearing stale ID:', accountId, retrieveErr.message);
          accountId = null;
          await userRef.set({stripeConnectAccountId: null}, {merge: true});
        }
      }

      if (!accountId) {
        // Parse dateOfBirth (ISO string or yyyy-mm-dd) into Stripe's
        // {day, month, year} format. Silently skip if missing/malformed —
        // Stripe will just ask the user for it directly.
        let dobPayload;
        if (dateOfBirth) {
          const d = new Date(dateOfBirth);
          if (!isNaN(d.getTime())) {
            dobPayload = {
              day: d.getUTCDate(),
              month: d.getUTCMonth() + 1,
              year: d.getUTCFullYear(),
            };
          }
        }

        // Split the legacy `name` into first/last if the client didn't send
        // them separately. Best-effort: "Jane Mary Doe" -> first="Jane", last="Mary Doe".
        let firstFromName = firstName;
        let lastFromName = lastName;
        if ((!firstFromName || !lastFromName) && name) {
          const parts = name.trim().split(/\s+/);
          if (parts.length === 1) {
            firstFromName = firstFromName || parts[0];
          } else if (parts.length >= 2) {
            firstFromName = firstFromName || parts[0];
            lastFromName = lastFromName || parts.slice(1).join(' ');
          }
        }

        // Create new Connect account with everything we already know about
        // the seeker so Stripe doesn't re-ask. The flags below collectively
        // skip the "What kind of business?" picker AND the "Business details"
        // screen (industry, website, product description) the user was
        // staring at before this change.
        const account = await stripe.accounts.create({
          type: 'express',
          country: 'US',
          email: email,
          // Skips the "Are you a business or individual?" question — all
          // seekers on Communally are individuals (parent-as-guardian for
          // minors still onboards as an individual under their own name).
          business_type: 'individual',
          // Prefills the "Business details" step so Stripe skips it.
          //   mcc 7299  = "Services — Other personal services" (best fit for
          //               mixed task work: yard, dog walking, tutoring, etc.)
          //   url       = Communally's marketplace URL (Stripe wants a real
          //               site users can buy a service from; ours qualifies).
          //   product_description tells Stripe what the seeker actually does.
          business_profile: {
            mcc: '7299',
            url: 'https://communallyapp.com',
            product_description: 'Provides short, local services for neighbors through the Communally marketplace — yard work, pet care, tutoring, errands, and similar tasks.',
            support_email: 'support@communallyapp.com',
          },
          // Prefill personal info we already have. Stripe still asks for
          // address + SSN (last 4) on its own screens — those are US KYC
          // requirements we can't skip.
          individual: {
            email,
            ...(firstFromName ? {first_name: firstFromName} : {}),
            ...(lastFromName ? {last_name: lastFromName} : {}),
            ...(dobPayload ? {dob: dobPayload} : {}),
          },
          capabilities: {
            card_payments: {requested: true},
            transfers: {requested: true},
          },
          metadata: {
            firebaseUID: userId,
          },
        });

        accountId = account.id;

        // Save to Firestore (create doc if missing)
        await userRef.set(
          {stripeConnectAccountId: accountId},
          {merge: true}
        );
      }

      // Create account link for onboarding.
      // `collection_options.fields = 'currently_due'` tells Stripe to ask only
      // for what's required for the seeker to start receiving payouts NOW,
      // deferring `eventually_due` fields (extra tax info etc.) until they
      // cross thresholds in the future. Shorter form → fewer drop-offs.
      const accountLink = await stripe.accountLinks.create({
        account: accountId,
        refresh_url: refreshURL,
        return_url: returnURL,
        type: 'account_onboarding',
        collection_options: {
          fields: 'currently_due',
        },
      });

      res.json({
        accountId: accountId,
        url: accountLink.url,
      });
    } catch (error) {
      console.error('Error creating Connect account:', error);
      res.status(500).json({error: error.message});
    }
  });
});

/**
 * Check Stripe Connect Account status
 * POST /connect-account-status
 * Body: {
 *   accountId: string
 * }
 */
exports.connectAccountStatus = functions.https.onRequest(async (req, res) => {
  cors(req, res, async () => {
    try {
      if (req.method !== 'POST') {
        res.status(405).json({error: 'Method not allowed'});
        return;
      }
      if (!paymentsEnabled(res)) return;

      const {accountId} = req.body;

      const account = await stripe.accounts.retrieve(accountId);

      res.json({
        detailsSubmitted: account.details_submitted,
        chargesEnabled: account.charges_enabled,
        payoutsEnabled: account.payouts_enabled,
        disabledReason: account.requirements?.disabled_reason || null,
        currentlyDue: account.requirements?.currently_due || [],
        pastDue: account.requirements?.past_due || [],
        pendingVerification: account.requirements?.pending_verification || [],
      });
    } catch (error) {
      console.error('Error checking account status:', error);
      res.status(500).json({error: error.message});
    }
  });
});

/**
 * Release held payment to worker after job completion
 * POST /release-payment
 * Body: {
 *   paymentId: string
 * }
 */
exports.releasePayment = functions.https.onRequest(async (req, res) => {
  cors(req, res, async () => {
    try {
      if (req.method !== 'POST') {
        res.status(405).json({error: 'Method not allowed'});
        return;
      }
      if (!paymentsEnabled(res)) return;

      const {paymentId, idToken} = req.body;

      if (!paymentId) {
        res.status(400).json({error: 'Missing paymentId'});
        return;
      }
      // AUTH REQUIRED: this endpoint moves real money via stripe.transfers
      // .create or flips an escrow Payment doc to `.payable`. Without auth,
      // anyone with a paymentId could force-release escrow before the hirer
      // is ready (killing dispute leverage) or trigger duplicate transfers
      // by spamming the endpoint.
      if (!idToken || typeof idToken !== 'string') {
        res.status(400).json({error: 'Missing idToken'});
        return;
      }
      let decoded;
      try {
        decoded = await admin.auth().verifyIdToken(idToken);
      } catch (e) {
        res.status(401).json({error: 'Invalid or expired authentication'});
        return;
      }

      const paymentRef = admin.firestore().collection('payments').doc(paymentId);
      const paymentDoc = await paymentRef.get();

      if (!paymentDoc.exists) {
        res.status(404).json({error: 'Payment not found'});
        return;
      }

      const payment = paymentDoc.data();

      // Only the hirer or worker on THIS specific payment can trigger
      // release. Mirrors the auth pattern on refundPayment + claimEarnings.
      if (payment.hirerId !== decoded.uid && payment.workerId !== decoded.uid) {
        console.warn(`releasePayment: caller ${decoded.uid} is not a party on payment ${paymentId}`);
        res.status(403).json({error: 'Not authorized to release this payment'});
        return;
      }

      if (payment.status === 'released') {
        res.json({
          success: true,
          alreadyReleased: true,
          transferId: payment.stripeTransferId || null,
        });
        return;
      }

      // Already deferred — caller doesn't need to do anything else.
      // The worker will drain it via claimEarnings.
      if (payment.status === 'payable') {
        res.json({
          success: true,
          deferred: true,
          alreadyDeferred: true,
        });
        return;
      }

      if (payment.status !== 'held') {
        res.status(400).json({
          error: 'Payment must be held before it can be released.',
        });
        return;
      }

      if (!payment.stripePaymentIntentId) {
        res.status(400).json({
          error: 'Missing Stripe payment intent for this payment.',
        });
        return;
      }

      const workerDoc = await admin.firestore()
          .collection('users')
          .doc(payment.workerId)
          .get();

      if (!workerDoc.exists) {
        res.status(404).json({error: 'Worker account not found'});
        return;
      }

      const workerData = workerDoc.data();
      const destinationAccountId = workerData?.stripeConnectAccountId;

      // DEFERRED PAYOUT: if the worker hasn't connected a Stripe account
      // yet (or it isn't payouts-ready), we don't fail the job completion.
      // The hirer's funds were already captured into Communally's platform
      // balance back at acceptance time, so they're safe. We flip this
      // payment to `payable` (= "ready to be cashed out by the worker")
      // and bump a `pendingClaimableCents` counter on the worker's user
      // doc for fast display in the Earnings UI. The worker drains all
      // `payable` payments later via `claimEarnings` once they finish
      // Connect onboarding.
      //
      // Wrapped in a transaction with a pre-read status check so two
      // concurrent calls (e.g., both parties hitting Confirm + Cloud
      // Functions retrying) don't both succeed in incrementing
      // pendingClaimableCents — only the first one wins, the second
      // sees `payable` and short-circuits to the already-handled path.
      const db = admin.firestore();
      const deferToBalance = async (reason) => {
        const workerPayoutCents = Math.round(
            Number(payment.workerPayout || 0) * 100
        );
        let didDefer = false;
        await db.runTransaction(async (tx) => {
          const snap = await tx.get(paymentRef);
          if (!snap.exists) throw new Error('Payment vanished');
          const cur = snap.data();
          if (cur.status !== 'held') {
            // Someone else already moved this away from .held; bail out.
            // Could be a concurrent caller that already deferred, OR
            // released, OR refunded. Either way, no work to do here.
            didDefer = false;
            return;
          }
          tx.update(paymentRef, {
            status: 'payable',
            payableAt: admin.firestore.FieldValue.serverTimestamp(),
            deferReason: reason,
          });
          if (workerPayoutCents > 0) {
            const userRef = db.collection('users').doc(payment.workerId);
            tx.set(userRef, {
              pendingClaimableCents:
                admin.firestore.FieldValue.increment(workerPayoutCents),
            }, {merge: true});
          }
          didDefer = true;
        });
        res.json({
          success: true,
          deferred: true,
          alreadyDeferred: !didDefer,
          reason,
          amountCents: didDefer ? workerPayoutCents : 0,
        });
      };

      if (!destinationAccountId) {
        await deferToBalance('no_connect_account');
        return;
      }

      const account = await stripe.accounts.retrieve(destinationAccountId);
      if (!account.payouts_enabled) {
        await deferToBalance('payouts_not_enabled');
        return;
      }

      const paymentIntent = await stripe.paymentIntents.retrieve(
          payment.stripePaymentIntentId,
          {expand: ['latest_charge']}
      );

      if (paymentIntent.status !== 'succeeded') {
        res.status(400).json({
          error: 'Stripe payment has not finished successfully yet.',
        });
        return;
      }

      // Older payments may have been created as direct destination charges.
      // In that case, Stripe already routed the payout during the original
      // charge, so we just mark the app-side payment as released.
      //
      // Transaction-wrapped: a concurrent call that has already raced into
      // the deferToBalance branch (status → `.payable`) must not get
      // overwritten back to `.released` here — that would orphan the
      // increment on `pendingClaimableCents` and double-count earnings.
      if (paymentIntent.transfer_data?.destination) {
        const directTransferId =
          payment.stripeTransferId || `direct_charge_${paymentIntent.id}`;

        let didFlip = false;
        await db.runTransaction(async (tx) => {
          const snap = await tx.get(paymentRef);
          if (!snap.exists) return;
          const cur = snap.data();
          if (cur.status !== 'held') {
            // Already moved on (payable / released / refunded). Don't
            // stomp it.
            return;
          }
          tx.update(paymentRef, {
            status: 'released',
            releasedAt: admin.firestore.FieldValue.serverTimestamp(),
            stripeTransferId: directTransferId,
          });
          didFlip = true;
        });

        res.json({
          success: true,
          transferId: directTransferId,
          alreadyTransferred: !didFlip,
        });
        return;
      }

      const latestCharge = paymentIntent.latest_charge;
      const latestChargeId = typeof latestCharge === 'string' ?
        latestCharge :
        latestCharge?.id;

      if (!latestChargeId) {
        res.status(400).json({
          error: 'Stripe charge information is missing for this payment.',
        });
        return;
      }

      // Sanity floor on the transfer amount. Stripe rejects sub-$0.50
      // transfers with an opaque 400 — surface a clear error instead
      // of a Stripe SDK exception.
      const transferAmountCents = Math.round(
          Number(payment.workerPayout || 0) * 100
      );
      if (transferAmountCents < 50) {
        res.status(400).json({
          error: 'Worker payout is below the minimum payable amount (~$0.50).',
        });
        return;
      }

      // Idempotency key on paymentId protects against duplicate transfers
      // if releasePayment is called twice (concurrent confirms, function
      // retry, double-tap). Stripe returns the existing Transfer object
      // for any retry with the same key — same outcome, no double-pay.
      const transfer = await stripe.transfers.create({
        amount: transferAmountCents,
        currency: paymentIntent.currency,
        destination: destinationAccountId,
        source_transaction: latestChargeId,
        metadata: {
          paymentId: paymentId,
          applicationId: payment.applicationId || '',
          opportunityId: payment.opportunityId || '',
          hirerId: payment.hirerId || '',
          workerId: payment.workerId || '',
        },
      }, {
        idempotencyKey: `release_${paymentId}`,
      });

      // Final status write inside a transaction with re-check so
      // concurrent calls don't both flip and create inconsistent state.
      // The Stripe transfer is already idempotent above; this just
      // makes sure the Firestore mirror agrees with itself. Exact
      // `cur.status === 'held'` guard — if anything else has already
      // moved the doc on (payable, released, refunded), bail out
      // rather than overwriting their bookkeeping fields.
      await db.runTransaction(async (tx) => {
        const snap = await tx.get(paymentRef);
        if (!snap.exists) return;
        const cur = snap.data();
        if (cur.status !== 'held') return;
        tx.update(paymentRef, {
          status: 'released',
          releasedAt: admin.firestore.FieldValue.serverTimestamp(),
          stripeTransferId: transfer.id,
        });
      });

      res.json({
        success: true,
        transferId: transfer.id,
      });
    } catch (error) {
      // Log full Stripe error server-side, return sanitized error to
      // client. Stripe SDK errors include request IDs and account
      // hints that aid enumeration / abuse if echoed.
      console.error('Error releasing payment:', error);
      res.status(500).json({error: 'Could not release payment. Please try again or contact support.'});
    }
  });
});

/**
 * claimEarnings — drains the worker's accumulated `payable` payments by
 * issuing real Stripe transfers from the platform balance to their
 * Connect account. Powers the "Cash Out $X" button in the Earnings UI.
 *
 * Why this exists: we let workers do jobs BEFORE they finish Stripe
 * Connect onboarding, so their earnings can pile up in our platform
 * balance with `status: payable`. This endpoint converts that pile into
 * actual money in their bank in one tap.
 *
 * Auth: caller must pass a Firebase idToken whose uid matches the
 * payments' workerId — workers can only claim their own earnings.
 *
 * POST /claimEarnings
 * Body: { idToken: string }
 */
exports.claimEarnings = functions
  .runWith({timeoutSeconds: 300, memory: '256MB'})
  .https.onRequest(async (req, res) => {
  cors(req, res, async () => {
    try {
      if (req.method !== 'POST') {
        res.status(405).json({error: 'Method not allowed'});
        return;
      }
      if (!paymentsEnabled(res)) return;

      const {idToken} = req.body || {};
      if (!idToken || typeof idToken !== 'string') {
        res.status(400).json({error: 'Missing idToken'});
        return;
      }

      let decoded;
      try {
        decoded = await admin.auth().verifyIdToken(idToken);
      } catch (e) {
        res.status(401).json({error: 'Invalid or expired authentication'});
        return;
      }
      const uid = decoded.uid;
      const db = admin.firestore();

      const userRef = db.collection('users').doc(uid);
      const userDoc = await userRef.get();
      if (!userDoc.exists) {
        res.status(404).json({error: 'User not found'});
        return;
      }

      const userData = userDoc.data();
      const destinationAccountId = userData?.stripeConnectAccountId;

      if (!destinationAccountId) {
        res.status(400).json({
          error: 'Connect a bank account to cash out your earnings.',
          requiresBankSetup: true,
        });
        return;
      }

      const account = await stripe.accounts.retrieve(destinationAccountId);
      if (!account.payouts_enabled) {
        res.status(400).json({
          error: 'Your bank setup isn\'t complete yet. Finish Stripe verification to cash out.',
          requiresBankSetup: true,
        });
        return;
      }

      // Find all payable earnings for this worker.
      const payableSnap = await db.collection('payments')
          .where('workerId', '==', uid)
          .where('status', '==', 'payable')
          .get();

      if (payableSnap.empty) {
        res.json({
          success: true,
          transferredCount: 0,
          transferredCents: 0,
          message: 'No earnings to cash out.',
        });
        return;
      }

      let transferredCount = 0;
      let transferredCents = 0;
      const failures = [];

      for (const doc of payableSnap.docs) {
        const payment = doc.data();
        try {
          if (!payment.stripePaymentIntentId) {
            failures.push({paymentId: doc.id, reason: 'missing_payment_intent'});
            continue;
          }

          const paymentIntent = await stripe.paymentIntents.retrieve(
              payment.stripePaymentIntentId,
              {expand: ['latest_charge']},
          );

          if (paymentIntent.status !== 'succeeded') {
            failures.push({paymentId: doc.id, reason: 'payment_not_succeeded'});
            continue;
          }

          const latestCharge = paymentIntent.latest_charge;
          const latestChargeId = typeof latestCharge === 'string' ?
            latestCharge :
            latestCharge?.id;
          if (!latestChargeId) {
            failures.push({paymentId: doc.id, reason: 'missing_charge'});
            continue;
          }

          const amountCents = Math.round(Number(payment.workerPayout || 0) * 100);
          // Idempotency key keyed on the Payment doc ID protects against
          // a double-tap on Cash Out causing duplicate Stripe transfers
          // before this loop's `status: released` write has propagated.
          // Stripe dedupes any retry with the same key and returns the
          // original Transfer object — net effect: same outcome, no
          // double-pay.
          const transfer = await stripe.transfers.create({
            amount: amountCents,
            currency: paymentIntent.currency,
            destination: destinationAccountId,
            source_transaction: latestChargeId,
            metadata: {
              paymentId: doc.id,
              applicationId: payment.applicationId || '',
              opportunityId: payment.opportunityId || '',
              hirerId: payment.hirerId || '',
              workerId: payment.workerId || '',
              claimedAtFlow: 'claimEarnings',
            },
          }, {
            idempotencyKey: `claim_${doc.id}`,
          });

          await doc.ref.update({
            status: 'released',
            releasedAt: admin.firestore.FieldValue.serverTimestamp(),
            stripeTransferId: transfer.id,
          });

          // Decrement the counter PER-PAYMENT (not after the loop) so a
          // function timeout mid-loop leaves the cached counter
          // consistent with however many transfers actually completed.
          // Old behavior: bulk decrement at end of loop — if a worker
          // had 50+ payable payments and Stripe API latency pushed the
          // function past its 60s timeout, some Stripe transfers would
          // fire and Firestore docs would flip to `.released`, but the
          // cached counter would never decrement and stay permanently
          // inflated. Per-payment increment(-amount) is atomic in
          // Firestore so safe under concurrent claims.
          await userRef.set({
            pendingClaimableCents: admin.firestore.FieldValue.increment(-amountCents),
          }, {merge: true});

          transferredCount += 1;
          transferredCents += amountCents;
        } catch (e) {
          console.error(`claimEarnings: failed for payment ${doc.id}:`, e.message);
          failures.push({paymentId: doc.id, reason: e.message});
        }
      }

      // Final timestamp write — only the lastClaimedAt now, since the
      // counter is already decremented inside the loop. Skip if nothing
      // succeeded.
      if (transferredCents > 0) {
        await userRef.set({
          lastClaimedAt: admin.firestore.FieldValue.serverTimestamp(),
        }, {merge: true});
      }

      res.json({
        success: true,
        transferredCount,
        transferredCents,
        failures,
      });
    } catch (error) {
      console.error('Error in claimEarnings:', error);
      res.status(500).json({error: error.message || 'Cash out failed'});
    }
  });
});

/**
 * refundPayment — refunds the Stripe charge for a held or released payment.
 * POST /refundPayment
 * Body: { paymentId: string, reason?: string }
 */
exports.refundPayment = functions.https.onRequest(async (req, res) => {
  cors(req, res, async () => {
    try {
      if (req.method !== 'POST') {
        res.status(405).json({error: 'Method not allowed'});
        return;
      }
      if (!paymentsEnabled(res)) return;

      const {paymentId, reason, idToken} = req.body;
      if (!paymentId) {
        res.status(400).json({error: 'Missing paymentId'});
        return;
      }

      // Auth required — previously this endpoint accepted any signed
      // payload, which meant anyone who learned a paymentId (e.g., from
      // their own job's Firestore doc + a guess) could trigger refunds
      // on someone else's payment. Now we verify the Firebase idToken
      // and require the caller to be either the hirer or worker on the
      // specific payment.
      if (!idToken || typeof idToken !== 'string') {
        res.status(400).json({error: 'Missing idToken'});
        return;
      }
      let decoded;
      try {
        decoded = await admin.auth().verifyIdToken(idToken);
      } catch (e) {
        res.status(401).json({error: 'Invalid or expired authentication'});
        return;
      }
      const uid = decoded.uid;

      const db = admin.firestore();
      const paymentRef = db.collection('payments').doc(paymentId);
      const paymentDoc = await paymentRef.get();
      if (!paymentDoc.exists) {
        res.status(404).json({error: 'Payment not found'});
        return;
      }

      const payment = paymentDoc.data();

      // Caller must be a party to this specific payment.
      if (payment.hirerId !== uid && payment.workerId !== uid) {
        res.status(403).json({error: 'Not authorized to refund this payment'});
        return;
      }

      if (payment.status === 'refunded') {
        res.json({success: true, alreadyRefunded: true});
        return;
      }

      // Block refund on any post-completion state. Both `.released`
      // (already transferred to worker's bank) and `.payable` (sitting
      // in worker's in-app Communally balance, waiting to be cashed
      // out) represent earned wages — the worker performed the job and
      // both parties confirmed completion. Refunding here would steal
      // earnings. iOS `cancelApplication` blocks this client-side
      // already, but the endpoint needs the same guard so a forged
      // direct API call can't drain a worker's completed earnings.
      // Genuine post-completion refunds (e.g., dispute, fraud) require
      // manual reconciliation via Stripe Dashboard + admin SDK.
      if (payment.status === 'released' || payment.status === 'payable') {
        res.status(400).json({
          error: 'Cannot refund a completed job. The worker has already earned this payment.',
        });
        return;
      }

      if (!payment.stripePaymentIntentId) {
        // Tricky race: payment is .pending (Stripe Sheet not yet
        // completed, OR webhook hasn't propagated yet). If we just
        // mark .refunded here and the PI succeeds later, the webhook's
        // findPaymentDocFor will skip this doc (terminal status) →
        // charge captures into platform balance with no refund issued
        // and no record showing it owes one. Money lost.
        //
        // Strategy: flag the doc as `refundRequestedAt` but leave it
        // in the active status pipeline. The stripeWebhook handler
        // checks for this flag on payment_intent.succeeded events and
        // issues a real Stripe refund immediately when the charge
        // captures.
        //
        // TOCTOU race we MUST close: between our initial `payment` read
        // (no PI yet) and our `refundRequestedAt` write, the webhook
        // can race in, see no flag, and flip the doc to `.held` with
        // a `stripePaymentIntentId` populated. If our write commits
        // *after* that, the flag lands on an already-`.held` doc and
        // nothing scans for it → money stuck in escrow. We close it by
        // doing the flag-write inside a transaction that re-reads, and
        // if the webhook beat us, we either chain a real refund right
        // here (PI now known, status not yet terminal) or abort with a
        // clear "already moved past" error.
        let mustRefundNow = null; // {piId, statusAtCommit}
        await db.runTransaction(async (tx) => {
          const fresh = await tx.get(paymentRef);
          if (!fresh.exists) throw new Error('Payment vanished mid-refund');
          const cur = fresh.data();
          if (cur.status === 'refunded') return; // idempotent re-entry
          if (cur.status === 'released' || cur.status === 'payable') {
            throw new Error('Cannot refund a completed job. The worker has already earned this payment.');
          }
          if (cur.stripePaymentIntentId) {
            // Webhook beat us. Mark the doc for inline refund (handled
            // outside the transaction since Stripe API calls can't run
            // inside Firestore transactions).
            mustRefundNow = {
              piId: cur.stripePaymentIntentId,
              status: cur.status,
            };
            tx.update(paymentRef, {
              refundRequestedAt: admin.firestore.FieldValue.serverTimestamp(),
              refundReason: reason || 'Cancelled before charge',
              refundRequestedBy: uid,
            });
            return;
          }
          // Happy path: still no PI. Set the flag — webhook will pick
          // it up when the charge captures.
          tx.update(paymentRef, {
            refundRequestedAt: admin.firestore.FieldValue.serverTimestamp(),
            refundReason: reason || 'Cancelled before charge',
            refundRequestedBy: uid,
          });
        });

        if (mustRefundNow) {
          // Webhook already captured the charge while we were deciding.
          // Issue the refund synchronously now and flip status to
          // `.refunded` so this code path doesn't strand the money.
          // Idempotency key tied to paymentId means a Stripe webhook
          // retry that also sees `refundRequestedAt` will return the
          // SAME refund object, not a second one.
          try {
            const refund = await stripe.refunds.create({
              payment_intent: mustRefundNow.piId,
              reason: 'requested_by_customer',
              metadata: {
                paymentId,
                applicationId: payment.applicationId || '',
                refundReason: reason || 'Job cancelled',
                requestedByUid: uid,
                source: 'refundPayment-toctou-recovery',
              },
            }, {
              idempotencyKey: `refund_${paymentId}`,
            });
            await paymentRef.update({
              status: 'refunded',
              refundedAt: admin.firestore.FieldValue.serverTimestamp(),
              refundReason: reason || 'Job cancelled',
              stripeRefundId: refund.id,
            });
            res.json({success: true, refundId: refund.id, race: 'webhook_arrived_first'});
            return;
          } catch (refundErr) {
            // Refund failed but flag is set; webhook retries will pick
            // it up. Tell the client refund is queued so they don't
            // think the cancel itself failed.
            console.error('refundPayment inline-recovery refund failed:', refundErr.message);
            res.status(202).json({
              success: true,
              pendingChargeCapture: true,
              message: 'Cancellation recorded — refund will retry automatically.',
            });
            return;
          }
        }

        res.json({
          success: true,
          pendingChargeCapture: true,
          message: 'Refund will be issued automatically as soon as Stripe confirms the charge.',
        });
        return;
      }

      // Issue actual Stripe refund. Idempotency key on paymentId means
      // a double-tap or retry returns the original refund object
      // instead of issuing a second one.
      const refund = await stripe.refunds.create({
        payment_intent: payment.stripePaymentIntentId,
        reason: 'requested_by_customer',
        metadata: {
          paymentId: paymentId,
          applicationId: payment.applicationId || '',
          refundReason: reason || 'Job cancelled',
          requestedByUid: uid,
        },
      }, {
        idempotencyKey: `refund_${paymentId}`,
      });

      await paymentRef.update({
        status: 'refunded',
        refundedAt: admin.firestore.FieldValue.serverTimestamp(),
        refundReason: reason || 'Job cancelled',
        stripeRefundId: refund.id,
      });

      res.json({success: true, refundId: refund.id});
    } catch (error) {
      // Log full Stripe error server-side, sanitize what we return.
      console.error('Error refunding payment:', error);
      res.status(500).json({error: 'Could not refund payment. Please try again or contact support.'});
    }
  });
});

/**
 * Stripe webhook handler for payment events
 * POST /stripe-webhook
 */
exports.stripeWebhook = functions.https.onRequest(async (req, res) => {
  if (!stripe) {
    res.status(503).send('Payment service not configured');
    return;
  }
  const sig = req.headers['stripe-signature'];
  const webhookSecret = stripeWebhookSecret;

  if (!webhookSecret) {
    res.status(500).send('Missing STRIPE_WEBHOOK_SECRET');
    return;
  }

  let event;

  try {
    event = stripe.webhooks.constructEvent(req.rawBody, sig, webhookSecret);
  } catch (err) {
    console.error('Webhook signature verification failed:', err.message);
    res.status(400).send(`Webhook Error: ${err.message}`);
    return;
  }

  // Helper: find a Payment doc for a given PaymentIntent. iOS creates the
  // Payment doc BEFORE the Stripe Sheet now, so the doc exists when this
  // webhook fires. But there's a subtle retry case: if a hirer's first
  // Stripe attempt fails (card declined → doc gets `.failed`) and they
  // retry, a NEW Payment doc is created. A naive `where(applicationId)`
  // .limit(1) could match the STALE failed doc and flip it to .held —
  // leaving the new doc stuck at .pending and the user's accounting
  // wrong. So we filter in-memory to ACTIVE docs (.pending/.processing)
  // and pick the most recent one, which is always the live attempt.
  const findPaymentDocFor = async (paymentIntent) => {
    const md = paymentIntent.metadata || {};

    const pickFreshest = (docs) => {
      const active = docs.filter((d) => {
        const s = d.data().status;
        return s === 'pending' || s === 'processing';
      });
      if (active.length === 0) return null;
      active.sort((a, b) => {
        const aT = a.data().createdAt?.seconds || 0;
        const bT = b.data().createdAt?.seconds || 0;
        return bT - aT;
      });
      return active[0].ref;
    };

    // 1. Prefer applicationId metadata + active-status filter (handles
    //    the retry-after-failure case correctly).
    if (md.applicationId) {
      const snap = await admin.firestore()
          .collection('payments')
          .where('applicationId', '==', md.applicationId)
          .get();
      const freshest = pickFreshest(snap.docs);
      if (freshest) return freshest;
      // If nothing active matches but a doc exists for this applicationId,
      // fall through — the stripePaymentIntentId fallback below may still
      // catch a directly-linked doc.
    }

    // 2. stripePaymentIntentId fallback for any doc that was already
    //    linked client-side. Even on this path, only update if the doc
    //    is still in an active status — otherwise we'd be flipping a
    //    terminal-state doc (.released / .refunded / .failed / .cancelled)
    //    which would silently corrupt history.
    const snap = await admin.firestore()
        .collection('payments')
        .where('stripePaymentIntentId', '==', paymentIntent.id)
        .limit(1)
        .get();
    if (!snap.empty) {
      const status = snap.docs[0].data().status;
      if (status === 'pending' || status === 'processing') {
        return snap.docs[0].ref;
      }
    }

    return null;
  };

  // Handle the event
  switch (event.type) {
    case 'payment_intent.succeeded': {
      const paymentIntent = event.data.object;
      console.log('Payment succeeded:', paymentIntent.id,
          'metadata:', JSON.stringify(paymentIntent.metadata || {}));

      const succeededRef = await findPaymentDocFor(paymentIntent);
      if (!succeededRef) {
        console.warn(
            `  → No Payment doc found for PaymentIntent ${paymentIntent.id}. ` +
            `Charge succeeded but app record is missing — investigate.`
        );
        break;
      }

      // Check for a pending refund request (user cancelled before
      // webhook fired). If present, issue the Stripe refund immediately
      // and skip the .held transition — money was charged then
      // refunded in the same operation, no escrow.
      const docSnap = await succeededRef.get();
      const docData = docSnap.data() || {};
      if (docData.refundRequestedAt) {
        try {
          const refund = await stripe.refunds.create({
            payment_intent: paymentIntent.id,
            reason: 'requested_by_customer',
            metadata: {
              paymentId: succeededRef.id,
              applicationId: docData.applicationId || '',
              refundReason: docData.refundReason || 'Cancelled before charge',
              autoRefundedOnWebhook: 'true',
            },
          }, {
            idempotencyKey: `refund_${succeededRef.id}`,
          });
          await succeededRef.update({
            status: 'refunded',
            stripePaymentIntentId: paymentIntent.id,
            stripeRefundId: refund.id,
            refundedAt: admin.firestore.FieldValue.serverTimestamp(),
            chargedAt: admin.firestore.FieldValue.serverTimestamp(),
          });
          console.log(`  → Auto-refunded ${succeededRef.id} (was pending refund)`);
        } catch (refundErr) {
          // Refund failed — leave as held with refundRequestedAt set so
          // ops can retry. Don't crash the webhook (Stripe will retry
          // and we'd just loop).
          console.error(`  → Auto-refund FAILED for ${succeededRef.id}: ${refundErr.message}`);
          await succeededRef.update({
            status: 'held',
            chargedAt: admin.firestore.FieldValue.serverTimestamp(),
            stripePaymentIntentId: paymentIntent.id,
            autoRefundError: refundErr.message,
          });
        }
        break;
      }

      // Normal happy path: flip to held.
      await succeededRef.update({
        status: 'held',
        chargedAt: admin.firestore.FieldValue.serverTimestamp(),
        stripePaymentIntentId: paymentIntent.id,
      });
      console.log(`  → Payment ${succeededRef.id} flipped to held`);
      break;
    }

    case 'payment_intent.payment_failed':
      const failedPayment = event.data.object;
      console.log('Payment failed:', failedPayment.id);

      const failedRef = await findPaymentDocFor(failedPayment);
      if (failedRef) {
        await failedRef.update({
          status: 'failed',
          failureReason: failedPayment.last_payment_error?.message || 'Stripe payment failed',
        });
      }
      break;

    case 'account.updated':
      const account = event.data.object;
      console.log('Connect account updated:', account.id);
      
      // Update user's Connect account status in Firestore
      const usersSnapshot = await admin.firestore()
          .collection('users')
          .where('stripeConnectAccountId', '==', account.id)
          .limit(1)
          .get();
      
      if (!usersSnapshot.empty) {
        await usersSnapshot.docs[0].ref.update({
          stripeConnectActive: account.charges_enabled && account.payouts_enabled,
          stripeConnectDetailsSubmitted: account.details_submitted,
        });
      }
      break;

    case 'identity.verification_session.verified':
    case 'identity.verification_session.processing':
    case 'identity.verification_session.requires_input':
    case 'identity.verification_session.canceled': {
      const vs = event.data.object;
      const userId = vs.metadata && vs.metadata.userId;
      if (!userId) {
        console.log('Identity session event without metadata.userId', vs.id);
        break;
      }
      const patch = {stripeIdentityLastSessionId: vs.id};
      if (vs.status === 'verified') {
        patch.stripeIdentityVerified = true;
        patch.stripeIdentityVerifiedAt = admin.firestore.FieldValue.serverTimestamp();
      } else if (vs.status === 'canceled' || vs.status === 'redacted') {
        patch.stripeIdentityVerified = false;
      }
      await admin.firestore().collection('users').doc(userId).set(patch, {merge: true});
      console.log('Identity session', vs.id, vs.status, 'for user', userId);
      break;
    }

    default:
      console.log(`Unhandled event type ${event.type}`);
  }

  res.json({received: true});
});

/**
 * Send parental approval email.
 *
 * AUTH: required. Caller's uid must equal the minor's userId — only the
 * minor can request their own parental approval email be sent.
 *
 * TOKEN HANDLING (security-critical): the approval token is generated
 * SERVER-SIDE and stored in `users/{userId}/private/parentalConsent`,
 * a subcollection only the admin SDK can read. The token is never
 * exposed via Firestore client reads (the parent receives it via email
 * link only). Without this, a minor could read their own
 * `parentApprovalToken` field from /users/{userId} and self-approve.
 *
 * RATE LIMIT: max 5 sends per minor per 24h, prevents email-spam abuse.
 *
 * POST /send-parental-approval
 * Body: {
 *   parentEmail: string,
 *   childName: string,
 *   userId: string,           // must match caller's uid
 *   idToken: string,          // Firebase Auth idToken (required)
 *   token: string             // ignored — server generates its own
 * }
 */
exports.sendParentalApproval = functions.https.onRequest(async (req, res) => {
  cors(req, res, async () => {
    try {
      if (req.method !== 'POST') {
        res.status(405).json({error: 'Method not allowed'});
        return;
      }

      const {parentEmail, childName, userId, idToken} = req.body;

      if (!parentEmail || !childName || !userId) {
        res.status(400).json({error: 'Missing required fields'});
        return;
      }
      if (!idToken || typeof idToken !== 'string') {
        res.status(400).json({error: 'Missing idToken'});
        return;
      }

      let decoded;
      try {
        decoded = await admin.auth().verifyIdToken(idToken);
      } catch (e) {
        res.status(401).json({error: 'Invalid or expired authentication'});
        return;
      }
      if (decoded.uid !== userId) {
        console.warn(`sendParentalApproval spoof: caller ${decoded.uid} tried to send email for ${userId}`);
        res.status(403).json({error: 'Cannot request parental approval for another user'});
        return;
      }

      const db = admin.firestore();

      // Rate limit: max 5 send-attempts per minor per 24h. Stored on the
      // private subcollection so client can't read or reset.
      const consentRef = db.collection('users').doc(userId)
          .collection('private').doc('parentalConsent');
      const consentSnap = await consentRef.get();
      const existing = consentSnap.exists ? consentSnap.data() : {};
      const sendsLast24h = Array.isArray(existing.sentAt) ?
        existing.sentAt.filter((ts) => {
          const ms = typeof ts === 'number' ? ts : (ts?.toMillis?.() || 0);
          return Date.now() - ms < 24 * 60 * 60 * 1000;
        }) :
        [];
      if (sendsLast24h.length >= 5) {
        res.status(429).json({
          error: 'You\'ve sent the approval email a lot today. Check your parent\'s inbox/spam, or wait a few hours before trying again.',
        });
        return;
      }

      // Generate a fresh, cryptographically-random token server-side.
      // 32 hex chars = 128 bits of entropy — infeasible to brute-force
      // even at thousands of attempts/sec (and we rate-limit anyway).
      const token = crypto.randomBytes(16).toString('hex');

      // Persist token + attempt counter to private subcollection (NOT
      // the public /users/{userId} doc — the minor can read that).
      await consentRef.set({
        token,
        tokenIssuedAt: admin.firestore.FieldValue.serverTimestamp(),
        // Reset wrong-guess counter on every new token issuance.
        approvalAttempts: 0,
        sentAt: [...sendsLast24h, Date.now()],
        parentEmail,
        childName,
      }, {merge: true});

      console.log('Sending parental approval email:', {
        parentEmail,
        childName,
        userId,
      });

      // Create approval link
      const approvalLink = `https://communally-a4cb3.web.app/approve?userId=${userId}&token=${token}`;

      // Email configuration
      const nodemailer = require('nodemailer');
      
      // Create transporter using Gmail
      // You'll need to set these in Firebase config:
      // firebase functions:config:set gmail.email="your-email@gmail.com" gmail.password="your-app-password"
      const transporter = nodemailer.createTransport({
        service: 'gmail',
        auth: {
          user: gmailEmail,
          pass: gmailPassword,
        },
      });

      // Email content
      const mailOptions = {
        from: '"Communally" <communally.app@gmail.com>',
        to: parentEmail,
        subject: 'Parental Approval Required - Communally',
        html: `
          <div style="font-family: Arial, sans-serif; max-width: 600px; margin: 0 auto; padding: 20px;">
            <div style="background: linear-gradient(135deg, #44c656 0%, #33a045 100%); padding: 30px; border-radius: 10px 10px 0 0; text-align: center;">
              <h1 style="color: white; margin: 0; font-size: 28px;">👋 Parental Approval Needed</h1>
            </div>
            
            <div style="background: #f8f8f8; padding: 30px; border-radius: 0 0 10px 10px;">
              <p style="font-size: 16px; color: #333; line-height: 1.6;">
                Hi there!
              </p>
              
              <p style="font-size: 16px; color: #333; line-height: 1.6;">
                Your child, <strong>${childName}</strong>, has signed up for Communally - a platform where teens can find local job opportunities like babysitting, lawn care, and tutoring.
              </p>
              
              <p style="font-size: 16px; color: #333; line-height: 1.6;">
                Since they're under 18, we need your approval before they can start using the app.
              </p>
              
              <div style="text-align: center; margin: 30px 0;">
                <a href="${approvalLink}" 
                   style="background: linear-gradient(135deg, #44c656 0%, #33a045 100%); 
                          color: white; 
                          padding: 15px 40px; 
                          text-decoration: none; 
                          border-radius: 25px; 
                          font-weight: bold; 
                          font-size: 18px;
                          display: inline-block;">
                  ✓ Approve Account
                </a>
              </div>
              
              <p style="font-size: 14px; color: #666; line-height: 1.6;">
                By approving, you confirm that ${childName} has your permission to use Communally to find job opportunities in your area.
              </p>
              
              <p style="font-size: 14px; color: #666; line-height: 1.6;">
                If you didn't expect this email or have questions, please contact us at support@communally.app
              </p>
              
              <hr style="border: none; border-top: 1px solid #ddd; margin: 30px 0;">
              
              <p style="font-size: 12px; color: #999; text-align: center;">
                © 2026 Communally. All rights reserved.
              </p>
            </div>
          </div>
        `,
      };

      // Send email
      await transporter.sendMail(mailOptions);

      console.log('Parental approval email sent successfully');

      res.json({
        success: true,
        message: 'Approval email sent',
      });
    } catch (error) {
      console.error('Error sending approval email:', error);
      res.status(500).json({error: 'Could not send approval email. Please try again or contact support.'});
    }
  });
});

/**
 * Approve parental consent (called when parent clicks approval link).
 *
 * Token is now read from `users/{userId}/private/parentalConsent` (a
 * server-only subcollection). Previously the token lived on the public
 * /users/{userId} doc — a minor could read their own token from
 * Firestore and self-approve. Combined with the open users-read rule,
 * any signed-in user could harvest another user's token and approve
 * them on the false parent's behalf.
 *
 * Attempts are counted per-token in the same subcollection; 5 wrong
 * guesses locks the token entirely and forces the minor to request a
 * new approval email.
 *
 * No idToken auth required here — the legitimate caller is the parent
 * (unauthenticated, clicking an email link). Security comes from token
 * randomness + lock-on-5-failures.
 *
 * POST /approve-parental-consent
 * Body: { userId: string, token: string, parentFullName?, relationship?, parentContact? }
 */
exports.approveParentalConsent = functions.https.onRequest(async (req, res) => {
  cors(req, res, async () => {
    try {
      if (req.method !== 'POST') {
        res.status(405).json({error: 'Method not allowed'});
        return;
      }

      const {userId, token, parentFullName, relationship, parentContact} = req.body;

      if (!userId || !token) {
        res.status(400).json({error: 'Missing required fields'});
        return;
      }

      console.log('Processing parental approval:', {userId, relationship});

      const db = admin.firestore();
      const userRef = db.collection('users').doc(userId);
      const consentRef = userRef.collection('private').doc('parentalConsent');

      // Load both docs in parallel.
      const [userSnap, consentSnap] = await Promise.all([
        userRef.get(),
        consentRef.get(),
      ]);

      if (!userSnap.exists) {
        res.status(404).json({error: 'User not found'});
        return;
      }

      const userData = userSnap.data();

      // Check if already approved (idempotent — re-clicks of email link
      // are fine, just respond OK).
      if (userData.parentApprovalDate) {
        res.status(200).json({
          success: true,
          message: 'Account already approved',
          alreadyApproved: true,
        });
        return;
      }

      // Token must come from the private subcollection (server-side
      // generated, admin-SDK-only readable). The previous fallback
      // ("if no consent doc, accept `userData.parentApprovalToken` from
      // the public users doc") was REMOVED — it re-opened the exact
      // COPPA bypass C6 was meant to close: any teen could read their
      // OWN public users doc (firestore.rules allows isSignedIn() read
      // on /users/{any}), grab the legacy token, and POST it here to
      // self-approve.
      //
      // For pre-migration in-flight emails: the parent has to ask the
      // teen to tap "Resend" so a fresh token is minted in the private
      // subcollection. A small UX hit (likely zero affected users for a
      // launch app) is the right trade vs an open COPPA bypass.
      if (!consentSnap.exists) {
        // Defensive purge: if the legacy public-doc field is still there
        // from a pre-fix run, scrub it now so it can never be misused.
        if (userData.parentApprovalToken) {
          await userRef.update({
            parentApprovalToken: admin.firestore.FieldValue.delete(),
          }).catch(() => {});
        }
        res.status(404).json({error: 'No active approval request — please ask your child to send a fresh approval email.'});
        return;
      }
      const consentData = consentSnap.data();
      if (consentData.locked) {
        res.status(429).json({
          error: 'Too many wrong attempts. Ask your child to request a new approval email.',
        });
        return;
      }
      // Token TTL: refuse tokens older than 14 days. Forces re-issue
      // for anyone who screenshots/forwards an old email and tries
      // weeks later.
      const issuedAt = consentData.tokenIssuedAt;
      if (issuedAt && typeof issuedAt.toMillis === 'function') {
        const ageMs = Date.now() - issuedAt.toMillis();
        if (ageMs > 14 * 24 * 60 * 60 * 1000) {
          await consentRef.delete().catch(() => {});
          res.status(410).json({error: 'Approval link expired — please ask your child to send a fresh email.'});
          return;
        }
      }
      const canonicalToken = consentData.token;
      const attempts = consentData.approvalAttempts || 0;

      // Constant-time compare so we never leak token bytes via
      // response-time side channels. Both inputs are 32-char lowercase
      // hex (16 bytes); reject any caller-supplied token that doesn't
      // match that shape before parsing.
      const tokenIsHex32 = typeof token === 'string' && /^[0-9a-f]{32}$/i.test(token);
      const canonicalIsHex32 = typeof canonicalToken === 'string' && /^[0-9a-f]{32}$/i.test(canonicalToken);
      let tokensMatch = false;
      if (tokenIsHex32 && canonicalIsHex32) {
        const a = Buffer.from(canonicalToken.toLowerCase(), 'hex');
        const b = Buffer.from(token.toLowerCase(), 'hex');
        if (a.length === b.length) {
          tokensMatch = crypto.timingSafeEqual(a, b);
        }
      }
      if (!tokensMatch) {
        // Wrong token — increment attempts, lock at 5.
        const newAttempts = attempts + 1;
        await consentRef.set({
          approvalAttempts: newAttempts,
          locked: newAttempts >= 5,
          lastFailedAt: admin.firestore.FieldValue.serverTimestamp(),
        }, {merge: true});
        res.status(403).json({error: 'Invalid approval token'});
        return;
      }

      // Approval payload — accept both the new mini-form fields and the
      // legacy one-tap path (where these come back undefined).
      const update = {
        isParentalApproved: true,
        parentApprovalDate: admin.firestore.FieldValue.serverTimestamp(),
        // Wipe the legacy token field if it was still there. Going
        // forward all tokens live in the private subcollection only.
        parentApprovalToken: admin.firestore.FieldValue.delete(),
      };
      if (typeof parentFullName === 'string' && parentFullName.trim().length > 0) {
        update.parentFullNameOnApproval = parentFullName.trim();
      }
      if (typeof relationship === 'string' && relationship.trim().length > 0) {
        update.parentRelationship = relationship.trim();
      }
      if (typeof parentContact === 'string' && parentContact.trim().length > 0) {
        update.parentContactOnApproval = parentContact.trim();
      }

      // Update user with approval
      await userRef.update(update);

      // Burn the token after successful use so it can't be replayed
      // (and remove the rate-limit state).
      await consentRef.delete().catch(() => {});

      console.log('Parental approval granted for user:', userId);      res.json({
        success: true,
        message: 'Parental approval granted',
      });
    } catch (error) {
      console.error('Error approving consent:', error);
      res.status(500).json({error: 'Could not process approval. Please try again or contact support.'});
    }
  });
});

/**
 * Send a real FCM push notification whenever a new notification document is created.
 * This fires for every user (both foreground and background / killed app state).
 *
 * Requires: users/{uid} to have an `fcmToken` field (saved by the iOS app on sign-in).
 */
exports.sendPushOnNotification = functions.firestore
    .document('notifications/{notificationId}')
    .onCreate(async (snap) => {
      const data = snap.data();
      const {userId, title, message: body} = data;

      if (!userId || !title || !body) return null;

      const userSnap = await admin.firestore().collection('users').doc(userId).get();
      const fcmToken = userSnap.data()?.fcmToken;

      if (!fcmToken) {
        console.log(`sendPushOnNotification: no FCM token for user ${userId}`);
        return null;
      }

      const payload = {
        token: fcmToken,
        notification: {title, body},
        apns: {
          payload: {
            aps: {sound: 'default', badge: 1},
          },
        },
        data: {
          notificationId: snap.id,
          type: data.type || '',
          relatedId: data.relatedId || '',
        },
      };

      return admin.messaging().send(payload).catch((err) => {
        console.error('sendPushOnNotification FCM error:', err.message);
      });
    });

// Firebase Auth custom tokens (Firestore/Storage security rules)
const authMint = require('./authMint');
exports.mintCustomAuthToken = authMint.mintCustomAuthToken;

/**
 * Returns true if the reporter has a NON-TRIVIAL Communally relationship
 * with the reported user. Used by `submitCriticalSafetyReport` to gate
 * auto-suspension on having a real, two-sided interaction so the endpoint
 * can't be weaponized as a one-tap DoS against strangers.
 *
 * "Non-trivial" closes the self-bootstrap attack: Firestore rules let any
 * signed-in user CREATE a conversation with `participantIds: [me, victim]`
 * without the victim's consent (rules can't check inbox-consent). If we
 * just relied on "is there a doc?" the attacker could spin up a fake
 * conversation, then immediately call this endpoint and trigger
 * auto-suspension. The real signal is whether the OTHER party also
 * participated.
 *
 * Heuristics (any one is enough):
 *  - A conversation exists AND the reported user sent at least one
 *    message (proves they're really in the thread, not just added to it).
 *  - An application exists AND its status is past `pending` (i.e. the
 *    other party acted: accepted, rejected, completed, etc.).
 *
 * Trivially-created docs (a conversation with zero messages, an
 * application still in `pending`) are NOT enough — those are exactly
 * the docs an attacker could fabricate in seconds.
 */
async function reporterHasRelationshipWith(db, reporterId, reportedUserId) {
  // Two-sided conversation: shared conversation where the REPORTED user
  // actually sent at least one message. Just being in `participantIds`
  // is not enough (attacker can add themselves + victim to a new doc).
  const convoSnap = await db.collection('conversations')
      .where('participantIds', 'array-contains', reporterId)
      .limit(50)
      .get();
  for (const doc of convoSnap.docs) {
    const parts = doc.data().participantIds || [];
    if (!parts.includes(reportedUserId)) continue;
    const msgSnap = await db.collection('conversations')
        .doc(doc.id)
        .collection('messages')
        .where('senderId', '==', reportedUserId)
        .limit(1)
        .get();
    if (!msgSnap.empty) return true;
  }
  // Two-sided application: reporter applied to a job posted by the
  // reported user AND the application is past `pending` (i.e. the
  // reported user took some action — accepted, rejected, completed).
  // A still-`pending` application means the hirer hasn't acted, so a
  // brand-new application from a stranger doesn't yet count.
  const appsAsApplicant = await db.collection('applications')
      .where('applicantId', '==', reporterId)
      .where('hirerIdSnapshot', '==', reportedUserId)
      .limit(5)
      .get();
  for (const doc of appsAsApplicant.docs) {
    const status = (doc.data().status || '').toLowerCase();
    if (status && status !== 'pending') return true;
  }
  // Two-sided application: reporter hired the reported user — the
  // reported user actually applied, so this side is symmetric (any
  // status counts: they reached out first).
  const appsAsHirer = await db.collection('applications')
      .where('applicantId', '==', reportedUserId)
      .where('hirerIdSnapshot', '==', reporterId)
      .limit(1)
      .get();
  if (!appsAsHirer.empty) return true;
  return false;
}

/**
 * submitCriticalSafetyReport — called when a user reports assault or violence.
 * 1. Writes a critical safety report to Firestore.
 * 2. If reporter and reported have a real relationship (conversation or
 *    job history), immediately flags the accused user's account
 *    (isSuspendedPending). Stranger reports queue for manual review.
 * 3. Sends an urgent email to the Communally admin team.
 *
 * POST /submitCriticalSafetyReport
 * Body: { reporterId, reporterName, reportedUserId, reportedUserName,
 *         type, description, relatedJobId?, relatedJobTitle?, idToken }
 */
exports.submitCriticalSafetyReport = functions.https.onRequest(async (req, res) => {
  cors(req, res, async () => {
    try {
      if (req.method !== 'POST') {
        res.status(405).json({error: 'Method not allowed'});
        return;
      }

      const {
        reporterId,
        reporterName,
        reportedUserId,
        reportedUserName,
        type,
        description,
        relatedJobId,
        relatedJobTitle,
        // AUTH: required to prevent mass-suspension attack where anyone
        // could POST {reporterId, reportedUserId} and immediately set
        // `isSuspendedPending: true` on any victim. The whole endpoint
        // becomes a one-tap DoS for any user account without auth.
        idToken,
      } = req.body;

      if (!reporterId || !reportedUserId || !type || !description) {
        res.status(400).json({error: 'Missing required fields'});
        return;
      }
      if (!idToken || typeof idToken !== 'string') {
        res.status(400).json({error: 'Missing idToken'});
        return;
      }

      let decoded;
      try {
        decoded = await admin.auth().verifyIdToken(idToken);
      } catch (e) {
        res.status(401).json({error: 'Invalid or expired authentication'});
        return;
      }
      if (decoded.uid !== reporterId) {
        console.warn(`Safety report spoof attempt: caller ${decoded.uid} tried to report as ${reporterId}`);
        res.status(403).json({error: 'Cannot file a report on behalf of another user'});
        return;
      }
      if (reporterId === reportedUserId) {
        res.status(400).json({error: 'You cannot report yourself'});
        return;
      }

      const db = admin.firestore();

      // Rate-limit: one report per (reporter, reported) pair per 24h.
      // Prevents a single attacker from spamming admin email + repeatedly
      // re-suspending a target who gets unsuspended.
      const oneDayAgoTs = admin.firestore.Timestamp.fromMillis(Date.now() - 24 * 60 * 60 * 1000);
      const recentSnap = await db.collection('reports')
          .where('reporterId', '==', reporterId)
          .where('reportedUserId', '==', reportedUserId)
          .where('createdAt', '>', oneDayAgoTs)
          .limit(1)
          .get();
      if (!recentSnap.empty) {
        res.status(429).json({
          error: 'You\'ve already reported this user in the last 24 hours. Our safety team is reviewing — we\'ll follow up.',
        });
        return;
      }

      // Relationship gate before auto-suspending: only auto-suspend if
      // the reporter and reported user have an existing job/conversation
      // relationship. Stranger reports still file (so safety team sees
      // them) but don't auto-trigger account suspension — prevents
      // targeted DoS where an attacker creates fake reports against
      // hirers they've never interacted with.
      const hasRelationship = await reporterHasRelationshipWith(
          db, reporterId, reportedUserId
      );

      const now = admin.firestore.FieldValue.serverTimestamp();

      // 1. Write critical safety report
      const reportRef = await db.collection('reports').add({
        reporterId,
        reporterName: reporterName || 'Anonymous',
        reportedUserId,
        reportedUserName: reportedUserName || 'Unknown',
        type,
        description,
        relatedJobId: relatedJobId || null,
        relatedJobTitle: relatedJobTitle || null,
        status: 'reviewing',
        isCritical: true,
        autoSuspended: hasRelationship,
        createdAt: now,
      });

      // 2. Only auto-suspend if reporter has a real relationship with the
      // reported user. Strangers' reports queue for manual review without
      // immediate suspension. This prevents the launch-day mass-suspension
      // attack vector while preserving fast response for real safety
      // issues between people who actually interacted.
      if (hasRelationship) {
        await db.collection('users').doc(reportedUserId).set({
          isSuspendedPending: true,
          suspensionReason: 'critical_safety_report',
          suspendedAt: now,
        }, {merge: true});
      } else {
        console.warn(
            `Safety report ${reportRef.id} from ${reporterId} against ${reportedUserId} — ` +
            `no prior relationship, NOT auto-suspending. Manual review required.`
        );
      }

      console.log(`🚨 CRITICAL SAFETY REPORT ${reportRef.id}: ${type} — accused: ${reportedUserId}`);

      // 3. Send urgent admin email
      const nodemailer = require('nodemailer');
      const transporter = nodemailer.createTransport({
        service: 'gmail',
        auth: {user: gmailEmail, pass: gmailPassword},
      });

      const adminEmail = process.env.ADMIN_EMAIL || gmailEmail || 'communallyapp@gmail.com';

      // HTML-escape every caller-controlled field before splicing into
      // the admin email template. A reporter can put `<script>` or
      // bogus links into `description`/`reportedUserName` — without
      // escaping, those render in the admin's email client (Gmail's
      // sanitiser will strip scripts but link-injection / spoofed
      // Firebase URLs survive). Cheap defense-in-depth.
      const escapeHtml = (val) => {
        if (val === null || val === undefined) return '';
        return String(val)
            .replace(/&/g, '&amp;')
            .replace(/</g, '&lt;')
            .replace(/>/g, '&gt;')
            .replace(/"/g, '&quot;')
            .replace(/'/g, '&#39;');
      };
      const safeType = escapeHtml(type).replace(/_/g, ' ');
      const safeReportId = escapeHtml(reportRef.id);
      const safeReporterName = escapeHtml(reporterName);
      const safeReporterId = escapeHtml(reporterId);
      const safeReportedUserName = escapeHtml(reportedUserName);
      const safeReportedUserId = escapeHtml(reportedUserId);
      const safeRelatedJobTitle = escapeHtml(relatedJobTitle);
      const safeRelatedJobId = escapeHtml(relatedJobId);
      const safeDescription = escapeHtml(description);

      const mailOptions = {
        from: '"Communally Safety" <communallyapp@gmail.com>',
        to: adminEmail,
        subject: `🚨 URGENT SAFETY REPORT — ${safeType.toUpperCase()} — Action Required`,
        html: `
          <div style="font-family:Arial,sans-serif;max-width:600px;margin:0 auto;padding:20px;">
            <div style="background:#cc0000;padding:24px;border-radius:10px 10px 0 0;text-align:center;">
              <h1 style="color:white;margin:0;font-size:24px;">🚨 CRITICAL SAFETY REPORT</h1>
              <p style="color:rgba(255,255,255,0.9);margin:8px 0 0 0;font-size:16px;">Immediate action required</p>
            </div>
            <div style="background:#fff8f8;border:2px solid #cc0000;border-top:none;padding:28px;border-radius:0 0 10px 10px;">
              <table style="width:100%;border-collapse:collapse;">
                <tr><td style="padding:8px 0;font-weight:bold;color:#555;width:180px;">Report Type:</td>
                    <td style="padding:8px 0;color:#cc0000;font-weight:bold;text-transform:uppercase;">${safeType}</td></tr>
                <tr><td style="padding:8px 0;font-weight:bold;color:#555;">Report ID:</td>
                    <td style="padding:8px 0;color:#333;">${safeReportId}</td></tr>
                <tr><td style="padding:8px 0;font-weight:bold;color:#555;">Reporter:</td>
                    <td style="padding:8px 0;color:#333;">${safeReporterName} (ID: ${safeReporterId})</td></tr>
                <tr><td style="padding:8px 0;font-weight:bold;color:#555;">Reported User:</td>
                    <td style="padding:8px 0;color:#cc0000;font-weight:bold;">${safeReportedUserName} (ID: ${safeReportedUserId})</td></tr>
                ${relatedJobTitle ? `<tr><td style="padding:8px 0;font-weight:bold;color:#555;">Related Job:</td>
                    <td style="padding:8px 0;color:#333;">${safeRelatedJobTitle} (ID: ${safeRelatedJobId})</td></tr>` : ''}
              </table>

              <div style="background:#fff0f0;border-left:4px solid #cc0000;padding:16px;margin:20px 0;border-radius:4px;">
                <p style="font-weight:bold;color:#cc0000;margin:0 0 8px 0;">Description:</p>
                <p style="color:#333;line-height:1.6;margin:0;white-space:pre-wrap;">${safeDescription}</p>
              </div>

              <div style="background:#fff3cd;border-left:4px solid #ff9800;padding:16px;margin:20px 0;border-radius:4px;">
                <p style="font-weight:bold;color:#e65100;margin:0 0 8px 0;">⚡ Action Already Taken:</p>
                <p style="color:#333;margin:0;">${hasRelationship ?
    `The reported user's account (${safeReportedUserId}) has been automatically flagged with <strong>isSuspendedPending: true</strong>. They remain visible in Firebase but you should review and take final action immediately.` :
    `<strong>NOT auto-suspended</strong> — reporter and reported user have no prior conversation or job relationship. Treat as manual-review only; do NOT suspend without verifying the report yourself.`
}</p>
              </div>

              <div style="text-align:center;margin:24px 0 0 0;">
                <a href="https://console.firebase.google.com/u/0/project/communally-a4cb3/firestore/data/users/${encodeURIComponent(reportedUserId)}"
                   style="background:#cc0000;color:white;padding:14px 28px;text-decoration:none;border-radius:8px;font-weight:bold;font-size:16px;display:inline-block;margin-bottom:12px;">
                  View Accused User in Firebase
                </a>
                <br/>
                <a href="https://console.firebase.google.com/u/0/project/communally-a4cb3/firestore/data/reports/${encodeURIComponent(reportRef.id)}"
                   style="background:#555;color:white;padding:14px 28px;text-decoration:none;border-radius:8px;font-weight:bold;font-size:16px;display:inline-block;">
                  View Full Report
                </a>
              </div>
            </div>
          </div>
        `,
      };

      try {
        await transporter.sendMail(mailOptions);
        console.log('✅ Critical safety alert email sent to admin');
      } catch (emailErr) {
        console.error('⚠️ Failed to send admin email (report was still saved):', emailErr.message);
      }

      res.status(200).json({
        success: true,
        reportId: reportRef.id,
        message: 'Critical safety report submitted. Account flagged and admin notified.',
      });
    } catch (err) {
      console.error('❌ submitCriticalSafetyReport error:', err);
      res.status(500).json({error: 'Could not submit safety report. Please try again or contact support.'});
    }
  });
});

/**
 * expireOldOpportunities — runs every hour.
 * Expiry = scheduledDate + 24h (or createdAt + 24h if no scheduled date).
 */
exports.expireOldOpportunities = functions.pubsub
  .schedule('every 60 minutes')
  .onRun(async () => {
    const db = admin.firestore();
    const now = new Date();
    const snap = await db.collection('opportunities')
      .where('status', '==', 'open')
      .where('isActive', '==', true)
      .get();

    if (snap.empty) {
      console.log('⏰ No open opportunities to check.');
      return null;
    }

    const batch = db.batch();
    let count = 0;
    snap.docs.forEach((doc) => {
      const data = doc.data();
      const base = data.scheduledDate ? data.scheduledDate.toDate() : data.createdAt.toDate();
      const expiry = new Date(base.getTime() + 24 * 60 * 60 * 1000);
      if (expiry <= now) {
        batch.update(doc.ref, { isActive: false, status: 'cancelled' });
        console.log(`⏰ Expiring opportunity: ${doc.id} (${data.title})`);
        count++;
      }
    });

    if (count === 0) {
      console.log('⏰ No opportunities to expire yet.');
      return null;
    }
    await batch.commit();
    console.log(`✅ Expired ${count} opportunities.`);
    return null;
  });

/**
 * Permanently delete a user's account and everything attached to it.
 * Required by Apple App Store Guideline 5.1.1(v).
 *
 * Auth: must pass an `idToken` that resolves (via admin.auth().verifyIdToken)
 * to the same uid the caller wants to delete — so users can only delete
 * themselves, never anyone else.
 *
 * Body: { idToken: string }
 *
 * Side effects:
 *  - Deletes the user's Firestore doc and userStats doc
 *  - Deletes user-owned content (opportunities they posted, applications they
 *    submitted, ratings, blocks, notifications, pins, liveLocations, reports)
 *  - Deletes their conversations and the messages subcollections inside them
 *  - Anonymizes payments (kept for financial audit; userId stripped, name → "Deleted user")
 *  - Deletes Firebase Storage files under users/{uid}/ and users-banners/{uid}/
 *  - Deletes the Firebase Auth account so all sessions on every device are revoked
 */
exports.deleteUserAccount = functions
  .runWith({ timeoutSeconds: 300, memory: '512MB' })
  .https.onRequest(async (req, res) => {
    cors(req, res, async () => {
      try {
        if (req.method !== 'POST') {
          return res.status(405).json({ error: 'Method not allowed' });
        }
        const { idToken } = req.body || {};
        if (!idToken || typeof idToken !== 'string') {
          return res.status(400).json({ error: 'Missing idToken' });
        }

        let decoded;
        try {
          decoded = await admin.auth().verifyIdToken(idToken);
        } catch (e) {
          return res.status(401).json({ error: 'Invalid auth token' });
        }
        const uid = decoded.uid;
        const db = admin.firestore();
        console.log(`🗑️  Deleting account ${uid}...`);

        // Helper: delete every doc returned by a query, in chunks.
        const deleteByQuery = async (query, label) => {
          const snap = await query.get();
          if (snap.empty) return 0;
          // Firestore batch limit is 500.
          let pending = [];
          let count = 0;
          for (const doc of snap.docs) {
            pending.push(doc.ref);
            if (pending.length >= 400) {
              const batch = db.batch();
              pending.forEach((r) => batch.delete(r));
              await batch.commit();
              count += pending.length;
              pending = [];
            }
          }
          if (pending.length) {
            const batch = db.batch();
            pending.forEach((r) => batch.delete(r));
            await batch.commit();
            count += pending.length;
          }
          if (count > 0) console.log(`  · ${label}: deleted ${count}`);
          return count;
        };

        // --- Owned content (hard delete) ---
        await deleteByQuery(
          db.collection('applications').where('applicantId', '==', uid),
          'applications (as applicant)'
        );
        await deleteByQuery(
          db.collection('applications').where('hirerIdSnapshot', '==', uid),
          'applications (as hirer)'
        );
        await deleteByQuery(
          db.collection('opportunities').where('hirerId', '==', uid),
          'opportunities'
        );
        await deleteByQuery(
          db.collection('ratings').where('raterId', '==', uid),
          'ratings (left by user)'
        );
        await deleteByQuery(
          db.collection('ratings').where('ratedUserId', '==', uid),
          'ratings (about user)'
        );
        await deleteByQuery(
          db.collection('blockedUsers').where('blockerId', '==', uid),
          'blocks (by user)'
        );
        // Field is `blockedUserId` per firestore.rules:251-253. An earlier
        // version of this function queried `blockedId`, which silently
        // matched zero docs — blocks against the deleted user lingered
        // forever even though blocks BY the user were cleaned up.
        await deleteByQuery(
          db.collection('blockedUsers').where('blockedUserId', '==', uid),
          'blocks (against user)'
        );
        await deleteByQuery(
          db.collection('notifications').where('userId', '==', uid),
          'notifications'
        );
        await deleteByQuery(
          db.collection('pins').where('hirerId', '==', uid),
          'pins (as hirer)'
        );
        await deleteByQuery(
          db.collection('pins').where('workerId', '==', uid),
          'pins (as worker)'
        );
        await deleteByQuery(
          db.collection('liveLocations').where('userId', '==', uid),
          'liveLocations'
        );
        await deleteByQuery(
          db.collection('reports').where('reporterId', '==', uid),
          'reports (filed by user)'
        );
        await deleteByQuery(
          db.collection('reports').where('reportedUserId', '==', uid),
          'reports (about user)'
        );
        // Community posts authored by the user. Apple's account-deletion
        // review explicitly checks that user-generated content disappears
        // when the account does — leaving these as "Deleted user" posts
        // on a public city feed fails review.
        await deleteByQuery(
          db.collection('communityPosts').where('authorId', '==', uid),
          'community posts'
        );

        // --- Conversations + nested messages ---
        const convoSnap = await db.collection('conversations')
          .where('participantIds', 'array-contains', uid)
          .get();
        for (const convoDoc of convoSnap.docs) {
          const msgs = await convoDoc.ref.collection('messages').get();
          if (!msgs.empty) {
            // Chunk message deletes
            let pending = [];
            for (const m of msgs.docs) {
              pending.push(m.ref);
              if (pending.length >= 400) {
                const batch = db.batch();
                pending.forEach((r) => batch.delete(r));
                await batch.commit();
                pending = [];
              }
            }
            if (pending.length) {
              const batch = db.batch();
              pending.forEach((r) => batch.delete(r));
              await batch.commit();
            }
          }
          await convoDoc.ref.delete();
        }
        if (convoSnap.size > 0) {
          console.log(`  · conversations: deleted ${convoSnap.size}`);
        }

        // --- Payments: refund stuck money FIRST, then anonymize ---
        //
        // Before we wipe the hirer/worker identity on payment docs, we
        // have to reconcile any money that's currently mid-flight. Two
        // statuses matter:
        //   * `.held`    — hirer's card was charged, money sits in
        //                  Communally's platform balance, job hasn't
        //                  completed. Either side deleting their account
        //                  means the job can never finish → refund the
        //                  hirer in full.
        //   * `.payable` — job DID complete and the worker has a balance
        //                  to claim. If the WORKER deletes, they can no
        //                  longer cash out → refund the hirer. If the
        //                  HIRER deletes, the worker keeps their claim
        //                  (their workerId stays correct in the doc;
        //                  only hirerId gets anonymized below).
        //
        // Without this pre-refund pass, the original behavior was: a
        // hirer's money could be permanently stranded in Communally's
        // platform balance because the only docs that tracked it got
        // anonymized to `hirerId: "deleted_user"`.
        if (stripe) {
          const stuckSnap1 = await db.collection('payments')
              .where('hirerId', '==', uid).get();
          const stuckSnap2 = await db.collection('payments')
              .where('workerId', '==', uid).get();

          const seen = new Set();
          const stuckDocs = [];
          [...stuckSnap1.docs, ...stuckSnap2.docs].forEach((d) => {
            if (seen.has(d.id)) return;
            seen.add(d.id);
            const s = d.data().status;
            if (s === 'held' || s === 'payable') stuckDocs.push(d);
          });

          if (stuckDocs.length > 0) {
            console.log(`  · pre-deletion: reconciling ${stuckDocs.length} stuck payment(s)`);
          }

          for (const doc of stuckDocs) {
            const payment = doc.data();
            const userIsWorker = payment.workerId === uid;
            const userIsHirer = payment.hirerId === uid;

            // Hirer-deleting + .payable → leave alone, worker keeps claim.
            if (payment.status === 'payable' && userIsHirer && !userIsWorker) {
              console.log(`    · keeping payable ${doc.id} — worker can still claim`);
              continue;
            }
            if (!payment.stripePaymentIntentId) {
              console.warn(`    · skipping ${doc.id}: no stripePaymentIntentId, can't refund`);
              continue;
            }
            try {
              const refund = await stripe.refunds.create({
                payment_intent: payment.stripePaymentIntentId,
                reason: 'requested_by_customer',
                metadata: {
                  paymentId: doc.id,
                  deletionReason: userIsWorker ? 'worker_account_deleted' : 'hirer_account_deleted',
                },
              }, {
                idempotencyKey: `delete_refund_${doc.id}`,
              });
              await doc.ref.update({
                status: 'refunded',
                refundedAt: admin.firestore.FieldValue.serverTimestamp(),
                refundReason: `Account deleted (${userIsWorker ? 'worker' : 'hirer'})`,
                stripeRefundId: refund.id,
              });
              console.log(`    · refunded ${doc.id} (${payment.status} → refunded)`);
            } catch (refundErr) {
              // Don't abort the deletion if one refund fails — log loudly
              // so the team can manually reconcile that one charge.
              console.error(
                `    · refund FAILED for ${doc.id}, manual reconciliation needed: ${refundErr.message}`
              );
            }
          }
        } else {
          console.warn('  · stripe not configured, skipping pre-deletion refund pass');
        }

        // Anonymize (keep docs for financial audit).
        const anonymizePayments = async (field, nameField) => {
          const snap = await db.collection('payments').where(field, '==', uid).get();
          if (snap.empty) return;
          const batch = db.batch();
          snap.docs.forEach((doc) => {
            const update = {};
            update[field] = 'deleted_user';
            if (nameField) update[nameField] = 'Deleted user';
            batch.update(doc.ref, update);
          });
          await batch.commit();
          console.log(`  · payments anonymized (${field}): ${snap.size}`);
        };
        await anonymizePayments('hirerId', 'hirerName');
        await anonymizePayments('workerId', 'workerName');

        // --- userStats ---
        await db.collection('userStats').doc(uid).delete().catch(() => {});

        // --- users/{uid}/private subcollection ---
        // Holds the parental-consent token + attempt counter (see
        // firestore.rules:33-38). Firestore does NOT cascade-delete
        // subcollections when the parent doc is removed, so without this
        // pass the token survives the account — defeating the COPPA
        // cleanup intent of "delete account" for under-18 users.
        await deleteByQuery(
          db.collection('users').doc(uid).collection('private'),
          'user private subcollection'
        );

        // --- User doc itself ---
        await db.collection('users').doc(uid).delete();
        console.log('  · user doc deleted');

        // --- Storage files ---
        try {
          const bucket = admin.storage().bucket();
          await bucket.deleteFiles({ prefix: `users/${uid}/` }).catch(() => {});
          await bucket.deleteFiles({ prefix: `users-banners/${uid}/` }).catch(() => {});
          await bucket.deleteFiles({ prefix: `qualifications/${uid}/` }).catch(() => {});
          // Government ID + selfie uploads from hirer onboarding.
          await bucket.deleteFiles({ prefix: `identity_docs/${uid}/` }).catch(() => {});
          // Any other per-user folders we may add over time. Catch-all for
          // anything namespaced by uid we forgot to enumerate above.
          await bucket.deleteFiles({ prefix: `${uid}/` }).catch(() => {});
          console.log('  · storage cleaned');
        } catch (e) {
          console.warn(`  · storage cleanup warning: ${e.message}`);
          // Non-fatal — Firestore deletion already happened.
        }

        // --- Auth account (revokes every session, signs out every device) ---
        await admin.auth().deleteUser(uid);
        console.log(`✅ Account ${uid} fully deleted.`);

        res.json({ success: true });
      } catch (e) {
        console.error('deleteUserAccount error:', e);
        res.status(500).json({ error: e.message || 'Internal error' });
      }
    });
  });
