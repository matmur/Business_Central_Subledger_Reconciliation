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
            ToolTip = 'Specifies the work date on which this reconciliation was run.';
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
            ToolTip = 'Specifies the G/L receivables control account tied to the posting group.';
        }
        field(5; "Sub-Ledger Balance"; Decimal)
        {
            Caption = 'Sub-Ledger Balance';
            AutoFormatType = 1;
            ToolTip = 'Specifies the summed remaining amount (LCY) of the open customer ledger entries for this posting group.';
        }
        field(6; "G/L Balance"; Decimal)
        {
            Caption = 'G/L Balance';
            AutoFormatType = 1;
            ToolTip = 'Specifies the balance of the G/L receivables control account for this posting group.';
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
            ToolTip = 'Specifies whether the posting group is balanced or shows drift.';
        }
    }

    keys
    {
        key(PK; "Entry No.")
        {
            Clustered = true;
        }
    }

    // Delta and Status are derived, not entered. Computing them in OnInsert means every
    // row is internally consistent the instant it is written, regardless of who inserts it.
    // The insert must be called with Insert(true) for this trigger to fire.
    trigger OnInsert()
    begin
        Delta := "Sub-Ledger Balance" - "G/L Balance";
        if Delta = 0 then
            Status := Status::Balanced
        else
            Status := Status::"Drift Detected";
    end;
}
