# FCC Filing Ingestion — Phase 1 Vertical Slice (Plan)

**Project:** DAI / P01 — FCC Source-Expert Agent
**Status:** Plan greenlit; Phase 1 implementation gated on Drive→repo sync.
**Branch:** `claude/fcc-ingestion-pipeline-plan-2cQIp`

> This document supersedes the original systematic-pipeline plan that was
> the first commit on this branch. The architecture review, schema, risk
> register, and cost-estimation methodology from that draft survive — they
> are folded into the sections below, refined against Abe's locked
> decisions. Phase 1 has converged to a 5-filing vertical slice on Apple ×
> 2022–2023 × handset.

---

## Context

The original brief asked for a full systematic FCC ingestion pipeline. After
Q&A, the plan converged on:

- **Phase 1 = 5-filing vertical slice** on Apple × 2022–2023 × handset.
  Anchor on **BCG-E8725A** (parent) or **BCG-E8727A** (variant), plus 4
  more filings selected from the synced corpus to include at least one
  parent+variant pair.
- **Production scope (Phase 4 target):** top 10 manufacturers by UE filing
  volume × all user equipment × 2020–2026. Working manufacturer list:
  Apple, Samsung, Google, Huawei, Xiaomi, OPPO, Motorola/Lenovo, Sony,
  OnePlus, Nothing (adjust based on actual corpus volume). All UE classes:
  handsets, tablets, wearables, XR/AR, hotspots/MiFi, IoT-class UE.
  **Working assumption: 20K filings** in scope (Abe to refine after corpus
  measurement; expected range 15–25K).
- **Retention:** Option A — keep raw PDFs in the corpus store; manual
  deletion later as needed. `pattern_refs` resolve as
  `(file_hash, page, bbox)` against retained PDFs. Canonical artifact
  exporter deferred to Phase 3+ if storage becomes a constraint.
- **Similarity model:** spec similarity for v1, with five explicit
  dimensions: `frequency_overlap`, `peak_gain_proximity`,
  `antenna_type_match`, `form_factor_match`, `polarization_match`.
  Behavioral (pattern-shape) similarity is a v2 stretch goal.
- **Confidentiality posture:** conservative-skip-on-uncertainty.
- **Entity registry:** read-only consumer of the patent pipeline's
  canonical version. FCC pipeline does not fork.
- **Repo layout:** existing DAI components (Structure Profiler v0.5, patent
  three-tier dispatcher, entity registry, concept vocabulary, PROTOCOL.md,
  `dai-patent-agents.skill`) live in Abe's Google Drive. They will be
  synced to local FS via Drive-for-Desktop and **vendored** into this repo
  under `vendor/dai_shared/` (read-only, Python-import-friendly underscore
  form). This repo is the home of the FCC pipeline; vendoring is the
  bridge until a proper monorepo or package layout lands.

**Gating step (Abe owns):** Drive→repo sync of (a) shared components into
`vendor/dai_shared/`, and (b) Apple 2022–2023 handset filings into a
locally-readable Drive-for-Desktop path. Phase 1 implementation cannot
start until both syncs land.

---

## 1. Vendor structure

```
vendor/dai_shared/                     # read-only, mirrors Drive contents
  __init__.py
  PROTOCOL.md
  structure_profiler/
    __init__.py
    structure_profiler.py              # v0.5, PyMuPDF-based
  three_tier/
    __init__.py
    dispatcher.py                      # Haiku/Opus/Opus-deep router from patent pipeline
    prompts/                           # any shared prompt scaffolding
  entity_registry/
    __init__.py
    registry.py                        # read-only client
    data/                              # registry data files if shipped inline
  concepts/
    __init__.py
    vocabulary.py                      # antenna types, modulation, form factor enums
  skills/
    dai-patent-agents.skill            # reference, not imported as code
  README.md                            # Drive→vendor path map + sync date + commit
```

Imports (FCC pipeline side):

```python
from vendor.dai_shared.structure_profiler import StructureProfiler
from vendor.dai_shared.three_tier.dispatcher import TierDispatcher
from vendor.dai_shared.entity_registry.registry import EntityRegistry
from vendor.dai_shared.concepts.vocabulary import AntennaType, FormFactor
```

`vendor/dai_shared/README.md` records, per file, the source Drive path +
sync date + source commit hash (if Drive component is git-tracked).
Re-syncs overwrite cleanly because vendor is read-only on the FCC side.

---

## 2. Phase 1 deliverable (5-filing slice)

Five filings, end-to-end, producing five KB records and a manual eval note.

### 2.1 Filing selection

I pick all 5 FCC IDs after Drive→vendor sync lands and the corpus is
locally browsable. Selection criteria:

