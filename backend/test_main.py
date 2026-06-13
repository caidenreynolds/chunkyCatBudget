import tempfile
import unittest
from pathlib import Path

from fastapi import HTTPException

from backend.app import main


class BudgetApiTests(unittest.TestCase):
    def setUp(self) -> None:
        self.temp_dir = tempfile.TemporaryDirectory()
        main.DATABASE_URL = f"sqlite:///{Path(self.temp_dir.name) / 'budget.db'}"
        main.init_db()
        with main.db() as conn:
            self.profile_id = conn.execute(
                "SELECT id FROM budget_profiles ORDER BY id LIMIT 1"
            ).fetchone()["id"]

    def tearDown(self) -> None:
        self.temp_dir.cleanup()

    def _account(self, name: str) -> dict:
        return main.create_account(main.AccountIn(name=name), self.profile_id)

    def _chunk(self, name: str, account_id: int, amount: float) -> dict:
        return main.create_chunk(
            main.ChunkIn(
                name=name,
                account_id=account_id,
                amount_per_paycheck=amount,
            ),
            self.profile_id,
        )

    def test_paycheck_allocates_chunks_across_accounts(self) -> None:
        checking = self._account("Checking")
        savings = self._account("Savings")
        checking_chunk = self._chunk("Bills", checking["id"], 100)
        savings_chunk = self._chunk("Emergency fund", savings["id"], 200)
        paycheck_profile = main.upsert_paycheck_profile(
            main.PaycheckProfileIn(
                name="Primary paycheck",
                net_pay_amount=1000,
                pay_frequency="biweekly",
                default_account_id=checking["id"],
            ),
            self.profile_id,
        )

        result = main.add_paycheck(
            main.AddPaycheckIn(
                paycheck_profile_id=paycheck_profile["id"],
                account_id=savings["id"],
            ),
            self.profile_id,
        )

        accounts = {
            account["id"]: account
            for account in main.list_accounts(self.profile_id)
        }
        chunks = {
            chunk["id"]: chunk
            for chunk in main.list_chunks(self.profile_id)
        }
        self.assertEqual(result["paycheck"]["account_id"], checking["id"])
        self.assertEqual(result["unallocated_amount"], 700)
        self.assertEqual(accounts[checking["id"]]["balance"], 800)
        self.assertEqual(accounts[checking["id"]]["unallocated_balance"], 700)
        self.assertEqual(accounts[savings["id"]]["balance"], 200)
        self.assertEqual(accounts[savings["id"]]["unallocated_balance"], 0)
        self.assertEqual(chunks[checking_chunk["id"]]["balance"], 100)
        self.assertEqual(chunks[savings_chunk["id"]]["balance"], 200)
        paycheck = main.list_paychecks(self.profile_id)[0]
        self.assertEqual(paycheck["account_name"], "Checking")
        self.assertEqual(paycheck["allocated_amount"], 300)
        self.assertEqual(paycheck["unallocated_amount"], 700)
        self.assertEqual(
            [allocation["chunk_name"] for allocation in paycheck["allocations"]],
            ["Bills", "Emergency fund"],
        )

        reverted = main.revert_paycheck(paycheck["id"], self.profile_id)
        accounts = {
            account["id"]: account
            for account in main.list_accounts(self.profile_id)
        }
        chunks = {
            chunk["id"]: chunk
            for chunk in main.list_chunks(self.profile_id)
        }
        self.assertTrue(reverted["is_reverted"])
        self.assertEqual(accounts[checking["id"]]["balance"], 0)
        self.assertEqual(accounts[savings["id"]]["balance"], 0)
        self.assertEqual(chunks[checking_chunk["id"]]["balance"], 0)
        self.assertEqual(chunks[savings_chunk["id"]]["balance"], 0)

        with self.assertRaisesRegex(HTTPException, "already been reverted"):
            main.revert_paycheck(paycheck["id"], self.profile_id)

    def test_existing_chunk_type_cannot_change(self) -> None:
        checking = self._account("Checking")
        chunk = self._chunk("Bills", checking["id"], 100)

        with self.assertRaisesRegex(HTTPException, "Chunk type cannot be changed"):
            main.update_chunk(
                chunk["id"],
                main.ChunkIn(
                    name=chunk["name"],
                    account_id=checking["id"],
                    chunk_type="loan",
                    amount_per_paycheck=chunk["amount_per_paycheck"],
                    balance=chunk["balance"],
                ),
                self.profile_id,
            )

    def test_revert_restores_loan_balance_before_paycheck(self) -> None:
        checking = self._account("Checking")
        loan = main.create_chunk(
            main.ChunkIn(
                name="Car loan",
                chunk_type="loan",
                amount_per_paycheck=100,
                loan_balance=1000,
                loan_interest_rate=0,
            ),
            self.profile_id,
        )
        paycheck_profile = main.upsert_paycheck_profile(
            main.PaycheckProfileIn(
                net_pay_amount=100,
                pay_frequency="biweekly",
                default_account_id=checking["id"],
            ),
            self.profile_id,
        )
        main.add_paycheck(
            main.AddPaycheckIn(paycheck_profile_id=paycheck_profile["id"]),
            self.profile_id,
        )
        paycheck = main.list_paychecks(self.profile_id)[0]

        main.revert_paycheck(paycheck["id"], self.profile_id)

        account = main.list_accounts(self.profile_id)[0]
        restored_loan = next(
            chunk for chunk in main.list_chunks(self.profile_id)
            if chunk["id"] == loan["id"]
        )
        self.assertEqual(account["balance"], 0)
        self.assertEqual(restored_loan["loan_balance"], 1000)


if __name__ == "__main__":
    unittest.main()
