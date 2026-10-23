import { MCP_SCOPES,oauthConfig } from '@/lib/oauth/config';
export function GET(){try{const config=oauthConfig();return Response.json({resource:config.resource,authorization_servers:[config.issuer],scopes_supported:MCP_SCOPES,bearer_methods_supported:['header']},{headers:{'Cache-Control':'no-store'}});}catch{return Response.json({error:'oauth_not_configured'},{status:503});}}
