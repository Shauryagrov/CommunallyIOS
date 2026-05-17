# Communally — Session Handoff

This is a context dump for a Claude session continuing on another machine. Paste/share this with the next Claude.

---

## The product in one paragraph

Communally is a US-only local job marketplace iOS app (SwiftUI + Firebase + Stripe). Teens (13–17) and adults (18+) can sign up as either **seekers** (apply for jobs) or **hirers** (post jobs). Hirers pay through Stripe Payment Sheet; funds sit in Communally's platform balance (escrow), then transfer to the seeker's Stripe Connect account after both parties confirm completion. Under-18 seekers can't onboard to Stripe Connect (US KYC rule) so the design pushes them to have a parent fill out payouts in the parent's name. Repo root: `/Users/madhurgrover/Communally-1 4/`. Launch target was originally today (2026-05-16/17), pivoted to "App Store submission today, real-world launch when Apple approves."

## Current state

App is in late pre-launch testing. End-to-end payment flow is now working as of this session — verified `.pending` → `.held` → `.payable` → `.released` (Paid to bank). UI gates removed for "earn first, set up payouts later" pattern. Testing mode is on across schedule rules.

## Architecture cheat sheet

- **iOS source**: `Communally/` (Views, Services, Managers, Models)
- **Firestore rules**: `firestore.rules`
- **Cloud Functions**: `firebase-functions/index.js` (Stripe webhooks, Connect onboarding, payment release, claim earnings, custom safety report, account deletion)
- **Public hosting**: `public/stripe-return.html`, `public/stripe-refresh.html`
- **Entitlements**: `Communally/Communally.entitlements` (Apple Pay merchant ID is `merchant.shaurlabs.Communally`)
- **Stripe key (live)**: `pk_live_…` baked into `Communally/Services/StripeConfig.swift`
- **Backend URL**: `https://us-central1-communally-a4cb3.cloudfunctions.net`
- **Webhook endpoint name** in Stripe Dashboard: "vibrant-rhythm" — subscribed to `payment_intent.succeeded`, `payment_intent.payment_failed`, `account.updated`, `identity.verification_session.verified`, `identity.verification_session.canceled`, `charge.refunded`

## Critical design decision: DEFERRED PAYOUT FLOW (DoorDash pattern)

Seekers can apply to jobs WITHOUT Stripe Connect set up. Their earnings accumulate in an in-app "Communally balance" (Payment doc `status: 'payable'`). When they finally connect Stripe + tap Cash Out, all `.payable` payments are drained as real Stripe transfers in one batch.

**Flow:**
1. Hirer pays via Stripe Sheet → Payment doc created with `status: 'pending'` BEFORE the sheet shows (this order matters, see "Critical bug fix" below)
2. Stripe webhook fires `payment_intent.succeeded` → backend updates Payment doc to `status: 'held'`
3. Both parties confirm completion → JobCompletionView calls `PaymentManager.releasePayment` → backend `/releasePayment` endpoint
4. **If seeker has Stripe Connect + payouts enabled** → real `stripe.transfers.create` fires → `status: 'released'`
5. **If seeker has NO Connect** → backend marks doc `status: 'payable'`, increments user doc's `pendingClaimableCents` → returns `{success: true, deferred: true}`. Money stays in platform balance.
6. Seeker visits EarningsView → sees claimable balance → taps "Cash out $X" → backend `/claimEarnings` endpoint drains all `.payable` payments → real Stripe transfers → `status: 'released'`

## Critical bug fix from this session (PaymentView race condition)

**Bug:** Every payment was getting stuck on `.pending` forever. Cause: iOS app created the Payment doc AFTER the Stripe Sheet succeeded. The Stripe webhook fires the instant Stripe captures, querying for the Payment doc by `stripePaymentIntentId` — but the doc didn't exist yet. Silent no-op. Then iOS tried to flip status via `updateData` with no completion handler, and the brittle `getDocument` round-trip in `PaymentManager.createPayment` sometimes returned a Payment with `id: nil`, causing `safeId` to return a random UUID and updates to hit a phantom doc.

**Fix (across 3 files):**
- `PaymentManager.createPayment` now pre-allocates the doc ref via `db.collection().document()` then `setData`, so the ID is always real
- `PaymentView.processPayment` creates the Payment doc BEFORE invoking Stripe Sheet
- `firebase-functions/index.js` webhook now uses `findPaymentDocFor()` helper — looks up by `metadata.applicationId` first, falls back to `stripePaymentIntentId`

## Testing mode flags (FLIP BEFORE SHIPPING PRODUCTION)

Two files have `private static let testingMode: Bool = true`:
- `Communally/Views/PostOpportunityView.swift` (line ~47)
- `Communally/Views/OpportunityDetailView.swift` `RescheduleOpportunitySheet` (around line ~1338)

