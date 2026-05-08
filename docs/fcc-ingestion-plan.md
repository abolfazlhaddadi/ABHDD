# FCC Filing Ingestion Pipeline — Plan

**Project:** DAI / P01 — FCC Source-Expert Agent
**Status:** Plan only. No implementation until Abe approves.
**Branch:** `claude/fcc-ingestion-pipeline-plan-2cQIp`
**Brief:** see request thread, 2026-05-08

---

## 0. Repo state caveat (read first)

This repo (`abolfazlhaddadi/abhdd`) currently contains only a `README.md`. The brief
references existing components — Structure Profiler v0.5, the
`dai-patent-agents.skill`, `PROTOCOL.md`, the patent three-tier pipeline, the shared
concept vocabulary, and the entity registry — none of which are in this tree. The
component-map and reuse decisions below are therefore based **only on the brief's
descriptions**, not on inspection of source. Before implementation starts, Abe needs
to either (a) bring those components into this repo, (b) point me at the repo(s)
where they live, or (c) confirm that this is a greenfield repo and those references
are aspirational.

---

## 1. Architecture review

The pipeline is broadly correct. The staging order, the bias toward stratified
sampling before full extraction, the three-tier LLM cost discipline, and the
"numbers + refs, not full PDFs" storage philosophy all match what works. Specific
pushback below — most of it is "you've under-scoped this stage" rather than "this
stage is wrong."

### What's right

- **Stratified sampling first.** Catches TCB-specific and era-specific quirks
  before they corrupt extraction recipes. Standard pattern for heterogeneous
  document corpora.
- **Three-tier dispatch.** Reusing the patent pipeline's Haiku/Opus/Opus-deep
  pattern keeps cost discipline. The 80/15/2 rough split is realistic.
- **Lightweight records.** A KB optimized for similarity queries should not
  carry the source PDFs. This is correct.
- **Form 731 version library as separate ground truth.** Right instinct —
  separates the stable form schema from variable exhibit conventions.

### Where the plan is under-scoped or mis-weighted

1. **Form 731 carries ~5% of the per-filing variance — exhibits carry the rest.**
   Form 731 gives you metadata (FCC ID, grantee, declared frequencies, equipment
   class). Almost all the technical content — radiation patterns, gain tables,
   S-parameter plots, antenna geometry — lives in the **exhibits**, which Form 731
   does not structure. Stage 1's "Form 731 Version Library" is useful but small.
   The dominant pattern-discovery work is on **TCB report templates** and
   **manufacturer exhibit conventions**, neither of which the brief calls out as a
   distinct dataset. Recommend renaming Stage 1 to "Reference Template Library"
   and adding TCB report templates as a second sub-corpus.

2. **Sampling cell math doesn't add up.** Time (4) × manufacturer (10) × product
   (7) = 280 cells × 3–5 filings = 840–1400 sample filings, not the 200–500
   target. Either accept the larger sample (cost: ~10× the v1 estimate) or
   sparsify the grid — e.g., only the top 3 manufacturers per product type, only
   2 time buckets for products that didn't exist pre-2018 (wearables). I'd
   recommend sparsifying; the inner loop is expensive.

3. **Categorization (Stage 4) is the hardest stage and is treated as a router.**
   In practice this is where most failure modes hide — a misclassified exhibit
   sends garbage to the wrong extractor and corrupts the record. The brief
   describes it as "a dispatcher with confidence scoring," which is correct in
   spirit but undersells the work. Recommend treating it as an **explicit
   classifier with a held-out eval set per cell**, with confidence thresholds
   that escalate ambiguous documents to Tier 2 review rather than firing the
   extractor blindly.

4. **`pattern_refs` to a discarded PDF is a dead pointer.** The brief proposes
   discarding raw PDFs after extraction and storing pointers like
   `figure 4 on page 12 of <hash>.pdf`. If the PDF is gone, that ref is
   unresolvable. Three options, pick one before Phase 1:
   - **(A)** Retain the PDFs (cheap storage, simple, defeats the "lightweight"
     pitch slightly but only at the corpus-storage layer).
   - **(B)** At extraction time, also export a canonical artifact per ref
     (cropped figure image + caption) and store *that*. Refs point to the
     artifact, not the PDF.
   - **(C)** Retain the URL only and re-fetch on demand. Fragile — FCC EAS link
     stability across years is not great, and re-fetch latency kills query UX.

   I recommend **(B)**. Storage cost is small (figure crops are KB, not MB); refs
   stay resolvable; the "no full PDFs" pitch holds.

