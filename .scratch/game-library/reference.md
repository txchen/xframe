# Game library reference research

Inspected on 2026-09-21. XStreaming source is pinned to commit
`383e19d324f2d3029d1c304752f4d38a9360bb95`. This note describes implementation
patterns, not a promise that every catalog field or entitlement is stable.

## Library behavior

- XStreaming uses a responsive poster grid, three columns on a narrow screen and
  four to eight on a larger screen. Cards have a portrait aspect ratio of about
  1:1.38. Its page size is 24 or 36 titles. Pagination is **client-side incremental
  disclosure** (`slice(0, currentPage * pageSize)`), not a paginated cloud API.
  Native XFrame can use a bounded page of cards with explicit previous/next
  controls for predictable keyboard use and rendering cost.
  [Grid sizing](https://github.com/Geocld/XStreaming/blob/383e19d324f2d3029d1c304752f4d38a9360bb95/src/pages/Cloud.tsx#L1023-L1037),
  [pagination](https://github.com/Geocld/XStreaming/blob/383e19d324f2d3029d1c304752f4d38a9360bb95/src/pages/Cloud.tsx#L1577-L1591).
- Search matches `ProductTitle` case-insensitively. A-Z and Z-A sort use localized
  string comparison. Category changes and sort selection reset the page. Native
  XFrame should also reset or clamp the page after any query/catalog change and
  use a stable identifier as a tie-breaker for duplicate display names.
  [Filtering and sorting](https://github.com/Geocld/XStreaming/blob/383e19d324f2d3029d1c304752f4d38a9360bb95/src/pages/Cloud.tsx#L1528-L1575),
  [page resets](https://github.com/Geocld/XStreaming/blob/383e19d324f2d3029d1c304752f4d38a9360bb95/src/pages/Cloud.tsx#L3261-L3284).
- Poster loading prefers `Image_Poster.URL`, then uses tile/box art fallbacks.
  Scheme-relative URLs are normalized to HTTPS. Image failure is distinct from
  catalog failure. Native equivalents are asynchronous image loading, a local
  placeholder, validated HTTPS image URLs, and an accessible title independent
  of image success.
  [Image resolver and failure state](https://github.com/Geocld/XStreaming/blob/383e19d324f2d3029d1c304752f4d38a9360bb95/src/components/XStreamingGameCard.tsx#L26-L138).

## Metadata shape

XStreaming hydrates product IDs with a public POST to
`https://catalog.gamepass.com/v3/products?market=US&language=en-US&hydration=RemoteLowJade0`
and body `{ "Products": ["PRODUCT_ID"] }`. The response is a `Products` object
keyed by product ID. It combines this metadata with authenticated cloud titles.
[Catalog request and merge](https://github.com/Geocld/XStreaming/blob/383e19d324f2d3029d1c304752f4d38a9360bb95/src/xCloud/index.ts#L979-L1034).

A read-only, unauthenticated request to that Microsoft endpoint for Fortnite
(`BT5P2X999VH2`) verified this subset on 2026-09-21:

```json
{
  "Products": {
    "BT5P2X999VH2": {
      "ProductTitle": "Fortnite",
      "Image_Poster": { "URL": "//store-images.s-microsoft.com/image/..." },
      "Image_Tile": { "URL": "//store-images.s-microsoft.com/image/..." },
      "Categories": ["Action & adventure", "Other", "Shooter", "Simulation", "Strategy"],
      "LocalizedCategories": ["Action & adventure", "Other", "Shooter", "Simulation", "Strategy"],
      "PublisherName": "Epic Games Inc."
    }
  }
}
```

Image paths above are abbreviated; they are not fixtures. Other observed fields
were `StoreId`, `XCloudTitleId`, `XboxTitleId`, `ChildXboxTitleIds`, `Streamability`,
and `XCloudOfferings`. Optional decoding is appropriate: one live product does
not establish mandatory fields across the catalog. Categories provide a real
metadata-backed genre filter without inventing entitlement labels. Keep streaming
bearer tokens out of public metadata and image requests.

## Patterns not to copy literally

- XStreaming's `newest` sort reverses the source list rather than comparing a
  release date. XFrame should not label a reverse-alphabetic result "Newest".
  [Sort implementation](https://github.com/Geocld/XStreaming/blob/383e19d324f2d3029d1c304752f4d38a9360bb95/src/pages/Cloud.tsx#L1552-L1562).
- Its category collections use Microsoft SIGL feeds and intersect product IDs
  with cloud title data. Its Game Pass/Ubisoft validators also use title-keyword
  heuristics. Do not infer ownership, subscription access, or availability from
  title text, public catalog membership, or publisher alone.
  [SIGL IDs, validators, intersection](https://github.com/Geocld/XStreaming/blob/383e19d324f2d3029d1c304752f4d38a9360bb95/src/utils/xcloud.ts#L10-L164).
- It supplements authenticated titles using a repository-maintained public
  product list, then deduplicates by display name. XFrame can preserve its current
  authenticated-title boundary and stable title-ID identity; same-named editions
  are not necessarily duplicates.
  [Supplementary list and name deduplication](https://github.com/Geocld/XStreaming/blob/383e19d324f2d3029d1c304752f4d38a9360bb95/src/xCloud/index.ts#L917-L971).

## Recommended initial native slice

Use the existing authenticated title set, hydrate optional poster/tile/category/
publisher metadata, show a responsive grid with title placeholders, implement
case- and diacritic-insensitive search, genre filter, A-Z/Z-A sorting, exact result
counts, bounded paging, and clear loading/empty/error states. Keep preview launch
explicit and preserve existing session cleanup. Favorites or recents can follow
as local-only collections; ownership and subscription collections need separate
service-backed semantics.