- Apple × 2022–2023 × handset.
- Anchor on **BCG-E8725A** (parent) or **BCG-E8727A** (variant) if either
  is in the corpus.
- Include at least **one parent+variant pair** so the de-dup logic in §2.5
  is exercised end-to-end.
- Prefer filings with **full exhibit sets** (cover letter + Form 731 +
  test report + antenna exhibit + photos + schematics + RF exposure).
- Avoid permissive-change refilings (delta-only exhibits) and modular
  grants (minimal exhibits).

I'll publish the chosen 5 FCC IDs in `docs/phase1-eval.md` before the
extraction run so Abe can veto/redirect before any API calls.

### 2.2 Pipeline steps

1. **Load** PDFs from Drive-mounted FS (one directory per FCC ID).
2. **Profile** structure with vendored Structure Profiler v0.5 — section /
   exhibit hierarchy, filename list, page counts.
3. **De-dup** (see §2.5). For each filing, identify parent FCC ID and
   variant relationships before extraction.
4. **Classify** each PDF in each filing with a hardcoded filename-pattern
   lookup → one of `{form_731, test_report, antenna_exhibit, photos,
   schematics, cover_letter, other}`. No learned model in Phase 1.
5. **Extract** with three Tier-1 (Haiku) prompts via vendored
   `TierDispatcher`:
   - **Form 731** → `fcc_id`, `grantee_code`, `grantee`,
     `application_date`, `grant_date`, `equipment_class_codes`,
     `device_class`, declared `frequency_bands_mhz`, `form_version`,
     `tcb_id` if present.
   - **Test report** → `tx_power_dbm` (per band), `modulation_types`.
   - **Antenna exhibit** → `antenna_types`, `peak_gain_dbi_by_band`,
     `polarization`, `pattern_refs` as `{file_hash, page, bbox}`.
6. **Write** five JSON records (production-shape schema, partial-fill OK)
   plus a `provenance` block (drive path, file hash per source PDF,
   retrieval date, pipeline_version, vendor sync commit).
7. **Eval** by hand: open each filing on FCC EAS, score every populated
   field true / false / partial, write `docs/phase1-eval.md`. Target
   ≥ 80 % field accuracy on populated fields.

### 2.3 Out of scope for Phase 1

OCR, confidentiality classifier (manual cover-letter inspection only),
learned categorization, Tier 2/3 escalation, canonical artifact exporter,
similarity query interface, checkpoint/resume (5 filings — one-shot is
fine), agent shim.

### 2.4 Schema fill-rate target

**Will populate:** `fcc_id`, `grantee_code`, `grantee`, `form_version`,
`application_date`, `device_class`, `equipment_class_codes`,
`frequency_bands_mhz`, `tx_power_dbm`, `antenna_types`,
`peak_gain_dbi_by_band`, `polarization`, `pattern_refs`, `form_factor`,
`provenance`, `extraction_confidence` (per field),
`confidentiality_status` (per field — default `public` unless cover letter
says otherwise), `tcb_id` (if present in metadata).

**Will leave null:** `grant_date` (populate if obvious),
`modulation_types`, `antenna_count`, `efficiency_pct_by_band`,
`multiband_summary`, `host_context`, `cross_refs`, `ocr_quality_score`.

### 2.5 De-dup against TCB resubmissions / variants

The Apple parent+variant pattern is pervasive (e.g., **BCG-E8725A** parent
→ **BCG-E8726A / E8727A / E8728A** variants sharing one test report).
Without de-dup, the 20K-filing target likely contains 5–10K *distinct
devices* and 10–15K variants.

**Approach for the slice:**

- Read Form 731 from each filing; extract `parent_fcc_id` if declared.
- Group filings by parent.
- Tag each KB record with `parent_fcc_id` and `variant_fcc_ids[]`.
- For variants that share a test report with a parent, link
  `pattern_refs` to the parent's exhibit by FCC ID, not duplicate the
  underlying file hash.

Implement in Phase 1 against the 5-filing sample so the data shape is
right end-to-end.

---

## 3. Critical files

To be created in this repo (Phase 1 implementation, blocked on Drive sync):

```
fcc/
  __init__.py
  loader.py            # Drive-mounted FS loader; FCC ID → directory of PDFs
  profiler.py          # thin wrapper around vendored StructureProfiler v0.5
  classify.py          # hardcoded filename-pattern lookup
  dedup.py             # parent/variant detection + grouping
  extract/
    __init__.py
    form_731.py        # Tier-1 prompt + parser
    test_report.py     # Tier-1 prompt + parser
    antenna_exhibit.py # Tier-1 prompt + parser
  schema.py            # pydantic record model
  run_slice.py         # CLI: takes FCC ID(s), runs steps 1–6, writes records

out/
  <FCC_ID>.json        # one record per filing

docs/
  phase1-eval.md       # manual eval note (selected FCC IDs + filled-in results)

vendor/
  dai_shared/          # synced from Drive, read-only (Abe owns sync)
```

