using System.IO;
using System.Threading.Tasks;
using Microsoft.AspNetCore.Mvc;
using Microsoft.Azure.WebJobs;
using Microsoft.Azure.WebJobs.Extensions.Http;
using Microsoft.AspNetCore.Http;
using Microsoft.Extensions.Logging;
using Newtonsoft.Json;
using System.Net.Http;
using System.Text;
using System;

namespace BCVoiceAssistant.Functions
{
    public static class ProcessVoiceQuery
    {
        private static readonly HttpClient httpClient = new HttpClient();

        [FunctionName("ProcessVoiceQuery")]
        public static async Task<IActionResult> Run(
            [HttpTrigger(AuthorizationLevel.Function, "post", Route = null)] HttpRequest req,
            ILogger log)
        {
            log.LogInformation("Processing voice query request");

            try
            {
                // Read request body
                string requestBody = await new StreamReader(req.Body).ReadToEndAsync();
                var request = JsonConvert.DeserializeObject<VoiceQueryRequest>(requestBody);

                if (string.IsNullOrEmpty(request?.Query))
                {
                    return new BadRequestObjectResult(new { error = "Query is required" });
                }

                log.LogInformation($"Processing query: {request.Query}");

                // Step 1: Use Azure OpenAI to understand the intent and formulate BC query
                var queryIntent = await AnalyzeQueryIntent(request.Query, log);

                // Step 2: Execute BC OData query
                var bcData = await ExecuteBCQuery(queryIntent, request.BCBaseUrl, log);

                // Step 3: Format response in natural language
                var naturalLanguageResponse = await FormatResponse(request.Query, bcData, log);

                return new OkObjectResult(new
                {
                    response = naturalLanguageResponse,
                    rawData = bcData,
                    intent = queryIntent
                });
            }
            catch (Exception ex)
            {
                log.LogError($"Error processing query: {ex.Message}");
                return new ObjectResult(new { error = ex.Message })
                {
                    StatusCode = 500
                };
            }
        }

        private static async Task<QueryIntent> AnalyzeQueryIntent(string query, ILogger log)
        {
            // TODO: Replace with actual Azure OpenAI call
            // For now, use simple pattern matching
            
            var intent = new QueryIntent
            {
                Entity = "Unknown",
                Action = "Query",
                Filters = new System.Collections.Generic.Dictionary<string, string>()
            };

            query = query.ToLower();

            // Detect entity type
            if (query.Contains("customer"))
                intent.Entity = "Customer";
            else if (query.Contains("sales order") || query.Contains("order"))
                intent.Entity = "SalesOrder";
            else if (query.Contains("item") || query.Contains("inventory") || query.Contains("product"))
                intent.Entity = "Item";
            else if (query.Contains("invoice"))
                intent.Entity = "SalesInvoice";

            // Detect filters
            if (query.Contains("today"))
                intent.Filters["date"] = DateTime.Today.ToString("yyyy-MM-dd");
            else if (query.Contains("this week"))
                intent.Filters["dateRange"] = "thisWeek";
            else if (query.Contains("this month"))
                intent.Filters["dateRange"] = "thisMonth";

            // Detect top N
            if (query.Contains("top"))
            {
                var words = query.Split(' ');
                for (int i = 0; i < words.Length - 1; i++)
                {
                    if (words[i] == "top" && int.TryParse(words[i + 1], out int count))
                    {
                        intent.Filters["top"] = count.ToString();
                        break;
                    }
                }
            }

            log.LogInformation($"Detected intent - Entity: {intent.Entity}, Action: {intent.Action}");

            return intent;
        }

        private static async Task<string> ExecuteBCQuery(QueryIntent intent, string bcBaseUrl, ILogger log)
        {
            try
            {
                string odataQuery = BuildODataQuery(intent);
                string fullUrl = $"{bcBaseUrl.TrimEnd('/')}/{odataQuery}";

                log.LogInformation($"Executing BC query: {fullUrl}");

                // Note: In production, you'll need to handle authentication
                // This is a placeholder - you'll need to add Bearer token
                var request = new HttpRequestMessage(HttpMethod.Get, fullUrl);
                // request.Headers.Add("Authorization", "Bearer " + token);

                var response = await httpClient.SendAsync(request);
                var content = await response.Content.ReadAsStringAsync();

                if (!response.IsSuccessStatusCode)
                {
                    log.LogError($"BC query failed: {response.StatusCode} - {content}");
                    return $"Error querying Business Central: {response.StatusCode}";
                }

                return content;
            }
            catch (Exception ex)
            {
                log.LogError($"Error executing BC query: {ex.Message}");
                return $"Error: {ex.Message}";
            }
        }

        private static string BuildODataQuery(QueryIntent intent)
        {
            string query = "";

            switch (intent.Entity)
            {
                case "Customer":
                    query = "Customer?$select=No,Name,Balance";
                    break;
                case "SalesOrder":
                    query = "SalesOrder?$select=No,Order_Date,Sell_to_Customer_Name,Amount";
                    break;
                case "Item":
                    query = "Item?$select=No,Description,Inventory,Unit_Price";
                    break;
                case "SalesInvoice":
                    query = "SalesInvoice?$select=No,Posting_Date,Sell_to_Customer_Name,Amount_Including_VAT";
                    break;
                default:
                    query = "Company";
                    break;
            }

            // Add filters
            if (intent.Filters.ContainsKey("top"))
            {
                query += $"&$top={intent.Filters["top"]}";
            }

            if (intent.Filters.ContainsKey("date"))
            {
                query += $"&$filter=Date eq {intent.Filters["date"]}";
            }

            return query;
        }

        private static async Task<string> FormatResponse(string originalQuery, string bcData, ILogger log)
        {
            // TODO: Use Azure OpenAI to generate natural language response
            // For now, return a simple formatted response

            try
            {
                var json = JsonConvert.DeserializeObject<ODataResponse>(bcData);
                
                if (json?.Value == null || json.Value.Count == 0)
                {
                    return "I couldn't find any matching records in Business Central.";
                }

                int count = json.Value.Count;
                return $"I found {count} record{(count != 1 ? "s" : "")} matching your query. " +
                       $"The results are displayed in the conversation history.";
            }
            catch
            {
                return "I received data from Business Central. The results are shown above.";
            }
        }
    }

    // Request/Response models
    public class VoiceQueryRequest
    {
        public string Query { get; set; }
        public string BCBaseUrl { get; set; }
        public string TenantId { get; set; }
    }

    public class QueryIntent
    {
        public string Entity { get; set; }
        public string Action { get; set; }
        public System.Collections.Generic.Dictionary<string, string> Filters { get; set; }
    }

    public class ODataResponse
    {
        [JsonProperty("value")]
        public System.Collections.Generic.List<object> Value { get; set; }
    }
}
