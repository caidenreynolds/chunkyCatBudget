# Profile sharing review

Reviewed the local implementation after adding CSV backup and restore. These findings describe existing behavior; a full authentication and sharing redesign is outside these feature changes.

## Critical: API access does not authenticate the caller

`backend/app/main.py`: `login` returns user metadata without a session or token. Budget data endpoints accept a `profile_id` but never establish who is calling. `dashboard_summary`, account/chunk mutations, paycheck operations, transfers, transactions and `delete_budget_profile` lack membership/role checks. A caller who reaches the API can read another profile or modify/delete it, regardless of the interface's read-only controls. The new backup endpoints check membership/admin status, but their caller-provided `user_id` can also be impersonated under the existing identity model.

Reproduction: request a dashboard with another profile ID, or PUT an account in that profile without signing in. Fix by issuing authenticated sessions, deriving caller identity on the server, and applying membership checks for reads and role checks for every mutation. Do not trust a submitted user ID as identity.

## High: invitations permit impersonation and stale role changes

`invite_budget_profile_member` checks `invited_by_user_id` supplied by the caller. The Settings screen lets the user choose that ID from every user in the database rather than using the signed-in identity. `accept_invitation` likewise trusts a submitted `user_id`; checking its email against the invitation does not authenticate the recipient.

Acceptance uses `ON CONFLICT ... DO UPDATE SET role = excluded.role`. Multiple pending invitations can therefore change an existing member's role later, including demoting the owner if they accept a read-only invitation. There is no owner protection, expiration, cancellation, or duplicate pending invitation check. Derive inviter/recipient from a session, restrict role changes to explicit authorized operations, protect the owner, and expire/revoke superseded invitations.

## High: passwordless users can be claimed

`create_user` can create a user without a password. `login` sets the submitted password on first login for any user lacking password credentials; `create_user` can also set an existing passwordless user's password. Anyone knowing such an email can claim that identity and its shared profiles. Require a verified enrollment/reset flow instead.

## Medium: member management is incomplete

There is a members listing API, but Settings shows the global `/api/users` directory rather than this profile's members. There are no endpoints or controls to change a member's role, remove access, cancel invitations, decline invitations, or leave a shared profile. Admin is the only write role: it combines editing and inviting, with no separate read/write member role. Add profile-scoped member management, owner protections, and a clear permission matrix.

## Medium: interface permits deletion of read-only profiles

The home screen enables selection and deletion for every accessible profile. `_deleteSelectedProfiles` calls the unprotected delete endpoint, so a read-only member can delete the entire shared profile through the normal interface. Restrict both the control and the API; distinguish deleting a profile from leaving one.

## Medium: directory and invitation privacy

`list_users`, `list_budget_profiles` without a user ID, `list_budget_profile_members`, and `list_invitations` can expose users, profiles, membership and invitation details without authentication. Restrict directory access and scope invitations to the authenticated recipient or authorized profile administrator.

## Verification boundary

These findings follow the API and Flutter code paths; no live accounts were accessed or modified. Backup tests exercise membership/admin checks within the existing caller-ID model, not an authenticated security boundary.