To be updated:

- `README.md` — project description + pointer to `fcc/run_slice.py`.

---

## 4. Schema (production target; slice fills a subset)

Same schema as the original systematic plan. The slice populates the
subset listed in §2.4; the rest stay null.

| Field | Type | Notes |
|---|---|---|
| `fcc_id` | string | Primary key. |
| `grantee_code` | string | First 3–5 chars of FCC ID. |
| `grantee` | entity_ref | Resolved against entity registry. |
| `form_version` | string | Form 731 revision used. |
| `tcb_id` | string | Certifying body. |
| `application_date` | date | |
| `grant_date` | date | Distinct from application date. |
| `device_class` | enum | DAI taxonomy (handset, tablet, wearable, …). |
| `equipment_class_codes` | list[string] | FCC's own taxonomy (DTS, PCB, NII, …). |
| `frequency_bands_mhz` | list[range_with_label] | Each tagged with band label and tx/rx. |
| `tx_power_dbm` | dict[band → float] | Indexed by band, not flat. |
| `modulation_types` | list[enum] | |
| `antenna_count` | int? | Optional — often ambiguous. |
| `antenna_types` | list[enum] | PIFA, monopole, patch, slot, array, … |
| `peak_gain_dbi_by_band` | dict[band → float] | Band-conditional. |
| `efficiency_pct_by_band` | dict[band → float] | Key for similarity. |
| `polarization` | enum or list | Important for similarity. |
| `multiband_summary` | list[antenna_element] | Bands grouped by element. |
| `pattern_refs` | list[ref] | `{type, file_hash, page, bbox, artifact_id?}`. |
| `form_factor` | enum | |
| `host_context` | object? | Chassis material, screen size, where extractable. |
| `cross_refs` | list[ref] | Predecessor models, modular grants. Includes `parent_fcc_id` and `variant_fcc_ids[]`. |
| `confidentiality_status` | dict[field → enum] | Per-field. {public, withheld, redacted, unknown}. |
| `extraction_confidence` | dict[field → float] | Calibrated from extractor. |
| `ocr_quality_score` | float | Document-level; null when no OCR. |
| `provenance` | object | source URL, retrieval date, file hash, form_version, pipeline_version, vendor sync commit. |

---

## 5. Risk register (Phase 1-scoped)

### R1 — Confidentiality slip
Even at 5 filings, an extractor could pull from a withheld section.
**Mitigation:** before running extractors, manually open the cover letter
of each filing and note any confidentiality assertions; configure the
classifier to skip those exhibits. Per-field `confidentiality_status`
populated on every record.

### R2 — Variant grouping wrong
If the de-dup logic mis-groups a parent and a variant, downstream
similarity queries return phantom duplicates. **Mitigation:** the
5-filing slice should explicitly include at least one parent+variant pair
(BCG-E8725A + a sibling) so the de-dup logic is exercised. Manual
verification in eval.

### R3 — Hardcoded classifier misses a doc
Apple filename conventions are stable across this 2022–2023 cohort, but
not guaranteed. **Mitigation:** manual review of the document list per
filing; any unclassified PDF gets a manual class assignment in Phase 1.

### R4 — Vendor sync drift
Drive-side components evolve; vendored copy goes stale. **Mitigation:**
`vendor/dai_shared/README.md` records sync date + commit; treat re-syncs
as discrete events with a commit message that names the sync source.

Risks **deferred** (re-engage at corpus scope): cost overrun, OCR quality
on pre-2020 filings, similarity-query ranking, classifier brittleness at
scale, entity-registry conflicts.

---

## 6. Cost estimate (refreshed against 20K-filing scope)

Assumptions:

- 20K filings in scope (working number; refine after corpus measurement).
- ~15 documents per filing on average.
- Three-tier dispatch: ~80 % stay at Tier 1 (Haiku 4.5), ~15 % escalate
  to Tier 2 (Opus 4.7), ~2 % to Tier 3 (Opus 4.7 deep).
- After de-dup, ~10–14K *distinct* extraction targets; variants are
  pointer-only and don't repeat extraction. Estimate uses 20K to be
  conservative.

**Token-per-document working numbers** (input + output, conservative):

- Tier 1: ~3K input + 0.5K output per doc.
- Tier 2: ~8K input + 2K output per doc.
- Tier 3: ~15K input + 5K output per doc.