5. **The stated use case implies numerical pattern data, but the schema is
   summary statistics.** "Find products with antenna behavior similar to X in the
   3.5 GHz band" — *similar how?* Two interpretations:
   - **Behavioral similarity:** match on radiation pattern shape (peak gain
     direction, beamwidth, null structure, polarization). Requires extracting
     pattern data numerically — very hard, since patterns are usually polar plot
     images, not tables.
   - **Spec similarity:** match on summary statistics (peak gain, efficiency,
     band coverage, antenna type, count). Tractable — the proposed schema
     supports this.

   The proposed schema is closer to spec similarity. That's a reasonable v1, but
   align with Abe explicitly — if the real ask is behavioral similarity, the
   pipeline needs a pattern-image-extraction stage that's not in the brief.

6. **OCR is a footnote and shouldn't be.** Pre-2015 filings are frequently
   scanned. OCR quality on test reports — narrow columns, dense numerical
   tables, italic units — is bad enough that naive Tesseract output will
   silently corrupt frequencies and power values. Recommend an explicit OCR
   sub-pipeline: image preprocessing, OCR, per-field quality scoring, and a
   "quarantine" path for low-quality docs that escalates to Tier 2 with the
   image rather than the OCR text. Or — defer pre-2015 from v1 entirely.

7. **Confidentiality enforcement requires detection, not just respect.** The
   brief says "do not extract from sections marked confidential." Good policy,
   but those sections aren't always machine-readable as such — sometimes a
   stamp, sometimes a cover-letter assertion that exhibit X is confidential,
   sometimes a redacted block. Need an explicit **confidentiality region
   classifier** as a first pass, with a conservative default (skip on
   uncertainty). This is a non-trivial component — call it out, don't bury it.

8. **Stages 6 and 7 are thin.** "Lightweight KB Records" and "Agent Integration"
   together are most of the product value, and the brief gives them a paragraph
   each. Specifically: the similarity query interface, the ranking function, and
   the provenance round-trip back to FCC ID + page need their own design
   (probably their own brief). Out of scope to plan here, but flag it.

### Net assessment

Right-shaped pipeline. Stages 1, 4, 6, 7 are under-specified; OCR and
confidentiality detection deserve to be first-class components. Sampling math
needs a rework. Pattern-ref durability needs a decision. Use case (behavioral vs.
spec similarity) needs to be pinned down with Abe.

---

## 2. Open questions (for Abe, before Phase 1)

Numbered for ease of reply.

**Repo / existing components**

1. Where do `structure_profiler.py` (v0.5), `dai-patent-agents.skill`,
   `PROTOCOL.md`, the patent three-tier pipeline, the entity registry, and the
   concept vocabulary actually live? Same repo? Different repos? Are they
   importable, or do they need to be vendored in?
2. Is the FCC ingestion pipeline a sub-package of this repo, a new package, or a
   new repo? (Affects packaging, CI, and dependency layout.)

**Corpus**

3. Where is the corpus stored? Drive (which path)? Local disk? S3? Confirming
   that "Drive-for-Desktop sync" applies to *output* records — what about
   *input* PDFs?
4. Approximate corpus size: total GB, file count? The brief says
   "tens of thousands of filings" elsewhere — is that the v1 scope, or does v1
   target a narrower slice?
5. File formats: PDF only? Any XML/structured exhibits? Any pre-existing index
   or manifest (FCC ID → file paths)?
6. Have the filings already been de-duped against TCB resubmissions and
   permissive-change refilings (where the same device is filed twice with minor
   updates)?

**Scope**

7. Is "all manufacturers, all product types, 2010–2026" the v1 target, or
   should v1 narrow (e.g., handsets only, top 5 manufacturers, 2018–2026)?
   Recommended narrowing for v1: handsets + tablets, top 5 mfrs, 2018–2026 —
   fewer cells, denser data per cell, richer extraction validation.
8. Is the similarity use case **behavioral** (radiation pattern shape) or
   **spec** (summary statistics)? See architecture review §5.
9. Is numerical pattern extraction in scope for v1, or deferred?

**Policy**

