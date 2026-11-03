package cn.fpgavision.monitor;

import android.app.*;
import android.content.*;
import android.graphics.*;
import android.net.Uri;
import android.os.SystemClock;
import android.view.*;
import android.widget.*;
import java.util.*;
import java.util.concurrent.*;
import java.util.concurrent.atomic.AtomicBoolean;
import java.text.SimpleDateFormat;
import org.json.*;

/** Native event/message list and native video playback: no remote CSS dependency. */
final class EventCenter {
 final MainActivity a;
 final ScrollView view;
 final LinearLayout root,eventList,messageList;
 final TextView summary,connection;
 final ExecutorService network=Executors.newSingleThreadExecutor();
 final ExecutorService images=Executors.newFixedThreadPool(2);
 final AtomicBoolean loading=new AtomicBoolean(false);
 final android.util.LruCache<String,Bitmap> thumbnails=new android.util.LruCache<>(16);
 volatile long lastRefresh=0;volatile boolean closed=false;
 long latestSeq=0;String fingerprint="";
 Dialog detail;VideoView video;
 EventCenter(MainActivity activity){
  a=activity;root=a.column();root.setPadding(0,a.dp(6),0,a.dp(6));view=new ScrollView(a);view.addView(root);
  LinearLayout top=a.card(root,"事件与消息","NATIVE / RECORDS");
  summary=a.text("暂无事件数据",12,a.TEAL);top.addView(summary);
  connection=a.text("人脸录像 · 扫描留档 · 分拣异常与机械臂消息",10,a.MUTED);LinearLayout.LayoutParams cp=new LinearLayout.LayoutParams(-1,-2);cp.topMargin=a.dp(5);top.addView(connection,cp);
  Button refresh=a.button("刷新记录",false),read=a.button("全部已读",false),test=a.button("测试消息",false);a.addButtons(top,refresh,read,test);
  Button sort=a.button("分拣工作台",false);top.addView(sort);sort.setOnClickListener(v->{if(a.base.isEmpty()){a.connectionDialog();return;}a.startActivity(new Intent(Intent.ACTION_VIEW,Uri.parse(a.base+"/sort")));});
  refresh.setOnClickListener(v->refresh(true));
  read.setOnClickListener(v->post("/api/notifications/read",MainActivity.json("upto",latestSeq),"消息已标为已读"));
  test.setOnClickListener(v->post("/api/notifications/test",MainActivity.json(),"测试消息已生成，仅保存成功的视频会触发手机提醒"));
  eventList=a.column();root.addView(eventList);
  messageList=a.column();root.addView(messageList);
  render(new JSONArray(),new JSONArray(),0);
 }
 static String time(String raw){
  if(raw==null||raw.isEmpty()||raw.equals("null"))return "—";
  try{
   SimpleDateFormat input=new SimpleDateFormat("yyyy-MM-dd'T'HH:mm:ss.SSSXXX",Locale.US);
   java.util.Date date=input.parse(raw);
   return new SimpleDateFormat("MM-dd HH:mm:ss",Locale.getDefault()).format(date);
  }catch(Exception e){return raw.replace('T',' ').replaceAll("\\+.*$","");}
 }
 static String state(String value){
  switch(value){case "observed":return "已记录";case "completed":return "已保存";case "recording":return "录制中";case "interrupted":return "记录中断";case "no_video":return "无完整视频";default:return value;}
 }
 void post(String path,JSONObject body,String message){
  if(a.base.isEmpty()){a.connectionDialog();return;}String server=a.base;
  network.execute(()->{try{Server.post(server,path,body);a.ui.post(()->{if(!closed&&server.equals(a.base)){a.toast(message);refresh(true);}});}
   catch(Exception e){a.ui.post(()->{if(!closed)a.toast(e.getMessage());});}});
 }
 void refresh(boolean force){
  if(closed||a.base.isEmpty()||!a.resumed)return;
  long now=SystemClock.elapsedRealtime();if(!force&&now-lastRefresh<4000)return;
  if(!loading.compareAndSet(false,true))return;lastRefresh=now;String server=a.base;
  network.execute(()->{try{
   JSONObject events=Server.get(server,"/api/events?limit=30",10000),messages=Server.get(server,"/api/notifications?recent=1&limit=30",10000);
   JSONArray eventRows=events.getJSONArray("events"),messageRows=messages.getJSONArray("items");
   long seq=messages.getLong("latest_seq");int unread=messages.optInt("unread");
   a.ui.post(()->{if(closed||!server.equals(a.base))return;latestSeq=seq;
    String key=eventRows.toString()+messageRows.toString()+unread;
    summary.setText("最近 "+eventRows.length()+" 条事件  ·  "+unread+" 条未读");
    connection.setText("● 已同步电脑记录 · "+new SimpleDateFormat("HH:mm:ss",Locale.getDefault()).format(new Date()));
    if(!key.equals(fingerprint)){fingerprint=key;render(eventRows,messageRows,unread);}
    a.tabs[2].setText(unread>0?"事件消息 · "+Math.min(99,unread):"事件消息");
   });
  }catch(Exception e){a.ui.post(()->{if(!closed&&server.equals(a.base))connection.setText("连接中断，稍后自动重试");});}
  finally{loading.set(false);}});
 }
 void render(JSONArray events,JSONArray messages,int unread){
  eventList.removeAllViews();messageList.removeAllViews();
  LinearLayout list=a.card(eventList,"事件记录","TIMELINE");
  if(events.length()==0)a.note(list,"暂无事件。人脸、分拣异常和机械臂记录会显示在这里。");
  for(int n=0;n<events.length();n++){
   JSONObject event=events.optJSONObject(n);if(event==null)continue;
   String id=event.optString("id");LinearLayout item=a.row();item.setPadding(0,a.dp(11),0,a.dp(11));
   ImageView image=new ImageView(a);image.setScaleType(ImageView.ScaleType.CENTER_CROP);image.setBackground(a.shape(0xffeaf3f4,8));image.setClipToOutline(true);image.setContentDescription("事件首帧");
   item.addView(image,new LinearLayout.LayoutParams(a.dp(62),a.dp(42)));
   LinearLayout body=a.column();TextView title=a.text(event.optString("title",time(event.optString("started_at"))),12,a.INK);title.setTypeface(Typeface.DEFAULT,Typeface.BOLD);body.addView(title);
   String duration=event.isNull("duration_seconds")?"":String.format(Locale.getDefault()," · %.1f 秒",event.optDouble("duration_seconds"));
   TextView sub=a.text(state(event.optString("state"))+duration,10,event.optString("state").equals("recording")?a.TEAL:a.MUTED);body.addView(sub);
   LinearLayout.LayoutParams bp=new LinearLayout.LayoutParams(0,-2,1);bp.leftMargin=a.dp(10);item.addView(body,bp);
   Button open=a.button("查看",false);item.addView(open,new LinearLayout.LayoutParams(a.dp(54),a.dp(38)));open.setOnClickListener(v->open(id));item.setOnClickListener(v->open(id));list.addView(item);
   if(n<8&&!event.isNull("thumbnail")&&!id.isEmpty())thumbnail(image,id);
   if(n<events.length()-1){View line=new View(a);line.setBackgroundColor(a.LINE);list.addView(line,new LinearLayout.LayoutParams(-1,a.dp(1)));}
  }
  LinearLayout notices=a.card(messageList,"消息通知",unread>0?unread+" UNREAD":"NOTIFICATIONS");
  if(messages.length()==0)a.note(notices,"暂无消息。可以发送测试通知检查消息通道。");
  for(int n=messages.length()-1;n>=0;n--){
   JSONObject item=messages.optJSONObject(n);if(item==null)continue;
   LinearLayout row=a.column();row.setPadding(a.dp(11),a.dp(10),a.dp(11),a.dp(10));
   row.setBackground(a.shape(item.optBoolean("read")?0xfff7f9fb:0xffeaf6f2,10));
   TextView title=a.text(item.optString("title"),12,a.INK);title.setTypeface(Typeface.DEFAULT,Typeface.BOLD);row.addView(title);
   TextView body=a.text(item.optString("body"),10,a.MUTED);body.setMaxLines(3);body.setPadding(0,a.dp(5),0,a.dp(5));row.addView(body);
   row.addView(a.text(time(item.optString("created_at")),9,a.MUTED));
   LinearLayout.LayoutParams p=new LinearLayout.LayoutParams(-1,-2);p.bottomMargin=a.dp(7);notices.addView(row,p);
   if(!item.optString("kind").equals("test"))row.setOnClickListener(v->open(item.optString("event_id")));
  }
 }
 void thumbnail(ImageView image,String id){
  String server=a.base,key=server+"/"+id;Bitmap cached=thumbnails.get(key);if(cached!=null){image.setImageBitmap(cached);return;}
  images.execute(()->{if(closed||!server.equals(a.base))return;try{byte[] bytes=Server.image(server,"/api/events/"+Uri.encode(id)+"/thumbnail");
   BitmapFactory.Options options=new BitmapFactory.Options();options.inSampleSize=2;Bitmap bitmap=BitmapFactory.decodeByteArray(bytes,0,bytes.length,options);
   if(bitmap==null)return;thumbnails.put(key,bitmap);
   a.ui.post(()->{if(!closed&&server.equals(a.base))image.setImageBitmap(bitmap);});
  }catch(Exception ignored){}});
 }
 void open(String id){
  if(a.base.isEmpty()){a.connectionDialog();return;}String server=a.base;
  a.toast("正在读取事件");
  network.execute(()->{try{
   JSONObject event=Server.get(server,"/api/events/"+Uri.encode(id),10000).getJSONObject("event");
   a.ui.post(()->{if(!closed&&server.equals(a.base))showDetail(server,event);});
  }catch(Exception e){a.ui.post(()->{if(!closed)a.toast(e.getMessage());});}});
 }
 void showDetail(String server,JSONObject event){
  if(detail!=null)detail.dismiss();
  Dialog dialog=new Dialog(a);detail=dialog;
  LinearLayout panel=a.column();panel.setPadding(a.dp(18),a.dp(18),a.dp(18),a.dp(18));panel.setBackground(a.shape(Color.WHITE,16));
  LinearLayout heading=a.row();TextView title=a.text(event.optString("title","人脸事件")+" · "+state(event.optString("state")),16,a.INK);title.setTypeface(Typeface.DEFAULT,Typeface.BOLD);heading.addView(title,new LinearLayout.LayoutParams(0,-2,1));
  Button close=a.button("关闭",false);heading.addView(close);panel.addView(heading);close.setOnClickListener(v->dialog.dismiss());
  a.note(panel,"开始  "+time(event.optString("started_at"))+"\n结束  "+time(event.optString("ended_at"))+
   (event.isNull("duration_seconds")?"":"\n持续  "+String.format(Locale.getDefault(),"%.1f 秒",event.optDouble("duration_seconds"))));
  if(event.has("description"))a.note(panel,event.optString("description"));
  if(event.optString("kind").equals("face_scan")&&!event.isNull("thumbnail")){
   ImageView shot=new ImageView(a);shot.setScaleType(ImageView.ScaleType.FIT_CENTER);panel.addView(shot,new LinearLayout.LayoutParams(-1,a.dp(195)));thumbnail(shot,event.optString("id"));
  }
  if(event.optString("state").equals("completed")){
   VideoView player=new VideoView(a);video=player;LinearLayout.LayoutParams vp=new LinearLayout.LayoutParams(-1,a.dp(195));vp.topMargin=a.dp(14);panel.addView(player,vp);
   TextView info=a.text("点击播放，查看电脑端保存的事件录像",11,a.MUTED);info.setPadding(0,a.dp(9),0,a.dp(5));panel.addView(info);
   MediaController controller=new MediaController(a);controller.setAnchorView(player);player.setMediaController(controller);
   String url=server+"/api/events/"+Uri.encode(event.optString("id"))+"/video";
   Map<String,String> headers=new HashMap<>();headers.put("ngrok-skip-browser-warning","fpga-vision-app");headers.put("User-Agent","FPGA-Vision-Native/1.2");
   player.setVideoURI(Uri.parse(url),headers);
   player.setOnPreparedListener(m->{info.setText("事件录像 · "+time(event.optString("started_at")));player.start();});
   player.setOnErrorListener((m,what,extra)->{info.setText("暂时无法播放，请检查电脑网络或选择浏览器下载");return true;});
   Button play=a.button("播放 / 暂停",true),download=a.button("浏览器下载",false);a.addButtons(panel,play,download);
   play.setOnClickListener(v->{if(player.isPlaying())player.pause();else player.start();});download.setOnClickListener(v->a.external(url+"?download=1"));
  }
  if(!event.optString("error").isEmpty())a.note(panel,event.optString("error"));
  ScrollView scroll=new ScrollView(a);scroll.addView(panel);dialog.setContentView(scroll);
  dialog.setOnDismissListener(d->{if(video!=null){video.stopPlayback();video=null;}detail=null;});
  dialog.show();dialog.getWindow().setBackgroundDrawableResource(android.R.color.transparent);dialog.getWindow().setLayout(Math.min(a.getResources().getDisplayMetrics().widthPixels-a.dp(24),a.dp(540)),-2);
 }
 void pause(){if(video!=null&&video.isPlaying())video.pause();}
 void reset(){fingerprint="";lastRefresh=0;thumbnails.evictAll();root.scrollTo(0,0);}
 void close(){closed=true;network.shutdownNow();images.shutdownNow();if(detail!=null)detail.dismiss();thumbnails.evictAll();}
}

