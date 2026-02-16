// PWA Configuration - Auto-load on startup
// This file is loaded before app.js to pre-configure settings

(function() {
    'use strict';
    
    // Production configuration for Azure deployment
    const PRODUCTION_CONFIG = {
        clientId: '2dfcd259-35d2-43f4-ad0c-7e8863588472',
        tenantId: '60d3cd31-aac9-4a19-90f7-4cff0310f993',
        bcEnvironment: 'https://api.businesscentral.dynamics.com/v2.0/60d3cd31-aac9-4a19-90f7-4cff0310f993/GB-Demonstration',
        relayUrl: 'https://func-bcvoice-v2.azurewebsites.net/api/relay'
    };
    
    // Check if running on Azure Static Web Apps (production)
    const isProduction = window.location.hostname.includes('azurestaticapps.net');
    
    // Auto-configure if in production and not already configured
    if (isProduction) {
        const existingClientId = localStorage.getItem('bc_clientId');
        
        // Only set if not configured or using old values
        if (!existingClientId || existingClientId === '') {
            console.log('[Config] Auto-configuring production settings...');
            localStorage.setItem('bc_clientId', PRODUCTION_CONFIG.clientId);
            localStorage.setItem('bc_tenantId', PRODUCTION_CONFIG.tenantId);
            localStorage.setItem('bc_environment', PRODUCTION_CONFIG.bcEnvironment);
            localStorage.setItem('bc_relayUrl', PRODUCTION_CONFIG.relayUrl);
            console.log('[Config] ✅ Production settings configured');
        }
    }
    
    console.log('[Config] Environment:', isProduction ? 'Production' : 'Development');
})();
