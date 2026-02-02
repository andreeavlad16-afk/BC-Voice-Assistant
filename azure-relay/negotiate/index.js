/**
 * SignalR Negotiate Function
 * Returns connection info for clients to connect to SignalR hub
 * Azure Functions v4 with function.json declarative bindings
 */

module.exports = async function (context, req) {
    try {
        // Get user ID from query parameters
        const userId = (req.query && req.query.userId) || 'anonymous';
        
        // The SignalR connection info is bound via function.json 
        // and available in context.bindings.connectionInfo
        const connectionInfo = context.bindings.connectionInfo;
        
        if (!connectionInfo) {
            context.res = {
                status: 500,
                body: { error: 'SignalR connection info not available' }
            };
            return;
        }
        
        context.log(`✅ Negotiate: User ${userId} requesting SignalR connection`);
        
        context.res = {
            status: 200,
            jsonBody: connectionInfo
        };
    } catch (error) {
        context.log(`❌ Negotiate error: ${error.message}`);
        context.res = {
            status: 500,
            jsonBody: { error: error.message }
        };
    }
};
