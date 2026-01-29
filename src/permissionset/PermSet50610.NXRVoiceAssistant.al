permissionset 50610 "NXR Voice Assistant"
{
    Caption = 'NXR Voice Assistant';
    Assignable = true;

    Permissions =
        table "NXR Voice Assistant Setup" = X,
        tabledata "NXR Voice Assistant Setup" = RMID,
        table "NXR Voice Query Intent" = X,
        tabledata "NXR Voice Query Intent" = RMID,
        codeunit "NXR Voice Assistant Mgt." = X,
        codeunit "NXR Voice Query Executor" = X,
        codeunit "NXR Voice AI Service" = X,
        codeunit "NXR Voice Dynamic Query Exec." = X,
        codeunit "NXR Voice Speech Transcription" = X,
        codeunit "NXR Generic OData Executor" = X,
        page "NXR Voice Assistant" = X,
        page "NXR Voice Assistant Setup" = X,
        page "NXR Voice Command API" = X;
}
