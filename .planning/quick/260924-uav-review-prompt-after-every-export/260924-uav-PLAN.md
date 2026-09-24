---
quick_id: 260924-uav
---
# Review prompt after every export
Call StoreKit requestReview after every completed save/share (share sheet completion, incl. Save to Photos). Remove ReviewRequestManager gating. Defer the ask to scenePhase .active if the user left the app.
