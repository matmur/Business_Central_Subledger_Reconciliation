codeunit 50103 "Recon Check Job"
{
    // Entry point for scheduled runs. A Job Queue Entry with "Object Type to Run" = Codeunit
    // and "Object ID to Run" = 50103 calls OnRun here.
    //
    // TableNo = "Job Queue Entry" is the conventional signature for a Job Queue codeunit, not
    // a platform requirement — the Job Queue will happily run a codeunit without it. Declaring
    // it means Rec is the Job Queue Entry record, which is what you need if the job ever has
    // to read its own parameter string or report progress back onto the entry. Kept here so
    // that extension point exists without a later signature change.
    TableNo = "Job Queue Entry";

    trigger OnRun()
    var
        SubLedgerReconMgt: Codeunit "Sub-Ledger Recon Mgt.";
    begin
        SubLedgerReconMgt.RunReconciliation();
    end;
}
