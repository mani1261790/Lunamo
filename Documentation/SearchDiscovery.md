# Search discovery

Canonical landing page: https://mani1261790.github.io/Lunamo/

## Implemented
- Static title, description, canonical URL and visible page copy.
- SoftwareApplication JSON-LD with verified app facts; no invented reviews or ratings.
- Sitemap: https://mani1261790.github.io/Lunamo/sitemap.xml
- Landing-page link in the repository README and repository homepage.
- A single URL with the existing in-page language switch remains intentional.

## Verified by the user (2026-11-19)
The user completed Google Search Console ownership verification and requested indexing. Their URL Inspection screenshot shows the canonical landing page is indexed. The deployed verification tag must be preserved.

Sitemap submission still reports a fetch failure in Search Console. Public HTTP 200 and valid XML do not establish that Google has fetched it successfully. Do not repeatedly request indexing or treat the missing sitemap as a blocker to an already indexed page.

## Additional discovery work (2026-11-19)
- Added guide.html with installation, supported notebook imports, execution, packages and updates, based on public release documentation.
- Linked the guide from the LP and README and included its canonical URL in the sitemap.
- Kept Japanese and English on the same URL, with the existing language preference. Static Japanese content is available without JavaScript; English indexing is not guaranteed by client-side switching.
- Next measurement: Search Console performance queries, impressions and clicks after data becomes available. Guide indexing remains unverified until Google crawls it.

Bing Webmaster Tools may import the verified Search Console property after account access is available.

A robots.txt inside /Lunamo/ is not the host's robots.txt. The authoritative location is https://mani1261790.github.io/robots.txt; do not modify unrelated hosting repositories without checking their ownership and rules. Its observed 404 does not disallow crawling.

The structured data describes the app; it does not qualify this page for Google's software-app rich result without a real review/rating. A sitemap or indexing request does not guarantee search inclusion or ranking.

References:
- https://support.google.com/webmasters/answer/9008080
- https://developers.google.com/search/docs/crawling-indexing/ask-google-to-recrawl
- https://developers.google.com/search/docs/appearance/structured-data/software-app
