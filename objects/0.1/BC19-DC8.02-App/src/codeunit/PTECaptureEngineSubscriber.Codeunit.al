/// <summary>
/// Codeunit LV Capture Engine (ID 70002).
/// </summary>
codeunit 62031 "PTE Capture Engine Subscriber"
{

    [EventSubscriber(ObjectType::Codeunit, Codeunit::"CDC Capture Engine", 'OnBeforeFindDocumentSource', '', true, true)]
    local procedure CDCCaptureEngine_OnBeforeFindDocumentSource(var Document: Record "CDC Document"; var IsHandled: Boolean)
    begin
        FindDocumentSourceByIBAN(Document);
        IsHandled := TRUE;
    end;

    local procedure FindDocumentSourceByIBAN(var CDCDocument: Record "CDC Document")
    begin
        if CDCCaptureEngine.FindSourceWithSearchTexts(CDCDocument) then
            EXIT;

        IF CDCCaptureEngine.FindSourceWithIdentTemplate(CDCDocument) THEN
            EXIT;

        IF FindSourceWithIBAN(CDCDocument) THEN
            EXIT;

        CDCCaptureEngine.FindSourceWithIdentFields(CDCDocument);
    end;

    local procedure FindSourceWithIBAN(var CDCDocument: Record "CDC Document"): Boolean
    var
        DocCat: Record "CDC Document Category";
        RecIDMgt: Codeunit "CDC Record ID Mgt.";
        RecRef: RecordRef;
        RecID: RecordId;
        MatchPoints: Integer;
        SourceID: Integer;
        IdentFieldNameValue: Text;
    begin
        GetRecFromIdentField(CDCDocument, CDCDocument."Temp Page No.", RecID, MatchPoints, IdentFieldNameValue);
        if MatchPoints > 0 then begin
            DocCat.GET(CDCDocument."Document Category Code");
            if DocCat."Source Table No." <> 0 then begin
                RecRef.GET(RecID);
                SourceID := RecIDMgt.GetRecIDTreeID(RecRef, TRUE);
                Commit();

                CDCDocument.VALIDATE("Source Record ID Tree ID", SourceID);
                CDCDocument."Identified by" := COPYSTR(STRSUBSTNO(IdentificationFieldsTxt, IdentFieldNameValue), 1,
                  MAXSTRLEN(CDCDocument."Identified by"));
                CDCDocument.Modify(true);
                exit(true);
            end;
        end else
            CDCDocument."Identified by" := '';
    end;

    local procedure GetRecFromIdentField(VAR CDCDocument: Record "CDC Document"; PageNo: Integer; VAR RecID: RecordID; VAR Points: Integer; VAR IdentFields: Text[1024])
    var
        XMLBuffer: Record "CDC XML Buffer";
        VendorBankAccount: Record "Vendor Bank Account";
        Vendor: Record Vendor;
        DocCat: Record "CDC Document Category";
        IdentifierField: Record "CDC Doc. Category Ident. Field";
        DocWord: Record "CDC Document Word";
        SourceExcl: Record "CDC Document Cat. Source Excl.";
        BigString: Codeunit "CDC BigString Management";
        RecIDMgt: Codeunit "CDC Record ID Mgt.";
        RecRef: RecordRef;
        BestRecRef: RecordRef;
        VendorRecRef: RecordRef;
        FieldRef: FieldRef;
        BestIdentificationFields: Text;
        IdentificationFields: Text;
        IdentFieldNameAndValue: Text;
        BestRecMatchPoint: Integer;
        RecMatchPoint: Integer;
        RecIDTreeID: Integer;
        RecPoints: Integer;

    begin
        DocCat.GET(CDCDocument."Document Category Code");
        VendorBankAccount.SETFILTER("Vendor No.", '<>%1', '');
        VendorBankAccount.SETFILTER(IBAN, '<>%1', '');
        if NOT VendorBankAccount.FindSet() then
            exit;

        IF CDCDocument."File Type" = CDCDocument."File Type"::XML THEN BEGIN
            CDCDocument.BuildXmlBuffer(XMLBuffer);
            XMLBuffer.SETFILTER(Type, '%1|%2', XMLBuffer.Type::Element, XMLBuffer.Type::Attribute);
            IF NOT XMLBuffer.FINDSET(FALSE, FALSE) THEN
                EXIT;

            REPEAT
                BigString.Append(UPPERCASE(DELCHR(XMLBuffer.Value, '=', ' ,.-;:/\*+')));
            UNTIL XMLBuffer.Next() = 0;
        END ELSE BEGIN
            DocWord.SETCURRENTKEY("Document No.", "Page No.", Top, Left);
            DocWord.SETRANGE("Document No.", CDCDocument."No.");
            DocWord.SETRANGE("Page No.", PageNo);
            IF NOT DocWord.FINDSET(FALSE, FALSE) THEN
                EXIT;

            REPEAT
                BigString.Append(UPPERCASE(DELCHR(DocWord.Word, '=', ' ,.-;:/\*+-')));
            UNTIL DocWord.NEXT() = 0;
        END;

        REPEAT
            Vendor.GET(VendorBankAccount."Vendor No.");
            RecRef.GETTABLE(Vendor);
            RecIDTreeID := RecIDMgt.GetRecIDTreeID(RecRef, FALSE);
            IF NOT SourceExcl.GET(CDCDocument."Document Category Code", RecIDTreeID) THEN BEGIN
                RecMatchPoint := 0;
                IdentificationFields := '';
                VendorRecRef.GETTABLE(VendorBankAccount);
                FieldRef := VendorRecRef.FIELD(VendorBankAccount.FIELDNO(IBAN));
                RecPoints := GetPoints(FORMAT(FieldRef.VALUE), BigString, STRLEN(FORMAT(FieldRef.VALUE))) * IdentifierField.Rating;
                IF RecPoints > 0 THEN BEGIN
                    RecMatchPoint += RecPoints;
                    IdentFieldNameAndValue := VendorBankAccount.FIELDCAPTION(IBAN) + ': ' + FORMAT(FieldRef.VALUE);

                    IF IdentificationFields <> '' THEN
                        IdentificationFields := IdentificationFields + ', ';

                    IF STRLEN(IdentificationFields + IdentFieldNameAndValue) <= 1024 THEN
                        IdentificationFields := IdentificationFields + IdentFieldNameAndValue;
                END;

                IF BestRecMatchPoint < RecMatchPoint THEN BEGIN
                    BestRecMatchPoint := RecMatchPoint;
                    BestRecRef := RecRef.Duplicate();
                    BestIdentificationFields := IdentificationFields;
                END;
            END;
        UNTIL VendorBankAccount.NEXT = 0;

        CLEAR(RecRef);

        IF FORMAT(BestRecRef) = '' THEN
            EXIT;

        RecID := BestRecRef.RECORDID;
        Points := BestRecMatchPoint;
        IdentFields := BestIdentificationFields;
        CLEAR(BestRecRef);
    end;

    local procedure GetPoints(Text: Text[250]; VAR BigString: Codeunit "CDC BigString Management"; Points: Integer): Integer
    begin
        Text := UPPERCASE(DELCHR(Text, '=', ' ,.-;:/\*+-'));
        IF (Text <> '') AND (BigString.IndexOf(Text) <> -1) THEN
            EXIT(Points);
    end;

    var
        CDCCaptureEngine: Codeunit "CDC Capture Engine";
        IdentificationFieldsTxt: Label 'Identification Fields: %1', Comment = '%1 -> Identification Fields Description';

}
