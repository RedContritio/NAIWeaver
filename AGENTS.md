# Project testing account

- Use the production account `agent_test` for every live browser, smoke, and
  end-to-end test against the deployed NAIWeaver service.
- Do not use personal, admin, or other production accounts for live tests.
- Keep passwords, session cookies, passkeys, and WebAuthn enrollment links out
  of the repository.
- Unit tests must keep using isolated fixture users and temporary databases;
  they must never connect to or mutate the production database.
- `agent_test` has a permanent 10,000-green-point allocation. Do not exercise
  red-point-only operations unless the user explicitly expands that account's
  permissions and balance.
