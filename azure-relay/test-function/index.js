module.exports = async function (context, req) {
    context.log('Test function called');
    context.res = {
        status: 200,
        body: { message: 'Function app is working!', timestamp: new Date() }
    };
};