10. **Retention policy** for raw PDFs after extraction — keep, discard, or the
    "extract canonical artifacts then discard" middle path I'd recommend
    (architecture review §4)?
11. Storage budget for retained artifacts (figures, photos)?
12. Confidentiality posture: conservative-skip-on-uncertainty (recommended) or
    extract-and-tag with a downstream filter? Affects classifier design.

**Resources**

13. Compute budget: Anthropic API spend ceiling for the vertical slice and full
    run? Need a cap before kicking off a Tier 1 pass over 50K filings.
14. Wall-clock target for full-corpus run? Sets parallelism strategy.
15. Engineer-days available — solo, paired, or with help on OCR / classifier
    work?

**Integration**

16. Which version of the entity registry / concept vocabulary is canonical at
    write time? Concurrent with the patent pipeline, or downstream of it?
17. Is the orchestrator that calls the FCC source-expert agent already defined
    (interface, query schema), or does this pipeline define it?

---

## 3. Phased implementation plan

Five phases. Phase 1 is a vertical slice. Phases 2–4 widen and harden. Phase 5
hooks the agent up. Time estimates assume one engineer working primarily on
this, with pre-existing access to the patent pipeline code for reuse.

### Phase 1 — Vertical slice (≈ 10–15 engineer-days)

**Goal:** End-to-end pipeline on one cell. Hardcode everything that isn't on
the critical path.

**Cell:** Apple × 2022–2023 × handset, 5 filings.

**Deliverables:**
- Filing fetcher / loader for the 5 chosen FCC IDs (or local-file loader if
  Abe provides them).
- Structure Profiler v0.5 invoked per PDF; section/exhibit hierarchy dumped to
  JSON.
- **Hardcoded** classification: a small lookup of filename patterns →
  document class. No learned classifier yet.
- Three extractors (Tier 1 only, Haiku):
  - Form 731 metadata extractor (FCC ID, grantee, dates, declared bands).
  - Test report frequency/power extractor.
  - Antenna exhibit gain/type extractor.
- KB record writer producing v1 records (schema below) to a single JSONL file.
- Provenance fields populated.
- Pattern refs stored as `(file_hash, page, bbox)` — actual artifact export
  deferred to Phase 3.
- Manual eval: read all 5 records, score each field for correctness, write a
  short eval report (`docs/phase1-eval.md`).

**Exit criteria:** ≥ 80 % field accuracy across the 5 filings, all stages
runnable end-to-end on a fresh checkout, runbook documented.

**Out of scope for Phase 1:** OCR, confidentiality classifier, learned
categorization, Tier 2/3 escalation, similarity query interface.

### Phase 2 — Pattern discovery & typology (≈ 10–15 engineer-days)

**Goal:** Build the classifier and recipes that let Phase 3 run on the full
corpus.

**Deliverables:**
- Form 731 + TCB-report version library, scraped and cataloged.
- Stratified sample drawn from the corpus per the sparsified grid in §1.2 —
  target ~150 filings, ~10 cells.
- Per-cell structural profiles produced by Structure Profiler.
- Document typology v1: classes (test report, antenna exhibit, schematic, photo
  set, cover letter, RF exposure, …) with example documents per class.
- Categorization classifier v1 (rules + small LLM-assisted classifier),
  trained/calibrated on the sample, evaluated on a held-out 20 % split.
- Per-class extraction recipes (extends Phase 1 extractors).
- Per-manufacturer override hooks (empty for v1, structure in place).

**Exit criteria:** classifier ≥ 90 % accuracy on held-out, extraction recipes
exist for all classes representing ≥ 95 % of sampled documents.

### Phase 3 — Production extractor (≈ 10–15 engineer-days)

**Goal:** Harden the pipeline for full-corpus runs.

**Deliverables:**
- Three-tier dispatch (Haiku / Opus / Opus-deep) wired to confidence
  thresholds from Phase 2 classifier.
- OCR sub-pipeline: Tesseract (or a hosted alternative, decision item) + image
  preprocessing + per-field OCR confidence scoring + quarantine path.
- Confidentiality region classifier: detects withheld-section markers,
  cover-letter confidentiality assertions, redaction blocks. Default-skip on
  uncertainty.
- Canonical artifact exporter: per `pattern_refs`, crop the figure region and
  save with caption + provenance.
- Checkpoint / resume: per-filing state (pending, extracting, done, failed,
  quarantined) in a small SQLite DB. Idempotent re-runs.
