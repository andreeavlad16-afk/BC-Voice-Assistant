module.exports = async function (context, req) {
    context.log('Simple test function');
    
    context.res = {
        status: 200,
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ 
            message: 'Function is running',
            hasBody: !!req.body,
            body: req.body 
        })
    };
};
