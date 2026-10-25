import { handle,browser,body } from '@/lib/agents/http';
import { removeSubscription,saveSubscription } from '@/lib/push/subscriptions';
export async function POST(request:Request) { return handle(async()=>saveSubscription(await browser(request,'write'),await body(request)),201); }
export async function DELETE(request:Request) { return handle(async()=>{removeSubscription(await browser(request,'write'),await body(request));return null;},204); }
