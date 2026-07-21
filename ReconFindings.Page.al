page 50104 "Recon Findings"
{
    PageType = List;
    ApplicationArea = All;
    UsageCategory = Lists;
    SourceTable = "Recon Finding";
    Caption = 'Reconciliation Findings';
    Editable = false;
    SourceTableView = sorting("Entry No.") order(descending);

    layout
    {
        area(Content)
        {
            repeater(Findings)
            {
                field("Check Date"; Rec."Check Date") { StyleExpr = RowStyle; }
                field("Customer Posting Group"; Rec."Customer Posting Group") { StyleExpr = RowStyle; }
                field("G/L Control Account No."; Rec."G/L Control Account No.") { StyleExpr = RowStyle; }
                field("Sub-Ledger Balance"; Rec."Sub-Ledger Balance") { StyleExpr = RowStyle; }
                field("G/L Balance"; Rec."G/L Balance") { StyleExpr = RowStyle; }
                field(Delta; Rec.Delta) { StyleExpr = RowStyle; }
                field(Status; Rec.Status) { StyleExpr = RowStyle; }
            }
        }
    }

    actions
    {
        area(Processing)
        {
            action(RunReconciliationCheck)
            {
                Caption = 'Run Reconciliation Check';
                Image = Refresh;
                ToolTip = 'Recalculates the sub-ledger vs. G/L reconciliation and records one finding per customer posting group.';

                trigger OnAction()
                var
                    SubLedgerReconMgt: Codeunit "Sub-Ledger Recon Mgt.";
                begin
                    SubLedgerReconMgt.RunReconciliation();
                    CurrPage.Update(false);
                end;
            }
        }
        // Modern promoted-action pattern (actionref), so no deprecation warnings.
        area(Promoted)
        {
            group(Category_Process)
            {
                Caption = 'Process';

                actionref(RunReconciliationCheck_Promoted; RunReconciliationCheck) { }
            }
        }
    }

    var
        RowStyle: Text;

    // Row styling is decided per record: red (Unfavorable) when drift is detected,
    // green (Favorable) when the group is balanced. StyleExpr on each field paints the row.
    trigger OnAfterGetRecord()
    begin
        if Rec.Status = Rec.Status::"Drift Detected" then
            RowStyle := 'Unfavorable'
        else
            RowStyle := 'Favorable';
    end;
}
