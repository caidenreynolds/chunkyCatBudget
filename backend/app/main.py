from __future__ import annotations

import os
import sqlite3
from contextlib import contextmanager
from datetime import datetime, timezone
from pathlib import Path
from typing import Any, Literal

from fastapi import FastAPI, HTTPException
from fastapi.middleware.cors import CORSMiddleware
from pydantic import BaseModel, Field


DATABASE_URL = os.getenv("DATABASE_URL", "sqlite:///./backend/data/budget.db")


def _database_path() -> Path:
    if not DATABASE_URL.startswith("sqlite:///"):
        raise RuntimeError("Only sqlite:/// DATABASE_URL values are supported")
    path = Path(DATABASE_URL.removeprefix("sqlite:///"))
    if not path.is_absolute():
        path = Path.cwd() / path
    path.parent.mkdir(parents=True, exist_ok=True)
    return path


@contextmanager
def db() -> Any:
    conn = sqlite3.connect(_database_path())
    conn.row_factory = sqlite3.Row
    conn.execute("PRAGMA foreign_keys = ON")
    try:
        yield conn
        conn.commit()
    finally:
        conn.close()


def now() -> str:
    return datetime.now(timezone.utc).isoformat()


def row_to_dict(row: sqlite3.Row | None) -> dict[str, Any] | None:
    return dict(row) if row else None


def rows_to_dicts(rows: list[sqlite3.Row]) -> list[dict[str, Any]]:
    return [dict(row) for row in rows]


class AccountIn(BaseModel):
    name: str = Field(min_length=1)
    balance: float = 0
    type: str = "checking"
    is_active: bool = True


class PaycheckProfileIn(BaseModel):
    gross_pay_amount: float = Field(ge=0)
    net_pay_amount: float = Field(ge=0)
    net_pay_mode: Literal["manual", "expected", "estimated"] = "expected"
    pay_frequency: Literal["weekly", "biweekly", "semimonthly", "monthly", "custom"]


class ChunkIn(BaseModel):
    name: str = Field(min_length=1)
    account_id: int
    amount_per_paycheck: float = Field(ge=0)
    balance: float = Field(default=0, ge=0)
    is_active: bool = True


class AddPaycheckIn(BaseModel):
    amount_mode: Literal["expected", "custom"] = "expected"
    custom_amount: float | None = Field(default=None, ge=0)
    account_id: int | None = None


class MoneyMovementIn(BaseModel):
    source_type: Literal["chunk", "unallocated", "paycheck"]
    source_id: int | None = None
    destination_type: Literal["chunk", "account", "unallocated", "outside_account"]
    destination_id: int | None = None
    amount: float = Field(gt=0)
    note: str = ""


class TransactionIn(BaseModel):
    account_id: int
    amount: float
    description: str = ""
    allocation_type: Literal["chunk", "unallocated", "outside_account"] = "unallocated"
    allocation_id: int | None = None


app = FastAPI(title="Chunky Cat Budget API", version="0.1.0")
app.add_middleware(
    CORSMiddleware,
    allow_origins=os.getenv("CORS_ORIGINS", "*").split(","),
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)


