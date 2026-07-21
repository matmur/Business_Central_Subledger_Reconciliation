codeunit 50103 "Recon Check Job"
{
    // TableNo = "Job Queue Entry" makes this codeunit runnable by the Job Queue.
    // When a Job Queue Entry with "Object Type to Run" = Codeunit and
    // "Object ID to Run" = 50103 fires, the platform calls OnRun with the
    // Job Queue Entry record as Rec. That record parameter is why the signature
    // must match the Job Queue Entry table.
    TableNo = "Job Queue Entry";

    trigger OnRun()
    var
        SubLedgerReconMgt: Codeunit "Sub-Ledger Recon Mgt.";
    begin
        SubLedgerReconMgt.RunReconciliation();
    end;
}
