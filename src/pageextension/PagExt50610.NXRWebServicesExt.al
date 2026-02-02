/// <summary>
/// Page extension for Web Services page to add bulk publish functionality.
/// Adds action to automatically publish all available pages as web services.
/// </summary>
pageextension 50610 "NXR Web Services Ext" extends "Web Services"
{
    actions
    {
        addlast(Processing)
        {
            action(PublishAllPages)
            {
                ApplicationArea = All;
                Caption = 'Publish All Pages';
                ToolTip = 'Automatically publish all available pages as OData web services for voice assistant queries';
                Image = Process;
                Promoted = true;
                PromotedCategory = Process;
                PromotedIsBig = true;

                trigger OnAction()
                var
                    WebServicePublisher: Codeunit "NXR Web Service Publisher";
                begin
                    if Confirm('This will publish all available pages as OData web services. Continue?', false) then begin
                        WebServicePublisher.PublishAllPages();
                        Message('Successfully published all pages as web services!');
                    end;
                end;
            }
        }
    }
}
