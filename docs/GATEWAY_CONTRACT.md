# NAIWeaver gateway contract

This is the single reference for how the Flutter web client and the gateway
(`server/app`) agree on pricing, submission, errors and history payloads.
Server and client changes must keep to it; change this file first when the
contract changes.

## 1. Errors

Every gateway-originated error is JSON:

```json
{"detail": {"code": "points_insufficient", "message": "human readable", "...": "extra fields"}}
```

The client maps `code` to localized text and never shows raw exceptions.

| code | HTTP | extra fields | meaning |
|---|---|---|---|
| `not_authenticated` | 401 | | gateway session missing/expired (never used for upstream 401) |
| `auth_unavailable` | 503 | | the identity provider is temporarily unavailable (or not configured, or its signing key is not yet published); any existing session is kept |
| `login_failed` | 403 | | the identity provider returned an error or the login could not be verified |
| `account_not_linked` | 403 | | the identity provider subject is not in the account mapping, or the account is disabled |
| `permission_denied` | 403 | `permission` | user lacks the permission |
| `invalid_parameters` | 400 | `field` | strict validation failed |
| `points_insufficient` | 409 | `point_kind` (`green`/`red`), `required`, `remaining` | cannot reserve the quote |
| `quote_changed` | 409 | `quote` (see §3) | the price the client showed differs from the server quote |
| `free_allowance_exhausted` | 409 | `quote` | free-eligible work is temporarily priced in red points (§4) and the user cannot or did not confirm |
| `queue_full` | 429 | `limit` | per-user queued task limit |
| `duplicate_request` | 409 | | idempotency key reused with a different body |
| `request_too_large` | 413 | `limit` | body exceeds the limit (counted on the stream, not Content-Length) |
| `upstream_error` | 502 | `upstream_status` | NovelAI returned non-2xx (`upstream_status` is `null` when NovelAI was unreachable); upstream 401/403 are never forwarded as-is |
| `interrupted` | — (task status) | | task was running when the gateway restarted; reservation released |

Authentication is only-WebAuth (OIDC) in production. For local development,
`NAIWEAVER_DEV_USER=<username>` signs loopback clients in as that user when
`NAIWEAVER_ENV` is not `production` and no OIDC issuer is configured; the
gateway refuses to start in production with it set. There is no password login.

Other codes the gateway emits: `not_found` (404, including unknown `/api/*`
paths), `task_active` (409, deleting a queued/running item),
`duplicate_generation` / `duplicate_within_batch` (409, identical effective
parameters; extra `task_id`, `batch_index`, `seed`), `rate_limited` (429,
feedback, and `GET /auth/login` once more than 30 logins start within a minute
across all clients), `method_not_allowed` (405), `service_unavailable` (503) and
`internal_error` (500). `queue_full` is also used for the one-active-text-job
limit (`limit: 1`). Body validation failures are `invalid_parameters` (400)
with `field` set to the offending body path.

Item failure codes (`error_code` on history items, §7): `upstream_error`,
`interrupted`, `free_allowance_exhausted`, `permission_denied` (the account
lost the permission while the item was queued), `invalid_parameters`,
`internal_error`.

## 2. Rules (`GET /api/me` → `rules`)

```json
{
  "rules": {
    "image": {
      "free_sizes": [[832, 1216], [1216, 832], [1024, 1024]],
      "free_max_steps": 28,
      "max_steps": 50,
      "max_dimension": 2048,
      "allowed_samplers": ["k_euler_ancestral", "..."],
      "batch_limit": 8,
      "green_point_discount": 0,
      "free_allowance_exhausted": false,
      "pricing": {
        "area_coefficient": 2.951823174884865e-6,
        "step_area_coefficient": 5.753298233447344e-7,
        "smea_multiplier": 1.2,
        "smea_dyn_multiplier": 1.4,
        "min_points": 2,
        "director_reference_points": 5,
        "free_vibe_count": 4,
        "extra_vibe_points": 2
      },
      "tool_caps": {"upscale": 10, "augment": 80, "encode_vibe": 2}
    }
  }
}
```

`max_steps` and `batch_limit` are already resolved for this user.

## 3. Quote algorithm (`classify_and_quote`)

Server-side single function; the client re-implements it only to display an
instant estimate from `rules`. Both sides share the golden cases in
`test/fixtures/quote_cases.json` (run by pytest and flutter test).

Per image:

0. Only known keys are accepted: the request's top level is `input`, `model`,
   `action`, `parameters`, and `parameters` may hold only the keys the client
   builds (listed in `test/fixtures/image_request_keys.json`) plus `autoSmea`
   (a boolean; true is priced as `sm`). Any other key is `invalid_parameters`
   with `field` set to the key (`parameters.<key>` inside `parameters`).