def init_db() -> None:
    with db() as conn:
        conn.executescript(
            """
            CREATE TABLE IF NOT EXISTS users (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                email TEXT UNIQUE,
                created_at TEXT NOT NULL
            );

            CREATE TABLE IF NOT EXISTS accounts (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                name TEXT NOT NULL,
                type TEXT NOT NULL DEFAULT 'checking',
                balance REAL NOT NULL DEFAULT 0,
                is_active INTEGER NOT NULL DEFAULT 1,
                created_at TEXT NOT NULL,
                updated_at TEXT NOT NULL
            );

            CREATE TABLE IF NOT EXISTS paycheck_profiles (
                id INTEGER PRIMARY KEY CHECK (id = 1),
                gross_pay_amount REAL NOT NULL,
                net_pay_amount REAL NOT NULL,
                net_pay_mode TEXT NOT NULL,
                pay_frequency TEXT NOT NULL,
                updated_at TEXT NOT NULL
            );

            CREATE TABLE IF NOT EXISTS budget_chunks (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                name TEXT NOT NULL,
                account_id INTEGER NOT NULL REFERENCES accounts(id),
                amount_per_paycheck REAL NOT NULL,
                balance REAL NOT NULL DEFAULT 0,
                is_active INTEGER NOT NULL DEFAULT 1,
                created_at TEXT NOT NULL,
                updated_at TEXT NOT NULL
            );

            CREATE TABLE IF NOT EXISTS paychecks (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                account_id INTEGER NOT NULL REFERENCES accounts(id),
                gross_amount REAL NOT NULL,
                net_amount REAL NOT NULL,
                amount_mode TEXT NOT NULL,
                created_at TEXT NOT NULL
            );

            CREATE TABLE IF NOT EXISTS paycheck_allocations (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                paycheck_id INTEGER NOT NULL REFERENCES paychecks(id),
                chunk_id INTEGER NOT NULL REFERENCES budget_chunks(id),
                amount REAL NOT NULL,
                created_at TEXT NOT NULL
            );

            CREATE TABLE IF NOT EXISTS money_movements (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                source_type TEXT NOT NULL,
                source_id INTEGER,
                destination_type TEXT NOT NULL,
                destination_id INTEGER,
                amount REAL NOT NULL,
                note TEXT NOT NULL DEFAULT '',
                created_at TEXT NOT NULL
            );

            CREATE TABLE IF NOT EXISTS transactions (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                account_id INTEGER NOT NULL REFERENCES accounts(id),
                amount REAL NOT NULL,
                description TEXT NOT NULL DEFAULT '',
                allocation_type TEXT NOT NULL,
                allocation_id INTEGER,
                created_at TEXT NOT NULL
            );

            CREATE TABLE IF NOT EXISTS bank_connections_future (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                provider TEXT NOT NULL,
                status TEXT NOT NULL,
                metadata_json TEXT NOT NULL DEFAULT '{}',
                created_at TEXT NOT NULL
            );
            """
        )


@app.on_event("startup")
def startup() -> None:
    init_db()


def get_account_or_404(conn: sqlite3.Connection, account_id: int) -> sqlite3.Row:
    account = conn.execute("SELECT * FROM accounts WHERE id = ?", (account_id,)).fetchone()
    if not account:
        raise HTTPException(status_code=404, detail="Account not found")
    return account


def get_chunk_or_404(conn: sqlite3.Connection, chunk_id: int) -> sqlite3.Row:
    chunk = conn.execute("SELECT * FROM budget_chunks WHERE id = ?", (chunk_id,)).fetchone()
    if not chunk:
        raise HTTPException(status_code=404, detail="Chunk not found")
    return chunk


def account_summaries(conn: sqlite3.Connection) -> list[dict[str, Any]]:
    rows = conn.execute(
        """
        SELECT
            a.*,
            COALESCE(SUM(CASE WHEN c.is_active = 1 THEN c.balance ELSE 0 END), 0) AS allocated_balance
        FROM accounts a
        LEFT JOIN budget_chunks c ON c.account_id = a.id
        GROUP BY a.id
        ORDER BY a.name
        """
    ).fetchall()
    summaries = []
    for row in rows:
        item = dict(row)
        item["is_active"] = bool(item["is_active"])
        item["unallocated_balance"] = item["balance"] - item["allocated_balance"]
        summaries.append(item)
    return summaries


def account_summary(conn: sqlite3.Connection, account_id: int) -> dict[str, Any] | None:
    return next((account for account in account_summaries(conn) if account["id"] == account_id), None)


@app.get("/api/health")
def health() -> dict[str, str]:
    return {"status": "ok"}


@app.get("/api/dashboard/summary")
def dashboard_summary() -> dict[str, Any]:
    with db() as conn:
        accounts = account_summaries(conn)
        chunks = rows_to_dicts(
            conn.execute(
                """
                SELECT c.*, a.name AS account_name
                FROM budget_chunks c
                JOIN accounts a ON a.id = c.account_id
                ORDER BY c.name
                """
            ).fetchall()
        )
        for chunk in chunks:
            chunk["is_active"] = bool(chunk["is_active"])
        movements = rows_to_dicts(
            conn.execute("SELECT * FROM money_movements ORDER BY created_at DESC LIMIT 8").fetchall()
        )
        paychecks = rows_to_dicts(
            conn.execute("SELECT * FROM paychecks ORDER BY created_at DESC LIMIT 5").fetchall()
        )
        return {
            "totals": {
                "account_balance": sum(a["balance"] for a in accounts),
                "allocated_balance": sum(a["allocated_balance"] for a in accounts),
                "unallocated_balance": sum(a["unallocated_balance"] for a in accounts),
            },
            "accounts": accounts,
            "chunks": chunks,
            "recent_money_movements": movements,
            "recent_paychecks": paychecks,
            "paycheck_profile": row_to_dict(
                conn.execute("SELECT * FROM paycheck_profiles WHERE id = 1").fetchone()
            ),
        }


