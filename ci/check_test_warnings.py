"""Bramka CI: test na severity warn ma zatrzymać PR, choć na prod tylko ostrzega.

dbt_project.yml ustawia +severity: warn dla większości testów, więc `dbt build` kończy się kodem 0
nawet przy oblanym teście. W PR to za mało: zmiana, która psuje regułę biznesową, przeszłaby na
zielono. Skrypt czyta target/run_results.json i zwraca kod 1, gdy którykolwiek węzeł ma status warn.
"""

import json
import sys


def main(path: str) -> int:
    with open(path, encoding="utf-8") as f:
        results = json.load(f)["results"]

    warned = [r for r in results if r["status"] == "warn"]
    for r in warned:
        # Format ::error:: GitHub Actions pokazuje jako adnotację w zakładce PR "Checks".
        print(f"::error::{r['unique_id']}: {r.get('message') or 'warn'}")

    print(f"Węzłów: {len(results)}, na warn: {len(warned)}")
    return 1 if warned else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1] if len(sys.argv) > 1 else "target/run_results.json"))
