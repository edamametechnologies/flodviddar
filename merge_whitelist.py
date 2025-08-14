import json, sys, shutil
from pathlib import Path


def normalize_endpoint(endpoint):
    return {k: v for k, v in endpoint.items() if k != "description"}


def merge_whitelist_in_place(file1, file2, make_backup=True):
    f1 = Path(file1)
    f2 = Path(file2)

    # Optional backup
    if make_backup:
        shutil.copy2(f1, f1.with_suffix(f1.suffix + ".bak"))

    with open(f1) as a, open(f2) as b:
        data1 = json.load(a)
        data2 = json.load(b)

    endpoints1 = data1["whitelists"][0]["endpoints"]
    endpoints2 = data2["whitelists"][0]["endpoints"]

    seen = {json.dumps(normalize_endpoint(ep), sort_keys=True) for ep in endpoints1}

    added = 0
    for ep in endpoints2:
        key = json.dumps(normalize_endpoint(ep), sort_keys=True)
        if key not in seen:
            endpoints1.append(ep)
            seen.add(key)
            added += 1

    with open(f1, "w") as out:
        json.dump(data1, out, indent=4)

    print(f"Added {added} new endpoints to {file1}")


if __name__ == "__main__":
    if len(sys.argv) < 3:
        print(f"Usage: {sys.argv[0]} file1.json file2.json [--no-backup]")
        sys.exit(1)
    merge_whitelist_in_place(
        sys.argv[1], sys.argv[2], make_backup="--no-backup" not in sys.argv
    )
