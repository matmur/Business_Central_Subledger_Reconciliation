codeunit 50102 "Sub-Ledger Recon Mgt."
{
    // Reconciles per G/L receivables account, because several posting groups can share one account.
    // Each open entry counts against the account it was actually posted to (README, "The two design decisions").

    procedure RunReconciliation()
    var
        CustPostingGroup: Record "Customer Posting Group";
        CustLedgerEntry: Record "Cust. Ledger Entry";
        ReconFinding: Record "Recon Finding";
        SubLedgerByAccount: Dictionary of [Code[20], Decimal];
        AccountByGroup: Dictionary of [Code[20], Code[20]];
        ReceivablesAccounts: Dictionary of [Code[20], Boolean];
        GroupsByAccount: Dictionary of [Code[20], List of [Code[20]]];
        AccountNo: Code[20];
        FallbackAccount: Code[20];
        SubLedgerBalance: Decimal;
    begin
        ReconFinding.DeleteAll();

        if CustPostingGroup.FindSet() then
            repeat
                AccountNo := CustPostingGroup."Receivables Account";
                if AccountNo <> '' then begin
                    AccountByGroup.Set(CustPostingGroup.Code, AccountNo);
                    ReceivablesAccounts.Set(AccountNo, true);
                    if not SubLedgerByAccount.ContainsKey(AccountNo) then
                        SubLedgerByAccount.Add(AccountNo, 0);
                    AddGroup(GroupsByAccount, AccountNo, CustPostingGroup.Code);
                end;
            until CustPostingGroup.Next() = 0;
        AddClassifiedReceivablesAccounts(ReceivablesAccounts);

        CustLedgerEntry.SetRange(Open, true);
        CustLedgerEntry.SetLoadFields("Customer No.", "Customer Posting Group", "Transaction No.");
        CustLedgerEntry.SetAutoCalcFields("Remaining Amt. (LCY)");
        if CustLedgerEntry.FindSet() then
            repeat
                if not AccountByGroup.Get(CustLedgerEntry."Customer Posting Group", FallbackAccount) then
                    FallbackAccount := '';
                AccountNo := ResolveAccount(PostedAccountFor(CustLedgerEntry, ReceivablesAccounts), FallbackAccount);
                if AccountNo <> '' then begin
                    if not SubLedgerByAccount.Get(AccountNo, SubLedgerBalance) then
                        SubLedgerBalance := 0;
                    SubLedgerByAccount.Set(AccountNo, SubLedgerBalance + CustLedgerEntry."Remaining Amt. (LCY)");
                    AddGroup(GroupsByAccount, AccountNo, CustLedgerEntry."Customer Posting Group");
                end;
            until CustLedgerEntry.Next() = 0;

        foreach AccountNo in SubLedgerByAccount.Keys() do
            WriteFinding(AccountNo, SubLedgerByAccount.Get(AccountNo), GroupsByAccount);
    end;

    // The posted account wins; the posting group's current account is only the fallback.
    procedure ResolveAccount(PostedAccount: Code[20]; FallbackAccount: Code[20]): Code[20]
    begin
        if PostedAccount <> '' then
            exit(PostedAccount);
        exit(FallbackAccount);
    end;

    // Receivables account of the G/L line posted in the same transaction; empty if there is none.
    local procedure PostedAccountFor(CustLedgerEntry: Record "Cust. Ledger Entry"; var ReceivablesAccounts: Dictionary of [Code[20], Boolean]): Code[20]
    var
        GLEntry: Record "G/L Entry";
    begin
        if CustLedgerEntry."Transaction No." = 0 then
            exit('');

        GLEntry.SetRange("Transaction No.", CustLedgerEntry."Transaction No.");
        GLEntry.SetRange("Source Type", GLEntry."Source Type"::Customer);
        GLEntry.SetRange("Source No.", CustLedgerEntry."Customer No.");
        GLEntry.SetLoadFields("G/L Account No.");
        if GLEntry.FindSet() then
            repeat
                if ReceivablesAccounts.ContainsKey(GLEntry."G/L Account No.") then
                    exit(GLEntry."G/L Account No.");
            until GLEntry.Next() = 0;
        exit('');
    end;

    // Adds accounts in the system subcategory "Accounts Receivable"; GetAR() returns its localized name.
    local procedure AddClassifiedReceivablesAccounts(var ReceivablesAccounts: Dictionary of [Code[20], Boolean])
    var
        GLAccount: Record "G/L Account";
        GLAccountCategory: Record "G/L Account Category";
        GLAccountCategoryMgt: Codeunit "G/L Account Category Mgt.";
    begin
        GLAccountCategory.SetRange("System Generated", true);
        GLAccountCategory.SetRange(Description, CopyStr(GLAccountCategoryMgt.GetAR(), 1, MaxStrLen(GLAccountCategory.Description)));
        if GLAccountCategory.FindSet() then
            repeat
                GLAccount.SetRange("Account Subcategory Entry No.", GLAccountCategory."Entry No.");
                GLAccount.SetLoadFields("No.");
                if GLAccount.FindSet() then
                    repeat
                        ReceivablesAccounts.Set(GLAccount."No.", true);
                    until GLAccount.Next() = 0;
            until GLAccountCategory.Next() = 0;
    end;

    local procedure AddGroup(var GroupsByAccount: Dictionary of [Code[20], List of [Code[20]]]; AccountNo: Code[20]; GroupCode: Code[20])
    var
        Groups: List of [Code[20]];
    begin
        if GroupCode = '' then
            exit;
        if GroupsByAccount.Get(AccountNo, Groups) then
            if Groups.Contains(GroupCode) then
                exit;
        Groups.Add(GroupCode);
        GroupsByAccount.Set(AccountNo, Groups);
    end;

    local procedure WriteFinding(AccountNo: Code[20]; SubLedgerBalance: Decimal; var GroupsByAccount: Dictionary of [Code[20], List of [Code[20]]])
    var
        GLAccount: Record "G/L Account";
        ReconFinding: Record "Recon Finding";
        Groups: List of [Code[20]];
        GroupCode: Code[20];
        GroupText: Text;
    begin
        if GroupsByAccount.Get(AccountNo, Groups) then
            foreach GroupCode in Groups do
                if GroupText = '' then
                    GroupText := GroupCode
                else
                    GroupText += ', ' + GroupCode;

        ReconFinding.Init();
        ReconFinding."Check Date" := Today(); // both balances are measured now; WorkDate could be backdated
        ReconFinding."G/L Control Account No." := AccountNo;
        ReconFinding."Customer Posting Group" := CopyStr(GroupText, 1, MaxStrLen(ReconFinding."Customer Posting Group"));
        ReconFinding."Sub-Ledger Balance" := SubLedgerBalance;
        if GLAccount.Get(AccountNo) then begin
            GLAccount.CalcFields(Balance);
            ReconFinding."G/L Balance" := GLAccount.Balance;
        end;
        ReconFinding.Insert(true); // OnInsert derives Delta and Status
    end;
}
