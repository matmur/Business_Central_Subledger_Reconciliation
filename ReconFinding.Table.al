table 50101 "Recon Finding"
{
    Caption = 'Reconciliation Finding';
    DataClassification = CustomerContent;
    LookupPageId = "Recon Findings";
    DrillDownPageId = "Recon Findings";

    fields
    {
        field(1; "Entry No."; Integer)
        {
            Caption = 'Entry No.';
            AutoIncrement = true;
            ToolTip = 'Specifies a unique, system-assigned number for the reconciliation finding.';
        }
        field(2; "Check Date"; Date)
        {
            Caption = 'Check Date';
            ToolTip = 'Specifies the date on which this reconciliation was run. Both sides of the comparison are measured as of the moment of the run, not as of a historical date.';
        }
        field(3; "Customer Posting Group"; Text[250])
        {
            Caption = 'Customer Posting Group(s)';
            ToolTip = 'Specifies the customer posting group(s) whose receivables post to this control account. Multiple groups can share one account, so they are reconciled together.';
        }
        field(4; "G/L Control Account No."; Code[20])
        {
            Caption = 'G/L Control Account No.';
            TableRelation = "G/L Account"."No.";
            ToolTip = 'Specifies the G/L receivables control account being reconciled.';
        }
        field(5; "Sub-Ledger Balance"; Decimal)
        {
            Caption = 'Sub-Ledger Balance';
            AutoFormatType = 1;
            ToolTip = 'Specifies the summed remaining amount (LCY) of the open customer ledger entries of every posting group that points at this control account.';
        }
        field(6; "G/L Balance"; Decimal)
        {
            Caption = 'G/L Balance';
            AutoFormatType = 1;
            ToolTip = 'Specifies the current balance of this G/L receivables control account.';
        }
        field(7; Delta; Decimal)
        {
            Caption = 'Delta';
            AutoFormatType = 1;
            Editable = false;
            ToolTip = 'Specifies the difference between the sub-ledger balance and the G/L balance. A non-zero value indicates drift.';
        }
        field(8; Status; Enum "Recon Status")
        {
            Caption = 'Status';
            Editable = false;
            ToolTip = 'Specifies whether this control account is balanced or shows drift.';
        }
    }

    keys
    {
        key(PK; "Entry No.")
        {
            Clustered = true;
        }
    }

    // Delta and Status are derived, not entered. Computing them in OnInsert means every row is
    // internally consistent the instant it is written, regardless of who inserts it — including
    // a test that writes a finding directly without running a reconciliation.
    // The insert must be called as Insert(true) for this trigger to fire.
    trigger OnInsert()
    begin
        Delta := "Sub-Ledger Balance" - "G/L Balance";
        if Delta = 0 then
            Status := Status::Balanced
        else
            Status := Status::"Drift Detected";
    end;
}
