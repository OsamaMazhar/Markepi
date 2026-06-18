# Phase 7: Additional Inputs & System Integration (v2) - Discussion Log

> **Audit trail only.** Do not use as input to planning, research, or execution agents.
> Decisions are captured in CONTEXT.md — this log preserves the alternatives considered.

**Date:** 2026-06-18
**Phase:** 7-additional-inputs-system-integration-v2
**Areas discussed:** Live Photos, Signature capture, Files import & Open In, Quick actions, App Intents

---

## Live Photos

| Option | Description | Selected |
|--------|-------------|----------|
| PHLivePhotoEditingContext | Apple's high-level API for reading/writing Live Photos | ✓ |
| Manual paired asset extraction | Extract still + video independently, re-pack manually | |

**User's choice:** PHLivePhotoEditingContext (Recommended)

---

| Option | Description | Selected |
|--------|-------------|----------|
| Both still frame + all motion frames | Watermark persists through entire animation | ✓ |
| Still frame only | Watermark disappears during playback | |

**User's choice:** Both still frame + all motion frames (Recommended)

---

| Option | Description | Selected |
|--------|-------------|----------|
| Detect in PhotosPicker + handle as paired asset | Single Live Photo item, engine processes both components | ✓ |
| Separate still + video selection | Two separate items for one Live Photo | |

**User's choice:** Detect in PhotosPicker + handle as paired asset (Recommended)

---

| Option | Description | Selected |
|--------|-------------|----------|
| Preserve as Live Photo | Output remains a proper Live Photo asset | ✓ |
| Offer choice: Live Photo or still only | Additional export option | |

**User's choice:** Preserve as Live Photo (Recommended)

---

## Signature Capture

| Option | Description | Selected |
|--------|-------------|----------|
| PencilKit (PKCanvasView) | Pressure sensitivity, stroke smoothing, Apple Pencil support | ✓ |
| Simple UIView drawing | No pressure sensitivity or smoothing | |
| Import as image only | No drawing canvas, reuse existing LogoPickerView | |

**User's choice:** PencilKit (Recommended)

---

| Option | Description | Selected |
|--------|-------------|----------|
| New .signature WatermarkLayer case | SignatureInput model, preserves vector data for re-editing | ✓ |
| Render to PNG and reuse .image | Flatten to PNG, no model changes, loses editability | |

**User's choice:** New .signature WatermarkLayer case (Recommended)

---

| Option | Description | Selected |
|--------|-------------|----------|
| Modal sheet from layer controls | Full-screen PKCanvasView, follows LogoPickerView pattern | ✓ |
| In-place in controls area | Mini canvas embedded in scroll area | |

**User's choice:** Modal sheet from layer controls (Recommended)

---

| Option | Description | Selected |
|--------|-------------|----------|
| Ink color + stroke width + standard layer controls | Re-render stroke data in new color, full per-layer controls | ✓ |
| Position/scale/opacity only | Signature locked after capture | |

**User's choice:** Ink color + stroke width + position/scale/opacity (Recommended)

---

## Files Import & Open In

| Option | Description | Selected |
|--------|-------------|----------|
| Both: Register document types + in-app file browser | Covers both push (Open In) and pull (browse) use cases | ✓ |
| In-app file browser only | No system-level Open In registration | |
| Register document types only | No in-app browsing | |

**User's choice:** Both: Register document types + in-app file browser (Recommended)

---

| Option | Description | Selected |
|--------|-------------|----------|
| Replace current selection + enter watermarking | Clean "watermark this specific file" flow | ✓ |
| Add to existing selection | Append to thumbnail strip | |

**User's choice:** Replace current selection + enter watermarking (Recommended)

---

| Option | Description | Selected |
|--------|-------------|----------|
| Photos + videos: match existing engine capabilities | All formats the engine handles | ✓ |
| Photos only | No video import from Files | |

**User's choice:** Photos + videos: match existing engine capabilities (Recommended)

---

