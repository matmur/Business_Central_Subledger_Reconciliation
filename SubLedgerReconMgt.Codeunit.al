codeunit 50102 "Sub-Ledger Recon Mgt."
{
    // Core reconciliation. Drift is only meaningful per G/L control ACCOUNT, not per posting
    // group: several Customer Posting Groups can point at the same Receivables account, and
    // only their COMBINED sub-ledger is comparable to that account's balance. So we fold the
    // open customer ledger entries up by account and write one finding per account.
    //
    // Which account an entry belongs to is taken from the G/L entries that were posted WITH it,
    // not from the posting group's current setup. The posting group stored on the entry is
    // fixed at posting time, but the account behind that group can be changed afterwards.
    // Reading the setup would then measure old entries against a new account and report drift
    // twice - once on the account that lost the entries and once on the one that gained them,
    // both arithmetically correct and both wrong. The base application's report 33 works from
    // the setup and has exactly that behaviour; this uses the posted account instead.
    //
    // Price of that choice, deliberately paid: the account is resolved per entry through
    // G/L Entry instead of once per posting group. Entries with no transaction number, and
    // entries whose transaction carries no line on a known receivables account, fall back to
    // the posting group's current account - that is the old behaviour, kept as a safety net
    // rather than as the rule.

    procedure RunReconciliation()
    var
        CustPostingGroup: Record "Customer Posting Group";
        CustLedgerEntry: Record "Cust. Ledger Entry";
        ReconFinding: Record "Recon Finding";
        SubLedgerByAccount: Dictionary of [Code[20], Decimal];
        AccountByGroup: Dictionary of [Code[20], Code[20]];
        ReceivablesAccounts: Dictionary of [Code[20], Boolean];
        GroupsByAccount: Dictionary of [Code[20], Text];
        SeenGroupOnAccount: Dictionary of [Text, Boolean];
        AccountNo: Code[20];
    begin
        // Snapshot semantics: each run replaces the previous result rather than appending to
        // it, so the page always shows the current state and never a mix of runs.
        ReconFinding.DeleteAll();

        // Pass 1 -- read the current setup. It provides three things: which accounts count as
        // receivables control accounts, the fallback account per posting group, and a seed so
        // that an account with a balance but no open entries is still checked.
        if CustPostingGroup.FindSet() then
            repeat
                AccountNo := CustPostingGroup."Receivables Account";
                if AccountNo <> '' then begin
                    AccountByGroup.Set(CustPostingGroup.Code, AccountNo);
                    ReceivablesAccounts.Set(AccountNo, true);
                    if not SubLedgerByAccount.ContainsKey(AccountNo) then
                        SubLedgerByAccount.Set(AccountNo, 0);
                    RememberGroup(GroupsByAccount, SeenGroupOnAccount, AccountNo, CustPostingGroup.Code);
                end;
            until CustPostingGroup.Next() = 0;

        // Pass 2 -- every open entry, counted against the account it was actually posted to.
        CustLedgerEntry.SetRange(Open, true);
        CustLedgerEntry.SetAutoCalcFields("Remaining Amt. (LCY)");
        if CustLedgerEntry.FindSet() then
            repeat
                AccountNo := ResolveAccount(
                    PostedAccountFor(CustLedgerEntry, ReceivablesAccounts),
                    FallbackAccountFor(CustLedgerEntry."Customer Posting Group", AccountByGroup));
                if AccountNo <> '' then begin
                    AddAmount(SubLedgerByAccount, AccountNo, CustLedgerEntry."Remaining Amt. (LCY)");
                    RememberGroup(GroupsByAccount, SeenGroupOnAccount, AccountNo, CustLedgerEntry."Customer Posting Group");
                end;
            until CustLedgerEntry.Next() = 0;

        // Pass 3 -- one finding per distinct receivables account.
        foreach AccountNo in SubLedgerByAccount.Keys() do
            WriteFinding(AccountNo, SubLedgerByAccount.Get(AccountNo), GroupTextFor(GroupsByAccount, AccountNo));
    end;

    // The account this entry was actually posted to: the receivables line of the same
    // transaction, for the same customer. Returns empty when the entry has no transaction
    // number, or when its transaction holds no line on an account that any posting group
    // currently treats as a receivables account.
    local procedure PostedAccountFor(CustLedgerEntry: Record "Cust. Ledger Entry"; var ReceivablesAccounts: Dictionary of [Code[20], Boolean]): Code[20]
    var
        GLEntry: Record "G/L Entry";
    begin
        if CustLedgerEntry."Transaction No." = 0 then
            exit('');

        GLEntry.SetRange("Transaction No.", CustLedgerEntry."Transaction No.");
        GLEntry.SetRange("Source Type", GLEntry."Source Type"::Customer);
        GLEntry.SetRange("Source No.", CustLedgerEntry."Customer No.");
        if GLEntry.FindSet() then
            repeat
                if ReceivablesAccounts.ContainsKey(GLEntry."G/L Account No.") then
                    exit(GLEntry."G/L Account No.");
            until GLEntry.Next() = 0;

        exit('');
    end;

    local procedure FallbackAccountFor(PostingGroupCode: Code[20]; var AccountByGroup: Dictionary of [Code[20], Code[20]]): Code[20]
    begin
        if AccountByGroup.ContainsKey(PostingGroupCode) then
            exit(AccountByGroup.Get(PostingGroupCode));
        exit('');
    end;

    // The posted account wins; the posting group's current account is only a fallback. Public
    // so that the rule can be pinned down by a test without posting anything.
    procedure ResolveAccount(PostedAccount: Code[20]; FallbackAccount: Code[20]): Code[20]
    begin
        if PostedAccount <> '' then
            exit(PostedAccount);
        exit(FallbackAccount);
    end;

    local procedure AddAmount(var SubLedgerByAccount: Dictionary of [Code[20], Decimal]; AccountNo: Code[20]; Amount: Decimal)
    var
        RunningSum: Decimal;
    begin
        if SubLedgerByAccount.ContainsKey(AccountNo) then
            RunningSum := SubLedgerByAccount.Get(AccountNo);
        SubLedgerByAccount.Set(AccountNo, RunningSum + Amount);
    end;

    // Collects, for display only, which posting groups feed an account. Both the groups that
    // point at it today and the groups whose older entries still sit on it end up here, which
    // is what makes a past reassignment visible in the result instead of invisible.
    local procedure RememberGroup(var GroupsByAccount: Dictionary of [Code[20], Text]; var SeenGroupOnAccount: Dictionary of [Text, Boolean]; AccountNo: Code[20]; PostingGroupCode: Code[20])
    var
        SeenKey: Text;
        GroupList: Text;
    begin
        if PostingGroupCode = '' then
            exit;

        SeenKey := AccountNo + '|' + PostingGroupCode;
        if SeenGroupOnAccount.ContainsKey(SeenKey) then
            exit;
        SeenGroupOnAccount.Set(SeenKey, true);

        if GroupsByAccount.ContainsKey(AccountNo) then
            GroupList := GroupsByAccount.Get(AccountNo);
        if GroupList = '' then
            GroupList := PostingGroupCode
        else
            GroupList += ', ' + PostingGroupCode;
        GroupsByAccount.Set(AccountNo, GroupList);
    end;

    local procedure GroupTextFor(var GroupsByAccount: Dictionary of [Code[20], Text]; AccountNo: Code[20]): Text
    begin
        if GroupsByAccount.ContainsKey(AccountNo) then
            exit(GroupsByAccount.Get(AccountNo));
        exit('');
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
