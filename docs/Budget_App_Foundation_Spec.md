# Budget App Foundation Scope

## Core Budgeting System

This app is a paycheck-based budgeting system.

The user enters:
- Gross pay amount
- Net pay amount, either manually entered or estimated later
- Pay frequency

Supported pay frequencies:
- weekly
- biweekly
- semimonthly
- monthly
- custom

Every budget chunk applies once per paycheck.

## Main Money Buckets

The system tracks money in three major places:
- accounts
- chunks
- unallocated money

An account represents a real-world account.
A chunk represents a planned purpose for money.
Unallocated money represents money inside an account that has not yet been assigned to a chunk.

## Account and Chunk Rules

Each chunk belongs to exactly one tracked account.

The app should show:
- Account balance
- Total allocated to chunks
- Unallocated balance

Formula:

unallocated_balance = account_balance - sum(chunk balances assigned to that account)

## Paycheck Setup

Create a paycheck profile with:
- gross_pay_amount
- net_pay_amount
- net_pay_mode
- pay_frequency

## Adding a Paycheck

The user should have an Add Paycheck action.

The modal should ask:
- Use expected net pay
- Use custom amount

When the paycheck is added, the app automatically applies each active chunk once.

The remaining money becomes unallocated money.

## Transfers

A transfer can move money from:
- chunk
- unallocated money
- paycheck

A transfer can move money to:
- chunk
- account
- unallocated money
- outside account

Transfers should be logged.

## Bank-Connected Future Flow

Future versions may connect to banks and import transactions automatically.

Imported transactions should be allocatable to:
- chunks
- unallocated money
- outside accounts

## Core Database Tables

- users
- accounts
- paycheck_profiles
- budget_chunks
- paychecks
- paycheck_allocations
- money_movements
- transactions
- bank_connections_future

## API Routes

- GET /api/health
- GET /api/dashboard/summary

Accounts:
- GET /api/accounts
- POST /api/accounts
- PUT /api/accounts/{id}

Paycheck Profiles:
- GET /api/paycheck-profile
- POST /api/paycheck-profile
- PUT /api/paycheck-profile

Chunks:
- GET /api/chunks
- POST /api/chunks
- PUT /api/chunks/{id}
- DELETE /api/chunks/{id}

Paychecks:
- POST /api/paychecks/add
- GET /api/paychecks

Money Movements:
- POST /api/money-movements
- GET /api/money-movements

Transactions:
- GET /api/transactions
- POST /api/transactions

## Temporary GUI Structure

Required screens:
- Dashboard
- Paycheck Setup
- Accounts
- Chunks
- Add Paycheck
- Transfers / Money Movement
- Transactions
- Settings

Desktop:
- Sidebar navigation
- Dashboard cards
- Tables

Mobile:
- Bottom navigation
- Stacked cards
- Large Add Paycheck button
- Large Transfer button

## First Build Milestone

1. GitHub-ready repo structure
2. Flutter frontend foundation
3. FastAPI backend foundation
4. SQLite integration
5. Dockerfile for unRAID
6. docker-compose.yml
7. Persistent database volume
8. Dashboard
9. Account creation
10. Chunk creation
11. Add Paycheck flow
12. Automatic allocation
13. Unallocated money tracking
14. Transfer system
15. Responsive temporary GUI

## Product Direction

Workflow:

1. Set pay frequency
2. Enter expected paycheck
3. Create chunks that apply once per paycheck
4. Assign chunks to accounts
5. Add paycheck
6. Automatically allocate paycheck money
7. Track allocated vs unallocated money
8. Move money between chunks/accounts/outside accounts
9. Later connect bank data and allocate real transactions
