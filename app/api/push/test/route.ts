import { getDb } from '@/lib/db';
import { AccessError } from '@/lib/access/principal';
import { handle,browser } from '@/lib/agents/http';
import { testEvent } from '@/lib/push/events';
import { subscriptionsOf } from '@/lib/push/subscriptions';
import { vapid } from '@/lib/push/dispatch';
export async function POST(request:Request) { return handle(async()=>{const owner=await browser(request,'write');if(!vapid())throw new AccessError(503,'push_not_configured','Push notifications are not configured');const devices=subscriptionsOf(owner).length;if(devices===0)throw new AccessError(409,'no_subscription','No device is subscribed');getDb().transaction(()=>testEvent(owner))();return {devices};},202); }
