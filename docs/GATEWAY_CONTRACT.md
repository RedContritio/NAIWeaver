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
| `permission_denied` | 403 | `permission` | user lacks the permission |
| `invalid_parameters` | 400 | `field` | strict validation failed |
| `points_insufficient` | 409 | `point_kind` (`green`/`red`), `required`, `remaining` | cannot reserve the quote |
| `quote_changed` | 409 | `quote` (see §3) | the price the client showed differs from the server quote |
| `free_allowance_exhausted` | 409 | `quote` | free-eligible work is temporarily priced in red points (§4) and the user cannot or did not confirm |
| `queue_full` | 429 | `limit` | per-user queued task limit |
| `duplicate_request` | 409 | | idempotency key reused with a different body |
| `request_too_large` | 413 | `limit` | body exceeds the limit (counted on the stream, not Content-Length) |
| `upstream_error` | 502 | `upstream_status` | NovelAI returned non-2xx; upstream 401/403 are never forwarded as-is |
| `interrupted` | — (task status) | | task was running when the gateway restarted; reservation released |

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

1. Strictly parse `width`, `height`, `steps` as JSON integers (reject bool,
   float, string). Normalized values are written back into the forwarded body.
2. `free_eligible` = action is `generate` (or absent) and `(width, height)` in
   `free_sizes` and `steps <= free_max_steps` and `sm`/`sm_dyn` falsy and no
   non-empty paid-only parameter (image, mask, strength, noise,
   extra_noise_seed, add_original_image, mask_blur, director_reference_*,
   reference_*_multiple).
3. `base = max(ceil(ceil(area_coef*w*h + step_area_coef*w*h*steps) * smea_mult), min_points)`
   with `smea_mult` = 1.4 if `sm_dyn`, 1.2 if `sm`, else 1.0.
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
 "reasons": ["steps_over_free_limit", "director_refs", "size_not_free", "smea", "image_input", "allowance_exhausted"]}
```

`reasons` lists why the request is `paid` (empty for `free`).

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
- Single-image generation is a batch with one seed. There is no other
  submission path; `/api/nai/image/ai/generate-image` is rejected.

Free allowance: if a `free` task's measured Anlas delta is > 0, the gateway
records a billing anomaly, still charges that task in green, and marks the
allowance exhausted for `NAIWEAVER_FREE_ALLOWANCE_COOLDOWN_SECONDS`
(default 1800). While exhausted, free-eligible requests are quoted `paid`
with reason `allowance_exhausted`; queued `free` tasks that have not started
fail with `free_allowance_exhausted` and release their reservation.

## 5. Paid tools (`POST /api/nai/image/ai/{upscale|augment-image|encode-vibe}`)

Headers (both required):

- `Idempotency-Key: <8..128 chars>` — a retry with the same key returns the
  cached response (bounded in-memory cache) instead of calling NovelAI again.
- `X-NAIWeaver-Expected-Points: <int>` — must equal `tool_caps[...]`;
  otherwise 409 `quote_changed`.

The cap is reserved before the call; the charge is the measured Anlas delta,
never above the cap (cap is charged when the delta cannot be measured).
The client never auto-retries these POSTs.

## 6. Execution and settlement

- All NovelAI image calls (queued generations and paid tools) run through one
  serialized upstream lane. Red-point work (paid generations, paid tools)
  goes before free work; free work keeps the weighted fair order.
- Settlement for `paid`: `min(measured_delta, reserved)`; `reserved` when the
  delta is unavailable or negative; a delta above the reservation records a
  billing anomaly and charges the reservation.
- Upstream failure releases the whole reservation.
- On startup, tasks left `running` become `failed` with `interrupted` and
  their reservations are released; they are never re-run.

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
