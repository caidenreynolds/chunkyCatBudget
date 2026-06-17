# ChunkyCat Budget App Function Map

This document is a navigation guide for future development. It explains where the main app behavior lives, which screens exist, and which backend functions support each workflow.

## Deployment And Cache Behavior

Docker serves the Flutter web app through Nginx using `docker/nginx.conf`.

Important no-cache routes:

- `/`
- `/index.html`
- `/version.json`
- `/flutter_bootstrap.js`
- `/flutter_service_worker.js`
- `/main.dart.js`
- `/flutter.js`
- `/manifest.json`
- `/.last_build_id`

Why this matters: Flutter web uses `flutter_bootstrap.js` to load `main.dart.js`. If `main.dart.js` is cached too aggressively, users can see an old UI even after the container updates. The app now forces fresh validation for the app shell and app bundle so end users should not need to clear browser cache after updates.

Long-cache routes:

- hashed/static assets such as images, fonts, CanvasKit, and wasm may still be cached normally.

Build metadata:

- Docker generates `build/web/version.json`.
- GitHub Actions passes commit, build time, and run number into the Docker build.
- Flutter displays this build info on login/create account/settings screens through `BuildInfoText`.

## Frontend Entry Points

File: `lib/main.dart`

- `main()` starts the Flutter app.
- `ChunkyCatBudgApp` configures Material theme, global focus traversal, and `BudgetHome`.
- `BudgetApi` wraps HTTP calls and appends the active `profile_id` to profile-specific API paths.
- `ApiException` and `errorMessage()` normalize API errors for user-facing snackbars.
- `BuildInfo`, `loadBuildInfo()`, and `BuildInfoText` load and display `/version.json`.

## Authentication And Profile Selection

Frontend:

- `AuthGateway` decides whether to show login/create-account/profile selection/signed-in app.
- `LoginScreen` signs in with email/password.
- `CreateAccountScreen` registers a new user.
- `ProfileSelectionScreen` lists budget profiles the user can access, creates new profiles, supports select/reorder/delete mode, and passes the selected profile into the app.

Backend:

- `register()` handles `/api/register`.
- `login()` handles `/api/login`.
- `list_budget_profiles()` handles `/api/budget-profiles`.
- `create_budget_profile()` handles `POST /api/budget-profiles`.
- `reorder_budget_profiles()` handles `PUT /api/budget-profiles/reorder`.
- `delete_budget_profile()` handles `DELETE /api/budget-profiles/{profile_id}`.
- `list_budget_profile_members()`, `invite_budget_profile_member()`, `list_invitations()`, and `accept_invitation()` support shared profile access.

Current limitation:

- Sign-in state is in Flutter memory only. Refreshing the browser loses the signed-in state. Persistent server sessions are not implemented yet.

## App Shells And Navigation

Frontend:

- `_DesktopShell` renders the desktop/web layout with left sidebar and top signed-in bar.
- `_PhoneShell` renders the phone layout with bottom navigation.
- `_SignedInBar` shows selected profile, user email, role, switch profile, and sign out actions.
- `_Sidebar` renders desktop navigation and pins Settings at the bottom.
- `_ScreenHost` maps selected navigation index to the active screen.
- `MobileMoreScreen` holds phone-only secondary navigation.

Navigation indexes:

- `0` Dashboard
- `1` Budget Overview
- `2` Add Paycheck
- `3` Accounts
- `4` Chunks
- `5` Transfers
- `6` Transactions
- `7` Paycheck Setup
- `8` Settings
- `9` Phone More menu

Phone bottom navigation:

- Home
- Overview
- Transfer
- Chunks
- More

Phone More contains Paycheck Setup, Add Paycheck, Accounts, Budget Overview, Transactions, and Settings.

## Dashboard

Frontend:

- `DashboardScreen` shows account totals, quick actions, accounts, chunks, and recent transfers.
- `_DashboardActions` provides quick navigation to add paycheck, add transfer, accounts, chunks, and overview.
- Recent Transfers rows call `showTransferDetails()` when tapped/clicked.
- Paycheck rows open a detail dialog with the added date/time, deposit account, total, unallocated amount, and every chunk allocation.
- Active paycheck records can be reverted from the detail dialog.

Backend:

