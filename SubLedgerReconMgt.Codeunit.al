codeunit 50102 "Sub-Ledger Recon Mgt."
{
    // Core reconciliation. Drift is only meaningful per G/L control ACCOUNT, not per posting
    // group: several Customer Posting Groups can point at the same Receivables account, and
    // only their COMBINED sub-ledger is comparable to that account's balance. So we fold the
    // open customer ledger entries up by receivables account and write one finding per account.
    //
    // Known limitation, by design: the receivables account is read from the posting group's
    // CURRENT setup, while the G/L entries were posted to whatever account was configured at
    // posting time. If a posting group's Receivables Account is changed after entries exist,
    // both the old and the new account will show drift. That is the correct alarm, but the
    // finding cannot explain the cause on its own.
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
        // Snapshot semantics: each run replaces the previous result rather than appending to
        // it, so the page always shows the current state and never a mix of runs.
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
    //
    // "Remaining Amt. (LCY)" is a FlowField over Detailed Cust. Ledg. Entry. A FlowField is
    // not stored and not SIFT-maintained, so CalcSums cannot be used on it. SetAutoCalcFields
    // has the server compute it as part of the same fetch, which turns what would otherwise be
    // one CalcFields round trip per entry into a single query -- but the summing itself still
    // happens here, row by row.
    //
    // At the volumes this demonstrator targets that is the right trade: it stays readable and
    // needs no SIFT key. On a tenant with a large open-item count the scalable alternative is
    // to CalcSums over Detailed Cust. Ledg. Entry."Amount (LCY)" directly, which IS SIFT-able,
    // at the cost of having to reproduce the entry-type filtering the FlowField does for free.
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
        // G/L side: the control account's current total balance. "Balance" is a FlowField over
        // G/L Entry with no date filter, so it must be CalcFields'd before it holds a value.
        //
        // Both sides are therefore "as of now": open entries are open now, and the balance is
        // the running total now. That is why the finding is stamped with Today() rather than
        // WorkDate() -- WorkDate can be backdated, which would label a current measurement with
        // a date it does not describe. Point-in-time reconciliation would need both sides
        // filtered, and on the sub-ledger side that means reconstructing which entries were
        // open on that date; deliberately out of scope here.
        GLBalance := 0;
        if GLAccount.Get(AccountNo) then begin
            GLAccount.CalcFields(Balance);
            GLBalance := GLAccount.Balance;
        end;

        ReconFinding.Init();
        ReconFinding."Check Date" := Today();
        ReconFinding."G/L Control Account No." := AccountNo;
        ReconFinding."Customer Posting Group" := CopyStr(PostingGroups, 1, MaxStrLen(ReconFinding."Customer Posting Group"));
        ReconFinding."Sub-Ledger Balance" := SubLedgerBalance;
        ReconFinding."G/L Balance" := GLBalance;
        // Insert(true) so the table's OnInsert derives Delta and Status.
        ReconFinding.Insert(true);
    end;
}