- Batched API client with retry/backoff and per-tier rate limits.
- Per-tier cost meter and hard budget caps.
- Eval harness: held-out filings + golden records, per-field accuracy
  reporting, regression detection.

**Exit criteria:** full pipeline runs end-to-end on the Phase 2 sample with
≥ 90 % field accuracy and zero confidentiality leaks (verified by manual audit
of the sample's withheld sections).

### Phase 4 — Full-corpus run (≈ 1–2 engineer-weeks of attention; 3–7 days
wall-clock for the compute)

**Goal:** Produce the production KB.

**Deliverables:**
- Dry-run on 1 % of corpus, extrapolate cost, confirm against budget.
- Full run with checkpointing.
- KB ingest with provenance and entity-registry reconciliation.
- Run report: filings processed, success rate, quarantined count, cost,
  per-cell accuracy spot-checks.

**Exit criteria:** ≥ 95 % of filings produce a record (failures are accounted
for, not silent), entity registry reconciliation rate ≥ 90 %, costs within
budget.

### Phase 5 — Agent integration (≈ 10–15 engineer-days)

**Goal:** Make the KB queryable by the orchestrator.

**Deliverables:**
- Source-expert agent shim conforming to the orchestrator contract.
- Similarity query backend — exact form depends on use-case decision (open
  question 8). For spec-similarity v1: vector store over a feature vector
  built from the schema (gain × bands × type × form factor × polarization).
- Provenance round-trip: agent responses include FCC ID, page, and a link to
  the canonical artifact.
- Query eval set: ~20 sample queries with expected top-K, measured precision.

**Exit criteria:** orchestrator can issue a query, receive ranked references
with provenance, and resolve any pattern_ref to a viewable artifact.

---

## 4. Component map (reuse vs. new)

Reuse decisions are tentative pending the open questions about repo state.

### Reused (extend, don't fork)

| Component | Source | Use here |
|---|---|---|
| Structure Profiler v0.5 | existing PyMuPDF profiler | Section/exhibit hierarchy per PDF; extend with FCC-specific section heuristics → call this v0.6 |
| Three-tier LLM dispatcher | patent pipeline | Same Haiku / Opus / Opus-deep pattern, new per-class prompts |
| Entity registry | shared DAI | Grantee resolution, manufacturer normalization, device cross-refs |
| Concept vocabulary | shared DAI | Antenna type enum, modulation enum, form-factor enum |
| Provenance model | shared DAI | Source URL, retrieval date, file hash, FCC ID |
| Drive-for-Desktop output sync | confirmed in brief | KB record persistence |

### New (this project)

| Component | Notes |
|---|---|
| FCC corpus loader | Adapter to whatever store Abe lands on (open question 3) |
| Form 731 / TCB template library + diff tool | Stage 1 — small but standalone |
| Stratified sampler | Sparsified grid sampler with seed control for reproducibility |
| Document typology + classifier | Stage 4 — central, deserves its own eval harness |
| Per-class extraction recipes | One per document class, prompt + parser |
| OCR sub-pipeline | Image preprocess + Tesseract (or hosted) + quality scoring + quarantine |
| Confidentiality region classifier | First-pass tagger; conservative default-skip |
| Canonical artifact exporter | Crop figures/tables for durable refs |
| Checkpoint store | SQLite — tiny, pure-Python, no infra |
| Cost meter + budget cap | Per-tier counters with hard cutoffs |
| KB record schema + writer | Schema below |
| Eval harness | Golden records + per-field accuracy + regression detection |
| Agent shim | Orchestrator-facing query interface |
| Similarity backend | Feature vector + lightweight vector store; design depends on use case |

---

## 5. Schema proposal (refined Stage 5 fields)

Changes from the brief in **bold**.

