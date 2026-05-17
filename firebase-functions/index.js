const functions = require('firebase-functions');
const admin = require('firebase-admin');
const fs = require('fs');
const path = require('path');

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
        amount,
        currency,
        hirerId,
        workerId,
        applicationId,
        description,
        jobAmount,
        platformFee,
        stripeFee,
      } = req.body;

      console.log('Creating payment intent:', {
        amount,
        currency,
        hirerId,
        workerId,
        applicationId,
      });

      // Get or create Stripe customer for hirer
      const hirerDoc = await admin.firestore()
          .collection('users')
          .doc(hirerId)
          .get();
      
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
        await admin.firestore()
            .collection('users')
            .doc(hirerId)
            .update({
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
        amount: amount,
        currency: currency,
        customer: customerId,
        description: description,
        metadata: {
          hirerId: hirerId,
          workerId: workerId,
          applicationId: applicationId,
          jobAmount: jobAmount.toString(),
          platformFee: platformFee.toString(),
          stripeFee: stripeFee.toString(),
        },
        automatic_payment_methods: {
          enabled: true,
        },
      };

      const paymentIntent = await stripe.paymentIntents.create(paymentIntentParams);

      res.json({
        clientSecret: paymentIntent.client_secret,
        customerId: customerId,
        ephemeralKey: ephemeralKey.secret,
        paymentIntentId: paymentIntent.id,
      });
    } catch (error) {
      console.error('Error creating payment intent:', error);
      res.status(500).json({error: error.message});
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
      } = req.body;

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

      const {paymentId} = req.body;

      if (!paymentId) {
        res.status(400).json({error: 'Missing paymentId'});
        return;
      }

      const paymentRef = admin.firestore().collection('payments').doc(paymentId);
      const paymentDoc = await paymentRef.get();

      if (!paymentDoc.exists) {
        res.status(404).json({error: 'Payment not found'});
        return;
      }

      const payment = paymentDoc.data();

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
      const deferToBalance = async (reason) => {
        const workerPayoutCents = Math.round(
            Number(payment.workerPayout || 0) * 100
        );
        await paymentRef.update({
          status: 'payable',
          payableAt: admin.firestore.FieldValue.serverTimestamp(),
          deferReason: reason,
        });
        if (workerPayoutCents > 0) {
          await admin.firestore()
              .collection('users')
              .doc(payment.workerId)
              .set({
                pendingClaimableCents:
                  admin.firestore.FieldValue.increment(workerPayoutCents),
              }, {merge: true});
        }
        res.json({
          success: true,
          deferred: true,
          reason,
          amountCents: workerPayoutCents,
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
      // In that case, Stripe already routed the payout during the original charge,
      // so we just mark the app-side payment as released.
      if (paymentIntent.transfer_data?.destination) {
        const directTransferId =
          payment.stripeTransferId || `direct_charge_${paymentIntent.id}`;

        await paymentRef.update({
          status: 'released',
          releasedAt: admin.firestore.FieldValue.serverTimestamp(),
          stripeTransferId: directTransferId,
        });

        res.json({
          success: true,
          transferId: directTransferId,
          alreadyTransferred: true,
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

      const transfer = await stripe.transfers.create({
        amount: Math.round(Number(payment.workerPayout || 0) * 100),
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
      });

      await paymentRef.update({
        status: 'released',
        releasedAt: admin.firestore.FieldValue.serverTimestamp(),
        stripeTransferId: transfer.id,
      });

      res.json({
        success: true,
        transferId: transfer.id,
      });
    } catch (error) {
      console.error('Error releasing payment:', error);
      res.status(500).json({error: error.message});
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
exports.claimEarnings = functions.https.onRequest(async (req, res) => {
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

          transferredCount += 1;
          transferredCents += amountCents;
        } catch (e) {
          console.error(`claimEarnings: failed for payment ${doc.id}:`, e.message);
          failures.push({paymentId: doc.id, reason: e.message});
        }
      }

      // Decrement the cached counter by the amount we actually transferred.
      // Using `increment(negative)` is safe under concurrent claims because
      // Firestore applies it atomically.
      if (transferredCents > 0) {
        await userRef.set({
          pendingClaimableCents:
            admin.firestore.FieldValue.increment(-transferredCents),
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

      const {paymentId, reason} = req.body;
      if (!paymentId) {
        res.status(400).json({error: 'Missing paymentId'});
        return;
      }

      const paymentRef = admin.firestore().collection('payments').doc(paymentId);
      const paymentDoc = await paymentRef.get();
      if (!paymentDoc.exists) {
        res.status(404).json({error: 'Payment not found'});
        return;
      }

      const payment = paymentDoc.data();

      if (payment.status === 'refunded') {
        res.json({success: true, alreadyRefunded: true});
        return;
      }

      if (payment.status === 'released') {
        res.status(400).json({error: 'Payment has already been released to worker and cannot be refunded.'});
        return;
      }

      if (!payment.stripePaymentIntentId) {
        // Payment was never charged — just mark it cancelled in Firestore
        await paymentRef.update({
          status: 'refunded',
          refundedAt: admin.firestore.FieldValue.serverTimestamp(),
          refundReason: reason || 'Cancelled',
        });
        res.json({success: true, neverCharged: true});
        return;
      }

      // Issue actual Stripe refund
      const refund = await stripe.refunds.create({
        payment_intent: payment.stripePaymentIntentId,
        reason: 'requested_by_customer',
        metadata: {
          paymentId: paymentId,
          applicationId: payment.applicationId || '',
          refundReason: reason || 'Job cancelled',
        },
      });

      await paymentRef.update({
        status: 'refunded',
        refundedAt: admin.firestore.FieldValue.serverTimestamp(),
        refundReason: reason || 'Job cancelled',
        stripeRefundId: refund.id,
      });

      res.json({success: true, refundId: refund.id});
    } catch (error) {
      console.error('Error refunding payment:', error);
      res.status(500).json({error: error.message});
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
    case 'payment_intent.succeeded':
      const paymentIntent = event.data.object;
      console.log('Payment succeeded:', paymentIntent.id,
          'metadata:', JSON.stringify(paymentIntent.metadata || {}));

      const succeededRef = await findPaymentDocFor(paymentIntent);
      if (succeededRef) {
        await succeededRef.update({
          status: 'held',
          chargedAt: admin.firestore.FieldValue.serverTimestamp(),
          stripePaymentIntentId: paymentIntent.id,
        });
        console.log(`  → Payment ${succeededRef.id} flipped to held`);
      } else {
        console.warn(
            `  → No Payment doc found for PaymentIntent ${paymentIntent.id}. ` +
            `Charge succeeded but app record is missing — investigate.`
        );
      }
      break;

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
 * Send parental approval email
 * POST /send-parental-approval
 * Body: {
 *   parentEmail: string,
 *   childName: string,
 *   userId: string,
 *   token: string
 * }
 */
exports.sendParentalApproval = functions.https.onRequest(async (req, res) => {
  cors(req, res, async () => {
    try {
      if (req.method !== 'POST') {
        res.status(405).json({error: 'Method not allowed'});
        return;
      }

      const {parentEmail, childName, userId, token} = req.body;

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
      res.status(500).json({error: error.message});
    }
  });
});

/**
 * Approve parental consent (called when parent clicks approval link)
 * POST /approve-parental-consent
 * Body: {
 *   userId: string,
 *   token: string
 * }
 */
exports.approveParentalConsent = functions.https.onRequest(async (req, res) => {
  cors(req, res, async () => {
    try {
      if (req.method !== 'POST') {
        res.status(405).json({error: 'Method not allowed'});
        return;
      }

      const {userId, token, parentFullName, relationship, parentContact} = req.body;

      console.log('Processing parental approval:', {userId, relationship});

      // Get user document
      const userDoc = await admin.firestore()
          .collection('users')
          .doc(userId)
          .get();

      if (!userDoc.exists) {
        res.status(404).json({error: 'User not found'});
        return;
      }

      const userData = userDoc.data();

      // Verify token matches
      if (userData.parentApprovalToken !== token) {
        res.status(403).json({error: 'Invalid approval token'});
        return;
      }

      // Check if already approved
      if (userData.parentApprovalDate) {
        res.status(200).json({
          success: true,
          message: 'Account already approved',
          alreadyApproved: true,
        });
        return;
      }

      // Approval payload — accept both the new mini-form fields and the
      // legacy one-tap path (where these come back undefined).
      const update = {
        isParentalApproved: true,
        parentApprovalDate: admin.firestore.FieldValue.serverTimestamp(),
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
      await admin.firestore()
          .collection('users')
          .doc(userId)
          .update(update);

      console.log('Parental approval granted for user:', userId);      res.json({
        success: true,
        message: 'Parental approval granted',
      });
    } catch (error) {
      console.error('Error approving consent:', error);
      res.status(500).json({error: error.message});
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
 * submitCriticalSafetyReport — called when a user reports assault or violence.
 * 1. Writes a critical safety report to Firestore.
 * 2. Immediately flags the accused user's account (isSuspendedPending).
 * 3. Sends an urgent email to the Communally admin team.
 *
 * POST /submitCriticalSafetyReport
 * Body: { reporterId, reporterName, reportedUserId, reportedUserName,
 *         type, description, relatedJobId?, relatedJobTitle? }
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
      } = req.body;

      if (!reporterId || !reportedUserId || !type || !description) {
        res.status(400).json({error: 'Missing required fields'});
        return;
      }

      const db = admin.firestore();
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
        createdAt: now,
      });

      // 2. Immediately flag accused user account
      await db.collection('users').doc(reportedUserId).set({
        isSuspendedPending: true,
        suspensionReason: 'critical_safety_report',
        suspendedAt: now,
      }, {merge: true});

      console.log(`🚨 CRITICAL SAFETY REPORT ${reportRef.id}: ${type} — accused: ${reportedUserId}`);

      // 3. Send urgent admin email
      const nodemailer = require('nodemailer');
      const transporter = nodemailer.createTransport({
        service: 'gmail',
        auth: {user: gmailEmail, pass: gmailPassword},
      });

      const adminEmail = process.env.ADMIN_EMAIL || gmailEmail || 'communallyapp@gmail.com';

      const mailOptions = {
        from: '"Communally Safety" <communallyapp@gmail.com>',
        to: adminEmail,
        subject: `🚨 URGENT SAFETY REPORT — ${type.replace(/_/g, ' ').toUpperCase()} — Action Required`,
        html: `
          <div style="font-family:Arial,sans-serif;max-width:600px;margin:0 auto;padding:20px;">
            <div style="background:#cc0000;padding:24px;border-radius:10px 10px 0 0;text-align:center;">
              <h1 style="color:white;margin:0;font-size:24px;">🚨 CRITICAL SAFETY REPORT</h1>
              <p style="color:rgba(255,255,255,0.9);margin:8px 0 0 0;font-size:16px;">Immediate action required</p>
            </div>
            <div style="background:#fff8f8;border:2px solid #cc0000;border-top:none;padding:28px;border-radius:0 0 10px 10px;">
              <table style="width:100%;border-collapse:collapse;">
                <tr><td style="padding:8px 0;font-weight:bold;color:#555;width:180px;">Report Type:</td>
                    <td style="padding:8px 0;color:#cc0000;font-weight:bold;text-transform:uppercase;">${type.replace(/_/g, ' ')}</td></tr>
                <tr><td style="padding:8px 0;font-weight:bold;color:#555;">Report ID:</td>
                    <td style="padding:8px 0;color:#333;">${reportRef.id}</td></tr>
                <tr><td style="padding:8px 0;font-weight:bold;color:#555;">Reporter:</td>
                    <td style="padding:8px 0;color:#333;">${reporterName} (ID: ${reporterId})</td></tr>
                <tr><td style="padding:8px 0;font-weight:bold;color:#555;">Reported User:</td>
                    <td style="padding:8px 0;color:#cc0000;font-weight:bold;">${reportedUserName} (ID: ${reportedUserId})</td></tr>
                ${relatedJobTitle ? `<tr><td style="padding:8px 0;font-weight:bold;color:#555;">Related Job:</td>
                    <td style="padding:8px 0;color:#333;">${relatedJobTitle} (ID: ${relatedJobId})</td></tr>` : ''}
              </table>

              <div style="background:#fff0f0;border-left:4px solid #cc0000;padding:16px;margin:20px 0;border-radius:4px;">
                <p style="font-weight:bold;color:#cc0000;margin:0 0 8px 0;">Description:</p>
                <p style="color:#333;line-height:1.6;margin:0;">${description}</p>
              </div>

              <div style="background:#fff3cd;border-left:4px solid #ff9800;padding:16px;margin:20px 0;border-radius:4px;">
                <p style="font-weight:bold;color:#e65100;margin:0 0 8px 0;">⚡ Action Already Taken:</p>
                <p style="color:#333;margin:0;">The reported user's account (${reportedUserId}) has been automatically flagged with <strong>isSuspendedPending: true</strong>. They remain visible in Firebase but you should review and take final action immediately.</p>
              </div>

              <div style="text-align:center;margin:24px 0 0 0;">
                <a href="https://console.firebase.google.com/u/0/project/communally-a4cb3/firestore/data/users/${reportedUserId}"
                   style="background:#cc0000;color:white;padding:14px 28px;text-decoration:none;border-radius:8px;font-weight:bold;font-size:16px;display:inline-block;margin-bottom:12px;">
                  View Accused User in Firebase
                </a>
                <br/>
                <a href="https://console.firebase.google.com/u/0/project/communally-a4cb3/firestore/data/reports/${reportRef.id}"
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
      res.status(500).json({error: err.message});
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
        await deleteByQuery(
          db.collection('blockedUsers').where('blockedId', '==', uid),
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