While true:
- Curfew: 00:00–23:59 (vs production 7 AM – 7 PM)
- Lead time: 5 min (vs production 30 min)
- Job duration minimum: **2 min** (vs production 30 min)

Helper text + error messages are dynamic off these constants — flipping back to `false` updates the UI copy automatically.

## What's been done this session (chronological-ish)

1. Fixed Map "Finish your profile" card hiding under status bar (DashboardView windowTopSafeAreaInset)
2. Hid debug UI in production (`#if DEBUG` wrapping of Developer Options, Reset Bank Connection)
3. Added Apple Pay merchant ID to entitlements (`merchant.shaurlabs.Communally`)
4. Tightened Firestore rules — `userStats` self-write blocked + shape-enforced; `liveLocations` gated by `allowedViewers` allow-list
5. `LiveLocationManager.updateJourneyStatus` writes `allowedViewers: [hirerId]` and `ActiveJobView.confirmArrivedReadyToStart` threads the hirer ID through
6. Closed escrow loophole in `cancelApplication` — refuses to refund after worker has confirmed completion
7. Polished `LockedDecoyOpportunityList` (then later disabled it entirely — see #11)
8. Rewrote `public/stripe-return.html` so it doesn't lie ("Bank Setup Complete ✓" → "You're all set to head back")
9. Stripe Connect onboarding now prefills business details (mcc 7299, individual type, description, support email) + first/last name + DOB so seekers skip the "Business details" and "Your name" Stripe screens
10. **MAJOR**: Built deferred-payout system end-to-end
    - Added `.payable` PaymentStatus to `Models/Payment.swift`
    - `PaymentManager.getClaimableEarnings`, `claimEarnings()` method that calls new backend endpoint
    - Backend `releasePayment` modified: if worker has no Connect, marks `.payable` instead of erroring
    - New backend `claimEarnings` endpoint (auth-required) that drains all `.payable` payments via real Stripe transfers
    - New `EarningsView.swift` — seeker-facing balance hero + Cash Out CTA + recent earnings list + parent-can-do-it nudge for teens
11. Removed `requiresBankSetupToBrowse` gate (was `true`, now `false`) — seekers see real jobs without Stripe Connect
12. Removed `needsBankSetupToApply` gate in `OpportunityDetailView` — seekers can apply without Stripe
13. Removed silent gate in `ApplicationManager.applyToOpportunity` (`canReceivePayments` check that printed to console with no UI feedback) — this was the actual blocker
14. Split header gear icon into **Radius button (Map only) + Money button (always)** for seekers. Hirers got Community/Bell/Money. Same sizing + spacing.
15. SOS simplified to direct `tel:911` call (was a 4-option confirmation dialog). Share Location stays as separate button next to it.
16. Real-time sync fix on hirer's "Mark as Complete" button: now also accepts `pinService.isVerified(.jobStart)` as a truth source — used to require waiting for LiveLocation broadcast which had a race condition, causing the hirer to have to close+reopen the In Progress sheet
17. Hirer profile in OpportunityDetailView header is now tappable via `NavigationLink` to `UserProfileView`. Avatar inline. Removed `timeAgo` from "Posted by" line.
18. After hirer's payment completes, `OpportunityDetailView` auto-dismisses (0.55s delay) so they land on dashboard
19. Teen parental notice in BankSetupSheet AND EarningsView for under-18 users — orange card explains "ask a parent to fill this out, payouts go to their bank, you still see balance here"
20. Reschedule sheet curfew lifted (was hardcoded 7 AM – 7 PM, now uses its own testingMode)
21. Minimum job duration dropped from 5 min to 2 min in testing mode
22. Pet Care payment debugging — root cause was the order-of-ops race; now fixed
23. EarningsView hero made adaptive: shows pending when there's any, falls back to lifetime when everything's cashed out (so the screen doesn't feel "broken" after a successful Cash Out)
24. Added "Funds land in your bank within 1–2 business days" timing copy: permanent reminder under the Cash Out button, also in the cash-out success alert, AND in the hero subtitle when everything's been cashed out

## What's still on the user's plate

### Must do before App Store submit:
- [ ] Build to physical hirer device + complete a fresh end-to-end test (this session's bug fix needs the iOS code on the hirer's phone too)
- [ ] `firebase deploy --only functions` — full deploy, not just specific functions (especially `stripeWebhook` which was modified in this session)
- [ ] In Apple Developer: register `merchant.shaurlabs.Communally` as a Merchant ID
- [ ] In Xcode: Signing & Capabilities → Add Apple Pay capability → check `merchant.shaurlabs.Communally`
- [ ] In Stripe Dashboard → Payment methods → Apple Pay: add the merchant ID, exchange CSR for cert with Apple, upload back
- [ ] App Store Connect: screenshots, app description, age rating, privacy policy URL, review notes (explain teen-marketplace + parent-as-guardian payout setup so reviewer doesn't reject)
- [ ] Delete any orphaned `.pending` Payment docs from Firestore (artifacts from before today's bug fix)

### Should do soon after launch:
- [ ] Cloud Scheduler function to auto-cancel `.pending` Payment docs older than 30 min (orphan cleanup)
- [ ] Cloud Scheduler function to refund `.payable` payments older than 60 days unclaimed
- [ ] Move `userStats` writes to a Firestore-triggered Cloud Function so signed-in users can't overwrite each other's ratings (current rules block obvious tampering but leave residual risk — comment in `firestore.rules` flags this)
- [ ] Flip `requireStripeIdentityForPaidPosts` to true once you're comfortable gating paid posts behind ID verification
- [ ] Request platform credit limit increase in Stripe Dashboard so Instant Payouts to debit cards becomes viable
- [ ] Flip both `testingMode: Bool = true` flags to `false` before production
- [ ] Build out the `/regression-test` skill (user agreed to it, work was just starting when convo wrapped)

### Known issues / scope-creep:
- Push notification on payment release says "You've been paid $X" — slightly misleading for deferred case where money is in app balance, not bank. Not blocking.
- Apple Pay capability still requires external setup (Apple Dev portal + Stripe Dashboard). Code is correct.

## Key file paths I touched this session

```
/Users/madhurgrover/Communally-1 4/
├── Communally/
│   ├── Models/
│   │   └── Payment.swift                 (added .payable status)
│   ├── Services/
│   │   ├── ApplicationManager.swift      (removed bank gate from applyToOpportunity)
│   │   ├── PaymentManager.swift          (pre-allocate doc ID, claimEarnings method, getClaimableEarnings)
│   │   └── LiveLocationManager.swift     (allowedViewers scoping for security)
│   ├── Views/
│   │   ├── DashboardView.swift           (icon split, requiresBankSetupToBrowse=false, EarningsView wiring)
│   │   ├── OpportunityDetailView.swift   (removed apply gate, tappable hirer profile, auto-dismiss after pay, reschedule testingMode)
│   │   ├── PostOpportunityView.swift     (testingMode added, 2-min duration)
│   │   ├── EarningsView.swift            (NEW — entire file written this session)
│   │   ├── BankSetupView.swift           (teen parental notice, debug UI gated)
│   │   ├── JobCompletionView.swift       (copy updated for deferred flow)
│   │   ├── ActiveJobView.swift           (PIN-fallback for Complete button, SOS simplified)
│   │   └── PaymentView.swift             (CRITICAL: createPayment-then-Stripe order swap)
│   └── Communally.entitlements           (Apple Pay merchant ID)
├── firebase-functions/
│   └── index.js                          (releasePayment defers, claimEarnings endpoint, webhook findPaymentDocFor)
├── firestore.rules                       (userStats + liveLocations tightened)
└── public/
    └── stripe-return.html                (honest return page)
```

## Quick mental model of the seeker journey

1. Sign up → onboarding → home dashboard
2. Browse jobs (Map or list, filtered by radius slider on Map)
3. Tap a job → OpportunityDetailView (can tap hirer's avatar to vet them)
4. Apply (no bank required)
5. If accepted: ActiveJobView shows in progress, PIN exchange with hirer at the location, Job Start
6. After scheduled end time: both confirm completion in JobCompletionSheet, exchange completion PIN, submit ratings
7. Earnings show up in EarningsView (Pending Payout hero)
8. Tap Cash Out → BankSetup if no Connect → finish Stripe Connect → auto-runs cash-out → "We sent $X to your bank, lands in 1–2 days"

## Quick mental model of the hirer journey

1. Sign up → onboarding (including verified home address + age 18+) → dashboard
2. Post a job (PostOpportunityView, paid only, $/hr within category floor/ceiling)
3. Wait for applicants → see inline cards in OpportunityDetailView
4. Tap Accept → confirmation alert → PaymentConfirmationSheet → Stripe Payment Sheet
5. Pay → both detail sheet + payment sheet auto-dismiss → land back on dashboard
6. When worker arrives, share the Start PIN
7. After scheduled end + both confirm completion → escrow releases automatically

## Bash tool was broken this whole session

The shell sandbox kept returning proxy errors. Worked around by using Read/Edit/Write directly with hardcoded paths. Be aware if the next Claude session has the same issue — if so, you'll have to navigate by knowing paths instead of grepping.

## My current opinion on launch readiness

The app is in a solid state. The payment pipeline is the highest-risk piece and it's now end-to-end verified (user confirmed "Paid to bank"). The remaining items are external setup (Apple Pay cert exchange, App Store Connect submission), not code. If the next iteration smooths the App Store assets + does one more full end-to-end run on real devices (hirer + seeker), this is shippable.
