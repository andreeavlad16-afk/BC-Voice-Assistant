/// <summary>
/// Main voice assistant interface with voice input control and conversation history.
/// Provides voice recognition, transcription, and natural language query processing.
/// </summary>
page 50608 "NXR Voice Assistant"
{
    PageType = Card;
    ApplicationArea = All;
    UsageCategory = Tasks;
    Caption = 'Voice Assistant - Ask me anything about your data';

    layout
    {
        area(Content)
        {
            group(VoiceControl)
            {
                Caption = 'Voice & Text Input';
                InstructionalText = 'Click Start Listening to speak your question, or type it below and click Submit.';

                usercontrol(VoiceInput; "Voice Control Add-in")
                {
                    ApplicationArea = All;

                    trigger OnVoiceInput(inputText: Text)
                    begin
                        ProcessVoiceInput(inputText);
                    end;

                    trigger OnAudioInput(audioData: Text)
                    begin
                        ProcessAudioInput(audioData);
                    end;

                    trigger OnSpeechError(errorMessage: Text)
                    begin
                        Message('Speech error: %1', errorMessage);
                    end;

                    trigger OnReady()
                    begin
                        IsControlReady := true;
                        CurrPage.VoiceInput.SetBackendUrl(BackendServiceUrl);
                    end;
                }
            }

            group(TextInput)
            {
                Caption = 'Or Type Your Question';
                InstructionalText = 'Type your question and press Enter or click Submit';

                field(TypedQuery; TypedQueryText)
                {
                    ApplicationArea = All;
                    Caption = 'Your Question';
                    ToolTip = 'Type your question here and press Enter or click Submit. Ask about customers, items, vendors, sales orders, or invoices.';
                    MultiLine = false;

                    trigger OnValidate()
                    begin
                        // Allow pressing Enter to submit
                        if TypedQueryText <> '' then
                            SubmitTypedQuery();
                    end;
                }
            }

            group(ConversationHistory)
            {
                Caption = 'Your Conversation';
                InstructionalText = 'Your questions and answers appear here. Use Clear History to start fresh.';

                field(ConversationLog; ConversationText)
                {
                    ApplicationArea = All;
                    MultiLine = true;
                    Editable = false;
                    ShowCaption = false;
                    StyleExpr = true;
                }
            }

            group(Configuration)
            {
                Caption = 'Configuration';
                Visible = false;

                field(UseAdvancedAI; UseAdvancedAI)
                {
                    ApplicationArea = All;
                    Caption = 'Use Advanced AI (Azure OpenAI)';
                    ToolTip = 'Enable Azure OpenAI for more sophisticated query understanding. Requires Azure setup.';
                }

                field(BackendUrl; BackendServiceUrl)
                {
                    ApplicationArea = All;
                    Caption = 'Azure Backend URL (Optional)';
                    ToolTip = 'Azure Function App URL for advanced AI processing (only needed if Advanced AI is enabled)';
                    Enabled = UseAdvancedAI;

                    trigger OnValidate()
                    begin
                        if IsControlReady then
                            CurrPage.VoiceInput.SetBackendUrl(BackendServiceUrl);
                    end;
                }
            }
        }
    }

    actions
    {
        area(Processing)
        {
            action(StartListening)
            {
                ApplicationArea = All;
                Caption = '🎤 Start Listening';
                ToolTip = 'Click to start voice input. Speak your question clearly.';
                Image = Start;
                Promoted = true;
                PromotedCategory = Process;
                PromotedIsBig = true;
                PromotedOnly = true;

                trigger OnAction()
                begin
                    if IsControlReady then
                        CurrPage.VoiceInput.StartListening();
                end;
            }

            action(StopListening)
            {
                ApplicationArea = All;
                Caption = '⏹️ Stop Listening';
                ToolTip = 'Click to stop voice input.';
                Image = Stop;
                Promoted = true;
                PromotedCategory = Process;
                PromotedOnly = true;

                trigger OnAction()
                begin
                    if IsControlReady then
                        CurrPage.VoiceInput.StopListening();
                end;
            }

            action(SubmitQuery)
            {
                ApplicationArea = All;
                Caption = '📤 Submit Question';
                ToolTip = 'Submit your typed question';
                Image = SendTo;
                Promoted = true;
                PromotedCategory = Process;
                PromotedIsBig = true;
                PromotedOnly = true;

                trigger OnAction()
                begin
                    SubmitTypedQuery();
                end;
            }

            action(ToggleConfig)
            {
                ApplicationArea = All;
                Caption = '⚙️ Settings';
                ToolTip = 'Open Voice Assistant settings to configure AI backend, debug mode, and text-only mode';
                Image = Setup;
                Promoted = true;
                PromotedCategory = Process;

                trigger OnAction()
                begin
                    Page.Run(Page::"NXR Voice Assistant Setup");
                end;
            }

            action(ShowExamples)
            {
                ApplicationArea = All;
                Caption = '💡 Example Questions';
                ToolTip = 'Show examples of questions you can ask';
                Image = Info;
                Promoted = true;
                PromotedCategory = Process;

                trigger OnAction()
                begin
                    ShowExampleQueries();
                end;
            }

            action(ClearHistory)
            {
                ApplicationArea = All;
                Caption = 'Clear Conversation';
                ToolTip = 'Clear the conversation history to start fresh';
                Image = ClearLog;
                Promoted = true;
                PromotedCategory = Process;

                trigger OnAction()
                begin
                    ConversationText := '';
                    AddToConversation('Welcome! Ask me about your Business Central data.');
                    AddToConversation('Try: "Who are my top 5 customers?" or "Show me orders from this week"');
                    CurrPage.Update(false);
                end;
            }
        }
    }

    var
        VoiceAssistantMgt: Codeunit "NXR Voice Assistant Mgt.";
        DynamicQueryExecutor: Codeunit "NXR Voice Dynamic Query Exec.";
        SpeechTranscription: Codeunit "NXR Voice Speech Transcription";
        Setup: Record "NXR Voice Assistant Setup";
        ConversationText: Text;
        TypedQueryText: Text;
        BackendServiceUrl: Text;
        BCWebServiceUrl: Text;
        IsControlReady: Boolean;
        ShowConfig: Boolean;
        UseAdvancedAI: Boolean;

    trigger OnOpenPage()
    begin
        // Load configuration from setup
        LoadConfiguration();
        ShowConfig := false;

        // Show welcome message if no conversation exists
        if ConversationText = '' then begin
            AddToConversation('Welcome to Business Central Voice Assistant!');
            AddToConversation('');
            AddToConversation('You can:');
            AddToConversation('   • Click "Start Listening" and speak your question');
            AddToConversation('   • Type your question in the field below');
            AddToConversation('');
            AddToConversation('Try asking: "Who are my top 5 customers?" or "Show me orders from this week"');
            AddToConversation('Click "Example Questions" for more ideas!');
            AddToConversation('');
            AddToConversation('─────────────────────────────────');
        end;
    end;

    local procedure ProcessAudioInput(AudioDataJson: Text)
    var
        AudioPayload: JsonObject;
        Base64Audio: Text;
        MimeType: Text;
        Transcript: Text;
    begin
        // Parse the audio payload from JavaScript
        if not AudioPayload.ReadFrom(AudioDataJson) then begin
            Message('Invalid audio data received');
            exit;
        end;

        Base64Audio := GetJsonText(AudioPayload, 'audioData');
        MimeType := GetJsonText(AudioPayload, 'mimeType');

        if Base64Audio = '' then begin
            Message('No audio data received');
            exit;
        end;

        // Check if transcription is available
        if not SpeechTranscription.IsTranscriptionAvailable() then begin
            Message('Cloud transcription requires OpenAI or Azure API key. Please configure in Voice Assistant Setup.');
            exit;
        end;

        // Transcribe audio via cloud service
        Transcript := SpeechTranscription.TranscribeAudio(Base64Audio, MimeType);

        if Transcript = '' then begin
            Message('Could not transcribe audio. Please try again.');
            exit;
        end;

        // Send transcription back to JavaScript for further processing
        if IsControlReady then
            CurrPage.VoiceInput.OnTranscriptionResult(Transcript);
    end;

    local procedure SubmitTypedQuery()
    begin
        if TypedQueryText = '' then
            exit;

        ProcessVoiceInput(TypedQueryText);
        TypedQueryText := '';  // Clear input after submission
    end;

    local procedure ProcessVoiceInput(InputText: Text)
    var
        Response: Text;
        JsonPayload: JsonObject;
        StructuredQuery: JsonObject;
        RawQuery: Text;
        StructuredToken: JsonToken;
    begin
        // Try to parse as JSON (enhanced control add-in sends structured data)
        if TryParseJson(InputText, JsonPayload) then begin
            // Extract raw query for display
            RawQuery := GetJsonText(JsonPayload, 'rawQuery');
            if RawQuery = '' then
                RawQuery := InputText;

            // Add user input to conversation
            AddToConversation('You: ' + RawQuery);

            // Check if we have structured query from on-device AI
            if JsonPayload.Get('structured', StructuredToken) then begin
                if StructuredToken.IsObject() then begin
                    StructuredQuery := StructuredToken.AsObject();
                    Response := ProcessStructuredQuery(StructuredQuery);
                end else begin
                    // Token is not an object, use legacy processing
                    Response := VoiceAssistantMgt.ProcessQuery(RawQuery, BackendServiceUrl, BCWebServiceUrl);
                end;
            end else begin
                // Fallback to legacy processing
                Response := VoiceAssistantMgt.ProcessQuery(RawQuery, BackendServiceUrl, BCWebServiceUrl);
            end;
        end else begin
            // Legacy mode: plain text input
            AddToConversation('You: ' + InputText);
            Response := VoiceAssistantMgt.ProcessQuery(InputText, BackendServiceUrl, BCWebServiceUrl);
        end;

        // Add response to conversation
        AddToConversation('Assistant: ' + Response);

        // Send response back to control for speech output
        if IsControlReady then begin
            if Setup."Text Only Mode" then
                CurrPage.VoiceInput.DisplayResponse(Response)  // Text only, no speech
            else
                CurrPage.VoiceInput.SpeakResponse(Response);  // Normal mode with speech
        end;
    end;

    local procedure ProcessStructuredQuery(StructuredQuery: JsonObject): Text
    var
        ResultData: JsonObject;
        RecordCount: Integer;
        ResponseText: Text;
        Intent: Text;
    begin
        Intent := GetJsonText(StructuredQuery, 'intent');

        // Handle greeting and help intents directly
        if Intent = 'greeting' then
            exit('Hello! I''m your Business Central voice assistant. You can ask me about customers, items, vendors, sales orders, and invoices. For example, try "Which customers bought bicycles?" or "Show me today''s orders".');

        if Intent = 'help' then
            exit('You can ask me things like: Show my top customers. Which items are low on stock? Who supplies bicycles? What orders came in this week? Which customers bought touring bikes?');

        if Intent = 'unknown' then begin
            // Try legacy processing
            exit(VoiceAssistantMgt.ProcessQuery(GetJsonText(StructuredQuery, 'rawQuery'), BackendServiceUrl, BCWebServiceUrl));
        end;

        // Execute the structured query using dynamic executor
        if DynamicQueryExecutor.ExecuteStructuredQuery(StructuredQuery, ResultData, RecordCount, ResponseText) then
            exit(ResponseText)
        else
            exit('Sorry, I had trouble processing that query. Please try rephrasing.');
    end;

    [TryFunction]
    local procedure TryParseJson(InputText: Text; var JsonPayload: JsonObject)
    begin
        JsonPayload.ReadFrom(InputText);
    end;

    local procedure GetJsonText(JObject: JsonObject; PropertyName: Text): Text
    var
        JToken: JsonToken;
    begin
        if JObject.Get(PropertyName, JToken) then
            if JToken.IsValue() then
                exit(JToken.AsValue().AsText());
        exit('');
    end;

    local procedure AddToConversation(Text: Text)
    begin
        if ConversationText <> '' then
            ConversationText += '\' + Text
        else
            ConversationText := Text;

        // Force page update to show latest content (simulates auto-scroll)
        CurrPage.Update(false);
    end;

    local procedure LoadConfiguration()
    var
        VoiceAssistantSetup: Record "NXR Voice Assistant Setup";
    begin
        if VoiceAssistantSetup.Get() then begin
            Setup := VoiceAssistantSetup;  // Store in global variable
            BackendServiceUrl := VoiceAssistantSetup."API Endpoint";
            UseAdvancedAI := VoiceAssistantSetup."AI Backend Type" <> VoiceAssistantSetup."AI Backend Type"::None;
        end else begin
            // Default: No Azure backend needed - everything runs in BC
            BackendServiceUrl := '';
            UseAdvancedAI := false;
        end;
    end;

    local procedure ShowExampleQueries()
    var
        ExampleText: Text;
    begin
        ExampleText := '💡 EXAMPLE QUESTIONS YOU CAN ASK:\\';
        ExampleText += '\\';

        ExampleText += '👥 CUSTOMER QUESTIONS:\\';
        ExampleText += '• "Who are my top 5 customers?"\\';
        ExampleText += '• "Show me customers in London"\\';
        ExampleText += '• "Which customers have highest balance?"\\';
        ExampleText += '• "Find customers who bought bicycles"\\';
        ExampleText += '\\';

        ExampleText += '📦 ITEM & INVENTORY QUESTIONS:\\';
        ExampleText += '• "Which items are low on stock?"\\';
        ExampleText += '• "Show me items with inventory below 10"\\';
        ExampleText += '• "What are my best selling items?"\\';
        ExampleText += '• "Find items from vendor Contoso"\\';
        ExampleText += '\\';

        ExampleText += '💼 SALES QUESTIONS:\\';
        ExampleText += '• "Show me orders from this week"\\';
        ExampleText += '• "What are today''s sales orders?"\\';
        ExampleText += '• "Show me open sales orders"\\';
        ExampleText += '• "Find invoices from last month"\\';
        ExampleText += '\\';

        ExampleText += '🛍️ VENDOR QUESTIONS:\\';
        ExampleText += '• "Show me all vendors"\\';
        ExampleText += '• "Which vendors supply low stock items?"\\';
        ExampleText += '• "Show me open purchase orders"\\';
        ExampleText += '\\';

        ExampleText += '👤 EMPLOYEE QUESTIONS:\\';
        ExampleText += '• "List all employees"\\';
        ExampleText += '• "Show me employees in sales"\\';
        ExampleText += '\\';

        ExampleText += '✨ TIME-BASED QUERIES:\\';
        ExampleText += '• "Show me orders from today"\\';
        ExampleText += '• "Find invoices this year"\\';
        ExampleText += '• "Show me sales from last 30 days"\\';
        ExampleText += '\\';

        ExampleText += '📊 ADVANCED QUERIES:\\';
        ExampleText += '• "Total customer balance"\\';
        ExampleText += '• "Average invoice amount"\\';
        ExampleText += '• "How many customers do I have?"\\';
        ExampleText += '\\';

        ExampleText += 'ℹ️ Tip: Speak naturally! The assistant understands conversational questions.';

        Message(ExampleText);
    end;
}
