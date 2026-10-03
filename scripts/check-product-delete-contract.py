#!/usr/bin/env python3
from pathlib import Path

root = Path(__file__).resolve().parents[1]
surface = (root / "App/KeyboardExtension/AzooKeyProductKeyboardSurface.swift").read_text()
bridge = (root / "App/KeyboardExtension/AzooKeyCompositionBridge.swift").read_text()

delete_case_start = surface.index('        case "edit.delete":')
delete_case_end = surface.index('        case "cursor.move":', delete_case_start)
delete_case = surface[delete_case_start:delete_case_end]

required_case = [
    "composition.deleteBackward(count: count)",
    "composition.deleteForward(count: -count)",
]
for needle in required_case:
    if needle not in delete_case:
        raise SystemExit(f"edit.delete routing missing: {needle}")
if "composition.commitSelectionOrRaw()" in delete_case:
    raise SystemExit("negative edit.delete must not degrade to commit-only behavior")

forward_start = bridge.index("    func deleteForward(count: Int) {")
forward_end = bridge.index("    func moveCursor(_ offset: Int) {", forward_start)
forward = bridge[forward_start:forward_end]

required_forward = [
    "displayedTextManager.deleteForward(count: count)",
    "composingText.deleteForwardFromCursorPosition(count: count)",
    "displayedTextManager.updateComposingText(",
    "refreshCandidates()",
]
for needle in required_forward:
    if needle not in forward:
        raise SystemExit(f"composition forward-delete path missing: {needle}")

print("Product edit.delete forward contract PASS")
