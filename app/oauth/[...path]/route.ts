import {proxyOAuth} from '@/lib/oauth/http';
export const runtime='nodejs';
export const dynamic='force-dynamic';
export const GET=proxyOAuth;
export const POST=proxyOAuth;
export const HEAD=proxyOAuth;
export const OPTIONS=proxyOAuth;