@app.get("/api/accounts")
def list_accounts() -> list[dict[str, Any]]:
    with db() as conn:
        return account_summaries(conn)


@app.post("/api/accounts")
def create_account(payload: AccountIn) -> dict[str, Any]:
    stamp = now()
    with db() as conn:
        cursor = conn.execute(
            """
            INSERT INTO accounts (name, type, balance, is_active, created_at, updated_at)
            VALUES (?, ?, ?, ?, ?, ?)
            """,
            (payload.name, payload.type, payload.balance, int(payload.is_active), stamp, stamp),
        )
        return next(a for a in account_summaries(conn) if a["id"] == cursor.lastrowid)


@app.put("/api/accounts/{account_id}")
def update_account(account_id: int, payload: AccountIn) -> dict[str, Any]:
    with db() as conn:
        get_account_or_404(conn, account_id)
        conn.execute(
            """
            UPDATE accounts
            SET name = ?, type = ?, balance = ?, is_active = ?, updated_at = ?
            WHERE id = ?
            """,
            (payload.name, payload.type, payload.balance, int(payload.is_active), now(), account_id),
        )
        return next(a for a in account_summaries(conn) if a["id"] == account_id)


@app.get("/api/paycheck-profile")
def get_paycheck_profile() -> dict[str, Any] | None:
    with db() as conn:
        return row_to_dict(conn.execute("SELECT * FROM paycheck_profiles WHERE id = 1").fetchone())


@app.post("/api/paycheck-profile")
@app.put("/api/paycheck-profile")
def upsert_paycheck_profile(payload: PaycheckProfileIn) -> dict[str, Any]:
    with db() as conn:
        conn.execute(
            """
            INSERT INTO paycheck_profiles
                (id, gross_pay_amount, net_pay_amount, net_pay_mode, pay_frequency, updated_at)
            VALUES (1, ?, ?, ?, ?, ?)
            ON CONFLICT(id) DO UPDATE SET
                gross_pay_amount = excluded.gross_pay_amount,
                net_pay_amount = excluded.net_pay_amount,
                net_pay_mode = excluded.net_pay_mode,
                pay_frequency = excluded.pay_frequency,
                updated_at = excluded.updated_at
            """,
            (
                payload.gross_pay_amount,
                payload.net_pay_amount,
                payload.net_pay_mode,
                payload.pay_frequency,
                now(),
            ),
        )
        return row_to_dict(conn.execute("SELECT * FROM paycheck_profiles WHERE id = 1").fetchone())


@app.get("/api/chunks")
def list_chunks() -> list[dict[str, Any]]:
    with db() as conn:
        chunks = rows_to_dicts(
            conn.execute(
                """
                SELECT c.*, a.name AS account_name
                FROM budget_chunks c
                JOIN accounts a ON a.id = c.account_id
                ORDER BY c.name
                """
            ).fetchall()
        )
        for chunk in chunks:
            chunk["is_active"] = bool(chunk["is_active"])
        return chunks


@app.post("/api/chunks")
def create_chunk(payload: ChunkIn) -> dict[str, Any]:
    stamp = now()
    with db() as conn:
        get_account_or_404(conn, payload.account_id)
        cursor = conn.execute(
            """
            INSERT INTO budget_chunks
                (name, account_id, amount_per_paycheck, balance, is_active, created_at, updated_at)
            VALUES (?, ?, ?, ?, ?, ?, ?)
            """,
            (
                payload.name,
                payload.account_id,
                payload.amount_per_paycheck,
                payload.balance,
                int(payload.is_active),
                stamp,
                stamp,
            ),
        )
        chunk = conn.execute(
            """
            SELECT c.*, a.name AS account_name
            FROM budget_chunks c
            JOIN accounts a ON a.id = c.account_id
            WHERE c.id = ?
            """,
            (cursor.lastrowid,),
        ).fetchone()
        result = dict(chunk)
        result["is_active"] = bool(result["is_active"])
        return result