| Option | Description | Selected |
|--------|-------------|----------|
| .onOpenURL + CFBundleDocumentTypes | Native document type handling, no custom URL scheme | ✓ |
| Custom URL scheme (watermark://open) | Deep link approach, already referenced in ShareExtensionViewModel | |

**User's choice:** .onOpenURL + CFBundleDocumentTypes (Recommended)
**Notes:** User initially selected custom URL scheme, then asked to re-answer and chose .onOpenURL.

---

## Quick Actions

| Option | Description | Selected |
|--------|-------------|----------|
| Open app with last watermarked source | Requires tracking prior photos | |
| Open the most recent photo from camera roll | Requires PhotoKit permission | |

**User's choice:** Free-text: "No we don't keep the record of any photo."

---

| Option | Description | Selected |
|--------|-------------|----------|
| Open app directly to PhotosPicker | Fast-launch shortcut to import | |
| Use most recent camera roll photo | Requires photo library permission | |
| Drop the quick action | Replace or remove "Watermark Last Photo" | ✓ |

**User's choice:** Drop the quick action

---

| Option | Description | Selected |
|--------|-------------|----------|
| Detect image on pasteboard, open app with it loaded | Check UIPasteboard, pre-load if image exists | ✓ |
| Open app to PhotosPicker + show clipboard prompt | Extra confirmation step | |

**User's choice:** Detect image on pasteboard, open app with it loaded (Recommended)

---

| Option | Description | Selected |
|--------|-------------|----------|
| Just 'Watermark from Clipboard' | One clean quick action | |
| Add 'Open PhotosPicker' quick action | Second fast-launch shortcut | |

**User's choice:** Free-text: "bring back the watermark last photo and select the last newest photo from photo picker"

---

| Option | Description | Selected |
|--------|-------------|----------|
| Yes, use PhotoKit to fetch most recent photo | PHAsset fetch with creationDate descending | ✓ |
| No, use a different approach | | |

**User's choice:** Yes, use PhotoKit to fetch most recent photo (Recommended)
**Notes:** Clarification: PhotosPicker cannot be programmatically pre-selected. "Last newest photo" requires PhotoKit PHAsset fetch.

---

| Option | Description | Selected |
|--------|-------------|----------|
| Open app with media pre-loaded in watermarking UI | Full interactive config flow | ✓ |
| Process headlessly and present share sheet | No preview, uses last config | |

**User's choice:** Open app with media pre-loaded in watermarking UI (Recommended)

---

## App Intents (Siri & Shortcuts)

**Research:** WWDC 2026 — App Intents NOT deprecated; SiriKit IS deprecated. App Intents now mandatory for Siri AI integration. Apple recommends @AssistantIntent + AppIntent dual protocol, task-based intents over navigation intents.

| Option | Description | Selected |
|--------|-------------|----------|
| @AssistantIntent + AppIntent | Siri AI + Shortcuts, future-proof for iOS 27 | ✓ |
| AppIntent only (Shortcuts app) | No Siri AI integration | |

**User's choice:** @AssistantIntent + AppIntent (Recommended)

---

| Option | Description | Selected |
|--------|-------------|----------|
| 'Watermark Photo' + 'Watermark Video' | Two task-based intents | ✓ |
| Single 'Watermark Media' intent | One intent for all media types | |
| Multiple granular intents | Separate intents per watermark type | |

**User's choice:** 'Watermark Photo' + 'Watermark Video' (Recommended)

---

| Option | Description | Selected |
|--------|-------------|----------|
| Open app with media pre-loaded for interactive config | Full watermarking UI | ✓ |
| Both: headless default + optional preview | Dual mode | |
| Headless only | No UI, uses last config | |

**User's choice:** Open app with media pre-loaded for interactive config (Recommended)

---

| Option | Description | Selected |
|--------|-------------|----------|
| Media item + optional config | IntentFile + optional JSON WatermarkConfiguration | ✓ |
| Media item only | Always uses last-used config | |

**User's choice:** Media item + optional config (Recommended)

---

## Claude's Discretion

- PHLivePhotoEditingContext implementation details
- SignatureInput model structure and PencilKit serialization
- PKCanvasView UI customization
- CFBundleDocumentTypes UTI list compilation
- PhotoKit authorization for "Watermark Last Photo"
- UIPasteboard image type detection
- App Intents target architecture (in-app vs extension)
- @AssistantIntent natural language phrases
- IntentFile handling for media transfer
- Optional config JSON parameter approach
- Live Photos in extension entry points

## Deferred Ideas

None — discussion stayed within phase scope.
