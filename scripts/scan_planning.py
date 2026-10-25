
import json
import re
import urllib.request
from datetime import datetime, timezone
from pathlib import Path

API_URL = "https://planningdata.london.gov.uk/api-guest/applications/_search"

KEYWORDS = re.compile(
    r"extension|loft|conversion|renovation|refurbishment|"
    r"alteration|kitchen|bathroom|dwelling|residential|"
    r"roof|demolition|garage|basement|outbuilding|"
    r"erection|window|door|rear extension|side extension|"
    r"painting|flooring|plumbing|heating|landscaping|"
    r"carpentry|re-roofing",
    re.IGNORECASE,
)

# Request potentially available professional/public contact fields.
# Fields absent from the source will not magically be populated.
SOURCE_FIELDS = [
    "id",
    "lpa_name",
    "lpa_app_no",
    "last_updated",
    "description",
    "address",
    "site_address",
    "postcode",
    "status",
    "url",
    "application_type",
    "agent_name",
    "agent_company",
    "agent_email",
    "agent_phone",
    "contact_name",
    "contact_email",
    "contact_phone",
    "company_name",
    "organisation",
]

def main():
    payload = {
        "size": 100,
        "query": {"match_all": {}},
        "sort": [
            {
                "last_updated": {
                    "order": "desc",
                    "unmapped_type": "date",
                }
            }
        ],
        "_source": SOURCE_FIELDS,
    }

    request = urllib.request.Request(
        API_URL,
        data=json.dumps(payload).encode("utf-8"),
        headers={
            "Content-Type": "application/json",
            "X-API-AllowRequest": "be2rmRnt&",
            "User-Agent": "BuildLeadAI/1.1",
        },
        method="POST",
    )

    try:
        with urllib.request.urlopen(request, timeout=40) as response:
            data = json.load(response)
    except Exception as error:
        raise SystemExit(
            "Planning data request failed. Check API access: "
            + str(error)
        )

    hits = data.get("hits", {}).get("hits", [])
    matches = []

    for hit in hits:
        item = hit.get("_source", {})

        searchable_text = " ".join(
            str(item.get(key) or "")
            for key in (
                "description",
                "address",
                "site_address",
                "postcode",
                "application_type",
            )
        )

        if not KEYWORDS.search(searchable_text):
            continue

        item["id"] = item.get("id") or hit.get("_id")
        item["verification_required"] = True

        # Keep only explicitly supplied, non-empty professional
        # contact fields. Never infer or generate contact details.
        public_contact = {}

        for key in (
            "agent_name",
            "agent_company",
            "agent_email",
            "agent_phone",
            "contact_name",
            "contact_email",
            "contact_phone",
            "company_name",
            "organisation",
        ):
            value = item.get(key)
            if isinstance(value, str) and value.strip():
                public_contact[key] = value.strip()

        item["public_contact"] = public_contact
        item["contact_available"] = bool(public_contact)

        matches.append(item)

    Path("leads").mkdir(exist_ok=True)

    result = {
        "checked_at_utc": datetime.now(timezone.utc).isoformat(),
        "source": "Planning London Datahub",
        "records_checked": len(hits),
        "potential_signals": len(matches),
        "contacts_found": sum(
            1 for item in matches if item["contact_available"]
        ),
        "note": (
            "Planning signals are not confirmed jobs. "
            "Verify each application and any published business "
            "contact details before contacting anyone. "
            "Contact details are included only when supplied by "
            "the data source."
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
            f"checked={len(hits)}, "
            f"matches={len(matches)}, "
            f"contacts={result['contacts_found']}\n"
        )

    print(
        f"Checked {len(hits)} records; "
        f"found {len(matches)} potential leads; "
        f"contacts available in source: {result['contacts_found']}."
    )

if __name__ == "__main__":
    main()
