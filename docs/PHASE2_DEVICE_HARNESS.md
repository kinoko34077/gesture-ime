# Phase 2 iOS Gesture Harness

Issue: #10

## Purpose

This app is a measurement harness around `GestureIMECore`. It does not define gesture semantics.

It exposes:

- raw touch trace;
- current virtual anchor;
- committed anchors;
- current GesturePath;
- current candidate direction;
- eligible outgoing directions from the BindingTrie;
- dispatched actions;
- editable GesturePolicy values;
- trial counters for observed and accidental stage-2 activation.

## Build route

The normal development route does not require a local modern Mac:

```text
GitHub branch / PR
→ GitHub Actions macOS + Xcode
→ GestureHarness-unsigned.ipa
→ download on Windows
→ sideload/re-sign with the selected Windows+iPhone sideload tool
→ physical iPhone measurement
```

The GitHub Actions artifact is intentionally unsigned. The sideload tool is responsible for development signing/re-signing for the user's device.

## Measurement procedure

For each candidate GesturePolicy:

1. Select **4-way** and confirm only N/E/S/W are offered.
2. Select **Diagonal + 2-stage** and verify NE appears.
3. Use **Single-stage trial** while repeatedly performing ordinary flicks.
4. Record Trials and Accidental rate.
5. Use **Two-stage trial** and repeatedly perform deliberate [E,N] and [E,E].
6. Record successful two-stage recognition.
7. Adjust dead zone, stage-1 distance, stage-2 distance, and hysteresis.
8. Do not promote numeric defaults to the common canon until physical-device evidence is recorded on #10.

## Development signing boundary

Phase 2 does not use App Group or other shared-container entitlements.

Phase 3 may add a Keyboard Extension while continuing the same CI/sideload route. Phase 5 separately decides the signing/capability path for App Group/shared storage.
