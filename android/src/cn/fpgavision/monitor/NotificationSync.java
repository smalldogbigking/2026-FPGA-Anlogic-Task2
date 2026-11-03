package cn.fpgavision.monitor;

import android.Manifest;
import android.app.*;
import android.app.job.*;
import android.content.*;
import android.content.pm.PackageManager;
import android.net.Uri;
import android.os.*;
import java.util.concurrent.*;
import java.util.concurrent.atomic.AtomicBoolean;
import org.json.*;

/** Only completed videos produce alerts. No foreground service or persistent notification. */
final class NotificationSync {
 static final String CHANNEL="face-events";
 static final int JOB_ID=20261201;
 static final ExecutorService worker=Executors.newSingleThreadExecutor();
 static final AtomicBoolean busy=new AtomicBoolean(false);
 static volatile long lastAttempt=0;
 static boolean allowed(Context c){
  return (Build.VERSION.SDK_INT<33||c.checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS)==PackageManager.PERMISSION_GRANTED)
   &&c.getSystemService(NotificationManager.class).areNotificationsEnabled();
 }
 static void setup(Context context){
  NotificationManager m=context.getSystemService(NotificationManager.class);
  m.cancel(1);m.deleteNotificationChannel("monitor");
  NotificationChannel channel=new NotificationChannel(CHANNEL,"视频保存提醒",NotificationManager.IMPORTANCE_HIGH);
  channel.setDescription("仅在人脸事件视频成功保存后提醒，点击直接查看录像");channel.enableVibration(true);m.createNotificationChannel(channel);
 }
 static void schedule(Context context){
  Context c=context.getApplicationContext();setup(c);
  JobScheduler scheduler=c.getSystemService(JobScheduler.class);
  if(!c.getSharedPreferences("connection",Context.MODE_PRIVATE).getBoolean("listen",false)||!allowed(c)){scheduler.cancel(JOB_ID);return;}
  if(scheduler.getPendingJob(JOB_ID)==null){
   JobInfo job=new JobInfo.Builder(JOB_ID,new ComponentName(c,NotificationJobService.class))
    .setRequiredNetworkType(JobInfo.NETWORK_TYPE_ANY)
    .setPeriodic(Math.max(15*60*1000L,JobInfo.getMinPeriodMillis()),Math.max(5*60*1000L,JobInfo.getMinFlexMillis()))
    .setBackoffCriteria(30000,JobInfo.BACKOFF_POLICY_EXPONENTIAL).build();
   scheduler.schedule(job);
  }
 }
 static void cancel(Context c){c.getSystemService(JobScheduler.class).cancel(JOB_ID);c.getSystemService(NotificationManager.class).cancel(1);}
 static void request(Context context,boolean force){
  Context c=context.getApplicationContext();long now=SystemClock.elapsedRealtime();
  if(!force&&now-lastAttempt<2000)return;if(!busy.compareAndSet(false,true))return;lastAttempt=now;
  worker.execute(()->{try{sync(c);}catch(Exception ignored){}finally{busy.set(false);}});
 }
 static synchronized void sync(Context c) throws Exception {
  SharedPreferences prefs=c.getSharedPreferences("connection",Context.MODE_PRIVATE);
  String server=prefs.getString("url","");
  if(server.isEmpty()||!prefs.getBoolean("listen",false)||!allowed(c))return;
  JSONObject meta=Server.get(server,"/api/notifications?limit=1",10000);
  String instance=meta.getString("instance_id"),cursorKey="cursor_"+instance;
  if(!prefs.contains(cursorKey)){prefs.edit().putLong(cursorKey,meta.getLong("latest_seq")).commit();return;}
  long cursor=prefs.getLong(cursorKey,0);
  JSONObject data=Server.get(server,"/api/notifications?after="+cursor+"&limit=30",10000);
  if(!instance.equals(data.getString("instance_id")))return;
  JSONArray items=data.getJSONArray("items");
  for(int n=0;n<items.length();n++){
   if(Thread.currentThread().isInterrupted()||!prefs.getBoolean("listen",false)||!server.equals(prefs.getString("url","")))return;
   JSONObject item=items.getJSONObject(n);String eventId=item.optString("event_id"),sentKey="saved_"+instance+"_"+eventId;
   if(item.optString("kind").equals("face_completed")&&!prefs.getBoolean(sentKey,false)){
    JSONObject event=Server.get(server,"/api/events/"+Uri.encode(eventId),10000).getJSONObject("event");
    if(NotificationRules.isSavedVideo(item.optString("kind"),event.optString("state"),event.optString("video",null))){
     if(!allowed(c)||!prefs.getBoolean("listen",false)||!server.equals(prefs.getString("url",""))||Thread.currentThread().isInterrupted())return;
     Intent open=new Intent(c,MainActivity.class).addFlags(Intent.FLAG_ACTIVITY_SINGLE_TOP|Intent.FLAG_ACTIVITY_CLEAR_TOP);
     open.setData(Uri.parse("fpgavision://events/"+Uri.encode(eventId)));open.putExtra("event",eventId);
     PendingIntent pending=PendingIntent.getActivity(c,0,open,PendingIntent.FLAG_UPDATE_CURRENT|PendingIntent.FLAG_IMMUTABLE);
     String body="目标视频已保存 · "+EventCenter.time(event.optString("started_at"))+"\n点击直接查看录像";
     Notification notification=new Notification.Builder(c,CHANNEL).setSmallIcon(R.drawable.ic_notification)
      .setContentTitle("人脸识别，目标已保存").setContentText(body)
      .setStyle(new Notification.BigTextStyle().bigText(body)).setContentIntent(pending)
      .setAutoCancel(true).setOnlyAlertOnce(true).setGroup("saved-face-videos").build();
     c.getSystemService(NotificationManager.class).notify(eventId,2,notification);
     prefs.edit().putBoolean(sentKey,true).putLong(cursorKey,item.getLong("seq")).commit();
     continue;
    }
   }
   if(NotificationRules.isSortAlert(item.optString("kind"))&&!prefs.getBoolean(sentKey,false)){
    if(!allowed(c)||!prefs.getBoolean("listen",false)||!server.equals(prefs.getString("url","")))return;
    Intent open=new Intent(c,MainActivity.class).addFlags(Intent.FLAG_ACTIVITY_SINGLE_TOP|Intent.FLAG_ACTIVITY_CLEAR_TOP);
    open.setData(Uri.parse("fpgavision://events/"+Uri.encode(eventId)));open.putExtra("event",eventId);
    PendingIntent pending=PendingIntent.getActivity(c,0,open,PendingIntent.FLAG_UPDATE_CURRENT|PendingIntent.FLAG_IMMUTABLE);
    Notification notice=new Notification.Builder(c,CHANNEL).setSmallIcon(R.drawable.ic_notification)
      .setContentTitle(item.optString("title","分拣异常")).setContentText(item.optString("body"))
      .setContentIntent(pending).setAutoCancel(true).setOnlyAlertOnce(true).setGroup("sort-alerts").build();
    c.getSystemService(NotificationManager.class).notify(eventId,3,notice);prefs.edit().putBoolean(sentKey,true).commit();
   }
   prefs.edit().putLong(cursorKey,item.getLong("seq")).commit();
  }
 }
}

