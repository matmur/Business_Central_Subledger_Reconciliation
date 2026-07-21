codeunit 50102 "Sub-Ledger Recon Mgt."
{
    // Core reconciliation. Drift is only meaningful per G/L control ACCOUNT, not per posting
    // group: several Customer Posting Groups can point at the same Receivables account, and
    // only their COMBINED sub-ledger is comparable to that account's balance. So we fold the
    // open customer ledger entries up by receivables account and write one finding per account.
    procedure RunReconciliation()
    var
        CustPostingGroup: Record "Customer Posting Group";
        ReconFinding: Record "Recon Finding";
        SubLedgerByAccount: Dictionary of [Code[20], Decimal];
        GroupsByAccount: Dictionary of [Code[20], Text];
        AccountNo: Code[20];
        RunningSum: Decimal;
        GroupList: Text;
    begin
        // Fresh snapshot each run: clear prior findings so re-running doesn't stack duplicates.
        ReconFinding.DeleteAll();

        // Pass 1 -- fold every posting group's open sub-ledger into its receivables account,
        // and remember which groups feed each account (for display).
        if CustPostingGroup.FindSet() then
            repeat
                AccountNo := CustPostingGroup."Receivables Account";
                if AccountNo <> '' then begin
                    RunningSum := 0;
                    if SubLedgerByAccount.ContainsKey(AccountNo) then
                        RunningSum := SubLedgerByAccount.Get(AccountNo);
                    SubLedgerByAccount.Set(AccountNo, RunningSum + OpenRemainingForGroup(CustPostingGroup.Code));

                    GroupList := '';
                    if GroupsByAccount.ContainsKey(AccountNo) then
                        GroupList := GroupsByAccount.Get(AccountNo);
                    if GroupList = '' then
                        GroupList := CustPostingGroup.Code
                    else
                        GroupList += ', ' + CustPostingGroup.Code;
                    GroupsByAccount.Set(AccountNo, GroupList);
                end;
            until CustPostingGroup.Next() = 0;

        // Pass 2 -- one finding per distinct receivables account.
        foreach AccountNo in SubLedgerByAccount.Keys() do
            WriteFinding(AccountNo, SubLedgerByAccount.Get(AccountNo), GroupsByAccount.Get(AccountNo));
    end;

    // Sum of remaining (LCY) over the OPEN customer ledger entries of one posting group.
    // "Remaining Amt. (LCY)" is a FlowField (verified: Cust. Ledger Entry field 16, = sum of
    // Detailed Cust. Ledg. Entry."Amount (LCY)"). A FlowField is not stored / not SIFT-
    // maintained, so it cannot be CalcSum'd; SetAutoCalcFields has the server compute it during
    // the fetch and we accumulate over the set -- one set-based query, not N+1 CalcFields.
    local procedure OpenRemainingForGroup(PostingGroupCode: Code[20]): Decimal
    var
        CustLedgerEntry: Record "Cust. Ledger Entry";
        Total: Decimal;
    begin
        CustLedgerEntry.SetRange("Customer Posting Group", PostingGroupCode);
        CustLedgerEntry.SetRange(Open, true);
        CustLedgerEntry.SetAutoCalcFields("Remaining Amt. (LCY)");
        if CustLedgerEntry.FindSet() then
            repeat
                Total += CustLedgerEntry."Remaining Amt. (LCY)";
            until CustLedgerEntry.Next() = 0;
        exit(Total);
    end;

    local procedure WriteFinding(AccountNo: Code[20]; SubLedgerBalance: Decimal; PostingGroups: Text)
    var
        GLAccount: Record "G/L Account";
        ReconFinding: Record "Recon Finding";
        GLBalance: Decimal;
    begin
        // G/L side: the control account's current total balance. "Balance" (verified: G/L
        // Account field 36) is a FlowField summing G/L Entry amounts with no date filter, so it
        // must be CalcFields'd before it holds a value.
        GLBalance := 0;
        if GLAccount.Get(AccountNo) then begin
            GLAccount.CalcFields(Balance);
            GLBalance := GLAccount.Balance;
        end;

        ReconFinding.Init();
        ReconFinding."Check Date" := WorkDate();
        ReconFinding."G/L Control Account No." := AccountNo;
        ReconFinding."Customer Posting Group" := CopyStr(PostingGroups, 1, MaxStrLen(ReconFinding."Customer Posting Group"));
        ReconFinding."Sub-Ledger Balance" := SubLedgerBalance;
        ReconFinding."G/L Balance" := GLBalance;
        // Insert(true) so the table's OnInsert derives Delta and Status.
        ReconFinding.Insert(true);
    end;
}
