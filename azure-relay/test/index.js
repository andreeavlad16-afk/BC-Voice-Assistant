module.exports = async function (context, req) {
    context.log('Test function called');
    context.res = {
        status: 200,
        body: JSON.stringify({ message: "Hello from Azure Functions!" })
    };
};
