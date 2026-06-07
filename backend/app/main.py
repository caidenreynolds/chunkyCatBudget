from __future__ import annotations

import os
import hashlib
import hmac
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


def hash_password(password: str, salt_hex: str | None = None) -> tuple[str, str]:
    salt = bytes.fromhex(salt_hex) if salt_hex else os.urandom(16)
    password_hash = hashlib.pbkdf2_hmac("sha256", password.encode("utf-8"), salt, 210_000)
    return salt.hex(), password_hash.hex()


def verify_password(password: str, salt_hex: str, hash_hex: str) -> bool:
    _, candidate_hash = hash_password(password, salt_hex)
    return hmac.compare_digest(candidate_hash, hash_hex)


def row_to_dict(row: sqlite3.Row | None) -> dict[str, Any] | None:
    return dict(row) if row else None


def rows_to_dicts(rows: list[sqlite3.Row]) -> list[dict[str, Any]]:
    return [dict(row) for row in rows]


class AccountIn(BaseModel):
    name: str = Field(min_length=1)
    balance: float = 0
    type: str = "checking"
    source_mode: Literal["manual", "bank_connected"] = "manual"
    is_active: bool = True


class UserIn(BaseModel):
    email: str = Field(min_length=3)
    display_name: str = Field(default="", max_length=120)
    password: str | None = Field(default=None, min_length=8)


class LoginIn(BaseModel):
    email: str = Field(min_length=3)
    password: str = Field(min_length=8)


class RegisterIn(BaseModel):
    email: str = Field(min_length=3)
    display_name: str = Field(default="", max_length=120)
    password: str = Field(min_length=8)


class BudgetProfileIn(BaseModel):
    name: str = Field(min_length=1)
    owner_user_id: int


class ReorderProfilesIn(BaseModel):
    user_id: int
    profile_ids: list[int]


class MoveAccountChunksIn(BaseModel):
    destination_account_id: int


class ReorderAccountsIn(BaseModel):
    account_ids: list[int]


class InvitationIn(BaseModel):
    email: str = Field(min_length=3)
    role: Literal["admin", "read_only"]
    invited_by_user_id: int


class AcceptInvitationIn(BaseModel):
    user_id: int


class PaycheckProfileIn(BaseModel):
    id: int | None = None
    name: str = "Paycheck"
    gross_pay_amount: float | None = Field(default=None, ge=0)
    net_pay_amount: float = Field(gt=0)
    net_pay_mode: Literal["manual", "expected", "estimated"] = "expected"
    pay_frequency: Literal["weekly", "biweekly", "semimonthly", "monthly", "custom"]
    default_account_id: int | None = None


class ChunkIn(BaseModel):
    name: str = Field(min_length=1)
    account_id: int | None = None
    chunk_type: Literal["standard", "loan"] = "standard"
    amount_per_paycheck: float = Field(ge=0)
    balance: float = Field(default=0, ge=0)
    loan_balance: float | None = Field(default=None, ge=0)
    loan_interest_rate: float | None = Field(default=None, ge=0)
    is_active: bool = True


class AddPaycheckIn(BaseModel):
    paycheck_profile_id: int | None = None
    amount_mode: Literal["expected", "custom"] = "expected"
    custom_amount: float | None = Field(default=None, ge=0)
    account_id: int | None = None
    allocations: list["PaycheckAllocationIn"] | None = None


class PaycheckAllocationIn(BaseModel):
    chunk_id: int
    amount: float = Field(ge=0)


