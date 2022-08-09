pageextension 62030 "PTE Vendor Lookup Extension" extends "Vendor Lookup"
{
    actions
    {
        addafter(VendorList)
        {
            action(VendorBankAccounts)
            {
                ApplicationArea = All;
                Caption = 'Vendor Bank Accounts';
                ToolTip = 'View or set up the vendors bank accounts. You can set up any number of bank accounts for each vendor.';
                Image = BankAccount;
                Promoted = true;
                PromotedCategory = Category7;
                RunObject = page "Vendor Bank Account List";
                RunPageLink = "Vendor No." = field("No.");
            }

        }

    }
}