1. Strictly parse `width`, `height`, `steps` as JSON integers (reject bool,
   float, string). Normalized values are written back into the forwarded body.
   `width`/`height` are multiples of 64 in `64..max_dimension`, `steps` is in
   `1..max_steps`, `sampler` is in `allowed_samplers`, `sm`/`sm_dyn` are
   booleans or absent, `scale` is a number or absent, and
   `director_reference_images` / `reference_image_multiple` are lists or
   absent. Any violation is `invalid_parameters` naming the `field`.
   The model is normalized too (client: `NovelAIService.imageModelFor`): V5
   (`nai-diffusion-5-full` / `-5-curated`, `-5-full-inpainting` for `infill`),
   except that a request with any vibe or Precise Reference image runs on the
   matching V4.5 model, because V5 supports neither yet and vibes are encoded
   with the V4.5 models; Curated `infill` always uses
   `nai-diffusion-4-5-curated-inpainting`. The model does not change the price.
2. `free_eligible` = action is `generate` (or absent) and `(width, height)` in
   `free_sizes` and `steps <= free_max_steps` and `sm`/`sm_dyn` falsy and no
   non-empty paid-only parameter (image, mask, strength, noise,
   extra_noise_seed, add_original_image, mask_blur, director_reference_*,
   reference_*_multiple).
3. `base = max(ceil(ceil(area_coef*w*h + step_area_coef*w*h*steps) * smea_mult), min_points)`
   with `smea_mult` = 1.4 if `sm_dyn`, 1.2 if `sm`, else 1.0. Evaluate the
   products left to right in IEEE-754 doubles so both sides round alike.
4. `points = base + director_refs * director_reference_points + max(0, vibes - free_vibe_count) * extra_vibe_points`.
5. Mode:
   - `free_eligible` and allowance not exhausted → `free`, charged in green:
     `ceil(points * (100 - discount) / 100)` (admins: discount 100).
   - otherwise → `paid`, charged in red: `points`.

Batch total = per-image charge × number of seeds (rounding is per image).

Quote object:

```json
{"mode": "free", "points": 56, "per_image": 14, "images": 4,
 "breakdown": {"base": 20, "director_refs": 0, "extra_vibes": 0},
 "reasons": []}
```

`reasons` lists why the request is `paid` (empty for `free`), in this
canonical order: `size_not_free`, `steps_over_free_limit`, `smea`,
`image_input` (img2img/infill or any image/mask/strength/noise parameter),
`director_refs`, `vibes` (any `reference_*_multiple`), `allowance_exhausted`
(only when the request is otherwise free-eligible), `paid_tool` (tool quotes,
§5). `breakdown` values are points: `director_refs` = count ×
`director_reference_points`, `extra_vibes` = surcharge for vibes above
`free_vibe_count`.

## 4. Submitting generations (`POST /api/generation-tasks`)

```json
{"client_request_id": "8..128 chars", "request": {...}, "seeds": [1, 2],
 "expected_quote": {"mode": "free", "points": 56}}
```

- `expected_quote` is required. If it differs from the server quote the
  server returns 409 `quote_changed` with the server `quote`; the client asks
  the user and resubmits with the server values.
- The quote is reserved atomically before the task is accepted.
- `client_request_id` is the idempotency key: same id + same body returns the
  original submission; same id + different body → 409 `duplicate_request`.
  "Body" is the envelope without `client_request_id`; a replay is answered
  before re-quoting, so it succeeds even if prices changed since.
- `seeds` are JSON integers in `0..4294967295`; more than the user's
  `batch_limit` is 400 `invalid_parameters` with `field: "seeds"` and `limit`.
- Single-image generation is a batch with one seed. There is no other
  submission path; `/api/nai/image/ai/generate-image` is rejected with 400
  `invalid_parameters` (`field: "path"`).
- A quote whose mode the account may not use is 403 `permission_denied`
  (`permission: "image.generate.free" | "image.generate.paid"`).
- The 202 response is `{"task_id", "item_id", "items": [{"id",
  "batch_index", "status"}], "status"}`.

Free allowance: if a `free` task's measured Anlas delta is > 0, the gateway
records a billing anomaly, still charges that task in green, and marks the
allowance exhausted for `NAIWEAVER_FREE_ALLOWANCE_COOLDOWN_SECONDS`
(default 1800). While exhausted, free-eligible requests are quoted `paid`
with reason `allowance_exhausted`; queued `free` tasks that have not started
fail with `free_allowance_exhausted` and release their reservation. Such a
submission is answered 409 `free_allowance_exhausted` (with the red `quote`)
when the account cannot pay red points or `expected_quote` is not that red
quote; a paid account confirms by resubmitting with the red quote.
`GET /api/admin/config` reports `free_allowance: {exhausted,
exhausted_until, cooldown_seconds}`.