class MoneyMovementIn(BaseModel):
    movement_type: Literal["allocation", "manual_account_transfer"] = "allocation"
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
                email TEXT NOT NULL UNIQUE,
                display_name TEXT NOT NULL DEFAULT '',
                password_salt TEXT,
                password_hash TEXT,
                email_verified INTEGER NOT NULL DEFAULT 0,
                created_at TEXT NOT NULL
            );

            CREATE TABLE IF NOT EXISTS budget_profiles (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                name TEXT NOT NULL,
                owner_user_id INTEGER NOT NULL REFERENCES users(id),
                created_at TEXT NOT NULL,
                updated_at TEXT NOT NULL
            );

            CREATE TABLE IF NOT EXISTS user_profile_access (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                user_id INTEGER NOT NULL REFERENCES users(id),
                profile_id INTEGER NOT NULL REFERENCES budget_profiles(id),
                role TEXT NOT NULL CHECK (role IN ('admin', 'read_only')),
                sort_order INTEGER NOT NULL DEFAULT 0,
                created_at TEXT NOT NULL,
                UNIQUE(user_id, profile_id)
            );

            CREATE TABLE IF NOT EXISTS profile_invitations (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                profile_id INTEGER NOT NULL REFERENCES budget_profiles(id),
                email TEXT NOT NULL,
                role TEXT NOT NULL CHECK (role IN ('admin', 'read_only')),
                invited_by_user_id INTEGER NOT NULL REFERENCES users(id),
                accepted_by_user_id INTEGER REFERENCES users(id),
                status TEXT NOT NULL DEFAULT 'pending',
                created_at TEXT NOT NULL,
                accepted_at TEXT
            );

            CREATE TABLE IF NOT EXISTS accounts (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                profile_id INTEGER NOT NULL DEFAULT 1 REFERENCES budget_profiles(id),
                name TEXT NOT NULL,
                type TEXT NOT NULL DEFAULT 'checking',
                source_mode TEXT NOT NULL DEFAULT 'manual',
                balance REAL NOT NULL DEFAULT 0,
                is_active INTEGER NOT NULL DEFAULT 1,
                sort_order INTEGER NOT NULL DEFAULT 0,
                created_at TEXT NOT NULL,
                updated_at TEXT NOT NULL
            );

            CREATE TABLE IF NOT EXISTS paycheck_profiles (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                profile_id INTEGER NOT NULL DEFAULT 1 REFERENCES budget_profiles(id),
                name TEXT NOT NULL DEFAULT 'Paycheck',
                gross_pay_amount REAL NOT NULL,
                net_pay_amount REAL NOT NULL,
                net_pay_mode TEXT NOT NULL,
                pay_frequency TEXT NOT NULL,
                default_account_id INTEGER REFERENCES accounts(id),
                updated_at TEXT NOT NULL
            );

            CREATE TABLE IF NOT EXISTS budget_chunks (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                profile_id INTEGER NOT NULL DEFAULT 1 REFERENCES budget_profiles(id),
                name TEXT NOT NULL,
                account_id INTEGER NOT NULL REFERENCES accounts(id),
                chunk_type TEXT NOT NULL DEFAULT 'standard',
                amount_per_paycheck REAL NOT NULL,
                balance REAL NOT NULL DEFAULT 0,
                loan_balance REAL,
                loan_interest_rate REAL,
                is_active INTEGER NOT NULL DEFAULT 1,
                created_at TEXT NOT NULL,
                updated_at TEXT NOT NULL
            );

            CREATE TABLE IF NOT EXISTS paychecks (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                profile_id INTEGER NOT NULL DEFAULT 1 REFERENCES budget_profiles(id),
                paycheck_profile_id INTEGER REFERENCES paycheck_profiles(id),
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
                profile_id INTEGER NOT NULL DEFAULT 1 REFERENCES budget_profiles(id),
                movement_type TEXT NOT NULL DEFAULT 'allocation',
                source_type TEXT NOT NULL,
                source_id INTEGER,
                destination_type TEXT NOT NULL,
                destination_id INTEGER,
                amount REAL NOT NULL,
                note TEXT NOT NULL DEFAULT '',
                source_balance_before REAL,
                source_balance_after REAL,
                destination_balance_before REAL,
                destination_balance_after REAL,
                created_at TEXT NOT NULL
            );

            CREATE TABLE IF NOT EXISTS transactions (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                profile_id INTEGER NOT NULL DEFAULT 1 REFERENCES budget_profiles(id),
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
        migrate_db(conn)


def column_exists(conn: sqlite3.Connection, table: str, column: str) -> bool:
    return any(row["name"] == column for row in conn.execute(f"PRAGMA table_info({table})").fetchall())


def table_sql(conn: sqlite3.Connection, table: str) -> str:
    row = conn.execute("SELECT sql FROM sqlite_master WHERE type = 'table' AND name = ?", (table,)).fetchone()
    return row["sql"] if row and row["sql"] else ""


def migrate_db(conn: sqlite3.Connection) -> None:
    stamp = now()
    if not column_exists(conn, "users", "display_name"):
        conn.execute("ALTER TABLE users ADD COLUMN display_name TEXT NOT NULL DEFAULT ''")
    if not column_exists(conn, "users", "password_salt"):
        conn.execute("ALTER TABLE users ADD COLUMN password_salt TEXT")
    if not column_exists(conn, "users", "password_hash"):
        conn.execute("ALTER TABLE users ADD COLUMN password_hash TEXT")
    if not column_exists(conn, "users", "email_verified"):
        conn.execute("ALTER TABLE users ADD COLUMN email_verified INTEGER NOT NULL DEFAULT 0")
    if not column_exists(conn, "accounts", "source_mode"):
        conn.execute("ALTER TABLE accounts ADD COLUMN source_mode TEXT NOT NULL DEFAULT 'manual'")
    if not column_exists(conn, "accounts", "sort_order"):
        conn.execute("ALTER TABLE accounts ADD COLUMN sort_order INTEGER NOT NULL DEFAULT 0")
    if not column_exists(conn, "user_profile_access", "sort_order"):
        conn.execute("ALTER TABLE user_profile_access ADD COLUMN sort_order INTEGER NOT NULL DEFAULT 0")
    if not column_exists(conn, "money_movements", "movement_type"):
        conn.execute("ALTER TABLE money_movements ADD COLUMN movement_type TEXT NOT NULL DEFAULT 'allocation'")
    for column in ["source_balance_before", "source_balance_after", "destination_balance_before", "destination_balance_after"]:
        if not column_exists(conn, "money_movements", column):
            conn.execute(f"ALTER TABLE money_movements ADD COLUMN {column} REAL")
    if not column_exists(conn, "budget_chunks", "chunk_type"):
        conn.execute("ALTER TABLE budget_chunks ADD COLUMN chunk_type TEXT NOT NULL DEFAULT 'standard'")
    if not column_exists(conn, "budget_chunks", "loan_balance"):
        conn.execute("ALTER TABLE budget_chunks ADD COLUMN loan_balance REAL")
    if not column_exists(conn, "budget_chunks", "loan_interest_rate"):
        conn.execute("ALTER TABLE budget_chunks ADD COLUMN loan_interest_rate REAL")
    if not column_exists(conn, "paycheck_profiles", "profile_id"):
        conn.execute("ALTER TABLE paycheck_profiles ADD COLUMN profile_id INTEGER NOT NULL DEFAULT 1 REFERENCES budget_profiles(id)")
    if not column_exists(conn, "paycheck_profiles", "name"):
        conn.execute("ALTER TABLE paycheck_profiles ADD COLUMN name TEXT NOT NULL DEFAULT 'Paycheck'")
    if not column_exists(conn, "paycheck_profiles", "default_account_id"):
        conn.execute("ALTER TABLE paycheck_profiles ADD COLUMN default_account_id INTEGER REFERENCES accounts(id)")
    if not column_exists(conn, "paychecks", "paycheck_profile_id"):
        conn.execute("ALTER TABLE paychecks ADD COLUMN paycheck_profile_id INTEGER REFERENCES paycheck_profiles(id)")

    existing_user = conn.execute("SELECT * FROM users ORDER BY id LIMIT 1").fetchone()
    if existing_user is None:
        cursor = conn.execute(
            "INSERT INTO users (email, display_name, created_at) VALUES (?, ?, ?)",
            ("owner@example.local", "Default Owner", stamp),
        )
        owner_id = cursor.lastrowid
    else:
        owner_id = existing_user["id"]

    existing_profile = conn.execute("SELECT * FROM budget_profiles ORDER BY id LIMIT 1").fetchone()
    if existing_profile is None:
        cursor = conn.execute(
            """
            INSERT INTO budget_profiles (name, owner_user_id, created_at, updated_at)
            VALUES (?, ?, ?, ?)
            """,
            ("Default Budget", owner_id, stamp, stamp),
        )
        profile_id = cursor.lastrowid
        conn.execute(
            """
            INSERT OR IGNORE INTO user_profile_access (user_id, profile_id, role, created_at)
            VALUES (?, ?, 'admin', ?)
            """,
            (owner_id, profile_id, stamp),
        )
    else:
        profile_id = existing_profile["id"]

    for table in ["accounts", "budget_chunks", "paychecks", "money_movements", "transactions"]:
        if not column_exists(conn, table, "profile_id"):
            conn.execute(f"ALTER TABLE {table} ADD COLUMN profile_id INTEGER NOT NULL DEFAULT 1 REFERENCES budget_profiles(id)")
        conn.execute(f"UPDATE {table} SET profile_id = ? WHERE profile_id IS NULL OR profile_id = 1", (profile_id,))

    if not column_exists(conn, "paycheck_profiles", "profile_id"):
        conn.execute("ALTER TABLE paycheck_profiles ADD COLUMN profile_id INTEGER NOT NULL DEFAULT 1 REFERENCES budget_profiles(id)")
    conn.execute("UPDATE paycheck_profiles SET profile_id = ? WHERE profile_id IS NULL OR profile_id = 1", (profile_id,))
    if "UNIQUE(profile_id)" in table_sql(conn, "paycheck_profiles"):
        conn.executescript(
            """
            ALTER TABLE paycheck_profiles RENAME TO paycheck_profiles_old;
            CREATE TABLE paycheck_profiles (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                profile_id INTEGER NOT NULL DEFAULT 1 REFERENCES budget_profiles(id),
                name TEXT NOT NULL DEFAULT 'Paycheck',
                gross_pay_amount REAL NOT NULL,
                net_pay_amount REAL NOT NULL,
                net_pay_mode TEXT NOT NULL,
                pay_frequency TEXT NOT NULL,
                default_account_id INTEGER REFERENCES accounts(id),
                updated_at TEXT NOT NULL
            );
            INSERT INTO paycheck_profiles
                (id, profile_id, name, gross_pay_amount, net_pay_amount, net_pay_mode, pay_frequency, default_account_id, updated_at)
            SELECT id, profile_id, name, gross_pay_amount, net_pay_amount, net_pay_mode, pay_frequency, default_account_id, updated_at
            FROM paycheck_profiles_old;
            DROP TABLE paycheck_profiles_old;
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


def get_profile_or_404(conn: sqlite3.Connection, profile_id: int) -> sqlite3.Row:
    profile = conn.execute("SELECT * FROM budget_profiles WHERE id = ?", (profile_id,)).fetchone()
    if not profile:
        raise HTTPException(status_code=404, detail="Budget profile not found")
    return profile


def require_profile_admin(conn: sqlite3.Connection, profile_id: int, user_id: int) -> None:
    access = conn.execute(
        """
        SELECT * FROM user_profile_access
        WHERE profile_id = ? AND user_id = ? AND role = 'admin'
        """,
        (profile_id, user_id),
    ).fetchone()
    if not access:
        raise HTTPException(status_code=403, detail="Admin access is required for this budget profile")


def account_summaries(conn: sqlite3.Connection, profile_id: int = 1, include_inactive: bool = False) -> list[dict[str, Any]]:
    active_filter = "" if include_inactive else "AND a.is_active = 1"
    rows = conn.execute(
        """
        SELECT
            a.*,
            COALESCE(SUM(CASE WHEN c.is_active = 1 AND c.chunk_type != 'loan' THEN c.balance ELSE 0 END), 0) AS allocated_balance
        FROM accounts a
        LEFT JOIN budget_chunks c ON c.account_id = a.id AND c.profile_id = a.profile_id
        WHERE a.profile_id = ? {active_filter}
        GROUP BY a.id
        ORDER BY a.sort_order, a.name
        """.format(active_filter=active_filter),
        (profile_id,),
    ).fetchall()
    summaries = []
    for row in rows:
        item = dict(row)
        item["is_active"] = bool(item["is_active"])
        item["unallocated_balance"] = item["balance"] - item["allocated_balance"]
        summaries.append(item)
    return summaries


def account_summary(conn: sqlite3.Connection, account_id: int, profile_id: int = 1) -> dict[str, Any] | None:
    return next((account for account in account_summaries(conn, profile_id) if account["id"] == account_id), None)


def payments_per_year(pay_frequency: str) -> float:
    return {
        "weekly": 52,
        "biweekly": 26,
        "semimonthly": 24,
        "monthly": 12,
    }.get(pay_frequency, 26)


def updated_loan_balance(current_balance: Any, annual_rate: Any, payment: float, pay_frequency: str) -> float | None:
    if current_balance is None:
        return None
    balance = float(current_balance)
    rate = float(annual_rate or 0) / 100
    periodic_rate = rate / payments_per_year(pay_frequency)
    return max(0, balance * (1 + periodic_rate) - payment)


def movement_endpoint_balance(conn: sqlite3.Connection, endpoint_type: str, endpoint_id: int | None, profile_id: int) -> float | None:
    if endpoint_type == "chunk" and endpoint_id is not None:
        chunk = conn.execute(
            "SELECT chunk_type, balance, loan_balance FROM budget_chunks WHERE id = ? AND profile_id = ?",
            (endpoint_id, profile_id),
        ).fetchone()
        if not chunk:
            return None
        return float(chunk["loan_balance"] or 0) if chunk["chunk_type"] == "loan" else float(chunk["balance"])
    if endpoint_type in ("unallocated", "account") and endpoint_id is not None:
        summary = account_summary(conn, endpoint_id, profile_id)
        if not summary:
            return None
        return float(summary["unallocated_balance"] if endpoint_type == "unallocated" else summary["balance"])
    return None


@app.get("/api/health")
def health() -> dict[str, str]:
    return {"status": "ok"}


@app.get("/api/users")
def list_users() -> list[dict[str, Any]]:
    with db() as conn:
        return rows_to_dicts(conn.execute("SELECT id, email, display_name, email_verified, created_at FROM users ORDER BY email").fetchall())


@app.post("/api/users")
def create_user(payload: UserIn) -> dict[str, Any]:
    stamp = now()
    with db() as conn:
        existing = conn.execute("SELECT * FROM users WHERE lower(email) = lower(?)", (payload.email,)).fetchone()
        if existing:
            if payload.password and (not existing["password_salt"] or not existing["password_hash"]):
                salt, password_hash = hash_password(payload.password)
                conn.execute(
                    "UPDATE users SET display_name = ?, password_salt = ?, password_hash = ? WHERE id = ?",
                    (payload.display_name, salt, password_hash, existing["id"]),
                )
            return row_to_dict(conn.execute("SELECT id, email, display_name, email_verified, created_at FROM users WHERE id = ?", (existing["id"],)).fetchone())
        password_salt = None
        password_hash = None
        if payload.password:
            password_salt, password_hash = hash_password(payload.password)
        cursor = conn.execute(
            """
            INSERT INTO users (email, display_name, password_salt, password_hash, created_at)
            VALUES (?, ?, ?, ?, ?)
            """,
            (payload.email, payload.display_name, password_salt, password_hash, stamp),
        )
        return row_to_dict(conn.execute("SELECT id, email, display_name, email_verified, created_at FROM users WHERE id = ?", (cursor.lastrowid,)).fetchone())


@app.post("/api/register")
def register(payload: RegisterIn) -> dict[str, Any]:
    stamp = now()
    with db() as conn:
        existing = conn.execute("SELECT id FROM users WHERE lower(email) = lower(?)", (payload.email,)).fetchone()
        if existing:
            raise HTTPException(status_code=409, detail="An account with this email already exists")
        salt, password_hash = hash_password(payload.password)
        cursor = conn.execute(
            """
            INSERT INTO users (email, display_name, password_salt, password_hash, email_verified, created_at)
            VALUES (?, ?, ?, ?, 0, ?)
            """,
            (payload.email, payload.display_name, salt, password_hash, stamp),
        )
        return row_to_dict(
            conn.execute(
                "SELECT id, email, display_name, email_verified, created_at FROM users WHERE id = ?",
                (cursor.lastrowid,),
            ).fetchone()
        )


@app.post("/api/login")
def login(payload: LoginIn) -> dict[str, Any]:
    stamp = now()
    with db() as conn:
        user = conn.execute("SELECT * FROM users WHERE lower(email) = lower(?)", (payload.email,)).fetchone()
        if user is None:
            raise HTTPException(status_code=401, detail="Invalid email or password")
        if not user["password_salt"] or not user["password_hash"]:
            salt, password_hash = hash_password(payload.password)
            conn.execute(
                "UPDATE users SET password_salt = ?, password_hash = ? WHERE id = ?",
                (salt, password_hash, user["id"]),
            )
            return row_to_dict(conn.execute("SELECT id, email, display_name, email_verified, created_at FROM users WHERE id = ?", (user["id"],)).fetchone())
        if not verify_password(payload.password, user["password_salt"], user["password_hash"]):
            raise HTTPException(status_code=401, detail="Invalid email or password")
        return row_to_dict(conn.execute("SELECT id, email, display_name, email_verified, created_at FROM users WHERE id = ?", (user["id"],)).fetchone())


@app.get("/api/budget-profiles")
def list_budget_profiles(user_id: int | None = None) -> list[dict[str, Any]]:
    with db() as conn:
        if user_id is None:
            return rows_to_dicts(conn.execute("SELECT * FROM budget_profiles ORDER BY name").fetchall())
        return rows_to_dicts(
            conn.execute(
                """
                SELECT p.*, a.role, a.sort_order
                FROM budget_profiles p
                JOIN user_profile_access a ON a.profile_id = p.id
                WHERE a.user_id = ?
                ORDER BY a.sort_order, p.name
                """,
                (user_id,),
            ).fetchall()
        )


@app.post("/api/budget-profiles")
def create_budget_profile(payload: BudgetProfileIn) -> dict[str, Any]:
    stamp = now()
    with db() as conn:
        user = conn.execute("SELECT * FROM users WHERE id = ?", (payload.owner_user_id,)).fetchone()
        if not user:
            raise HTTPException(status_code=404, detail="Owner user not found")
        cursor = conn.execute(
            """
            INSERT INTO budget_profiles (name, owner_user_id, created_at, updated_at)
            VALUES (?, ?, ?, ?)
            """,
            (payload.name, payload.owner_user_id, stamp, stamp),
        )
        profile_id = cursor.lastrowid
        conn.execute(
            """
            INSERT INTO user_profile_access (user_id, profile_id, role, created_at)
            VALUES (?, ?, 'admin', ?)
            """,
            (payload.owner_user_id, profile_id, stamp),
        )
        return row_to_dict(conn.execute("SELECT * FROM budget_profiles WHERE id = ?", (profile_id,)).fetchone())


@app.put("/api/budget-profiles/reorder")
def reorder_budget_profiles(payload: ReorderProfilesIn) -> dict[str, bool]:
    with db() as conn:
        for index, profile_id in enumerate(payload.profile_ids):
            conn.execute(
                """
                UPDATE user_profile_access
                SET sort_order = ?
                WHERE user_id = ? AND profile_id = ?
                """,
                (index, payload.user_id, profile_id),
            )
        return {"updated": True}


@app.delete("/api/budget-profiles/{profile_id}")
def delete_budget_profile(profile_id: int) -> dict[str, bool]:
    with db() as conn:
        get_profile_or_404(conn, profile_id)
        paycheck_ids = [row["id"] for row in conn.execute("SELECT id FROM paychecks WHERE profile_id = ?", (profile_id,)).fetchall()]
        if paycheck_ids:
            placeholders = ",".join("?" for _ in paycheck_ids)
            conn.execute(f"DELETE FROM paycheck_allocations WHERE paycheck_id IN ({placeholders})", paycheck_ids)
        conn.execute("DELETE FROM transactions WHERE profile_id = ?", (profile_id,))
        conn.execute("DELETE FROM money_movements WHERE profile_id = ?", (profile_id,))
        conn.execute("DELETE FROM paychecks WHERE profile_id = ?", (profile_id,))
        conn.execute("DELETE FROM paycheck_profiles WHERE profile_id = ?", (profile_id,))
        conn.execute("DELETE FROM budget_chunks WHERE profile_id = ?", (profile_id,))
        conn.execute("DELETE FROM accounts WHERE profile_id = ?", (profile_id,))
        conn.execute("DELETE FROM profile_invitations WHERE profile_id = ?", (profile_id,))
        conn.execute("DELETE FROM user_profile_access WHERE profile_id = ?", (profile_id,))
        conn.execute("DELETE FROM budget_profiles WHERE id = ?", (profile_id,))
        return {"deleted": True}


@app.get("/api/budget-profiles/{profile_id}/members")
def list_budget_profile_members(profile_id: int) -> list[dict[str, Any]]:
    with db() as conn:
        get_profile_or_404(conn, profile_id)
        return rows_to_dicts(
            conn.execute(
                """
                SELECT u.id AS user_id, u.email, u.display_name, a.role, a.created_at
                FROM user_profile_access a
                JOIN users u ON u.id = a.user_id
                WHERE a.profile_id = ?
                ORDER BY u.email
                """,
                (profile_id,),
            ).fetchall()
        )


@app.post("/api/budget-profiles/{profile_id}/invitations")
def invite_budget_profile_member(profile_id: int, payload: InvitationIn) -> dict[str, Any]:
    stamp = now()
    with db() as conn:
        get_profile_or_404(conn, profile_id)
        require_profile_admin(conn, profile_id, payload.invited_by_user_id)
        cursor = conn.execute(
            """
            INSERT INTO profile_invitations
                (profile_id, email, role, invited_by_user_id, status, created_at)
            VALUES (?, ?, ?, ?, 'pending', ?)
            """,
            (profile_id, payload.email, payload.role, payload.invited_by_user_id, stamp),
        )
        return row_to_dict(conn.execute("SELECT * FROM profile_invitations WHERE id = ?", (cursor.lastrowid,)).fetchone())


@app.get("/api/invitations")
def list_invitations(email: str | None = None, profile_id: int | None = None) -> list[dict[str, Any]]:
    with db() as conn:
        clauses = []
        params: list[Any] = []
        if email is not None:
            clauses.append("lower(email) = lower(?)")
            params.append(email)
        if profile_id is not None:
            clauses.append("profile_id = ?")
            params.append(profile_id)
        where = " WHERE " + " AND ".join(clauses) if clauses else ""
        return rows_to_dicts(
            conn.execute(f"SELECT * FROM profile_invitations{where} ORDER BY created_at DESC", params).fetchall()
        )


@app.post("/api/invitations/{invitation_id}/accept")
def accept_invitation(invitation_id: int, payload: AcceptInvitationIn) -> dict[str, Any]:
    stamp = now()
    with db() as conn:
        invitation = conn.execute("SELECT * FROM profile_invitations WHERE id = ?", (invitation_id,)).fetchone()
        if not invitation:
            raise HTTPException(status_code=404, detail="Invitation not found")
        if invitation["status"] != "pending":
            raise HTTPException(status_code=400, detail="Invitation is not pending")
        user = conn.execute("SELECT * FROM users WHERE id = ?", (payload.user_id,)).fetchone()
        if not user:
            raise HTTPException(status_code=404, detail="User not found")
        if user["email"].lower() != invitation["email"].lower():
            raise HTTPException(status_code=400, detail="Invitation email does not match this user")
        conn.execute(
            """
            INSERT INTO user_profile_access (user_id, profile_id, role, created_at)
            VALUES (?, ?, ?, ?)
            ON CONFLICT(user_id, profile_id) DO UPDATE SET role = excluded.role
            """,
            (payload.user_id, invitation["profile_id"], invitation["role"], stamp),
        )
        conn.execute(
            """
            UPDATE profile_invitations
            SET status = 'accepted', accepted_by_user_id = ?, accepted_at = ?
            WHERE id = ?
            """,
            (payload.user_id, stamp, invitation_id),
        )
        return row_to_dict(conn.execute("SELECT * FROM profile_invitations WHERE id = ?", (invitation_id,)).fetchone())


@app.get("/api/dashboard/summary")
def dashboard_summary(profile_id: int = 1) -> dict[str, Any]:
    with db() as conn:
        get_profile_or_404(conn, profile_id)
        accounts = account_summaries(conn, profile_id)
        chunks = rows_to_dicts(
            conn.execute(
                """
                SELECT c.*, a.name AS account_name
                FROM budget_chunks c
                JOIN accounts a ON a.id = c.account_id
                WHERE c.profile_id = ? AND c.is_active = 1
                ORDER BY c.name
                """,
                (profile_id,),
            ).fetchall()
        )
        for chunk in chunks:
            chunk["is_active"] = bool(chunk["is_active"])
        movements = rows_to_dicts(
            conn.execute(
                "SELECT * FROM money_movements WHERE profile_id = ? ORDER BY created_at DESC LIMIT 8", (profile_id,)
            ).fetchall()
        )
        paychecks = rows_to_dicts(
            conn.execute("SELECT * FROM paychecks WHERE profile_id = ? ORDER BY created_at DESC LIMIT 5", (profile_id,)).fetchall()
        )
        paycheck_profiles = rows_to_dicts(
            conn.execute("SELECT * FROM paycheck_profiles WHERE profile_id = ? ORDER BY id", (profile_id,)).fetchall()
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
            "paycheck_profiles": paycheck_profiles,
            "paycheck_profile": paycheck_profiles[0] if paycheck_profiles else None,
        }


@app.get("/api/accounts")
def list_accounts(profile_id: int = 1) -> list[dict[str, Any]]:
    with db() as conn:
        get_profile_or_404(conn, profile_id)
        return account_summaries(conn, profile_id)


@app.post("/api/accounts")
def create_account(payload: AccountIn, profile_id: int = 1) -> dict[str, Any]:
    stamp = now()
    with db() as conn:
        get_profile_or_404(conn, profile_id)
        cursor = conn.execute(
            """
            INSERT INTO accounts (profile_id, name, type, source_mode, balance, is_active, created_at, updated_at)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?)
            """,
            (profile_id, payload.name, payload.type, payload.source_mode, payload.balance, int(payload.is_active), stamp, stamp),
        )
        return next(a for a in account_summaries(conn, profile_id) if a["id"] == cursor.lastrowid)


@app.put("/api/accounts/reorder")
def reorder_accounts(payload: ReorderAccountsIn, profile_id: int = 1) -> dict[str, bool]:
    with db() as conn:
        get_profile_or_404(conn, profile_id)
        for index, account_id in enumerate(payload.account_ids):
            conn.execute(
                "UPDATE accounts SET sort_order = ? WHERE id = ? AND profile_id = ?",
                (index, account_id, profile_id),
            )
        return {"updated": True}


@app.put("/api/accounts/{account_id}")
def update_account(account_id: int, payload: AccountIn, profile_id: int = 1) -> dict[str, Any]:
    with db() as conn:
        account = get_account_or_404(conn, account_id)
        if account["profile_id"] != profile_id:
            raise HTTPException(status_code=404, detail="Account not found")
        conn.execute(
            """
            UPDATE accounts
            SET name = ?, type = ?, source_mode = ?, balance = ?, is_active = ?, updated_at = ?
            WHERE id = ?
            """,
            (payload.name, payload.type, payload.source_mode, payload.balance, int(payload.is_active), now(), account_id),
        )
        return next(a for a in account_summaries(conn, profile_id) if a["id"] == account_id)


@app.delete("/api/accounts/{account_id}")
def delete_account(account_id: int, profile_id: int = 1) -> dict[str, bool]:
    with db() as conn:
        account = get_account_or_404(conn, account_id)
        if account["profile_id"] != profile_id:
            raise HTTPException(status_code=404, detail="Account not found")
        if account["balance"] != 0:
            raise HTTPException(
                status_code=400,
                detail="Only zero-balance accounts can be deleted",
            )
        chunk_count = conn.execute(
            "SELECT COUNT(*) AS count FROM budget_chunks WHERE account_id = ? AND chunk_type != 'loan'", (account_id,)
        ).fetchone()["count"]
        if chunk_count:
            raise HTTPException(status_code=400, detail="Move this account's chunks before deleting it")
        conn.execute("UPDATE accounts SET is_active = 0, updated_at = ? WHERE id = ?", (now(), account_id))
        return {"deleted": True}


@app.post("/api/accounts/{account_id}/move-chunks")
def move_account_chunks(account_id: int, payload: MoveAccountChunksIn, profile_id: int = 1) -> dict[str, int]:
    with db() as conn:
        source = get_account_or_404(conn, account_id)
        destination = get_account_or_404(conn, payload.destination_account_id)
        if source["profile_id"] != profile_id or destination["profile_id"] != profile_id:
            raise HTTPException(status_code=404, detail="Account not found")
        if source["id"] == destination["id"]:
            raise HTTPException(status_code=400, detail="Destination account must be different")
        cursor = conn.execute(
            "UPDATE budget_chunks SET account_id = ?, updated_at = ? WHERE account_id = ? AND profile_id = ? AND chunk_type != 'loan'",
            (payload.destination_account_id, now(), account_id, profile_id),
        )
        return {"moved_chunks": cursor.rowcount}


@app.get("/api/paycheck-profile")
def get_paycheck_profile(profile_id: int = 1) -> dict[str, Any] | None:
    with db() as conn:
        get_profile_or_404(conn, profile_id)
        return row_to_dict(conn.execute("SELECT * FROM paycheck_profiles WHERE profile_id = ?", (profile_id,)).fetchone())


@app.get("/api/paycheck-profiles")
def list_paycheck_profiles(profile_id: int = 1) -> list[dict[str, Any]]:
    with db() as conn:
        get_profile_or_404(conn, profile_id)
        return rows_to_dicts(conn.execute("SELECT * FROM paycheck_profiles WHERE profile_id = ? ORDER BY id", (profile_id,)).fetchall())


@app.post("/api/paycheck-profile")
@app.put("/api/paycheck-profile")
def upsert_paycheck_profile(payload: PaycheckProfileIn, profile_id: int = 1) -> dict[str, Any]:
    with db() as conn:
        get_profile_or_404(conn, profile_id)
        if payload.default_account_id is not None:
            account = get_account_or_404(conn, payload.default_account_id)
            if account["profile_id"] != profile_id:
                raise HTTPException(status_code=404, detail="Default account not found")
        existing = None
        if payload.id is not None:
            existing = conn.execute("SELECT * FROM paycheck_profiles WHERE id = ? AND profile_id = ?", (payload.id, profile_id)).fetchone()
            if not existing:
                raise HTTPException(status_code=404, detail="Paycheck profile not found")
        if existing:
            conn.execute(
                """
                UPDATE paycheck_profiles
                SET name = ?, gross_pay_amount = ?, net_pay_amount = ?, net_pay_mode = ?,
                    pay_frequency = ?, default_account_id = ?, updated_at = ?
                WHERE id = ? AND profile_id = ?
                """,
                (
                    payload.name.strip() or "Paycheck",
                    payload.gross_pay_amount if payload.gross_pay_amount is not None else payload.net_pay_amount,
                    payload.net_pay_amount,
                    payload.net_pay_mode,
                    payload.pay_frequency,
                    payload.default_account_id,
                    now(),
                    payload.id,
                    profile_id,
                ),
            )
            profile_id_to_return = payload.id
        else:
            cursor = conn.execute(
                """
                INSERT INTO paycheck_profiles
                    (profile_id, name, gross_pay_amount, net_pay_amount, net_pay_mode, pay_frequency, default_account_id, updated_at)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?)
                """,
                (
                    profile_id,
                    payload.name.strip() or "Paycheck",
                    payload.gross_pay_amount if payload.gross_pay_amount is not None else payload.net_pay_amount,
                    payload.net_pay_amount,
                    payload.net_pay_mode,
                    payload.pay_frequency,
                    payload.default_account_id,
                    now(),
                ),
            )
            profile_id_to_return = cursor.lastrowid
        return row_to_dict(conn.execute("SELECT * FROM paycheck_profiles WHERE id = ?", (profile_id_to_return,)).fetchone())


@app.delete("/api/paycheck-profiles/{paycheck_profile_id}")
def delete_paycheck_profile(paycheck_profile_id: int, profile_id: int = 1) -> dict[str, bool]:
    with db() as conn:
        paycheck_profile = conn.execute(
            "SELECT * FROM paycheck_profiles WHERE id = ? AND profile_id = ?", (paycheck_profile_id, profile_id)
        ).fetchone()
        if not paycheck_profile:
            raise HTTPException(status_code=404, detail="Paycheck profile not found")
        conn.execute("UPDATE paychecks SET paycheck_profile_id = NULL WHERE paycheck_profile_id = ?", (paycheck_profile_id,))
        conn.execute("DELETE FROM paycheck_profiles WHERE id = ?", (paycheck_profile_id,))
        return {"deleted": True}


@app.get("/api/chunks")
def list_chunks(profile_id: int = 1) -> list[dict[str, Any]]:
    with db() as conn:
        get_profile_or_404(conn, profile_id)
        chunks = rows_to_dicts(
            conn.execute(
                """
                SELECT c.*, a.name AS account_name
                FROM budget_chunks c
                JOIN accounts a ON a.id = c.account_id
                WHERE c.profile_id = ? AND c.is_active = 1
                ORDER BY c.name
                """,
                (profile_id,),
            ).fetchall()
        )
        for chunk in chunks:
            chunk["is_active"] = bool(chunk["is_active"])
        return chunks


@app.post("/api/chunks")
def create_chunk(payload: ChunkIn, profile_id: int = 1) -> dict[str, Any]:
    stamp = now()
    with db() as conn:
        get_profile_or_404(conn, profile_id)
        account_id = payload.account_id
        if payload.chunk_type == "loan":
            account = conn.execute("SELECT * FROM accounts WHERE profile_id = ? ORDER BY is_active DESC, id LIMIT 1", (profile_id,)).fetchone()
            if not account:
                raise HTTPException(status_code=400, detail="Create an account before adding a loan chunk")
            account_id = account["id"]
        elif account_id is None:
            raise HTTPException(status_code=400, detail="Chunk account is required")
        account = get_account_or_404(conn, account_id)
        if account["profile_id"] != profile_id:
            raise HTTPException(status_code=400, detail="Chunk account must belong to the selected budget profile")
        cursor = conn.execute(
            """
            INSERT INTO budget_chunks
                (profile_id, name, account_id, chunk_type, amount_per_paycheck, balance, loan_balance, loan_interest_rate, is_active, created_at, updated_at)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            """,
            (
                profile_id,
                payload.name,
                account_id,
                payload.chunk_type,
                payload.amount_per_paycheck,
                payload.balance,
                payload.loan_balance if payload.chunk_type == "loan" else None,
                payload.loan_interest_rate if payload.chunk_type == "loan" else None,
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
            WHERE c.id = ? AND c.profile_id = ?
            """,
            (cursor.lastrowid, profile_id),
        ).fetchone()
        result = dict(chunk)
        result["is_active"] = bool(result["is_active"])
        return result