| Field | Type | Notes |
|---|---|---|
| `fcc_id` | string | Primary key (with grantee code prefix). |
| `grantee_code` | string | First 3–5 chars of FCC ID. **Split out from `grantee`.** |
| `grantee` | entity_ref | Resolved against entity registry. |
| **`form_version`** | string | Form 731 revision used by this filing. |
| **`tcb_id`** | string | Certifying body. Drives template-variance handling. |
| `application_date` | date | From Form 731. |
| **`grant_date`** | date | Distinct from application date — useful for time-bucketing. |
| `device_class` | enum | DAI taxonomy (handset, tablet, wearable, …). |
| **`equipment_class_codes`** | list[string] | FCC's own taxonomy (DTS, PCB, NII, …). |
| **`frequency_bands_mhz`** | list[range_with_label] | Each range tagged with band label and tx/rx. |
| `tx_power_dbm` | list[float_by_band] | **Indexed by band, not flat.** |
| **`modulation_types`** | list[enum] | Affects antenna context. |
| `antenna_count` | int? | **Optional — often ambiguous, populate when confident.** |
| `antenna_types` | list[enum] | PIFA, monopole, patch, slot, array, … |
| **`peak_gain_dbi_by_band`** | dict[band → float] | **Was flat scalar — must be band-conditional.** |
| **`efficiency_pct_by_band`** | dict[band → float] | **New — key for similarity.** |
| **`polarization`** | enum or list | **New — important for behavioral similarity.** |
| **`multiband_summary`** | list[antenna_element] | **New — bands grouped by antenna element.** |
| `pattern_refs` | list[ref] | Each ref = `{type, file_hash, page, bbox, artifact_id?}`. Type ∈ {page_region, extracted_artifact, source_url}. |
| `form_factor` | enum | |
| **`host_context`** | object? | **New, optional — chassis material, screen size, etc., where extractable.** |
| **`cross_refs`** | list[ref] | **New — predecessor models, modular grants, related FCC IDs.** |
| **`confidentiality_status`** | dict[field → enum] | **Per-field, not per-filing. Values: public, withheld, redacted, unknown.** |
| **`extraction_confidence`** | dict[field → float] | **New — calibrated from extractor.** |
| **`ocr_quality_score`** | float | Document-level; missing if no OCR was needed. |
| `provenance` | object | source URL, retrieval date, file hash, form_version, pipeline_version. |

**Dropped from brief:**
- `dimensions_mm` — hard to extract reliably from photos, low query value, drop
  for v1.
- Top-level `confidentiality_flags` — folded into per-field
  `confidentiality_status`.

**Marked optional for v1 (can be omitted without breaking the record):**
- `antenna_count`, `host_context`, `cross_refs`, `efficiency_pct_by_band`.
  These are high-value but extraction quality will be uneven; populate when
  Tier 2 confidence is high, leave null otherwise.

---

## 6. Risk register

Top 5, ordered by expected impact.

### R1 — Confidentiality leak (legal / operational)

**Risk:** Extractor pulls data from a section legitimately withheld under
47 CFR 0.457(d), and that data lands in the KB.

**Likelihood:** medium without explicit mitigation.
**Impact:** high — legal exposure for the project sponsor and reputational
damage with the manufacturer ecosystem.

**Mitigation:**
- Confidentiality region classifier as a mandatory first pass, default-skip on
  uncertainty.
- Held-out audit set with known-confidential sections; CI eval refuses to
  promote a classifier that leaks any of them.
- Per-field `confidentiality_status`; KB query layer hard-filters anything
  not `public` or explicitly `cleared`.
- Manual audit of the first 100 production records before declaring Phase 4
  complete.

### R2 — Categorization classifier brittleness (technical)

**Risk:** A misclassified exhibit fires the wrong extractor and silently
corrupts records (e.g., a photo set classified as a test report → garbage
frequency values).

**Likelihood:** high without held-out evaluation.
**Impact:** medium-high — corrupts similarity search and is hard to detect
post-hoc.

**Mitigation:**
- Held-out eval set per cell; classifier promotion requires ≥ 90 % accuracy.
- Confidence threshold; below threshold escalates to Tier 2 (Opus with the
  document image, not just text) before any extractor runs.
- Sanity rules in extractors: a frequency value < 10 MHz or > 100 GHz
  triggers a quarantine, not a write.

### R3 — OCR quality on pre-2015 filings (technical)

**Risk:** Scanned pre-2015 filings produce bad OCR that silently corrupts
critical numerical fields (frequencies, powers, gains).

**Likelihood:** high if OCR is treated as a fallback.
**Impact:** medium — concentrated in the older corpus, contained if scoped.

**Mitigation:**
- Explicit OCR sub-pipeline with quality scoring; quarantine low-score
  documents to Tier 2 with the source image, not the OCR text.
- Consider scoping v1 to 2018-onward and deferring older filings to a v2.
- Numerical sanity rules per field (see R2).

