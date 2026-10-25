
import json
import re
import urllib.request
import urllib.error
from datetime import datetime, timezone
from pathlib import Path

API_URL = "https://planningdata.london.gov.uk/api-guest/applications/_search"

KEYWORDS = re.compile(
    r"extension|loft|conversion|renovation|refurbishment|"
    r"alteration|kitchen|bathroom|dwelling|residential|"
    r"roof|demolition|garage|basement|outbuilding|"
    r"erection|window|door|rear extension|side extension",
    re.IGNORECASE,
)

def main():
    payload = {
        "size": 100,
        "query": {"match_all": {}},
        "sort": [{"last_updated": {"order": "desc", "unmapped_type": "date"}}],
        "_source": [
            "id", "lpa_name", "lpa_app_no", "last_updated",
            "description", "address", "site_address", "postcode",
            "status", "url", "application_type"
        ],
    }

    request = urllib.request.Request(
        API_URL,
        data=json.dumps(payload).encode("utf-8"),
        headers={
            "Content-Type": "application/json",
            "X-API-AllowRequest": "be2rmRnt&",
            "User-Agent": "BuildLeadAI/1.0",
        },
        method="POST",
    )

    try:
        with urllib.request.urlopen(request, timeout=40) as response:
            data = json.load(response)
    except Exception as error:
        raise SystemExit(
            "Planning data request failed. Check the public API settings: "
            + str(error)
        )

    hits = data.get("hits", {}).get("hits", [])
    matches = []

    for hit in hits:
        item = hit.get("_source", {})
        text = " ".join(
            str(item.get(key) or "")
            for key in (
                "description", "address", "site_address",
                "postcode", "application_type"
            )
        )

        if KEYWORDS.search(text):
            item["id"] = item.get("id") or hit.get("_id")
            item["verification_required"] = True
            matches.append(item)

    Path("leads").mkdir(exist_ok=True)

    result = {
        "checked_at_utc": datetime.now(timezone.utc).isoformat(),
        "source": "Planning London Datahub",
        "records_checked": len(hits),
        "potential_signals": len(matches),
        "note": (
            "These are planning signals, not confirmed jobs. "
            "Verify details with the relevant council before acting."
        ),
        "leads": matches,
    }

    Path("leads/latest-leads.json").write_text(
        json.dumps(result, ensure_ascii=False, indent=2),
        encoding="utf-8",
    )

    with open("leads/scan-log.txt", "a", encoding="utf-8") as log:
        log.write(
            f"{result['checked_at_utc']}: "
            f"checked={len(hits)}, matches={len(matches)}\n"
        )

    print(
        f"Checked {len(hits)} records; "
        f"found {len(matches)} possible project signals."
    )

if __name__ == "__main__":
    main()