**Per-tier spend** (using published Haiku 4.5 / Opus 4.7 list pricing as
of model-knowledge cutoff — Abe should confirm against current console
rates before Phase 4 budget cap):

- **Tier 1 (Haiku 4.5):** ~240K calls → ~$300–800.
- **Tier 2 (Opus 4.7):** ~45K calls → ~$2,000–4,000.
- **Tier 3 (Opus 4.7 deep):** ~6K calls → ~$1,500–3,500.

**Phase 4 full-corpus total: ~$4–8K.** Range absorbs (a) actual de-dup
ratio, (b) prompt-cache hit rate on shared system prompts, (c) current
per-token rates vs. training-data-era rates.

**Phase 1 slice cost:** 5 filings × ~15 docs × Tier 1 only ≈ ~75 Haiku
calls → **< $1**.

**Phases 2–3 dev/eval cost:** ~150-filing sample → **~$50–200**.

**Action item for Abe:** confirm current Haiku 4.5 + Opus 4.7 per-token
rates before locking the Phase 4 budget cap. Recommend cap = $10K
(1.25× upper-range estimate) with hard cutoffs at $2K Tier 1, $5K
Tier 2, $4K Tier 3.

---

## 7. Verification (Phase 1 exit criteria)

1. **Setup:** Drive-for-Desktop mounted; `vendor/dai_shared/` populated;
   five FCC IDs' directories locally readable; Anthropic API key
   configured; Tier-1 budget cap set ($5).
2. **Run:** `python -m fcc.run_slice <FCC_ID> ...` produces five
   `out/<FCC_ID>.json` records.
3. **De-dup spot check:** any parent+variant pair in the slice produces
   the right `parent_fcc_id` / `variant_fcc_ids` linkage and shares
   `pattern_refs` rather than duplicating them.
4. **Field-by-field manual eval:** open each filing on FCC EAS in one
   window, the JSON record in another. Score every populated field as
   correct / incorrect / partial. Document in `docs/phase1-eval.md`.
5. **Sanity rules:** all frequencies between 10 MHz and 100 GHz; gains
   between -10 dBi and +30 dBi; record validates against
   `fcc/schema.py`.
6. **Confidentiality check:** confirm no values were extracted from any
   exhibit the cover letter marked confidential.
7. **Exit:** ≥ 80 % field accuracy on populated fields, zero
   confidentiality violations, de-dup logic correct on at least one
   parent+variant pair.

If the slice passes, Phase 2 (typology library + classifier on the
~150-filing stratified sample) is the next planning step.

---

## 8. Remaining gates before Phase 1 implementation

1. **Drive→vendor sync (Abe owns):** sync the shared DAI components from
   Drive into `vendor/dai_shared/` and commit, with
   `vendor/dai_shared/README.md` mapping Drive paths → vendor paths +
   sync date + source commits.
2. **Drive→corpus sync (Abe owns):** sync the Apple 2022–2023 handset
   filings (or the broader 10-mfr × UE × 2020–2026 corpus) into a
   locally-readable Drive-for-Desktop path so I can browse and select
   the 5 slice FCC IDs.
3. **Anthropic API key + Tier-1 budget cap** in env for the slice run.

Once 1–3 are resolved:

- I browse the synced corpus, select 5 FCC IDs per §2.1, publish the
  list to `docs/phase1-eval.md` for Abe's veto.
- I implement the Phase 1 pipeline against the file paths in §3.

---

## 9. Phase roadmap (post-slice)

The original systematic plan's later phases survive intact, sized against
the locked production scope:

- **Phase 2 — Pattern discovery & typology** (≈ 10–15 days). Sparsified
  stratified sample (~150 filings, ~10 cells across the 10 mfrs / UE
  classes / 2020–2026 time buckets). Form 731 + TCB-report version
  library. Document typology v1. Categorization classifier v1
  (rules + LLM-assisted), evaluated on 20 % held-out.
- **Phase 3 — Production extractor** (≈ 10–15 days). Three-tier dispatch.
  OCR sub-pipeline + quarantine. Confidentiality region classifier.
  Checkpoint/resume in SQLite. Cost meter and per-tier hard budget caps.
  Eval harness with golden records.
- **Phase 4 — Full-corpus run** (≈ 1–2 weeks attention; 3–7 days
  wall-clock). 1 % dry-run, full run, KB ingest with provenance and
  entity-registry reconciliation.
- **Phase 5 — Agent integration** (≈ 10–15 days). Source-expert shim,
  spec-similarity backend over the five named dimensions, provenance
  round-trip, sample query eval set.

These re-plan in detail after Phase 1 ships.