### R4 — Cost overrun on full-corpus run (operational)

**Risk:** Tier 1 over a 50K-filing corpus with 10–20 documents per filing is
~750K LLM calls. Even at Haiku prices, miscalibration of token counts or
retry storms can blow budget.

**Likelihood:** medium without hard caps.
**Impact:** medium — recoverable, but burns trust and runway.

**Mitigation:**
- Per-tier hard budget caps in the dispatcher; pipeline halts and resumes from
  checkpoint when caps are hit.
- 1 % dry-run before the full run; extrapolate cost; confirm before
  committing.
- Per-document token budget; oversized documents quarantine rather than retry.
- Cost meter visible in run report.

### R5 — Similarity is ill-defined (product / technical)

**Risk:** Even with perfect extraction, "similar antenna behavior" needs a
similarity function that the agent's downstream consumers agree on. Without
that definition, the KB is a pile of records nobody queries successfully.

**Likelihood:** medium — easy to defer past the deadline.
**Impact:** high — invalidates the whole value proposition.

**Mitigation:**
- Force the decision in open question 8 before Phase 1 ships.
- Define 3–5 explicit similarity dimensions with Abe — e.g.,
  `frequency_overlap`, `peak_gain_proximity`, `antenna_type_match`,
  `form_factor_match`, `polarization_match` — and build the v1 query
  interface around those.
- Sample query eval set in Phase 5 before full integration.

**Honorable mentions (not top 5, but worth tracking):** corpus drift over the
project lifetime; FCC.gov rate limits on re-fetch; entity registry conflicts
with the patent agent; PyMuPDF version drift if Structure Profiler v0.5 pins an
old one.

---

## 7. Cost / time estimate (order of magnitude)

All numbers are hand-wavy until the vertical slice produces real measurements.
Treat ranges as 1-sigma.

### Vertical slice (Phase 1)

- **Engineer time:** 10–15 days, 1 engineer.
- **LLM cost:** 5 filings × ~15 documents avg × Tier 1 only ≈ 75 Haiku calls
  ≈ **$1–5**.
- **Compute:** trivial. Local laptop suffices.

### Full pipeline build (Phases 1–3, before any large run)

- **Engineer time:** 30–45 days end-to-end, single engineer; less with help on
  OCR + classifier.
- **LLM cost during dev/eval:** Phase 2 sample (~150 filings × ~15 docs ×
  mostly Tier 1 + Tier 2 spot checks) ≈ **$50–200**.

### Full-corpus run (Phase 4)

Assuming 50K filings × 15 documents avg = 750K documents through Tier 1, 15 %
escalation to Tier 2, 2 % to Tier 3:

- Tier 1 (Haiku, 750K docs at ~$0.001 each): **~$750**.
- Tier 2 (Opus, ~110K docs at ~$0.05 each): **~$5,500**.
- Tier 3 (Opus-deep, ~15K docs at ~$0.50 each): **~$7,500**.
- **Total LLM:** **~$10–15K** order of magnitude. Could be 2–3× lower with
  aggressive prompt caching and tighter Tier 2 thresholds; could be 2× higher
  on miscalibration.

If v1 narrows to ~10K filings (top 5 mfrs, handsets+tablets, 2018+), divide
above by ~5 → **~$2–3K**.

- **Wall-clock for the run:** 3–7 days at moderate parallelism (10–20 concurrent
  Tier 1, fewer for Tier 2/3).
- **Engineer attention during the run:** ~1 week, mostly babysitting and
  triaging quarantines.

### Phase 5 (agent integration)

- **Engineer time:** 10–15 days.
- **LLM cost:** marginal (query-time only, low volume).

### Bottom line

- **Vertical slice:** ~2 weeks, < $10. Cheap to validate the approach.
- **To production-quality KB:** ~8–12 weeks engineer time + $2–15K LLM spend
  depending on v1 scope. The 2–3× scope reduction (handsets+tablets, top-5
  mfrs, 2018+) is the single biggest cost lever.

---

## 8. Recommended next step

Before any code is written, please answer at least the open questions in
§2.1–2.3 (repo state), 2.10 (retention), 2.7 (v1 scope), and 2.8 (similarity
type). Those four decisions gate Phase 1 design.

Once those are settled, I'll convert this plan into a Phase 1 task list with
concrete file paths and ship the vertical slice.
