import {NextRequest,NextResponse} from 'next/server';
import Stripe from 'stripe';
import {createClient} from '@/lib/supabase/server';

export async function POST(req:NextRequest){
 try {
  if(!process.env.STRIPE_SECRET_KEY || !process.env.NEXT_PUBLIC_SITE_URL)
   return NextResponse.json({error:'Stripe billing is not configured'},{status:503});
  const supabase=await createClient();
  const {data:{user},error:authError}=await supabase.auth.getUser();
  if(authError||!user)return NextResponse.json({error:'Please sign in'},{status:401});
  const body=await req.json().catch(()=>null);
  const orgId=body?.organization_id;
  if(typeof orgId!=='string'||!/^[0-9a-f-]{36}$/i.test(orgId))return NextResponse.json({error:'Invalid organization'},{status:400});
  const {data:member,error:memberError}=await supabase.from('organization_members').select('role').eq('organization_id',orgId).eq('user_id',user.id).maybeSingle();
  if(memberError||!member||!['owner','admin'].includes(member.role))return NextResponse.json({error:'Forbidden'},{status:403});
  const {data:subscription,error:subError}=await supabase.from('organization_subscriptions').select('stripe_customer_id').eq('organization_id',orgId).maybeSingle();
  if(subError||!subscription?.stripe_customer_id)return NextResponse.json({error:'No Stripe billing customer exists for this company'},{status:409});
  const stripe=new Stripe(process.env.STRIPE_SECRET_KEY);
  const origin=new URL(process.env.NEXT_PUBLIC_SITE_URL);
  if(!['https:','http:'].includes(origin.protocol))return NextResponse.json({error:'Invalid site URL'},{status:503});
  const portal=await stripe.billingPortal.sessions.create({customer:subscription.stripe_customer_id,return_url:new URL('/dashboard/billing',origin).toString()});
  return NextResponse.json({url:portal.url});
 }catch(error){console.error('Billing portal creation failed',error);return NextResponse.json({error:'Unable to open billing portal'},{status:500});}
}
