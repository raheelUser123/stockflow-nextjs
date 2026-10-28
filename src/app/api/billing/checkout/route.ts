import {NextRequest,NextResponse} from 'next/server';
import Stripe from 'stripe';
import {createClient} from '@/lib/supabase/server';

export async function POST(req:NextRequest){
 try {
  if(!process.env.STRIPE_SECRET_KEY || !process.env.STRIPE_PRICE_STARTER || !process.env.STRIPE_PRICE_PROFESSIONAL) return NextResponse.json({error:'Billing is not configured'}, {status:503});
  const stripe=new Stripe(process.env.STRIPE_SECRET_KEY);
  const supabase=await createClient();
  const {data:{user}}=await supabase.auth.getUser();if(!user)return NextResponse.json({error:'Unauthorized'},{status:401});
  const {organization_id,plan_code}=await req.json();
  if(typeof organization_id!=='string'||!['starter','professional'].includes(plan_code))return NextResponse.json({error:'Invalid request'},{status:400});
  const {data:member}=await supabase.from('organization_members').select('role').eq('organization_id',organization_id).eq('user_id',user.id).single();
  if(!member||!['owner','admin'].includes(member.role))return NextResponse.json({error:'Forbidden'},{status:403});
  const priceId=plan_code==='starter'?process.env.STRIPE_PRICE_STARTER:process.env.STRIPE_PRICE_PROFESSIONAL;
  const price=await stripe.prices.retrieve(priceId!);
  if(price.currency!=='pkr'||price.recurring?.interval!=='month')return NextResponse.json({error:'Stripe price must be a monthly PKR recurring price'},{status:503});
  const {data:sub}=await supabase.from('organization_subscriptions').select('stripe_customer_id,stripe_subscription_id').eq('organization_id',organization_id).single();
  if(sub?.stripe_subscription_id)return NextResponse.json({error:'Subscription already exists. Manage it through support to avoid duplicate billing.'},{status:409});
  const origin=process.env.NEXT_PUBLIC_SITE_URL?.replace(/\/$/,'');if(!origin)return NextResponse.json({error:'Site URL missing'},{status:503});
  const session=await stripe.checkout.sessions.create({mode:'subscription',line_items:[{price:priceId!,quantity:1}],customer:sub?.stripe_customer_id||undefined,customer_email:sub?.stripe_customer_id?undefined:user.email,client_reference_id:organization_id,metadata:{organization_id,plan_code},subscription_data:{metadata:{organization_id,plan_code}},success_url:`${origin}/dashboard/billing?checkout=success`,cancel_url:`${origin}/dashboard/billing?checkout=cancelled`});
  return NextResponse.json({url:session.url});
 }catch(e){console.error('Checkout error',e);return NextResponse.json({error:'Unable to create checkout session'},{status:500});}
}