- `dashboard_summary()` handles `/api/dashboard/summary`.
- It returns totals, account summaries, chunks, recent money movements, paycheck records, paycheck profiles, and first paycheck profile for backward compatibility.

## Budget Overview

Frontend:

- `BudgetOverviewScreen` compares expected paycheck income against active chunk deductions.
- It sums all paycheck profiles' `net_pay_amount`.
- It subtracts all active chunks' `amount_per_paycheck`.
- Chunks with positive paycheck amounts must be assigned to a paycheck profile.
- It shows leftover/unallocated expected per paycheck and warns when chunks exceed expected pay.

Backend:

- Uses data from `dashboard_summary()`.
- No separate backend endpoint exists for this page.

## Paycheck Setup

Frontend:

- `PaycheckSetupScreen` manages multiple paycheck profiles.
- `_PaycheckSetupScreenState` lets the user select an existing paycheck profile or create a new one.
- Each paycheck profile stores name, net pay, net pay mode, pay frequency, and default deposit account.
- Gross pay is intentionally hidden from the UI; the backend keeps the old database column for compatibility and stores gross as net for new/updated profiles.
- Net pay mode is currently a confidence/planning label: manual exact amount, expected recurring amount, or estimated placeholder.
- Net paycheck amount must be greater than zero.
- Required fields show an inline red `Required` error after an attempted save.
- Existing paycheck profiles can be renamed, edited, or deleted. Deleting a profile keeps historical paycheck records.

Backend:

- `get_paycheck_profile()` handles legacy `GET /api/paycheck-profile`.
- `list_paycheck_profiles()` handles `GET /api/paycheck-profiles`.
- `upsert_paycheck_profile()` handles `POST/PUT /api/paycheck-profile`.
- `delete_paycheck_profile()` handles `DELETE /api/paycheck-profiles/{paycheck_profile_id}`.
- `PaycheckProfileIn` is the request model.

Database:

- `paycheck_profiles` supports multiple profiles per budget profile.
- Migration removes the old `UNIQUE(profile_id)` constraint.
- Existing single-profile data is preserved.

## Add Paycheck

Frontend:

- `AddPaycheckScreen` lets the user choose a paycheck profile and uses that profile's default deposit account.
- It shows the expected deposit amount before submit.
- It can use expected net pay or a custom amount.
- Required fields show an inline red `Required` error after an attempted add.
- If the configured chunk total exceeds the paycheck, a review dialog lets the user cancel, deselect chunks, or enter smaller one-time allocation amounts before adding it.

Backend:

- `add_paycheck()` handles `POST /api/paychecks/add`.
- `list_paychecks()` handles `GET /api/paychecks`.
- `revert_paycheck()` handles `POST /api/paychecks/{paycheck_id}/revert`.
- `AddPaycheckIn` is the request model.

Behavior:

- Adds net pay to the paycheck profile's default deposit account.
- Allocates paycheck money into active chunks assigned to the selected paycheck profile, in chunk order.
- Standard chunk allocations in another account automatically move that amount from the paycheck's default account into the chunk's account.
- Custom reviewed allocations cannot exceed each chunk's configured amount or the paycheck total.
- Loan allocations are capped at the remaining loan balance.
- Remaining money becomes unallocated in the paycheck's default account.
- Every paycheck remains as a dated record with its exact chunk allocations and revert status.
- Reverting reverses the paycheck's account and standard chunk effects. Loan balances are restored only when they have not changed since that paycheck.

Database:

- `paychecks.reverted_at` records when a paycheck was reverted.
- `paycheck_allocations` stores the allocation account, chunk name, and before/after standard or loan balances needed for details and safe revert behavior.

## Accounts

Frontend:

- `AccountsScreen` lists accounts and supports select mode, reorder, delete, and move chunks.
- `_AccountCreateCard` creates a new account.
- `showAccountDialog()` edits account details.
- `confirmDeleteAccount()` confirms account deletion.

Backend:

- `list_accounts()` handles `GET /api/accounts`.
- `create_account()` handles `POST /api/accounts`.
- `reorder_accounts()` handles `PUT /api/accounts/reorder`.
- `update_account()` handles `PUT /api/accounts/{account_id}`.
- `delete_account()` handles `DELETE /api/accounts/{account_id}`.
- `move_account_chunks()` handles `POST /api/accounts/{account_id}/move-chunks`.
- `AccountIn`, `ReorderAccountsIn`, and `MoveAccountChunksIn` are request models.