@app.put("/api/chunks/{chunk_id}")
def update_chunk(chunk_id: int, payload: ChunkIn) -> dict[str, Any]:
    with db() as conn:
        get_chunk_or_404(conn, chunk_id)
        get_account_or_404(conn, payload.account_id)
        conn.execute(
            """
            UPDATE budget_chunks
            SET name = ?, account_id = ?, amount_per_paycheck = ?, balance = ?,
                is_active = ?, updated_at = ?
            WHERE id = ?
            """,
            (
                payload.name,
                payload.account_id,
                payload.amount_per_paycheck,
                payload.balance,
                int(payload.is_active),
                now(),
                chunk_id,
            ),
        )
        chunk = conn.execute(
            """
            SELECT c.*, a.name AS account_name
            FROM budget_chunks c
            JOIN accounts a ON a.id = c.account_id
            WHERE c.id = ?
            """,
            (chunk_id,),
        ).fetchone()
        result = dict(chunk)
        result["is_active"] = bool(result["is_active"])
        return result


@app.delete("/api/chunks/{chunk_id}")
def delete_chunk(chunk_id: int) -> dict[str, bool]:
    with db() as conn:
        get_chunk_or_404(conn, chunk_id)
        conn.execute("DELETE FROM budget_chunks WHERE id = ?", (chunk_id,))
        return {"deleted": True}


@app.post("/api/paychecks/add")
def add_paycheck(payload: AddPaycheckIn) -> dict[str, Any]:
    with db() as conn:
        profile = conn.execute("SELECT * FROM paycheck_profiles WHERE id = 1").fetchone()
        if not profile:
            raise HTTPException(status_code=400, detail="Create a paycheck profile first")
        account_id = payload.account_id
        if account_id is None:
            account = conn.execute("SELECT * FROM accounts WHERE is_active = 1 ORDER BY id LIMIT 1").fetchone()
            if not account:
                raise HTTPException(status_code=400, detail="Create an account first")
            account_id = account["id"]
        get_account_or_404(conn, account_id)
        net_amount = profile["net_pay_amount"] if payload.amount_mode == "expected" else payload.custom_amount
        if net_amount is None:
            raise HTTPException(status_code=400, detail="Custom amount is required")

        stamp = now()
        cursor = conn.execute(
            """
            INSERT INTO paychecks (account_id, gross_amount, net_amount, amount_mode, created_at)
            VALUES (?, ?, ?, ?, ?)
            """,
            (account_id, profile["gross_pay_amount"], net_amount, payload.amount_mode, stamp),
        )
        paycheck_id = cursor.lastrowid
        conn.execute("UPDATE accounts SET balance = balance + ?, updated_at = ? WHERE id = ?", (net_amount, stamp, account_id))

        chunks = conn.execute(
            "SELECT * FROM budget_chunks WHERE account_id = ? AND is_active = 1 ORDER BY id", (account_id,)
        ).fetchall()
        remaining = float(net_amount)
        allocations = []
        for chunk in chunks:
            amount = min(float(chunk["amount_per_paycheck"]), remaining)
            if amount <= 0:
                break
            conn.execute("UPDATE budget_chunks SET balance = balance + ?, updated_at = ? WHERE id = ?", (amount, stamp, chunk["id"]))
            conn.execute(
                """
                INSERT INTO paycheck_allocations (paycheck_id, chunk_id, amount, created_at)
                VALUES (?, ?, ?, ?)
                """,
                (paycheck_id, chunk["id"], amount, stamp),
            )
            allocations.append({"chunk_id": chunk["id"], "chunk_name": chunk["name"], "amount": amount})
            remaining -= amount

        paycheck = row_to_dict(conn.execute("SELECT * FROM paychecks WHERE id = ?", (paycheck_id,)).fetchone())
        return {"paycheck": paycheck, "allocations": allocations, "unallocated_amount": remaining}


@app.get("/api/paychecks")
def list_paychecks() -> list[dict[str, Any]]:
    with db() as conn:
        return rows_to_dicts(conn.execute("SELECT * FROM paychecks ORDER BY created_at DESC").fetchall())


