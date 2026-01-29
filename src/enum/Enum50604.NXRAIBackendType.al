enum 50604 "NXR AI Backend Type"
{
    Extensible = true;
    Caption = 'AI Backend Type';

    value(0; None)
    {
        Caption = 'None (Pattern Matching Only)';
    }
    value(1; LocalLLM)
    {
        Caption = 'Local LLM (OpenAI Compatible)';
    }
    value(2; AzureOpenAI)
    {
        Caption = 'Azure OpenAI Service';
    }
    value(3; OpenAI)
    {
        Caption = 'OpenAI API';
    }
    value(4; OnDeviceAI)
    {
        Caption = 'On-Device AI (Google AI Edge)';
    }
}
