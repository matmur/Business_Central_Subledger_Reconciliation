codeunit 50103 "Recon Check Job"
{
    // Job Queue entry point (Object Type to Run = Codeunit, Object ID to Run = 50103).
    TableNo = "Job Queue Entry";

    trigger OnRun()
    var
        SubLedgerReconMgt: Codeunit "Sub-Ledger Recon Mgt.";
    begin
        SubLedgerReconMgt.RunReconciliation();
    end;
}