@app.post("/api/money-movements")
def create_money_movement(payload: MoneyMovementIn) -> dict[str, Any]:
    with db() as conn:
        stamp = now()
        source_account_id: int | None = None
        destination_id = payload.destination_id

        if payload.source_type == "paycheck":
            raise HTTPException(
                status_code=400,
                detail="Paycheck money enters the budget through Add Paycheck, then can be allocated from unallocated money or chunks.",
            )

        if payload.source_type == "chunk":
            if payload.source_id is None:
                raise HTTPException(status_code=400, detail="source_id is required for chunk transfers")
            source_chunk = get_chunk_or_404(conn, payload.source_id)
            source_account_id = source_chunk["account_id"]
            if source_chunk["balance"] < payload.amount:
                raise HTTPException(status_code=400, detail="Chunk does not have enough allocated money")
            conn.execute(
                "UPDATE budget_chunks SET balance = balance - ?, updated_at = ? WHERE id = ?",
                (payload.amount, stamp, payload.source_id),
            )
        elif payload.source_type == "unallocated":
            if payload.source_id is None:
                raise HTTPException(status_code=400, detail="source_id must be the source account for unallocated transfers")
            source_account_id = payload.source_id
            source = account_summary(conn, payload.source_id)
            if not source:
                raise HTTPException(status_code=404, detail="Source account not found")
            if source["unallocated_balance"] < payload.amount:
                raise HTTPException(status_code=400, detail="Account does not have enough unallocated money")

        if payload.destination_type == "chunk":
            if payload.destination_id is None:
                raise HTTPException(status_code=400, detail="destination_id is required for chunk transfers")
            destination_chunk = get_chunk_or_404(conn, payload.destination_id)
            destination_account_id = destination_chunk["account_id"]
            if payload.source_type == "unallocated" and source_account_id != destination_account_id:
                raise HTTPException(
                    status_code=400,
                    detail="Unallocated money can only be assigned to chunks in the same account",
                )
            if payload.source_type == "chunk" and source_account_id != destination_account_id:
                destination = account_summary(conn, destination_account_id)
                if not destination or destination["unallocated_balance"] < payload.amount:
                    raise HTTPException(
                        status_code=400,
                        detail="Destination account needs enough unallocated money before a cross-account chunk transfer can be logged",
                    )
            conn.execute(
                "UPDATE budget_chunks SET balance = balance + ?, updated_at = ? WHERE id = ?",
                (payload.amount, stamp, payload.destination_id),
            )
        elif payload.destination_type == "account":
            if payload.destination_id is None:
                raise HTTPException(status_code=400, detail="destination_id is required to log an account destination")
            get_account_or_404(conn, payload.destination_id)
            if source_account_id != payload.destination_id:
                destination = account_summary(conn, payload.destination_id)
                if not destination or destination["unallocated_balance"] < payload.amount:
                    raise HTTPException(
                        status_code=400,
                        detail="Destination account balance must already reflect the bank/account transfer before it can be logged",
                    )
        elif payload.destination_type == "unallocated":
            if payload.source_type == "chunk":
                if destination_id is None:
                    destination_id = source_account_id
                if destination_id != source_account_id:
                    raise HTTPException(
                        status_code=400,
                        detail="Chunk money returns to unallocated money in the chunk account",
                    )
            elif payload.source_type == "unallocated":
                if destination_id is None:
                    destination_id = source_account_id
                if destination_id != source_account_id:
                    raise HTTPException(
                        status_code=400,
                        detail="Unallocated money cannot be logically moved to another account without a bank/account transfer first",
                    )
        elif payload.destination_type == "outside_account":
            pass

        cursor = conn.execute(
            """
            INSERT INTO money_movements
                (source_type, source_id, destination_type, destination_id, amount, note, created_at)
            VALUES (?, ?, ?, ?, ?, ?, ?)
            """,
            (
                payload.source_type,
                payload.source_id,
                payload.destination_type,
                destination_id,
                payload.amount,
                payload.note,
                stamp,
            ),
        )
        return row_to_dict(conn.execute("SELECT * FROM money_movements WHERE id = ?", (cursor.lastrowid,)).fetchone())


@app.get("/api/money-movements")
def list_money_movements() -> list[dict[str, Any]]:
    with db() as conn:
        return rows_to_dicts(conn.execute("SELECT * FROM money_movements ORDER BY created_at DESC").fetchall())


@app.get("/api/transactions")
def list_transactions() -> list[dict[str, Any]]:
    with db() as conn:
        return rows_to_dicts(conn.execute("SELECT * FROM transactions ORDER BY created_at DESC").fetchall())


@app.post("/api/transactions")
def create_transaction(payload: TransactionIn) -> dict[str, Any]:
    with db() as conn:
        get_account_or_404(conn, payload.account_id)
        cursor = conn.execute(
            """
            INSERT INTO transactions
                (account_id, amount, description, allocation_type, allocation_id, created_at)
            VALUES (?, ?, ?, ?, ?, ?)
            """,
            (
                payload.account_id,
                payload.amount,
                payload.description,
                payload.allocation_type,
                payload.allocation_id,
                now(),
            ),
        )
        conn.execute("UPDATE accounts SET balance = balance + ?, updated_at = ? WHERE id = ?", (payload.amount, now(), payload.account_id))
        return row_to_dict(conn.execute("SELECT * FROM transactions WHERE id = ?", (cursor.lastrowid,)).fetchone())
