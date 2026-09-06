# Film stock catalog

Source of truth for the library picker: `film-stocks.json` in this folder. The widget bundle has a copy of the same file — keep them in sync.

## What each row is for

Keep fields that help someone **pick a stock and shoot it correctly**. Lore is fine when it prevents a mistake (remjet, discontinued process, dual box names). Do not treat price as truth.

| Field | Required | Notes |
|---|---|---|
| `id` | yes | Stable UUID — never regenerate. Existing rolls point at this. |
| `name` | yes | Primary picker label. Use the name people search for (`Kodak Portra 400`, not the 2026 rebrand). |
| `aliases` | yes | Other box names and short codes. Search matches `name` **or** any alias. |
| `manufacturer` | yes | Brand filter key (`Kodak`, `Fujifilm`, `CineStill`, …). |
| `iso` | yes | Box speed. |
| `process` | yes | `C-41` / `E-6` / `B&W` / `ECN-2` / `K-14`. |
| `filmType` | yes | Prefer this over `category`. |
| `formatsAvailable` | yes | What the user can actually load. |
| `productionStatus` | yes | `In production` / `Discontinued`. |
| `isDiscontinued` | yes | Keep in sync with `productionStatus`. |
| `brandLine` | recommended | Professional / consumer / aerial, etc. |
| `usableRange` | recommended | Practical EI, not marketing. |
| `pushPullTolerance` | recommended | |
| `description` | recommended | Human library blurb at the top of stock detail. Omit or leave empty to hide the block. |
| `notes` | recommended | Process caveats, remjet, dual distribution, “keep for archive”. |
| `bestFor` | recommended | |
| `grainCharacter` | recommended | |
| `grainRMS` | optional | Often null. |
| `yearsActive` | optional | Lore; include rebrand years when it avoids confusion. |
| `priceTier` | optional | Do not treat as truth. |
| `category` | optional | Redundant with `filmType`; still decoded for older rows. |

## Naming rules

| Situation | Catalog |
|---|---|
| Rebrand / dual packaging, **same emulsion** (Portra ↔ Ektacolor Pro, T-Max ↔ Ektapan) | **One row** + `aliases` |
| Related but sold as distinct SKUs (Kodacolor 200 vs ColorPlus 200) | **Separate rows** (optional “related to” in notes) |
| Truly different discontinued emulsions (Portra 400NC / 400VC, Elite Chrome) | **Separate rows**, marked discontinued |

- Primary `name` stays the searchable classic (`Kodak Portra 400`, `Kodak T-Max 400`).
- The app subtitle is **Also sold as Ektacolor Pro 400** / **Also sold as Ektapan 400**. Short codes stay in `aliases` for search only.
- **Kodacolor 100/200** vs **Pro Image / ColorPlus**: keep as **separate SKUs** even if related.
- **Vision3** / **Double-X**: remjet / ECN-2 caveats belong in `notes`.
- **CineStill:** color trio is 50D / 400D / 800T. 400D includes 4×5. **BwXX** is their Double-X B&W — do not omit it. Skip RedRum for v1. 800T is rated 800 for C-41 (Vision3 500T-derived).
- **Fujifilm:** Superia X-TRA 400 is discontinued (~2024). Velvia 50 sheet is largely gone (35mm/120 only). Provia sheet supply is unreliable. Superia Premium 400 is Japan-made and scarce.
- Alaris Portra / T-Max boxes can still show up while inventory clears — that is why aliases exist, not duplicate entries.

## How to update a maker

1. Merge by `id`. Do not regenerate UUIDs.
2. Leave other makers untouched unless you are validating them.
3. Do not ship a `validation` key — that is review metadata only.
4. After editing, copy the file to `Film Photography Widget/Resources/film-stocks.json`.
