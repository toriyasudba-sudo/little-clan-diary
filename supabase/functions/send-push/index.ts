import webpush from 'npm:web-push@3.6.7';
import { createClient } from 'npm:@supabase/supabase-js@2';

const cors = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type, x-webhook-secret',
};

const supabaseUrl = Deno.env.get('SUPABASE_URL')!;
const secretKey = Deno.env.get('SUPABASE_SECRET_KEY') ?? Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!;
const vapidPublic = Deno.env.get('VAPID_PUBLIC_KEY')!;
const vapidPrivate = Deno.env.get('VAPID_PRIVATE_KEY')!;
const webhookSecret = Deno.env.get('WEBHOOK_SECRET')!;

const admin = createClient(supabaseUrl, secretKey, {auth: {persistSession: false, autoRefreshToken: false}});
webpush.setVapidDetails('mailto:admin@littleclan.school', vapidPublic, vapidPrivate);

export default {
  async fetch(req: Request) {
    if (req.method === 'OPTIONS') return new Response('ok', {headers: cors});
    if (req.method !== 'POST') return new Response('Method not allowed', {status:405, headers:cors});

    const suppliedSecret = req.headers.get('x-webhook-secret') ?? '';
    if (!webhookSecret || suppliedSecret !== webhookSecret) {
      return new Response(JSON.stringify({error:'Unauthorized'}), {status:401, headers:{...cors,'Content-Type':'application/json'}});
    }

    try {
      const payload = await req.json();
      const notificationId = payload?.notification_id ?? payload?.record?.id;
      if (!notificationId) throw new Error('notification_id is required');

      const {data: notification, error: notificationError} = await admin
        .from('notifications')
        .select('id,recipient_id,title,body,type,data')
        .eq('id', notificationId)
        .single();
      if (notificationError) throw notificationError;

      const {data: subscriptions, error: subscriptionsError} = await admin
        .from('push_subscriptions')
        .select('id,endpoint,subscription')
        .eq('user_id', notification.recipient_id);
      if (subscriptionsError) throw subscriptionsError;

      const message = JSON.stringify({
        title: notification.title,
        body: notification.body,
        tag: `little-clan-${notification.type}-${notification.id}`,
        notification_id: notification.id,
        url: './',
      });

      const results = await Promise.allSettled((subscriptions ?? []).map(async sub => {
        try {
          await webpush.sendNotification(sub.subscription, message, {TTL: 60 * 60 * 24});
          return {id: sub.id, ok:true};
        } catch (err: any) {
          const status = err?.statusCode;
          if (status === 404 || status === 410) {
            await admin.from('push_subscriptions').delete().eq('id', sub.id);
          }
          return {id: sub.id, ok:false, status};
        }
      }));

      return new Response(JSON.stringify({ok:true, notification_id:notification.id, subscriptions:results.length, results}), {
        headers:{...cors,'Content-Type':'application/json'}
      });
    } catch (error) {
      console.error(error);
      return new Response(JSON.stringify({error:String(error?.message ?? error)}), {
        status:500,
        headers:{...cors,'Content-Type':'application/json'}
      });
    }
  }
};
