## 1. Sale model (MarkepiCore/Premium)

- [x] 1.1 Add `PremiumProduct.lifetimeSale = "markepi.pro.lifetime.sale"`, and make `isSubscription` false for it. Verify `allIdentifiers` contains it and a test asserts it isn't a subscription.
- [x] 1.2 Add `LifetimeOffer` with `make(normal:sale:)` (design §2). Verify with unit tests on plain values:
  - sale lower → on sale, buys the sale ID, original = the normal display price;
  - prices equal → no sale, buys the normal ID;
  - sale higher → no sale;
  - only normal loaded, or only sale loaded → unstruck;
  - neither loaded → nil.
- [x] 1.3 Expose `StoreManager.lifetimeOffer`, computed from `products`, with no sale while `isPremium`. Add the DEBUG `debugSimulateSale`: 40% of the normal price, formatted with `priceFormatStyle`, compiled out of Release. Verify `swift test --skip ExtensionSnapshotTests --skip C2PARealSigningIntegrationTests` passes.
- [x] 1.4 Add the sale product to `Markepi.storekit` at $4.99 (no sale). Verify a local StoreKit run loads 4 products and the paywall is unchanged.

## 2. Paywall (App/Views/Premium/PaywallView.swift)

- [ ] 2.1 Route lifetime purchases through `lifetimeOffer.purchaseID`, and quote `lifetimeOffer.displayPrice` in the lifetime card and the CTA. Verify that with the `.storekit` sale price set to $1.99, buying lifetime charges $1.99, grants Pro, and the CTA reads "Unlock Forever — $1.99".
- [x] 2.2 Build `SalePriceGroup` (struck price, sale price, SALE tag; `.fixedSize()`, no scaling) and the lifetime card's three-layout `ViewThatFits` (design §4). Hide "Best value" while on sale, and set a VoiceOver label like "on sale, was X, now Y". Verify the previews at these prices:
  - `$4.99/$1.99`
  - `Rp 79.000/Rp 32.000`
  - `₫129.000/₫49.000`
  - `CHF 5.00/CHF 2.00`

  Check each pair at default and AX3 text sizes, and at iPhone portrait, landscape and iPad sheet widths. Nothing may be truncated or clipped, and each case must use the expected layout (1, 2 or 3).
- [ ] 2.3 Verify with DEBUG "Simulate Sale" on device that the paywall sheet, the iPad form sheet and the onboarding full-screen paywall show the sale. Check portrait and landscape: the CTA must stay reachable, and with the sale off the cards must be pixel-identical to before.

## 3. Home crown (App/Views/ContentView.swift)

- [x] 3.1 Give `PremiumCrownIcon` an `onSale` capsule (crown + "SALE", gold, the existing sweep, no sweep under Reduce Motion), driven by `!isPremium && lifetimeOffer.isOnSale`. Add the "on sale" accessibility label and the DEBUG "Simulate Sale" toggle in Settings. Verify on the start screen in portrait and landscape:
  - a free user with Simulate Sale on sees the SALE capsule;
  - with Force Premium on, no SALE;
  - with Simulate Sale off, it looks as it does today.

## 4. Release

- [x] 4.1 Run `bash scripts/build-gate.sh` and the MarkepiCore suite. Verify both are green.
- [ ] 4.2 App Store Connect, after explicit user OK:
  - Create the `markepi.pro.lifetime.sale` non-consumable with a display name, description and review screenshot, at a $4.99 base price.
  - Attach it to the next build's submission.

  Verify through the ASC API that it exists with a $4.99 US price.
- [ ] 4.3 After the IAP is approved and the user OKs it, schedule $1.99 from Oct 6 to Oct 31 2026. Verify the ASC price schedule shows $1.99 in that window and $4.99 after it.
- [x] 4.4 Add a "Running a sale" note to `notebook.md`. It covers scheduling the sale product's price and leaving 30+ days at the normal price between sales (reference-price rule). Verify the section exists.
