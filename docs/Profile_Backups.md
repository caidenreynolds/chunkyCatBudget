# Profile CSV backups

On the Budget Profiles home page, use the download button beside a profile to export it. Use **Import CSV Backup** on the same page to restore a file into a new profile, or select an existing profile where you have admin access and confirm permanent overwrite.

Backups include all bank accounts (including inactive accounts and account order), paycheck profiles, standard and loan chunk settings, their relationships, and current balances. Paycheck history, allocations made by past paychecks, transactions, transfers, notes, users, invitations, and sharing permissions are excluded. A new profile belongs to the importing user. Overwriting retains the destination profile's name, owner and members while replacing all budget data and deleting its history.

CSV file selection and download are supported in the web app. Other Flutter targets report that these operations require the web app.

The versioned CSV has `format,record_type,id,data` columns; `data` contains a quoted JSON object to preserve record-specific fields and names containing commas, quotes, or newlines. Keep the original file for restoration. Files are limited to 10 MB. Validation checks the format, required fields, amounts, duplicate IDs and relationships before making changes. Import runs in a single database transaction and remaps IDs, so an import cannot accidentally link to another profile's accounts or chunks.

The current API's identity model trusts client-provided user IDs. The new endpoints check profile membership/admin access using that model, but authenticated server-side sessions are needed to prevent impersonation (see Profile_Sharing_Review.md).