Important rules:

- Accounts can be manual or bank-connected.
- Zero-balance accounts can be deleted if chunks are moved first.
- Account transaction/transfer logs are retained where designed for cash-flow history.

## Chunks

Frontend:

- `ChunksScreen` lists chunks and opens chunk creation/edit dialogs.
- `ChunksScreen` supports select/delete mode. Deleting a chunk archives it, zeroes its allocated balance, and hides it from active chunk lists. This returns that amount to the account's computed unallocated balance while preserving historical references.
- Chunk rows can be opened to rename chunks, change account, change amount per paycheck, and edit loan settings. A chunk's type cannot be changed after creation.
- Chunks with an amount per paycheck greater than zero must be assigned to a paycheck profile.
- `showChunkDialog()` creates or edits a chunk.

Backend:

- `list_chunks()` handles `GET /api/chunks`.
- `create_chunk()` handles `POST /api/chunks`.
- `update_chunk()` handles `PUT /api/chunks/{chunk_id}`.
- `delete_chunk()` handles `DELETE /api/chunks/{chunk_id}`.
- `ChunkIn` is the request model.

Important rules:

- Chunks belong to one account.
- Chunks can be assigned to one paycheck profile. Add Paycheck only funds chunks assigned to the selected paycheck profile.
- Chunk balances contribute to account allocated balance.
- Account unallocated balance is account balance minus active chunk balances.
- Standard chunks track allocated budget money.
- Loan chunks are beta. They do not expose or count against a budget account/chunk allocation balance.
- Loan chunks support an optional current loan balance and APR. The displayed loan chunk balance is the remaining amount owed.
- During paycheck allocation, the app applies one pay-period of interest and then subtracts the chunk payment from the loan balance.
- Transfers cannot originate from loan chunks.
- Transfers to loan chunks reduce the remaining loan balance and reduce the paying account balance.

## Transfers

Frontend:

- `TransfersScreen` creates and lists money movements.
- `_TransfersScreenState` manages transfer type, source, destination, amount, note, source/destination balance hints, and client-side amount validation.
- Transfer history rows call `showTransferDetails()`.
- `showTransferDetails()` opens a details dialog from Dashboard or Transfers.
- `movementEndpointName()` converts source/destination IDs into readable account/chunk labels.
- `_BalanceHint` displays current source/destination balances.
- New transfer records store source/destination balance before and after the movement. Older transfers show `Not recorded`.

Backend:

- `create_money_movement()` handles `POST /api/money-movements`.
- `list_money_movements()` handles `GET /api/money-movements`.
- `MoneyMovementIn` is the request model.

Transfer types:

- `allocation`: moves money between chunks and unallocated balances without changing account balances.
- `manual_account_transfer`: moves unallocated money between manually managed accounts and changes those manual account balances.

Important rules:

- Unallocated-to-chunk must stay within the same account.
- Chunk-to-unallocated returns money to the chunk's account.
- Chunk-to-chunk across accounts requires the destination account to already have enough unallocated balance.
- Transfer amount cannot exceed the source available amount.
- Transfers to a loan chunk are automatically capped at its remaining loan balance, including zero.
- Backend enforces balance rules even if frontend validation misses something.

## Transactions

Frontend:

- `TransactionsScreen` records money entering or leaving an account from outside the budget.

Backend:

- `list_transactions()` handles `GET /api/transactions`.
- `create_transaction()` handles `POST /api/transactions`.
- `TransactionIn` is the request model.

Difference from transfers:

- Transactions represent outside-world activity such as purchases, deposits, fees, or income.
- Transfers move existing tracked money between budget locations.

## Settings

Frontend:

- `SettingsScreen` manages users and invitations for the selected budget profile.
- `_SettingsCard` frames settings sections.

Backend:

- `list_users()` and `create_user()` support basic user creation/listing.
- `list_budget_profile_members()` lists profile access.
- `invite_budget_profile_member()` creates invitations.
- `list_invitations()` lists invitations.
- `accept_invitation()` accepts an invitation.

## Shared Frontend Widgets And Helpers

Shared widgets:

- `_Page` provides consistent page title/action layout.
- `_ResponsiveGrid` lays metric cards out responsively.
- `_MetricCard` displays dashboard/overview metrics.
- `_DataCard` frames lists and empty states.
- `_ListRow` renders list rows and optional tap/click chevron behavior.
- `_FormCard` frames standard forms and applies reading-order focus traversal.
- `_SectionTitle` renders section headers.
- `_Notice` renders yellow warning/help messages.
- `_BalanceHint` renders gray balance context under transfer selectors.
- `_DetailLine` renders label/value lines in dialogs.
- `_MoneyField` is the shared money input and restricts input to `[0-9.]`.
- `_MoneyField`, `_DropdownField`, and `_EntityDropdown` support inline validation error text.
- `_SubmitButton` is the shared saving-aware submit button.
- `_ErrorView` renders retryable load errors.

Shared helpers:

- `listOfMaps()` safely casts decoded JSON lists.
- `parseMoney()` converts UI money strings to numeric values.
- `movementLabel()` creates display labels for movement values.
- `money()` formats numbers in Excel-like accounting style.
- `formatDateTime()` formats ISO timestamps for display.
- `showTransferDetails()` shows transfer detail dialogs.
- `movementEndpointName()` maps transfer endpoint IDs to user-readable names.
- `toast()` shows a snackbar.

## Backend Helper Functions

File: `backend/app/main.py`

Database and security helpers:

- `_database_path()` resolves SQLite file path from `DATABASE_URL`.
- `db()` opens SQLite connections with foreign keys enabled.
- `now()` returns current UTC timestamp.
- `hash_password()` hashes passwords with PBKDF2-HMAC-SHA256.
- `verify_password()` checks passwords.
- `row_to_dict()` and `rows_to_dicts()` convert SQLite rows to dictionaries.
- `init_db()` creates tables and runs migrations.
- `column_exists()` checks table columns.
- `table_sql()` reads SQLite table creation SQL.
- `migrate_db()` applies schema migrations.
- `startup()` runs database initialization on FastAPI startup.

Lookup and permission helpers:

- `get_account_or_404()` fetches an account or raises 404.
- `get_chunk_or_404()` fetches a chunk or raises 404.
- `get_profile_or_404()` fetches a budget profile or raises 404.
- `require_profile_admin()` checks whether a user has admin access.
- `account_summaries()` returns accounts with allocated/unallocated balances.
- `account_summary()` returns one summarized account.

Request models:

- `AccountIn`
- `UserIn`
- `LoginIn`
- `RegisterIn`
- `BudgetProfileIn`
- `ReorderProfilesIn`
- `MoveAccountChunksIn`
- `ReorderAccountsIn`
- `InvitationIn`
- `AcceptInvitationIn`
- `PaycheckProfileIn`
- `ChunkIn`
- `AddPaycheckIn`
- `MoneyMovementIn`
- `TransactionIn`

## Backend Route Groups

Health:

- `health()` handles `GET /api/health`.

Users/auth:

- `list_users()`
- `create_user()`
- `register()`
- `login()`

Budget profiles/access:

- `list_budget_profiles()`
- `create_budget_profile()`
- `reorder_budget_profiles()`
- `delete_budget_profile()`
- `list_budget_profile_members()`
- `invite_budget_profile_member()`
- `list_invitations()`
- `accept_invitation()`

Dashboard:

- `dashboard_summary()`

Accounts:

- `list_accounts()`
- `create_account()`
- `reorder_accounts()`
- `update_account()`
- `delete_account()`
- `move_account_chunks()`

Paycheck profiles and paychecks:

- `get_paycheck_profile()`
- `list_paycheck_profiles()`
- `upsert_paycheck_profile()`
- `delete_paycheck_profile()`
- `add_paycheck()`
- `list_paychecks()`

Chunks:

- `list_chunks()`
- `create_chunk()`
- `update_chunk()`
- `delete_chunk()`

Money movements/transfers:

- `create_money_movement()`
- `list_money_movements()`

Transactions:

- `list_transactions()`
- `create_transaction()`

## Common Development Checks

Run these before pushing:

```bash
python3 -m py_compile backend/app/main.py
flutter analyze
flutter test
flutter build web --release
```

For database migration checks, use the project virtualenv because system Python may not have FastAPI installed:

```bash
DATABASE_URL=sqlite:////private/tmp/chunkycat-smoke.db .venv/bin/python -c "from backend.app.main import init_db; init_db(); print('ok')"
```
