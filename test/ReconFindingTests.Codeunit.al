codeunit 50150 "Recon Finding Tests"
{
    // Tests the one piece of logic in this extension that is pure and therefore worth pinning
    // down: the Delta and Status a Recon Finding derives from the two balances written into it.
    //
    // These deliberately do not post ledger entries. Reconciliation over posted data belongs in
    // an integration test with a proper fixture; what is tested here is the invariant that
    // makes every finding trustworthy — that Delta and Status are never out of step with the
    // balances beside them, no matter who inserted the row.
    //
    // Assertions are hand-rolled rather than taken from Library Assert, so this test app
    // depends on nothing but the extension under test and installs in any sandbox.
    Subtype = Test;
    TestPermissions = Disabled;

    [Test]
    procedure EqualBalancesAreBalanced()
    var
        ReconFinding: Record "Recon Finding";
    begin
        // [SCENARIO] Sub-ledger and G/L agree, so the finding reports no drift.
        InsertFinding(ReconFinding, 1500.00, 1500.00);

        AssertDecimal(0, ReconFinding.Delta, 'Delta must be zero when both balances agree.');
        AssertStatus(ReconFinding.Status::Balanced, ReconFinding.Status, 'Equal balances must be Balanced.');
    end;

    [Test]
    procedure SubLedgerAheadIsPositiveDrift()
    var
        ReconFinding: Record "Recon Finding";
    begin
        // [SCENARIO] The sub-ledger carries more than the control account — e.g. a manual
        // credit was posted straight to the G/L account.
        InsertFinding(ReconFinding, 1500.00, 1000.00);

        AssertDecimal(500.00, ReconFinding.Delta, 'Delta must be sub-ledger minus G/L.');
        AssertStatus(ReconFinding.Status::"Drift Detected", ReconFinding.Status, 'A non-zero delta must be Drift Detected.');
    end;

    [Test]
    procedure GLAheadIsNegativeDrift()
    var
        ReconFinding: Record "Recon Finding";
    begin
        // [SCENARIO] The control account carries more than the sub-ledger. The sign matters:
        // it tells the user which side moved, so it must not be normalised to an absolute.
        InsertFinding(ReconFinding, 1000.00, 1500.00);

        AssertDecimal(-500.00, ReconFinding.Delta, 'Delta must stay signed when the G/L is ahead.');
        AssertStatus(ReconFinding.Status::"Drift Detected", ReconFinding.Status, 'A non-zero delta must be Drift Detected.');
    end;

    [Test]
    procedure SmallDifferenceIsStillDrift()
    var
        ReconFinding: Record "Recon Finding";
    begin
        // [SCENARIO] A one-cent difference is drift. There is no tolerance band by design —
        // a rounding difference in a control account is exactly the kind of thing that is
        // worth seeing rather than swallowing.
        InsertFinding(ReconFinding, 1000.01, 1000.00);

        AssertStatus(ReconFinding.Status::"Drift Detected", ReconFinding.Status, 'A one-cent difference must not be treated as balanced.');
    end;

    [Test]
    procedure InsertWithoutTriggerLeavesDerivedFieldsUnset()
    var
        ReconFinding: Record "Recon Finding";
    begin
        // [SCENARIO] Documents the contract that Delta and Status come from OnInsert. If this
        // ever starts passing with a derived Delta, the logic has moved somewhere else and the
        // comment on the table is stale.
        ReconFinding.Init();
        ReconFinding."Check Date" := Today();
        ReconFinding."G/L Control Account No." := 'TEST-NOTRIG';
        ReconFinding."Sub-Ledger Balance" := 900.00;
        ReconFinding."G/L Balance" := 100.00;
        ReconFinding.Insert(false);

        AssertDecimal(0, ReconFinding.Delta, 'Insert(false) must not derive Delta — the reconciliation relies on Insert(true).');
    end;

    local procedure InsertFinding(var ReconFinding: Record "Recon Finding"; SubLedgerBalance: Decimal; GLBalance: Decimal)
    begin
        ReconFinding.Init();
        ReconFinding."Check Date" := Today();
        ReconFinding."G/L Control Account No." := 'TEST-ACC';
        ReconFinding."Customer Posting Group" := 'TEST-GROUP';
        ReconFinding."Sub-Ledger Balance" := SubLedgerBalance;
        ReconFinding."G/L Balance" := GLBalance;
        ReconFinding.Insert(true);
    end;

    local procedure AssertDecimal(Expected: Decimal; Actual: Decimal; Because: Text)
    begin
        if Expected <> Actual then
            Error('%1 Expected %2, got %3.', Because, Expected, Actual);
    end;

    local procedure AssertStatus(Expected: Enum "Recon Status"; Actual: Enum "Recon Status"; Because: Text)
    begin
        if Expected <> Actual then
            Error('%1 Expected %2, got %3.', Because, Expected, Actual);
    end;
}
