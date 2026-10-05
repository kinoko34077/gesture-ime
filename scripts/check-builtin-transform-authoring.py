#!/usr/bin/env python3
import json
from pathlib import Path

PROFILE = Path("App/KeyboardExtension/Resources/default-ja.json")
data = json.loads(PROFILE.read_text(encoding="utf-8"))
tables = {table["id"]: table for table in data["transformTables"]}

required = {"kana.small", "kana.dakuten", "kana.handakuten", "latin.shift", "kana.utilityCycle"}
missing = required - tables.keys()
if missing:
    raise SystemExit(f"missing transform tables: {sorted(missing)}")

def effective(table):
    result = {}
    for entry in table.get("entries", []):
        source, target = entry["from"], entry["to"]
        if source in result and result[source] != target:
            raise SystemExit(f"{table['id']}: conflicting source {source}")
        result[source] = target
    for entry in table.get("entries", []):
        if table.get("reverseAll", False) or entry.get("reverse", False):
            source, target = entry["to"], entry["from"]
            if source in result and result[source] != target:
                raise SystemExit(f"{table['id']}: reverse conflict {source}")
            result[source] = target
    return result

for table_id in required:
    table = tables[table_id]
    if not table.get("title"):
        raise SystemExit(f"{table_id}: title required")
    if not table.get("authoringGroups"):
        raise SystemExit(f"{table_id}: authoringGroups required")
    declared = {tuple(path) for path in table["authoringGroups"]}
    for entry in table.get("entries", []):
        path = tuple(entry.get("groupPath", []))
        if not path:
            raise SystemExit(f"{table_id}: row {entry['from']} has no groupPath")
        for depth in range(1, len(path) + 1):
            if path[:depth] not in declared:
                raise SystemExit(f"{table_id}: undeclared group path {path[:depth]}")
        if entry.get("reverse", False):
            if any(
                other is not entry
                and other.get("from") == entry.get("to")
                and other.get("to") == entry.get("from")
                for other in table.get("entries", [])
            ):
                raise SystemExit(
                    f"{table_id}: redundant explicit inverse remains for "
                    f"{entry['from']}↔{entry['to']}"
                )

utility = tables["kana.utilityCycle"]
if utility.get("reverseAll") or any(e.get("reverse") for e in utility["entries"]):
    raise SystemExit("kana.utilityCycle must remain explicit and reverse-off")

expected = {
    "kana.small": {"あ": "ぁ", "ぁ": "あ", "つ": "っ", "っ": "つ", "か": "ゕ", "ゕ": "か"},
    "kana.dakuten": {"か": "が", "が": "か", "は": "ば", "ば": "は", "ぱ": "ば", "う": "ゔ", "ゔ": "う"},
    "kana.handakuten": {"は": "ぱ", "ぱ": "は", "ば": "ぱ", "ほ": "ぽ", "ぽ": "ほ"},
    "latin.shift": {"abc": "ABC", "a": "A", "w": "W"},
    "kana.utilityCycle": {"あ": "ぁ", "ぁ": "あ", "う": "ぅ", "ぅ": "ゔ", "ゔ": "う", "は": "ば", "ば": "ぱ", "ぱ": "は"},
}
for table_id, mappings in expected.items():
    actual = effective(tables[table_id])
    for source, target in mappings.items():
        if actual.get(source) != target:
            raise SystemExit(f"{table_id}: expected {source}→{target}, got {actual.get(source)!r}")

expected_authored_counts = {
    "kana.small": 12,
    "kana.dakuten": 26,
    "kana.handakuten": 10,
    "latin.shift": 34,
    "kana.utilityCycle": 65,
}
for table_id, count in expected_authored_counts.items():
    actual = len(tables[table_id].get("entries", []))
    if actual != count:
        raise SystemExit(f"{table_id}: authored row count {actual}, expected {count}")

print("Built-in TransformTable authoring contract OK")
