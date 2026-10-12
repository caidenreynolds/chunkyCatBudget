import csv
import io
import json
import unittest
from fastapi import HTTPException
from backend import test_main
from backend.app import main


class BackupTests(unittest.TestCase):
    tearDown = test_main.BudgetApiTests.tearDown
    _account = test_main.BudgetApiTests._account
    _paycheck_profile = test_main.BudgetApiTests._paycheck_profile
    _chunk = test_main.BudgetApiTests._chunk
    def setUp(self):
        test_main.BudgetApiTests.setUp(self)
        with main.db() as conn:
            self.user_id = conn.execute('SELECT owner_user_id FROM budget_profiles WHERE id = ?', (self.profile_id,)).fetchone()[0]

    def backup(self):
        return main.export_profile(self.profile_id, self.user_id)['csv_data']

    def test_round_trip_and_overwrite_clear_history(self):
        account = self._account('Checking, "family"\nshared')
        paycheck = self._paycheck_profile(account['id'])
        self._chunk('Food', account['id'], 100, paycheck['id'])
        loan = main.create_chunk(main.ChunkIn(name='Loan', chunk_type='loan', amount_per_paycheck=25, paycheck_profile_id=paycheck['id'], loan_balance=500, loan_interest_rate=5), self.profile_id)
        main.add_paycheck(main.AddPaycheckIn(paycheck_profile_id=paycheck['id']), self.profile_id)
        backup = self.backup()
        restored = main.import_profile(main.RestoreProfileIn(csv_data=backup, user_id=self.user_id))
        exported = main.export_profile(restored['id'], self.user_id)['csv_data']
        original_rows = list(csv.DictReader(io.StringIO(backup)))
        restored_rows = list(csv.DictReader(io.StringIO(exported)))
        self.assertEqual(len(original_rows), len(restored_rows))
        for old, new in zip(original_rows, restored_rows):
            old_data, new_data = json.loads(old['data']), json.loads(new['data'])
            for field in ['account_id', 'default_account_id', 'paycheck_profile_id']:
                if field in old_data and old_data[field] is not None:
                    self.assertNotEqual(old_data.pop(field), new_data.pop(field))
            self.assertEqual(old_data, new_data)
        self.assertEqual(main.list_paychecks(restored['id']), [])
        main.create_money_movement(main.MoneyMovementIn(source_type='unallocated', source_id=account['id'], destination_type='outside_account', amount=1, note='Delete this note'), self.profile_id)
        main.import_profile(main.RestoreProfileIn(csv_data=backup, user_id=self.user_id, target_profile_id=self.profile_id, confirm_overwrite=True))
        self.assertEqual(main.list_paychecks(self.profile_id), [])
        self.assertEqual(main.list_money_movements(self.profile_id), [])
        self.assertEqual(main.list_transactions(self.profile_id), [])
        self.assertEqual(main.list_accounts(self.profile_id)[0]['balance'], 975)

    def test_invalid_restore_leaves_existing_data_intact(self):
        account = self._account('Safe')
        paycheck = self._paycheck_profile(account['id'])
        self._chunk('Food', account['id'], 100, paycheck['id'])
        rows = list(csv.DictReader(io.StringIO(self.backup())))
        data = json.loads(rows[-1]['data'])
        data['account_id'] = 999999
        rows[-1]['data'] = json.dumps(data)
        output = io.StringIO()
        writer = csv.DictWriter(output, fieldnames=['format', 'record_type', 'id', 'data'])
        writer.writeheader()
        writer.writerows(rows)
        with self.assertRaises(HTTPException):
            main.import_profile(main.RestoreProfileIn(csv_data=output.getvalue(), user_id=self.user_id, target_profile_id=self.profile_id, confirm_overwrite=True))
        self.assertEqual(main.list_accounts(self.profile_id)[0]['name'], 'Safe')
        self.assertEqual(len(main.list_chunks(self.profile_id)), 1)

    def test_overwrite_requires_confirmation_and_admin(self):
        self._account('Safe')
        backup = self.backup()
        with self.assertRaises(HTTPException):
            main.import_profile(main.RestoreProfileIn(csv_data=backup, user_id=self.user_id, target_profile_id=self.profile_id))
        with main.db() as conn:
            conn.execute("UPDATE user_profile_access SET role = 'read_only' WHERE user_id = ? AND profile_id = ?", (self.user_id, self.profile_id))
        with self.assertRaises(HTTPException) as caught:
            main.import_profile(main.RestoreProfileIn(csv_data=backup, user_id=self.user_id, target_profile_id=self.profile_id, confirm_overwrite=True))
        self.assertEqual(caught.exception.status_code, 403)
        self.assertEqual(main.list_accounts(self.profile_id)[0]['name'], 'Safe')

    def test_lower_paycheck_reports_active_assigned_chunk_shortage(self):
        account = self._account('Checking')
        paycheck = self._paycheck_profile(account['id'])
        self._chunk('Food', account['id'], 600, paycheck['id'])
        inactive = self._chunk('Inactive', account['id'], 700, paycheck['id'])
        with main.db() as conn:
            conn.execute('UPDATE budget_chunks SET is_active = 0 WHERE id = ?', (inactive['id'],))
        saved = main.upsert_paycheck_profile(main.PaycheckProfileIn(id=paycheck['id'], net_pay_amount=500, pay_frequency='biweekly', default_account_id=account['id']), self.profile_id)
        self.assertEqual(saved['chunk_shortage'], 100)
        self.assertEqual(saved['chunk_total'], 600)
        unchanged = main.upsert_paycheck_profile(main.PaycheckProfileIn(id=paycheck['id'], net_pay_amount=500, pay_frequency='biweekly', default_account_id=account['id']), self.profile_id)
        self.assertEqual(unchanged['chunk_shortage'], 0)


if __name__ == '__main__':
    unittest.main()
