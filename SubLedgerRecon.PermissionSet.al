permissionset 50105 "Sub-Ledger Recon"
{
    // Without an assignable permission set, using this extension requires SUPER — which no
    // customer will grant for a reporting add-on, and which AppSource rejects outright.
    // Assignable = true makes it selectable in User Permission Sets.
    Assignable = true;
    Caption = 'Sub-Ledger Reconciliation';

    Permissions =
        table "Recon Finding" = X,
        // RIMD rather than R: the reconciliation run deletes the previous snapshot and
        // inserts the current one, so a read-only grant would break the feature for anyone
        // who is not SUPER.
        tabledata "Recon Finding" = RIMD,
        codeunit "Sub-Ledger Recon Mgt." = X,
        codeunit "Recon Check Job" = X,
        page "Recon Findings" = X;
}
