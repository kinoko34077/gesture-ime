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
2. Select **8-way + 2-stage** and confirm N/NE/E/SE/S/SW/W/NW are all offered at the root.
3. Commit E as stage 1 and confirm the virtual anchor moves; from the new anchor only E/N are offered by the current two-stage test bindings.
4. Use **Single-stage** while repeatedly performing ordinary one-stage flicks.
5. Record Trials and Accidental rate.
6. Use **Target [E,N]** and **Target [E,E]** separately and repeat each target gesture.
7. Record each target's success rate.
8. Adjust dead zone, stage-1 distance, stage-2 distance, and hysteresis.
9. Do not promote numeric defaults to the common canon until physical-device evidence is recorded on #10.

## Development signing boundary

Phase 2 does not use App Group or other shared-container entitlements.

Phase 3 may add a Keyboard Extension while continuing the same CI/sideload route. Phase 5 separately decides the signing/capability path for App Group/shared storage.
