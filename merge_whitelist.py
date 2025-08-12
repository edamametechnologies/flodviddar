import json
import sys


def normalize_endpoint(endpoint):
    """Return a normalized dict without 'description' for comparison."""
    return {k: v for k, v in endpoint.items() if k != "description"}


def merge_whitelists(file1, file2, output_file):
    # Load both JSON files
    with open(file1) as f1, open(file2) as f2:
        data1 = json.load(f1)
        data2 = json.load(f2)

    # Extract endpoint lists
    endpoints1 = data1["whitelists"][0]["endpoints"]
    endpoints2 = data2["whitelists"][0]["endpoints"]

    # Track unique endpoints (ignoring description)
    seen = {json.dumps(normalize_endpoint(ep), sort_keys=True) for ep in endpoints1}

    # Merge
    for ep in endpoints2:
        norm_ep_str = json.dumps(normalize_endpoint(ep), sort_keys=True)
        if norm_ep_str not in seen:
            endpoints1.append(ep)
            seen.add(norm_ep_str)

    # Save result
    with open(output_file, "w") as out:
        json.dump(data1, out, indent=4)

    print(f"Merged whitelist saved to {output_file}")


if __name__ == "__main__":
    if len(sys.argv) != 4:
        print(f"Usage: {sys.argv[0]} file1.json file2.json output.json")
        sys.exit(1)

    merge_whitelists(sys.argv[1], sys.argv[2], sys.argv[3])