## 5. Paid tools (`POST /api/nai/image/ai/{upscale|augment-image|encode-vibe}`)

Headers (both required):

- `Idempotency-Key: <8..128 chars>` — a retry with the same key, tool path
  and body returns the cached response (bounded in-memory cache) instead of calling NovelAI again.
- `X-NAIWeaver-Expected-Points: <int>` — must equal `tool_caps[...]`;
  otherwise 409 `quote_changed` with `quote` (`mode: "paid"`,
  `reasons: ["paid_tool"]`).

A missing or malformed header is 400 `invalid_parameters` naming the header.
The same key with a different body is 409 `duplicate_request`. Only
successful responses are cached (up to 32 entries / 128 MB, 10 minutes); a
failed call released its reservation and may be retried with the same key.

The cap is reserved before the call; the charge is the measured Anlas delta,
never above the cap (cap is charged when the delta cannot be measured).
A delta above the cap records a billing anomaly. A delta of 0 is re-read
once after a short wait (`NAIWEAVER_BALANCE_RECHECK_SECONDS`, default 1); if
still 0 the tool is charged 0 (it may really be free) and an `unmeasured`
anomaly is recorded. In-flight tool reservations are stored in
`tool_reservations`, so rebuilding the counters keeps them; the service drops
leftovers of a previous process at startup.
The client never auto-retries these POSTs.

## 6. Execution and settlement

- All NovelAI image calls (queued generations and paid tools) run through one
  serialized upstream lane. Red-point work (paid generations, paid tools)
  goes before free work; free work keeps the weighted fair order.
- Settlement for `paid`: `min(measured_delta, reserved)`; `reserved` when the
  delta is unavailable or negative; a delta above the reservation records a
  billing anomaly and charges the reservation. `free` work is charged its
  green reservation.
- Upstream failure releases the whole reservation. So does a 2xx response
  without a decodable image; the measured delta is still audited
  (`decode_failed` for paid work, the free-allowance rules for free work).
- A paid generation whose balance delta is still 0 after a re-read is charged
  its quote and recorded as `unmeasured`; a free task whose balance could not
  be read is also recorded as `unmeasured`.
- On startup, tasks left `running` become `failed` with `interrupted` and
  their reservations are released; they are never re-run. A task cut off by
  a graceful shutdown is marked the same way before the process exits.
- A queued task whose account was disabled or lost the permission fails with
  `permission_denied` and releases its reservation.

### Cancelling queued items (`POST /api/generation-tasks/{id}/cancel`)

`{id}` is the submission id. The caller must own the submission (anyone else,
admins included, gets 404 `not_found`). Every item of it that is still
`queued` becomes `cancelled`, leaves the pending queue and has its whole
reservation released in the same transaction. Items that are `running` or
already final are not touched, so the call is safe to repeat and to race with
the worker: an item the worker has not marked `running` is never executed
after it was cancelled. A cancelled item has no `error_code`. The response is
the submission as in §7 (200), whatever was or was not cancellable.

## 7. History and task items

Items returned by `/api/history`, `/api/generation-tasks/{id}`,
`/api/generation-items/{id}` and `/api/current-generation-task` contain only:

`id, user_id, username, batch_id, batch_index, batch_size, status,
error_code, error_message, mode, points_charged, prompt, negative_prompt,
width, height, steps, scale, sampler, seed, request_json, has_image,
created_at, completed_at`

- `batch_size` is the number of items in the batch; the client treats an
  item as part of a batch only when `batch_size > 1`.
- `has_image` replaces any use of `image_path` (never exposed).
- Hidden (deleted) items are never returned, including by the current-task
  endpoints.
- `points_charged` is the settled charge in the item's `mode` (green for
  `free`, red for `paid`); 0 until it succeeds.
- `/api/generation-tasks/{id}` and `/api/current-generation-task` (`{"task":
  ...}`) wrap the items as `{"id", "user_id", "type", "status",
  "item_count", "created_at", "completed_at", "items"}`. A task whose items
  are all hidden is 404 `not_found` (or skipped by the current-task
  endpoint).

## 8. Audit bodies (admin)

- `GET /api/admin/audit` items carry `request_body_available` and
  `request_body_expired`.
- Audit request bodies are kept forever by default
  (`NAIWEAVER_AUDIT_RETENTION_DAYS=0`). When a number of days is set, after that
  `GET /api/admin/audit/{id}/body` is 404 with a message that the body
  expired; the audit row itself is kept.
- `GET /api/admin/audit` returns a fixed field set; the storage path and body
  hash (`request_body_path`, `request_body_sha256`) are never exposed.
- `PATCH /api/admin/users/{id}` with `is_admin` changing to false resets
  `green_point_discount` to the role default (0) unless the request sets it.
- A rejected `POST /api/generation-tasks` is audited with metadata only (no
  stored body).
