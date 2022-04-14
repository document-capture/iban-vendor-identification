/// <summary>
/// Codeunit LV Purch. Doc. - Identificat. (ID 70001).
/// </summary>
codeunit 62030 "PTE Purch. Doc. - Identificat."
{
    TableNo = 6085590;

    trigger OnRun()
    var
        CDCTemplate: Record "CDC Template";
        CDCTemplateField: Record "CDC Template Field";
        Vendor: Record Vendor;
        VendorBankAccount: Record "Vendor Bank Account";
        CDCDocumentCatSourceExcl: Record "CDC Document Cat. Source Excl.";
        CDCDocumentCategory: Record "CDC Document Category";
        FoundVendor: Record Vendor;
        CDCTemplateFieldCaption: Record "CDC Template Field Caption";
        CDCCaptureEngine: Codeunit "CDC Capture Engine";
        CDCRecordIDMgt: Codeunit "CDC Record ID Mgt.";
        CDCCaptureManagement: Codeunit "CDC Capture Management";
        RecRef: RecordRef;
        IBAN: Code[50];
        Found: Boolean;
        RecIDTreeID: Integer;
        SourceID: Integer;
    begin
        // *********************************************************************************************************************************
        // SOURCE NO ALREADY IDENTIFIED. VALIDATING THE NO. WILL MAKE THE SYSTEM INSERT THE DEFAULT TEMPLATE
        // *********************************************************************************************************************************
        IF Rec."Source Record ID Tree ID" <> 0 THEN BEGIN
            Rec.VALIDATE("Source Record ID Tree ID", Rec."Source Record ID Tree ID");
            Rec.Modify(TRUE);
            EXIT;
        END;

        // *********************************************************************************************************************************
        // FIND THE IDENTIFICATION TEMPLATE
        // *********************************************************************************************************************************
        CDCTemplate.Reset();
        CDCTemplate.SETCURRENTKEY("Category Code", Type);
        CDCTemplate.SETRANGE("Category Code", Rec."Document Category Code");
        CDCTemplate.SETRANGE(Type, CDCTemplate.Type::Identification);
        IF Rec."File Type" = Rec."File Type"::XML THEN
            CDCTemplate.SETRANGE("Data Type", CDCTemplate."Data Type"::XML)
        ELSE
            CDCTemplate.SETRANGE("Data Type", CDCTemplate."Data Type"::PDF);

        IF NOT CDCTemplate.FindFirst() THEN
            EXIT;

        CDCTemplateField.SETRANGE("Template No.", CDCTemplate."No.");
        IF NOT CDCTemplateField.FindFirst() THEN
            EXIT;

        CDCDocumentCategory.GET(Rec."Document Category Code");

        // *********************************************************************************************************************************
        // CAPTURE THE IBAN FROM THE DOCUMENT VALUES
        // *********************************************************************************************************************************
        IBAN := COPYSTR(CDCCaptureEngine.CaptureField2(Rec, Rec."Temp Page No.", CDCTemplateField, FALSE, CDCTemplateFieldCaption), 1, MaxStrLen(VendorBankAccount.IBAN));

        // *********************************************************************************************************************************
        // IF IBAN WAS FOUND THEN TRY TO FIND A VENDOR WITH THE IBAN
        // *********************************************************************************************************************************
        IBAN := CopyStr(CDCCaptureManagement.ReplaceIllegalFilterCharacters(IBAN, FALSE, MAXSTRLEN(IBAN)), 1, MaxStrLen(IBAN));
        if IBAN <> '' then begin
            VendorBankAccount.SetRange(IBAN, IBAN);
            if VendorBankAccount.FindSet() then
                repeat
                    Vendor.Get(VendorBankAccount."Vendor No.");
                    RecIDTreeID := CDCRecordIDMgt.GetRecIDTreeID2(
                      CDCDocumentCategory."Source Table No.", Vendor.FIELDNO("No."), CDCDocumentCategory."Document Category GUID", Vendor."No.");

                    IF RecIDTreeID <> 0 THEN
                        Found := NOT CDCDocumentCatSourceExcl.GET(Rec."Document Category Code", RecIDTreeID);
                    IF Found THEN
                        FoundVendor := Vendor;
                UNTIL Found OR (VendorBankAccount.Next() = 0);

            IF NOT Found THEN BEGIN
                IBAN := CopyStr(RemoveLeadingLetters(IBAN), 1, MaxStrLen(IBAN));
                IF (STRLEN(IBAN) > 14) THEN BEGIN
                    VendorBankAccount.SetRange(IBAN, IBAN);
                    IF VendorBankAccount.FindSet() THEN
                        REPEAT
                            Vendor.Get(VendorBankAccount."Vendor No.");
                            RecIDTreeID := CDCRecordIDMgt.GetRecIDTreeID2(
                              CDCDocumentCategory."Source Table No.", Vendor.FIELDNO("No."), CDCDocumentCategory."Document Category GUID", Vendor."No.");
                            IF RecIDTreeID <> 0 THEN
                                Found := NOT CDCDocumentCatSourceExcl.GET(Rec."Document Category Code", RecIDTreeID);
                            IF Found THEN
                                FoundVendor := Vendor;
                        UNTIL Found OR (VendorBankAccount.Next() = 0);

                    IF NOT Found THEN BEGIN
                        VendorBankAccount.SetFilter(IBAN, '%1', '*' + IBAN + '*');
                        IF VendorBankAccount.FindSet() THEN
                            REPEAT
                                Vendor.Get(VendorBankAccount."Vendor No.");
                                RecIDTreeID := CDCRecordIDMgt.GetRecIDTreeID2(
                                  CDCDocumentCategory."Source Table No.", Vendor.FIELDNO("No."), CDCDocumentCategory."Document Category GUID", Vendor."No.");
                                IF RecIDTreeID <> 0 THEN
                                    Found := NOT CDCDocumentCatSourceExcl.GET(Rec."Document Category Code", RecIDTreeID);
                                IF Found THEN
                                    FoundVendor := Vendor;
                            UNTIL Found OR (VendorBankAccount.Next() = 0);
                    END;
                END;
            END;
        END;

        OnAfterFindVendorBeforeModify(Rec, CDCTemplateField, CDCTemplateFieldCaption, IBAN, FoundVendor, Found);

        IF NOT Found THEN
            EXIT;

        RecRef.GETTABLE(FoundVendor);
        SourceID := CDCRecordIDMgt.GetRecIDTreeID(RecRef, TRUE);
        Commit();

        Rec.VALIDATE("Source Record ID Tree ID", SourceID);
        Rec."Identified by" := STRSUBSTNO(IdentificationTemplateTxt, CDCTemplateFieldCaption.Caption, IBAN);

        Rec.MODIFY(TRUE);
    end;

    var
        IdentificationTemplateTxt: Label 'Identification Template: %1: %2', Comment = '%1 is Template Field Caption, %2 is IBAN';

    internal procedure CaptureVATNo(var CaptureFieldVal: Record "CDC Temp. Capture Field Valid.")
    var
        CompInfo: Record "Company Information";
    begin
        // *********************************************************************************************************************************
        // THIS FUNCTION IS CALLED DURING IDENTIFICATION. IF THE SYSTEM FINDS OUR OWN VAT REG. NO, IT WILL CONTINUE SEARCHING THE DOCUMENT
        // FOR THE VENDOR VAT NO.
        // *********************************************************************************************************************************
        CompInfo.Get();
        WITH CaptureFieldVal DO BEGIN
            // WE ONLY WAN'T TO VALIDATE THE VALUE IF THE VALUE ALREADY CONFORMS TO THE SPECIFIED REGEX-RULES
            IF "File Rule Entry No." = 0 THEN
                EXIT;

            // REMOVE ALL LETTERS FROM THE VAT NO. AND COMPARE ONLY THE NUMBER-SEQUENCE
            "Is Valid" := RemoveLeadingLetters(Value) <> RemoveLeadingLetters(CompInfo."VAT Registration No.")
        END;
    end;

    /// <summary>
    /// RemoveLeadingLetters.
    /// </summary>
    /// <param name="Text">Text[1024].</param>
    /// <returns>Return value of type Text[1024].</returns>
    procedure RemoveLeadingLetters(Text: Text[1024]): Text[1024]
    begin
        while Text <> '' do
            if (Text[1] >= 'A') AND (Text[1] <= 'Z') then
                Text := COPYSTR(Text, 2, MaxStrLen(Text))
            else
                exit(Text);
        exit(Text);
    end;

    [IntegrationEvent(false, false)]
    local procedure OnAfterFindVendorBeforeModify(var Document: Record "CDC Document"; var "Field": Record "CDC Template Field"; var FieldCaption: Record "CDC Template Field Caption"; var IBAN: Code[50]; var FoundVendor: Record Vendor; var Found: Boolean)
    begin
    end;
}

