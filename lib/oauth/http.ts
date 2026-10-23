import {isIP} from 'node:net';
import {request as httpRequest,type IncomingMessage} from 'node:http';
import {Readable} from 'node:stream';
import {oauthConfig} from './config';

const requestLimit=65536;
const responseLimit=262144;
let activeRequests=0;

async function boundedBody(stream:ReadableStream<Uint8Array>|null,limit:number,signal:AbortSignal):Promise<Uint8Array<ArrayBuffer>> {
  if(!stream)return new Uint8Array();
  const reader=stream.getReader();const chunks:Uint8Array[]=[];let length=0;
  const abort=()=>{void reader.cancel().catch(()=>{});};signal.addEventListener('abort',abort,{once:true});
  try{
    while(true){
      signal.throwIfAborted();const result=await reader.read();signal.throwIfAborted();
      if(result.done)break;length+=result.value.byteLength;
      if(length>limit){await reader.cancel();throw new RangeError('OAuth message exceeds its bound');}
      chunks.push(result.value);
    }
    return new Uint8Array(Buffer.concat(chunks));
  }finally{signal.removeEventListener('abort',abort);reader.releaseLock();}
}

export async function proxyOAuth(request:Request):Promise<Response> {
  const incoming=new URL(request.url);
  const metadata=/^\/\.well-known\/(oauth-authorization-server|openid-configuration)(\/oauth)?$/.test(incoming.pathname);
  if(!metadata&&!incoming.pathname.startsWith('/oauth/'))return new Response(null,{status:404});
  if(!['GET','HEAD','POST','OPTIONS'].includes(request.method))return new Response(null,{status:405,headers:{Allow:'GET, HEAD, POST, OPTIONS'}});
  if(activeRequests>=32)return Response.json({error:'temporarily_unavailable'},{status:429,headers:{'Cache-Control':'no-store','Retry-After':'1'}});
  if(Number(request.headers.get('content-length')??0)>requestLimit)return Response.json({error:'request_too_large'},{status:413});
  activeRequests++;
  try{
    const config=oauthConfig();
    const path=metadata?'/oauth/.well-known/openid-configuration':incoming.pathname;
    const upstream=new URL(`http://127.0.0.1:${config.port}`);upstream.pathname=path;upstream.search=incoming.search;
    const headers=new Headers();
    for(const name of ['accept','content-type','authorization','cookie','origin','access-control-request-method','access-control-request-headers']){const value=request.headers.get(name);if(value!==null)headers.set(name,value);}
    headers.set('host',new URL(config.origin).host);
    const forwarded=request.headers.get('x-forwarded-for')?.split(',').at(-1)?.trim();
    if(forwarded&&isIP(forwarded))headers.set('x-forwarded-for',forwarded);
    const signal=AbortSignal.any([request.signal,AbortSignal.timeout(5000)]);
    const body=await boundedBody(request.body,requestLimit,signal);
    const response=await new Promise<IncomingMessage>((resolve,reject)=>{
      const outgoing=httpRequest({hostname:'127.0.0.1',port:config.port,path:upstream.pathname+upstream.search,method:request.method,headers:Object.fromEntries(headers),signal},resolve);
      outgoing.on('error',reject);outgoing.end(body.length?body:undefined);
    });
    const output=await boundedBody(Readable.toWeb(response) as ReadableStream<Uint8Array>,responseLimit,signal);
    const responseHeaders=new Headers();
    for(const [name,value] of Object.entries(response.headers)){if(value!==undefined&&!['set-cookie','content-length','connection','transfer-encoding'].includes(name))responseHeaders.set(name,Array.isArray(value)?value.join(', '):value);}
    for(const cookie of response.headers['set-cookie']??[])responseHeaders.append('set-cookie',cookie);
    responseHeaders.set('Cache-Control','no-store');
    return new Response(request.method==='HEAD'||[204,304].includes(response.statusCode??0)?null:output,{status:response.statusCode??502,headers:responseHeaders});
  }catch(error){
    return Response.json({error:error instanceof RangeError?'request_too_large':'temporarily_unavailable'},{status:error instanceof RangeError?413:503,headers:{'Cache-Control':'no-store'}});
  }finally{activeRequests--;}
}