@app.put("/api/chunks/{chunk_id}")
def update_chunk(chunk_id: int, payload: ChunkIn, profile_id: int = 1) -> dict[str, Any]:
    with db() as conn:
        chunk = get_chunk_or_404(conn, chunk_id)
        account_id = chunk["account_id"] if payload.chunk_type == "loan" else payload.account_id
        if account_id is None:
            raise HTTPException(status_code=400, detail="Chunk account is required")
        account = get_account_or_404(conn, account_id)
        if chunk["profile_id"] != profile_id or account["profile_id"] != profile_id:
            raise HTTPException(status_code=404, detail="Chunk not found")
        conn.execute(
            """
            UPDATE budget_chunks
            SET name = ?, account_id = ?, chunk_type = ?, amount_per_paycheck = ?, balance = ?,
                loan_balance = ?, loan_interest_rate = ?, is_active = ?, updated_at = ?
            WHERE id = ?
            """,
            (
                payload.name,
                account_id,
                payload.chunk_type,
                payload.amount_per_paycheck,
                payload.balance,
                payload.loan_balance if payload.chunk_type == "loan" else None,
                payload.loan_interest_rate if payload.chunk_type == "loan" else None,
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
            WHERE c.id = ? AND c.profile_id = ?
            """,
            (chunk_id, profile_id),
        ).fetchone()
        result = dict(chunk)
        result["is_active"] = bool(result["is_active"])
        return result


@app.delete("/api/chunks/{chunk_id}")
def delete_chunk(chunk_id: int, profile_id: int = 1) -> dict[str, bool]:
    with db() as conn:
        chunk = get_chunk_or_404(conn, chunk_id)
        if chunk["profile_id"] != profile_id:
            raise HTTPException(status_code=404, detail="Chunk not found")
        conn.execute(
            "UPDATE budget_chunks SET balance = 0, is_active = 0, updated_at = ? WHERE id = ?",
            (now(), chunk_id),
        )
        return {"deleted": True}


@app.post("/api/paychecks/add")
def add_paycheck(payload: AddPaycheckIn, profile_id: int = 1) -> dict[str, Any]:
    with db() as conn:
        get_profile_or_404(conn, profile_id)
        if payload.paycheck_profile_id is not None:
            profile = conn.execute(
                "SELECT * FROM paycheck_profiles WHERE id = ? AND profile_id = ?", (payload.paycheck_profile_id, profile_id)
            ).fetchone()
        else:
            profile = conn.execute("SELECT * FROM paycheck_profiles WHERE profile_id = ? ORDER BY id LIMIT 1", (profile_id,)).fetchone()
        if not profile:
            raise HTTPException(status_code=400, detail="Create a paycheck profile first")
        account_id = payload.account_id or profile["default_account_id"]
        if account_id is None:
            account = conn.execute(
                "SELECT * FROM accounts WHERE profile_id = ? AND is_active = 1 ORDER BY id LIMIT 1", (profile_id,)
            ).fetchone()
            if not account:
                raise HTTPException(status_code=400, detail="Create an account first")
            account_id = account["id"]
        account = get_account_or_404(conn, account_id)
        if account["profile_id"] != profile_id:
            raise HTTPException(status_code=404, detail="Account not found")
        net_amount = profile["net_pay_amount"] if payload.amount_mode == "expected" else payload.custom_amount
        if net_amount is None:
            raise HTTPException(status_code=400, detail="Custom amount is required")
        if float(net_amount) <= 0:
            raise HTTPException(status_code=400, detail="Paycheck amount must be greater than zero")

        stamp = now()
        cursor = conn.execute(
            """
            INSERT INTO paychecks (profile_id, paycheck_profile_id, account_id, gross_amount, net_amount, amount_mode, created_at)
            VALUES (?, ?, ?, ?, ?, ?, ?)
            """,
            (profile_id, profile["id"], account_id, profile["gross_pay_amount"], net_amount, payload.amount_mode, stamp),
        )
        paycheck_id = cursor.lastrowid
        conn.execute("UPDATE accounts SET balance = balance + ?, updated_at = ? WHERE id = ?", (net_amount, stamp, account_id))

        chunks = conn.execute(
            """
            SELECT * FROM budget_chunks
            WHERE profile_id = ? AND is_active = 1
              AND (chunk_type = 'loan' OR account_id = ?)
            ORDER BY id
            """,
            (profile_id, account_id),
        ).fetchall()
        chunk_by_id = {chunk["id"]: chunk for chunk in chunks}
        requested_allocations = None
        if payload.allocations is not None:
            requested_allocations = []
            requested_total = 0.0
            for allocation in payload.allocations:
                chunk = chunk_by_id.get(allocation.chunk_id)
                if not chunk:
                    raise HTTPException(status_code=400, detail="Selected chunk is not available for this paycheck")
                configured_amount = float(chunk["amount_per_paycheck"])
                amount = float(allocation.amount)
                if amount > configured_amount:
                    raise HTTPException(status_code=400, detail=f"{chunk['name']} cannot exceed its configured paycheck amount")
                if chunk["chunk_type"] == "loan" and chunk["loan_balance"] is not None:
                    amount = min(amount, float(chunk["loan_balance"]))
                requested_total += amount
                requested_allocations.append((chunk, amount))
            if requested_total > float(net_amount):
                raise HTTPException(status_code=400, detail="Selected chunk allocations exceed the paycheck amount")

        remaining = float(net_amount)
        allocations = []
        allocation_rows = (
            requested_allocations
            if requested_allocations is not None
            else [(chunk, min(float(chunk["amount_per_paycheck"]), remaining)) for chunk in chunks]
        )
        for chunk, requested_amount in allocation_rows:
            amount = min(float(requested_amount), remaining)
            if chunk["chunk_type"] == "loan" and chunk["loan_balance"] is not None:
                amount = min(amount, float(chunk["loan_balance"]))
            if amount <= 0:
                continue
            loan_balance_after = None
            if chunk["chunk_type"] == "loan":
                loan_balance_after = updated_loan_balance(
                    chunk["loan_balance"],
                    chunk["loan_interest_rate"],
                    amount,
                    profile["pay_frequency"],
                )
                if loan_balance_after is not None:
                    conn.execute(
                        "UPDATE budget_chunks SET loan_balance = ?, updated_at = ? WHERE id = ?",
                        (loan_balance_after, stamp, chunk["id"]),
                    )
                conn.execute("UPDATE accounts SET balance = balance - ?, updated_at = ? WHERE id = ?", (amount, stamp, account_id))
            else:
                conn.execute("UPDATE budget_chunks SET balance = balance + ?, updated_at = ? WHERE id = ?", (amount, stamp, chunk["id"]))
            conn.execute(
                """
                INSERT INTO paycheck_allocations (paycheck_id, chunk_id, amount, created_at)
                VALUES (?, ?, ?, ?)
                """,
                (paycheck_id, chunk["id"], amount, stamp),
            )
            allocations.append({"chunk_id": chunk["id"], "chunk_name": chunk["name"], "amount": amount, "loan_balance_after": loan_balance_after})
            remaining -= amount

        paycheck = row_to_dict(conn.execute("SELECT * FROM paychecks WHERE id = ?", (paycheck_id,)).fetchone())
        return {"paycheck": paycheck, "allocations": allocations, "unallocated_amount": remaining}


@app.get("/api/paychecks")
def list_paychecks(profile_id: int = 1) -> list[dict[str, Any]]:
    with db() as conn:
        get_profile_or_404(conn, profile_id)
        return rows_to_dicts(
            conn.execute("SELECT * FROM paychecks WHERE profile_id = ? ORDER BY created_at DESC", (profile_id,)).fetchall()
        )


@app.post("/api/money-movements")
def create_money_movement(payload: MoneyMovementIn, profile_id: int = 1) -> dict[str, Any]:
    with db() as conn:
        get_profile_or_404(conn, profile_id)
        stamp = now()
        source_account_id: int | None = None
        destination_id = payload.destination_id
        if payload.destination_type == "chunk" and payload.destination_id is not None:
            possible_loan = get_chunk_or_404(conn, payload.destination_id)
            if possible_loan["profile_id"] != profile_id:
                raise HTTPException(status_code=404, detail="Chunk not found")
            if possible_loan["chunk_type"] == "loan" and possible_loan["loan_balance"] is not None:
                payload.amount = min(payload.amount, float(possible_loan["loan_balance"]))

        if payload.movement_type == "manual_account_transfer":
            if payload.source_type != "unallocated" or payload.destination_type != "unallocated":
                raise HTTPException(
                    status_code=400,
                    detail="Manual account transfers must move account unallocated money to account unallocated money",
                )
            if payload.source_id is None or payload.destination_id is None:
                raise HTTPException(status_code=400, detail="Source and destination accounts are required")
            if payload.source_id == payload.destination_id:
                raise HTTPException(status_code=400, detail="Source and destination accounts must be different")
            source_account = get_account_or_404(conn, payload.source_id)
            destination_account = get_account_or_404(conn, payload.destination_id)
            if source_account["profile_id"] != profile_id or destination_account["profile_id"] != profile_id:
                raise HTTPException(status_code=404, detail="Account not found")
            if source_account["source_mode"] != "manual" or destination_account["source_mode"] != "manual":
                raise HTTPException(status_code=400, detail="Only manually managed accounts can initiate software account transfers")
            source_summary = account_summary(conn, payload.source_id, profile_id)
            if not source_summary or source_summary["unallocated_balance"] < payload.amount:
                raise HTTPException(status_code=400, detail="Source account does not have enough unallocated money")
            source_before = float(source_summary["unallocated_balance"])
            destination_summary = account_summary(conn, payload.destination_id, profile_id)
            destination_before = float(destination_summary["unallocated_balance"]) if destination_summary else None
            conn.execute(
                "UPDATE accounts SET balance = balance - ?, updated_at = ? WHERE id = ?",
                (payload.amount, stamp, payload.source_id),
            )
            conn.execute(
                "UPDATE accounts SET balance = balance + ?, updated_at = ? WHERE id = ?",
                (payload.amount, stamp, payload.destination_id),
            )
            cursor = conn.execute(
                """
                INSERT INTO money_movements
                    (profile_id, movement_type, source_type, source_id, destination_type, destination_id, amount, note,
                     source_balance_before, source_balance_after, destination_balance_before, destination_balance_after, created_at)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                """,
                (
                    profile_id,
                    payload.movement_type,
                    payload.source_type,
                    payload.source_id,
                    payload.destination_type,
                    payload.destination_id,
                    payload.amount,
                    payload.note,
                    source_before,
                    source_before - payload.amount,
                    destination_before,
                    None if destination_before is None else destination_before + payload.amount,
                    stamp,
                ),
            )
            return row_to_dict(conn.execute("SELECT * FROM money_movements WHERE id = ?", (cursor.lastrowid,)).fetchone())

        if payload.source_type == "paycheck":
            raise HTTPException(
                status_code=400,
                detail="Paycheck money enters the budget through Add Paycheck, then can be allocated from unallocated money or chunks.",
            )

        if payload.source_type == "chunk":
            if payload.source_id is None:
                raise HTTPException(status_code=400, detail="source_id is required for chunk transfers")
            source_chunk = get_chunk_or_404(conn, payload.source_id)
            if source_chunk["profile_id"] != profile_id:
                raise HTTPException(status_code=404, detail="Chunk not found")
            if source_chunk["chunk_type"] == "loan":
                raise HTTPException(status_code=400, detail="Loan chunks cannot be used as a transfer source")
            source_account_id = source_chunk["account_id"]
            if source_chunk["balance"] < payload.amount:
                raise HTTPException(status_code=400, detail="Chunk does not have enough allocated money")
            source_balance_before = float(source_chunk["balance"])
            conn.execute(
                "UPDATE budget_chunks SET balance = balance - ?, updated_at = ? WHERE id = ?",
                (payload.amount, stamp, payload.source_id),
            )
        elif payload.source_type == "unallocated":
            if payload.source_id is None:
                raise HTTPException(status_code=400, detail="source_id must be the source account for unallocated transfers")
            source_account_id = payload.source_id
            source = account_summary(conn, payload.source_id, profile_id)
            if not source:
                raise HTTPException(status_code=404, detail="Source account not found")
            if source["unallocated_balance"] < payload.amount:
                raise HTTPException(status_code=400, detail="Account does not have enough unallocated money")
            source_balance_before = float(source["unallocated_balance"])
        else:
            source_balance_before = None

        if payload.destination_type == "chunk":
            if payload.destination_id is None:
                raise HTTPException(status_code=400, detail="destination_id is required for chunk transfers")
            destination_chunk = get_chunk_or_404(conn, payload.destination_id)
            if destination_chunk["profile_id"] != profile_id:
                raise HTTPException(status_code=404, detail="Chunk not found")
            if destination_chunk["chunk_type"] == "loan":
                destination_balance_before = float(destination_chunk["loan_balance"] or 0)
                payment = payload.amount
                if destination_chunk["loan_balance"] is not None:
                    conn.execute(
                        "UPDATE budget_chunks SET loan_balance = MAX(0, loan_balance - ?), updated_at = ? WHERE id = ?",
                        (payment, stamp, payload.destination_id),
                    )
                if source_account_id is not None:
                    conn.execute(
                        "UPDATE accounts SET balance = balance - ?, updated_at = ? WHERE id = ?",
                        (payload.amount, stamp, source_account_id),
                    )
                destination_id = payload.destination_id
            else:
                destination_account_id = destination_chunk["account_id"]
                if payload.source_type == "unallocated" and source_account_id != destination_account_id:
                    raise HTTPException(
                        status_code=400,
                        detail="Unallocated money can only be assigned to chunks in the same account",
                    )
                if payload.source_type == "chunk" and source_account_id != destination_account_id:
                    destination = account_summary(conn, destination_account_id, profile_id)
                    if not destination or destination["unallocated_balance"] < payload.amount:
                        raise HTTPException(
                            status_code=400,
                            detail="Destination account needs enough unallocated money before a cross-account chunk transfer can be logged",
                        )
                destination_balance_before = float(destination_chunk["balance"])
                conn.execute(
                    "UPDATE budget_chunks SET balance = balance + ?, updated_at = ? WHERE id = ?",
                    (payload.amount, stamp, payload.destination_id),
                )
        elif payload.destination_type == "account":
            if payload.destination_id is None:
                raise HTTPException(status_code=400, detail="destination_id is required to log an account destination")
            destination_account = get_account_or_404(conn, payload.destination_id)
            if destination_account["profile_id"] != profile_id:
                raise HTTPException(status_code=404, detail="Destination account not found")
            if source_account_id != payload.destination_id:
                destination = account_summary(conn, payload.destination_id, profile_id)
                if not destination or destination["unallocated_balance"] < payload.amount:
                    raise HTTPException(
                        status_code=400,
                        detail="Destination account balance must already reflect the bank/account transfer before it can be logged",
                    )
            destination_balance_before = movement_endpoint_balance(conn, "account", payload.destination_id, profile_id)
        elif payload.destination_type == "unallocated":
            destination_balance_before = movement_endpoint_balance(conn, "unallocated", destination_id or source_account_id, profile_id)
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
            destination_balance_before = None
            pass
        else:
            destination_balance_before = movement_endpoint_balance(conn, payload.destination_type, destination_id, profile_id)

        source_balance_after = movement_endpoint_balance(conn, payload.source_type, payload.source_id, profile_id)
        destination_balance_after = movement_endpoint_balance(conn, payload.destination_type, destination_id, profile_id)

        cursor = conn.execute(
            """
            INSERT INTO money_movements
                (profile_id, movement_type, source_type, source_id, destination_type, destination_id, amount, note,
                 source_balance_before, source_balance_after, destination_balance_before, destination_balance_after, created_at)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            """,
            (
                profile_id,
                payload.movement_type,
                payload.source_type,
                payload.source_id,
                payload.destination_type,
                destination_id,
                payload.amount,
                payload.note,
                source_balance_before,
                source_balance_after,
                destination_balance_before,
                destination_balance_after,
                stamp,
            ),
        )
        return row_to_dict(conn.execute("SELECT * FROM money_movements WHERE id = ?", (cursor.lastrowid,)).fetchone())


@app.get("/api/money-movements")
def list_money_movements(profile_id: int = 1) -> list[dict[str, Any]]:
    with db() as conn:
        get_profile_or_404(conn, profile_id)
        return rows_to_dicts(
            conn.execute("SELECT * FROM money_movements WHERE profile_id = ? ORDER BY created_at DESC", (profile_id,)).fetchall()
        )


@app.get("/api/transactions")
def list_transactions(profile_id: int = 1) -> list[dict[str, Any]]:
    with db() as conn:
        get_profile_or_404(conn, profile_id)
        return rows_to_dicts(
            conn.execute("SELECT * FROM transactions WHERE profile_id = ? ORDER BY created_at DESC", (profile_id,)).fetchall()
        )


@app.post("/api/transactions")
def create_transaction(payload: TransactionIn, profile_id: int = 1) -> dict[str, Any]:
    with db() as conn:
        get_profile_or_404(conn, profile_id)
        account = get_account_or_404(conn, payload.account_id)
        if account["profile_id"] != profile_id:
            raise HTTPException(status_code=404, detail="Account not found")
        stamp = now()
        cursor = conn.execute(
            """
            INSERT INTO transactions
                (profile_id, account_id, amount, description, allocation_type, allocation_id, created_at)
            VALUES (?, ?, ?, ?, ?, ?, ?)
            """,
            (
                profile_id,
                payload.account_id,
                payload.amount,
                payload.description,
                payload.allocation_type,
                payload.allocation_id,
                stamp,
            ),
        )
        conn.execute("UPDATE accounts SET balance = balance + ?, updated_at = ? WHERE id = ?", (payload.amount, stamp, payload.account_id))
        return row_to_dict(conn.execute("SELECT * FROM transactions WHERE id = ?", (cursor.lastrowid,)).fetchone())
