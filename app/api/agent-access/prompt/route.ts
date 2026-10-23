import { onboardingPrompt } from '@/lib/agents/onboarding';
import { handle,browser } from '@/lib/agents/http';
export async function GET(request:Request) { return handle(async()=>{await browser(request);return {prompt:onboardingPrompt()};}); }
