# Search discovery

Canonical landing page: https://mani1261790.github.io/Lunamo/

## Implemented
- Static title, description, canonical URL and visible page copy.
- SoftwareApplication JSON-LD with verified app facts; no invented reviews or ratings.
- Sitemap: https://mani1261790.github.io/Lunamo/sitemap.xml
- Landing-page link in the repository README and repository homepage.
- A single URL with the existing in-page language switch remains intentional.

## Pending account verification
2026-11-19: this chat could not connect to the signed-in local browser. No Search Console or Bing registration, ownership verification, or indexing request has been completed by this task.

Google Search Console: add a URL-prefix property for the exact URL above, select HTML tag verification, and install the account-issued google-site-verification tag in site/index.html. Keep the tag deployed after verification. After verifying, submit sitemap.xml and inspect the canonical landing URL, then request indexing. Record the actual result, not just the request.

Bing Webmaster Tools may import the verified Search Console property after account access is available.

A robots.txt inside /Lunamo/ is not the host's robots.txt. The authoritative location is https://mani1261790.github.io/robots.txt; do not modify unrelated hosting repositories without checking their ownership and rules. Its observed 404 does not disallow crawling.

The structured data describes the app; it does not qualify this page for Google's software-app rich result without a real review/rating. A sitemap or indexing request does not guarantee search inclusion or ranking.

References:
- https://support.google.com/webmasters/answer/9008080
- https://developers.google.com/search/docs/crawling-indexing/ask-google-to-recrawl
- https://developers.google.com/search/docs/appearance/structured-data/software-app
