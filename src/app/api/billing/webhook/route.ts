import {NextRequest,NextResponse} from 'next/server';
import Stripe from 'stripe';
import {createClient as createSupabase} from '@supabase/supabase-js';

export const runtime='nodejs';
const validStatuses=['trialing','active','past_due','canceled','expired'];
function statusOf(status:string){
 if(status==='active'||status==='trialing'||status==='past_due'||status==='canceled')return status;
 return 'expired';
}
export async function POST(req:NextRequest){
 const secret=process.env.STRIPE_SECRET_KEY,signing=process.env.STRIPE_WEBHOOK_SECRET,service=process.env.SUPABASE_SERVICE_ROLE_KEY,url=process.env.NEXT_PUBLIC_SUPABASE_URL;
 if(!secret||!signing||!service||!url)return NextResponse.json({error:'Billing not configured'},{status:503});
 const signature=req.headers.get('stripe-signature');
 if(!signature)return NextResponse.json({error:'Signature missing'},{status:400});
 const stripe=new Stripe(secret);
 let event:Stripe.Event;
 try{event=stripe.webhooks.constructEvent(await req.text(),signature,signing);}
 catch{return NextResponse.json({error:'Invalid signature'},{status:400});}
 if(!['checkout.session.completed','customer.subscription.created','customer.subscription.updated','customer.subscription.deleted','invoice.payment_failed','invoice.paid'].includes(event.type))return NextResponse.json({received:true});
 try{
  let subId:string|undefined;
  if(event.type==='checkout.session.completed'){
   const session=event.data.object as Stripe.Checkout.Session;
   if(session.mode!=='subscription')return NextResponse.json({received:true});
   subId=typeof session.subscription==='string'?session.subscription:session.subscription?.id;
  }else if(event.type.startsWith('customer.subscription.')){
   subId=(event.data.object as Stripe.Subscription).id;
  }else{
   const invoice=event.data.object as Stripe.Invoice;
   // Stripe API versions differ; only process invoice events when the subscription reference exists.
   const parent=invoice.parent?.subscription_details?.subscription;
   subId=typeof parent==='string'?parent:parent?.id;
  }
  if(!subId)return NextResponse.json({received:true,ignored:'no subscription reference'});
  // Retrieve canonical subscription state instead of trusting potentially out-of-order event snapshots.
  const sub=await stripe.subscriptions.retrieve(subId);
  const org=sub.metadata.organization_id,plan=sub.metadata.plan_code;
  if(!org||!['starter','professional'].includes(plan))return NextResponse.json({error:'Missing subscription metadata'},{status:422});
  const customer=typeof sub.customer==='string'?sub.customer:sub.customer.id;
  const periodEnd=sub.items.data.reduce((max,item)=>Math.max(max,item.current_period_end||0),0);
  const status=statusOf(sub.status);
  if(!validStatuses.includes(status))throw new Error('Invalid subscription status');
  const db=createSupabase(url,service,{auth:{autoRefreshToken:false,persistSession:false}});
  const {error}=await db.rpc('apply_stripe_lifecycle_event',{
   p_event_id:event.id,p_event_created:event.created,p_org:org,p_plan:plan,p_status:status,
   p_customer:customer,p_subscription:sub.id,p_event_type:event.type,
   p_period_end:periodEnd?new Date(periodEnd*1000).toISOString():null,
   p_cancel_at_period_end:sub.cancel_at_period_end
  });
  if(error)throw error;
  return NextResponse.json({received:true});
 }catch(err){console.error('Stripe lifecycle sync failed',err);return NextResponse.json({error:'Retry later'},{status:500});}
}
