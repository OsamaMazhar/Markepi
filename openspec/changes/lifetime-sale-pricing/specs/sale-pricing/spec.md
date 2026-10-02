## Purpose

Lets Markepi run a time-limited discount on the lifetime unlock from App Store Connect alone. The paywall shows the old and new price with a SALE tag, legible in every currency and layout, and the home screen announces the sale.

## ADDED Requirements

### Requirement: A sale is defined by the sale lifetime product's price

The app SHALL offer two lifetime products that grant the same Pro entitlement: the normal lifetime unlock and a sale lifetime unlock. A sale SHALL be on exactly when both products are loaded for the user's storefront and the sale product's price is strictly lower than the normal product's price. In every other case the sale SHALL be off:
- the prices are equal;
- the sale price is higher;
- either product failed to load;
- the user already holds Pro.

No app update SHALL be needed to start or end a sale; changing the sale product's price in App Store Connect is enough.

#### Scenario: Prices equal
- **WHEN** the normal and sale lifetime products are both priced $4.99
- **THEN** the paywall shows the lifetime plan at $4.99 with no strikethrough and no SALE tag, exactly as before this change

#### Scenario: Sale price lower
- **WHEN** the normal lifetime is $4.99 and the sale lifetime is $1.99
- **THEN** the sale is on

#### Scenario: Sale product unavailable
- **WHEN** the sale lifetime product fails to load (offline, not yet approved)
- **THEN** the sale is off and the normal lifetime plan is shown and purchasable

### Requirement: The lifetime plan shows the struck normal price, the sale price and a SALE tag

While a sale is on, the lifetime plan SHALL show a **SALE** tag in its badge slot beside the plan name, replacing "Best value", so the card carries one badge. Its price column SHALL show:
- the sale price, in the same bold price style as every other plan;
- directly under it, the normal lifetime price struck through, in a secondary colour.

Every plan's price SHALL sit in the same right-hand column, vertically centred, so prices line up across plans. All prices SHALL be the localized display prices from the store, never hard-coded amounts. The purchase button SHALL quote the sale price. VoiceOver SHALL read the plan as on sale, with both prices (for example "One-Time Unlock, on sale, was $4.99, now $1.99"), not as a bare struck number.

#### Scenario: Sale shown on the plan
- **WHEN** a free user opens the paywall during a $4.99 → $1.99 sale
- **THEN** the lifetime plan shows "One-Time Unlock" with a SALE tag, and $1.99 with ~~$4.99~~ under it in the price column, with no "Best value" badge
- **AND** the purchase button reads "Unlock Forever — $1.99" when the lifetime plan is selected

#### Scenario: Other plans unaffected
- **WHEN** a sale is on
- **THEN** the monthly and annual plans keep their own badge and price, in the same aligned price column

### Requirement: Sale prices wrap legibly instead of truncating

Plan prices SHALL never truncate, clip, overlap, or shrink below the plan's price text size, on any plan. Each plan SHALL use the first of these layouts that fits the width actually available:
1. **Price column:** the plan name, badge and subtitle on the left, with the subtitle wrapping as needed. The price column is on the right: the sale price with the struck price under it during a sale.
2. **Prices under the text:** the price group moves under the subtitle, leading-aligned. The price and the struck price share a line, or each gets its own line if that line doesn't fit.

If the plan name and badge don't fit on one line, the badge SHALL move under the name. The choice SHALL depend only on measured width, so it SHALL apply the same way on iPhone, iPad, portrait, landscape, the paywall sheet, the full-screen onboarding paywall, and every Dynamic Type size, including accessibility sizes.

#### Scenario: Short currency on iPhone portrait
- **WHEN** the prices are $4.99 and $1.99 on an iPhone in portrait at default text size
- **THEN** the lifetime plan uses the price column, aligned with the annual and monthly prices

#### Scenario: Long currency
- **WHEN** the prices are long, such as "₫129,000" and "₫51,600" or "IDR 79,000" and "IDR 31,600"
- **THEN** each plan uses the first layout that fits, and no digit of either price is truncated or clipped

#### Scenario: Accessibility text size
- **WHEN** the user's Dynamic Type is set to an accessibility size
- **THEN** each plan's prices sit under its text, every price is fully readable, no word is broken mid-word by a squeezed column, and the card grows taller instead of clipping

#### Scenario: iPad and landscape
- **WHEN** the paywall is shown on iPad, as a sheet or full screen, or on an iPhone in landscape during a sale
- **THEN** the plans follow the same rules from the width available, and the purchase button stays visible or reachable by scrolling

### Requirement: Purchasing during a sale buys the sale product, and either product restores Pro

While a sale is on, buying the lifetime plan SHALL purchase the sale lifetime product at the sale price. While the sale is off, it SHALL purchase the normal lifetime product. Owning either lifetime product SHALL grant Pro, including after Restore Purchases, on another device, and after the sale ends.

#### Scenario: Buy during the sale
- **WHEN** a free user buys the lifetime plan during a $1.99 sale
- **THEN** they are charged $1.99 and become Pro

#### Scenario: Sale buyer after the sale ends
- **WHEN** someone who bought the sale lifetime product reinstalls after the sale has ended and taps Restore Purchases
- **THEN** they are Pro

### Requirement: The home screen shows SALE while a sale is on

On the start screen, the toolbar Pro button SHALL show a **SALE** label next to the crown, inside one capsule, for free users while a sale is on. It SHALL open the same paywall. Pro users SHALL never see the label, and it SHALL disappear as soon as the sale ends or the user becomes Pro. It SHALL respect Reduce Motion, so any shine or animation stops. Its accessibility label SHALL say the upgrade is on sale.

#### Scenario: Free user during a sale
- **WHEN** a free user opens the app during a sale
- **THEN** the start screen's crown button shows the crown and "SALE" together, and tapping it opens the paywall with the sale shown

#### Scenario: Pro user during a sale
- **WHEN** a Pro user opens the app during a sale
- **THEN** the crown button looks as it does today, with no SALE label

#### Scenario: No sale
- **WHEN** no sale is on
- **THEN** the crown button looks as it does today
