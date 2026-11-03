package cn.fpgavision.monitor;

import android.Manifest;
import android.app.*;
import android.content.*;
import android.content.pm.PackageManager;
import android.content.res.ColorStateList;
import android.graphics.*;
import android.graphics.drawable.*;
import android.net.Uri;
import android.os.*;
import android.view.*;
import android.webkit.*;
import android.widget.*;
import java.util.*;
import java.util.concurrent.*;
import java.util.concurrent.atomic.AtomicBoolean;
import org.json.JSONObject;

/** Native live preview and device controls; event history uses the shared event page. */
public class MainActivity extends Activity {
 static final String VERSION=ClientContract.VERSION;
 static final int[] MODE_IDS={0,1,2,4,5,6,7,8,9,10,12,13};
 int modeIndex(int value){for(int i=0;i<MODE_IDS.length;i++)if(MODE_IDS[i]==value)return i;return 0;}
 final int BG=Color.rgb(244,247,249),INK=Color.rgb(23,43,58),MUTED=Color.rgb(131,149,161),TEAL=Color.rgb(8,127,130),LINE=Color.rgb(226,234,239);
 final Handler ui=new Handler(Looper.getMainLooper());
 final ScheduledExecutorService poller=Executors.newSingleThreadScheduledExecutor();
 final ExecutorService commands=Executors.newSingleThreadExecutor();
 final AtomicBoolean servoBusy=new AtomicBoolean(false);
 SharedPreferences prefs;volatile String base="";volatile boolean resumed=false,destroyed=false;
 volatile int page=0;volatile long frameVersion=-1;volatile JSONObject latest=new JSONObject(),media=new JSONObject();
 volatile long moveGeneration=0;boolean serviceAfterPermission=false,configSynced=false,outputSynced=false;
 LinearLayout root,content,livePage,controlPage,bottom;ScrollView liveScroll,controlScroll;
 TextView connection,frameState,modeLabel,recordLabel,eventLabel,subtitle,recognitionLabel,trackLabel;ImageView camera;
 TextView[] metricValues=new TextView[4];Button clarityButton;Spinner moveSpeed;EventCenter events;Dialog previewDialog;ImageView enlargedCamera;TextView enlargedState;
 Button recordButton,autoButton,previewButton;Button[] tabs=new Button[3];List<View> controlled=new ArrayList<>();
 Spinner mode,beauty,quality,fps,detail,rate,isp;SeekBar ispValue;TextView ispPercent;Dialog consoleDialog;
 Switch hdmi,led,alarm;Bitmap currentBitmap;
 int pan=1500,tilt=1500;boolean previewEnabled=true;

 int dp(float v){return Math.round(v*getResources().getDisplayMetrics().density);}
 GradientDrawable shape(int color,int radius){GradientDrawable g=new GradientDrawable();g.setColor(color);g.setCornerRadius(dp(radius));return g;}
 GradientDrawable bordered(int color,int radius){GradientDrawable g=shape(color,radius);g.setStroke(dp(1),LINE);return g;}
 TextView text(String value,int size,int color){TextView t=new TextView(this);t.setText(value);t.setTextSize(size);t.setTextColor(color);t.setIncludeFontPadding(false);return t;}
 LinearLayout column(){LinearLayout l=new LinearLayout(this);l.setOrientation(1);return l;}
 LinearLayout row(){LinearLayout l=new LinearLayout(this);l.setGravity(Gravity.CENTER_VERTICAL);return l;}
 Button button(String label,boolean primary){
  Button b=new Button(this);b.setText(label);b.setTextSize(12);b.setAllCaps(false);b.setMaxLines(1);b.setEllipsize(android.text.TextUtils.TruncateAt.END);b.setTextColor(primary?Color.WHITE:TEAL);
  b.setMinWidth(0);b.setMinimumWidth(0);b.setMinHeight(0);b.setMinimumHeight(0);b.setPadding(dp(8),dp(5),dp(8),dp(5));
  b.setTypeface(Typeface.create("sans-serif-medium",Typeface.NORMAL));
  b.setBackground(new RippleDrawable(ColorStateList.valueOf(0x22087f82),bordered(primary?TEAL:Color.WHITE,10),null));return b;
 }
 void addButtons(LinearLayout parent,Button...buttons){
  LinearLayout r=row();for(int n=0;n<buttons.length;n++){LinearLayout.LayoutParams p=new LinearLayout.LayoutParams(0,dp(44),1);if(n>0)p.leftMargin=dp(7);r.addView(buttons[n],p);}
  LinearLayout.LayoutParams rp=new LinearLayout.LayoutParams(-1,-2);rp.topMargin=dp(10);parent.addView(r,rp);
 }
 LinearLayout card(LinearLayout parent,String title,String tag){
  LinearLayout c=column();c.setPadding(dp(12),dp(12),dp(12),dp(12));c.setBackground(bordered(Color.WHITE,15));
  LinearLayout.LayoutParams p=new LinearLayout.LayoutParams(-1,-2);p.setMargins(dp(10),0,dp(10),dp(10));parent.addView(c,p);
  if(title!=null){LinearLayout h=row();TextView t=text(title,14,INK);t.setTypeface(Typeface.DEFAULT,Typeface.BOLD);h.addView(t,new LinearLayout.LayoutParams(0,-2,1));
   if(tag!=null)h.addView(text(tag,9,MUTED));c.addView(h);Space s=new Space(this);c.addView(s,new LinearLayout.LayoutParams(1,dp(9)));}
  return c;
 }
 void note(LinearLayout parent,String value){TextView t=text(value,10,MUTED);t.setLineSpacing(dp(3),1);LinearLayout.LayoutParams p=new LinearLayout.LayoutParams(-1,-2);p.topMargin=dp(10);parent.addView(t,p);}
 Spinner spinner(String[] values){Spinner s=new Spinner(this);ArrayAdapter<String>a=new ArrayAdapter<>(this,android.R.layout.simple_spinner_dropdown_item,values);s.setAdapter(a);s.setBackground(bordered(0xfff8fafb,8));s.setPadding(dp(5),0,dp(3),0);return s;}
 void fields(LinearLayout parent,String left,Spinner a,String right,Spinner b){
  LinearLayout r=row();String[] labels={left,right};Spinner[] widgets={a,b};
  for(int n=0;n<2;n++){LinearLayout col=column();TextView label=text(labels[n],10,MUTED);col.addView(label);LinearLayout.LayoutParams sp=new LinearLayout.LayoutParams(-1,dp(40));sp.topMargin=dp(5);col.addView(widgets[n],sp);LinearLayout.LayoutParams cp=new LinearLayout.LayoutParams(0,-2,1);if(n>0)cp.leftMargin=dp(10);r.addView(col,cp);}
  LinearLayout.LayoutParams p=new LinearLayout.LayoutParams(-1,-2);p.bottomMargin=dp(10);parent.addView(r,p);
 }
 public void onCreate(Bundle saved){
  super.onCreate(saved);prefs=getSharedPreferences("connection",MODE_PRIVATE);base=prefs.getString("url","");NotificationSync.setup(this);
  getWindow().setStatusBarColor(BG);getWindow().setNavigationBarColor(Color.WHITE);
  getWindow().getDecorView().setSystemUiVisibility(View.SYSTEM_UI_FLAG_LIGHT_STATUS_BAR|View.SYSTEM_UI_FLAG_LIGHT_NAVIGATION_BAR);
  root=column();root.setBackgroundColor(BG);
  root.setOnApplyWindowInsetsListener((v,insets)->{v.setPadding(insets.getSystemWindowInsetLeft(),insets.getSystemWindowInsetTop(),insets.getSystemWindowInsetRight(),insets.getSystemWindowInsetBottom());return insets;});
  LinearLayout top=row();top.setPadding(dp(14),dp(6),dp(12),dp(6));top.setBackgroundColor(Color.WHITE);
  ImageView logo=new ImageView(this);logo.setImageResource(R.mipmap.ic_launcher);top.addView(logo,new LinearLayout.LayoutParams(dp(37),dp(37)));
  LinearLayout brand=column();TextView title=text("安路视界",19,INK);title.setTypeface(Typeface.DEFAULT,Typeface.BOLD);brand.addView(title);
  brand.addView(text("2026 年 FPGA 赛道  ·  v"+VERSION,10,TEAL));LinearLayout.LayoutParams bp=new LinearLayout.LayoutParams(0,-2,1);bp.leftMargin=dp(7);top.addView(brand,bp);
  Button settings=button("连接设置",false);top.addView(settings,new LinearLayout.LayoutParams(dp(86),dp(36)));settings.setOnClickListener(v->connectionDialog());
  root.addView(top,new LinearLayout.LayoutParams(-1,dp(60)));
  LinearLayout statusRow=row();statusRow.setPadding(dp(16),dp(8),dp(16),dp(8));
  connection=text("● 尚未连接",11,MUTED);statusRow.addView(connection,new LinearLayout.LayoutParams(0,-2,1));
  subtitle=text("端侧感知 · 实时守护",9,MUTED);statusRow.addView(subtitle);root.addView(statusRow);
  content=column();root.addView(content,new LinearLayout.LayoutParams(-1,0,1));
  livePage=column();livePage.setPadding(0,dp(4),0,dp(4));liveScroll=new ScrollView(this);liveScroll.setFillViewport(true);liveScroll.setClipToPadding(false);liveScroll.addView(livePage);content.addView(liveScroll,new LinearLayout.LayoutParams(-1,-1));
  buildLive();
  controlPage=column();controlPage.setPadding(0,dp(4),0,dp(4));controlScroll=new ScrollView(this);controlScroll.addView(controlPage);content.addView(controlScroll,new LinearLayout.LayoutParams(-1,-1));controlScroll.setVisibility(View.GONE);buildControls();
  events=new EventCenter(this);content.addView(events.view,new LinearLayout.LayoutParams(-1,-1));events.view.setVisibility(View.GONE);
  bottom=row();bottom.setBackgroundColor(Color.WHITE);bottom.setPadding(dp(10),dp(7),dp(10),dp(7));
  String[] labels={"实时监控","设备控制","事件消息"};
  for(int i=0;i<3;i++){final int target=i;tabs[i]=button(labels[i],false);LinearLayout.LayoutParams p=new LinearLayout.LayoutParams(0,dp(44),1);p.setMargins(dp(3),0,dp(3),0);bottom.addView(tabs[i],p);tabs[i].setOnClickListener(v->showPage(target));}root.addView(bottom);
  setContentView(root);showPage(0);
  poller.scheduleWithFixedDelay(this::refresh,0,600,TimeUnit.MILLISECONDS);
  if(base.isEmpty())connectionDialog();else{startPreview();if(prefs.getBoolean("listen",false))enableListening();}
  String event=getIntent().getStringExtra("event");if(event!=null&&!base.isEmpty())openEvent(event);
 }
 void buildLive(){
  LinearLayout c=card(livePage,null,null);LinearLayout head=row();
  TextView title=text("实时画面",15,INK);title.setTypeface(Typeface.DEFAULT,Typeface.BOLD);head.addView(title,new LinearLayout.LayoutParams(0,-2,1));
  clarityButton=button("流畅",false);previewButton=button("暂停",false);
  head.addView(clarityButton,new LinearLayout.LayoutParams(dp(54),dp(32)));LinearLayout.LayoutParams pp=new LinearLayout.LayoutParams(dp(54),dp(32));pp.leftMargin=dp(6);head.addView(previewButton,pp);
  c.addView(head);Space gap=new Space(this);c.addView(gap,new LinearLayout.LayoutParams(1,dp(10)));
  FrameLayout screen=new FrameLayout(this);screen.setBackground(shape(0xff122735,11));screen.setClipToOutline(true);
  camera=new ImageView(this);camera.setContentDescription("开发板实时画面");camera.setScaleType(ImageView.ScaleType.FIT_CENTER);screen.addView(camera,new FrameLayout.LayoutParams(-1,-1));
  frameState=text("请先配置电脑端网址",10,0xffc2e2e4);frameState.setGravity(Gravity.CENTER);frameState.setPadding(dp(8),dp(3),dp(8),dp(3));
  FrameLayout.LayoutParams fp=new FrameLayout.LayoutParams(-1,dp(27),Gravity.BOTTOM);frameState.setBackgroundColor(0x99122735);screen.addView(frameState,fp);
  TextView live=text("● LIVE / FPGA",9,0xffa6e0d1);FrameLayout.LayoutParams lp=new FrameLayout.LayoutParams(-2,-2,Gravity.TOP|Gravity.LEFT);lp.setMargins(dp(9),dp(9),0,0);screen.addView(live,lp);
  c.addView(screen,new LinearLayout.LayoutParams(-1,dp(190)));
  screen.addOnLayoutChangeListener((v,l,t,r,b,ol,ot,or,ob)->{int wanted=(r-l)*9/16;if(wanted>0&&Math.abs(v.getLayoutParams().height-wanted)>1){v.getLayoutParams().height=wanted;v.requestLayout();}});
  LinearLayout stats=row();stats.setPadding(0,dp(11),0,dp(9));String[] labels={"视觉模式","输出画质","回传画面","画面延迟"};
  for(int i=0;i<4;i++){LinearLayout cell=column();cell.setGravity(Gravity.CENTER);cell.addView(text(labels[i],9,MUTED));metricValues[i]=text("—",12,INK);metricValues[i].setTypeface(Typeface.DEFAULT,Typeface.BOLD);metricValues[i].setMaxLines(1);metricValues[i].setEllipsize(android.text.TextUtils.TruncateAt.END);LinearLayout.LayoutParams vp=new LinearLayout.LayoutParams(-2,-2);vp.topMargin=dp(5);cell.addView(metricValues[i],vp);stats.addView(cell,new LinearLayout.LayoutParams(0,-2,1));}c.addView(stats);
  LinearLayout recognition=row();recognition.setPadding(dp(9),dp(8),dp(9),dp(8));recognition.setBackground(shape(0xffeef7f4,8));
  recognitionLabel=text("人脸 · 等待设备",10,TEAL);recognitionLabel.setMaxLines(3);trackLabel=text("云台 · 待机",10,MUTED);recognition.addView(recognitionLabel,new LinearLayout.LayoutParams(0,-2,1));recognition.addView(trackLabel);c.addView(recognition);
  Button photo=button("拍照",true),restore=button("恢复画面",false),full=button("全屏",false);recordButton=button("录像",false);addButtons(c,photo,recordButton,restore,full);
  photo.setOnClickListener(v->command("/api/media",json("action","photo"),"照片已保存到电脑",false));restore.setOnClickListener(v->startPreview());full.setOnClickListener(v->showPreview());
  recordButton.setOnClickListener(v->command("/api/media",json("action",media.optBoolean("recording")?"stop":"record"),"手动录像状态已更新",false));
  previewButton.setOnClickListener(v->{previewEnabled=!previewEnabled;setPreview();previewButton.setText(previewEnabled?"暂停":"开启");});
  clarityButton.setOnClickListener(v->{detail.setSelection(detail.getSelectedItemPosition()==0?1:0);startPreview();});
  LinearLayout footer=row();modeLabel=text("FPGA 图像引擎",9,MUTED);recordLabel=text("USB 视频链路",9,MUTED);footer.addView(modeLabel,new LinearLayout.LayoutParams(0,dp(27),1));footer.addView(recordLabel);c.addView(footer);
  LinearLayout quick=card(livePage,"快捷模式","一键切换");Button face=button("人脸",true),track=button("红色",false),raw=button("原图",false),more=button("全部模式",false);addButtons(quick,face,track,raw,more);
  controlled.add(face);controlled.add(track);controlled.add(raw);face.setOnClickListener(v->setMode(12));track.setOnClickListener(v->setMode(10));raw.setOnClickListener(v->setMode(0));more.setOnClickListener(v->showPage(1));
  LinearLayout gimbal=card(livePage,"云台与事件守护","按住移动 · 松开保持");LinearLayout area=row();LinearLayout pad=column();buildPad(pad);area.addView(pad,new LinearLayout.LayoutParams(dp(156),-2));
  LinearLayout tools=column();LinearLayout.LayoutParams tp=new LinearLayout.LayoutParams(0,-2,1);tp.leftMargin=dp(10);area.addView(tools,tp);
  tools.addView(text("移动速度",9,MUTED));moveSpeed=spinner(new String[]{"慢速","中速","快速"});moveSpeed.setSelection(1);tools.addView(moveSpeed,new LinearLayout.LayoutParams(-1,dp(34)));
  autoButton=button("自动录像 · 开",false);LinearLayout.LayoutParams ap=new LinearLayout.LayoutParams(-1,dp(38));ap.topMargin=dp(8);tools.addView(autoButton,ap);
  eventLabel=text("监测中，等待人脸",10,TEAL);eventLabel.setMaxLines(2);LinearLayout.LayoutParams ep=new LinearLayout.LayoutParams(-1,-2);ep.topMargin=dp(7);tools.addView(eventLabel,ep);
  autoButton.setOnClickListener(v->{JSONObject state=media.optJSONObject("face_events");boolean enabled=state==null||!state.optBoolean("enabled",true);command("/api/events/settings",json("enabled",enabled),enabled?"自动录像已开启":"自动录像已关闭",false);});gimbal.addView(area);
  LinearLayout last=card(livePage,"运行信息","ON DEVICE");TextView explanation=text("人脸出现开始录像，连续消失 5 秒后保存。期间再现自动续录，事件与消息同步留存。",11,MUTED);explanation.setLineSpacing(dp(3),1);last.addView(explanation);
 }
 void showPreview(){
  if(previewDialog!=null)return;stopMove();Dialog dialog=new Dialog(this,android.R.style.Theme_Material_Light_NoActionBar);previewDialog=dialog;
  LinearLayout panel=column();panel.setBackgroundColor(0xff122735);panel.setPadding(dp(12),dp(24),dp(12),dp(18));
  panel.setOnApplyWindowInsetsListener((v,insets)->{v.setPadding(dp(12)+insets.getSystemWindowInsetLeft(),dp(12)+insets.getSystemWindowInsetTop(),dp(12)+insets.getSystemWindowInsetRight(),dp(12)+insets.getSystemWindowInsetBottom());return insets;});
  LinearLayout bar=row();TextView title=text("实时画面",16,Color.WHITE);bar.addView(title,new LinearLayout.LayoutParams(0,dp(44),1));Button close=button("退出全屏",false);bar.addView(close);panel.addView(bar);close.setOnClickListener(v->dialog.dismiss());
  enlargedCamera=new ImageView(this);enlargedCamera.setScaleType(ImageView.ScaleType.FIT_CENTER);enlargedCamera.setImageBitmap(currentBitmap);panel.addView(enlargedCamera,new LinearLayout.LayoutParams(-1,0,1));
  enlargedState=text(frameState.getText().toString(),12,0xffb8d5da);enlargedState.setGravity(Gravity.CENTER);panel.addView(enlargedState,new LinearLayout.LayoutParams(-1,dp(42)));
  dialog.setContentView(panel);dialog.setOnDismissListener(d->{enlargedCamera=null;enlargedState=null;previewDialog=null;});dialog.show();dialog.getWindow().setLayout(-1,-1);
 }
 void buildPad(LinearLayout parent){
  LinearLayout pad=column();pad.setGravity(Gravity.CENTER);
  String[][] labels={{"↑"},{"←","归中","→"},{"↓"}};String[][] directions={{"up"},{"left","center","right"},{"down"}};
  for(int r=0;r<3;r++){LinearLayout line=row();line.setGravity(Gravity.CENTER);
   for(int n=0;n<labels[r].length;n++){String dir=directions[r][n];Button b=button(labels[r][n],dir.equals("center"));b.setTextSize(dir.equals("center")?11:21);LinearLayout.LayoutParams p=new LinearLayout.LayoutParams(dp(46),dp(44));p.setMargins(dp(3),dp(3),dp(3),dp(3));line.addView(b,p);controlled.add(b);
    if(dir.equals("center"))b.setOnClickListener(v->{stopMove();command("/api/servo",json("pan",1500,"tilt",1500),"云台归中指令已发送",true);});
    else{b.setOnTouchListener((v,e)->{if(e.getAction()==MotionEvent.ACTION_DOWN){v.getParent().requestDisallowInterceptTouchEvent(true);startMove(dir);v.setPressed(true);return true;}if(e.getAction()==MotionEvent.ACTION_UP||e.getAction()==MotionEvent.ACTION_CANCEL){stopMove();v.setPressed(false);v.getParent().requestDisallowInterceptTouchEvent(false);return true;}return true;});}
   }pad.addView(line);
  }parent.addView(pad);
 }
 void buildControls(){
  LinearLayout c=card(controlPage,"视频配置","NATIVE CONTROL");
  mode=spinner(new String[]{"0 · 原图","1 · 灰度","2 · 负片","3 · 热力","4 · 边缘","5 · 卡通","6 · 霓虹","7 · 数字","8 · 运动","9 · 红色跟踪","10 · 人脸跟踪","11 · 智能分拣"});
  beauty=spinner(new String[]{"关闭","自动","固定校正"});quality=spinner(new String[]{"720p","360p","180p"});fps=spinner(new String[]{"60 帧","30 帧","15 帧"});
  fields(c,"视觉模式",mode,"智能美化",beauty);fields(c,"输出画质",quality,"内容帧率",fps);
  Button apply=button("应用视频配置",true);addButtons(c,apply);controlled.add(apply);
  apply.setOnClickListener(v->command("/api/config",json("mode",MODE_IDS[mode.getSelectedItemPosition()],"beauty",new String[]{"off","auto","fixed"}[beauty.getSelectedItemPosition()],"quality",quality.getSelectedItemPosition(),"fps",new int[]{60,30,15}[fps.getSelectedItemPosition()]),"视频配置已发送",true));
  LinearLayout preview=card(controlPage,"实时画面设置","USB PREVIEW");detail=spinner(new String[]{"流畅 · 160×90","清晰 · 320×180"});rate=spinner(new String[]{"4 帧/秒","6 帧/秒","2 帧/秒","1 帧/秒"});fields(preview,"预览清晰度",detail,"目标帧率",rate);
  detail.setSelection(Math.max(0,Math.min(1,prefs.getInt("preview_detail",0))));rate.setSelection(Math.max(0,Math.min(3,prefs.getInt("preview_rate",0))));
  Button previewApply=button("应用并恢复画面",false);addButtons(preview,previewApply);previewApply.setOnClickListener(v->startPreview());
  LinearLayout output=card(controlPage,"输出控制","DEVICE");
  hdmi=new Switch(this);hdmi.setText("HDMI 显示");led=new Switch(this);led.setText("LED 闪烁");alarm=new Switch(this);alarm.setText("蜂鸣警报");
  for(Switch s:new Switch[]{hdmi,led,alarm}){s.setTextSize(13);s.setTextColor(INK);output.addView(s,new LinearLayout.LayoutParams(-1,dp(40)));}
  Button send=button("应用输出状态",false),calibrate=button("白墙标定",false);addButtons(output,send,calibrate);controlled.add(send);controlled.add(calibrate);
  send.setOnClickListener(v->command("/api/outputs",json("show",hdmi.isChecked(),"led",led.isChecked(),"alarm",alarm.isChecked()),"输出状态已发送",true));
  calibrate.setOnClickListener(v->command("/api/action",json("action","calibrate"),"白墙标定已发送",true));
  LinearLayout image=card(controlPage,"图像精细调节","ISP ENGINE");
  isp=spinner(new String[]{"白平衡 · 红","白平衡 · 蓝","曝光","传感器增益","饱和度（K2）"});image.addView(isp,new LinearLayout.LayoutParams(-1,dp(40)));
  ispPercent=text("50%",12,TEAL);ispPercent.setGravity(Gravity.RIGHT);image.addView(ispPercent);ispValue=new SeekBar(this);ispValue.setMax(100);ispValue.setProgress(50);image.addView(ispValue);
  ispValue.setOnSeekBarChangeListener(new SeekBar.OnSeekBarChangeListener(){public void onProgressChanged(SeekBar s,int value,boolean user){ispPercent.setText(value+"%");}public void onStartTrackingTouch(SeekBar s){}public void onStopTrackingTouch(SeekBar s){}});
  isp.setOnItemSelectedListener(new android.widget.AdapterView.OnItemSelectedListener(){public void onItemSelected(AdapterView<?> p,View v,int pos,long id){syncIsp();}public void onNothingSelected(AdapterView<?> p){}});
  Button imageApply=button("应用参数",true),reset=button("恢复自动校正",false);addButtons(image,imageApply,reset);controlled.add(imageApply);controlled.add(reset);
  imageApply.setOnClickListener(v->command("/api/isp",json("name",new String[]{"wb_r","wb_b","exposure","gain","saturation"}[isp.getSelectedItemPosition()],"normalized",ispValue.getProgress()),"图像参数已发送",true));
  reset.setOnClickListener(v->command("/api/isp",json("name","auto","value",0),"已恢复校正",true));
  note(image,"白平衡与饱和度需开启 K2；调节范围与电脑端保持一致。");
  LinearLayout advanced=card(controlPage,"完整控制台","ALL FEATURES");
  Button console=button("打开完整网页控制台",false),follow=button("恢复自动跟踪",false);addButtons(advanced,console,follow);controlled.add(follow);
  console.setOnClickListener(v->openConsole());follow.setOnClickListener(v->command("/api/action",json("action","recenter"),"自动跟踪指令已发送",true));
  note(advanced,"串口连接、精确角度、局部人脸照片等完整功能，可在同一 App 内使用。");
 }
 void syncIsp(){
  String[] keys={"wb_r","wb_b","exposure","gain","saturation"};int[][] limits={{40,96},{40,96},{4,1991},{16,80},{0,8}};
  int i=isp.getSelectedItemPosition();if(i<0)return;int lo=limits[i][0],hi=limits[i][1];ispValue.setProgress(Math.max(0,Math.min(100,Math.round(100f*(latest.optInt(keys[i],lo)-lo)/(hi-lo)))));
 }
 void configureWeb(WebView web){
  web.setBackgroundColor(BG);web.getSettings().setJavaScriptEnabled(true);web.getSettings().setDomStorageEnabled(true);
  web.getSettings().setAllowFileAccess(false);web.getSettings().setAllowContentAccess(false);web.getSettings().setMixedContentMode(0);
  web.getSettings().setUserAgentString(web.getSettings().getUserAgentString()+" FPGA-Vision-App/"+VERSION);
  web.setWebChromeClient(new WebChromeClient());
  web.setWebViewClient(new WebViewClient(){
   public WebResourceResponse shouldInterceptRequest(WebView w,WebResourceRequest r){
    if(!r.getMethod().equals("GET")||!Server.sameOrigin(base,r.getUrl().toString()))return null;
    String path=r.getUrl().getPath();String asset=null,mime=null;
    if("/static/style.css".equals(path)){asset="style.css";mime="text/css";}
    if("/static/app.js".equals(path)||"/static/events.js".equals(path)){asset=path.substring(8);mime="application/javascript";}
    if("/static/anlogic.png".equals(path)){asset="anlogic.png";mime="image/png";}
    if(asset!=null)try{return new WebResourceResponse(mime,"UTF-8",getAssets().open("web/"+asset));}catch(java.io.IOException ignored){}
    return Server.proxy(r);
   }
   public boolean shouldOverrideUrlLoading(WebView w,WebResourceRequest r){if(Server.sameOrigin(base,r.getUrl().toString()))return false;external(r.getUrl().toString());return true;}
   public void onReceivedError(WebView w,WebResourceRequest r,WebResourceError e){if(r.isForMainFrame())toast("页面连接失败，请检查电脑与 ngrok");}
  });
  web.setDownloadListener((url,agent,disposition,mime,length)->external(url));
 }
 void openConsole(){
  if(base.isEmpty()){connectionDialog();return;}
  if(consoleDialog!=null)return;
  stopMove();Dialog dialog=new Dialog(this,android.R.style.Theme_Material_Light_NoActionBar);consoleDialog=dialog;
  LinearLayout panel=column();panel.setBackgroundColor(BG);panel.setOnApplyWindowInsetsListener((v,insets)->{v.setPadding(insets.getSystemWindowInsetLeft(),insets.getSystemWindowInsetTop(),insets.getSystemWindowInsetRight(),insets.getSystemWindowInsetBottom());return insets;});
  LinearLayout bar=row();bar.setPadding(dp(14),dp(6),dp(14),dp(6));bar.addView(text("完整控制台",16,INK),new LinearLayout.LayoutParams(0,dp(36),1));Button close=button("返回原生控制",false);bar.addView(close);panel.addView(bar);
  WebView console=new WebView(this);configureWeb(console);panel.addView(console,new LinearLayout.LayoutParams(-1,0,1));dialog.setContentView(panel);
  close.setOnClickListener(v->dialog.dismiss());dialog.setOnDismissListener(d->{console.destroy();consoleDialog=null;});dialog.show();dialog.getWindow().setLayout(-1,-1);
  Map<String,String> headers=new HashMap<>();headers.put("ngrok-skip-browser-warning","fpga-vision-app");console.loadUrl(base+"/",headers);
 }
 void external(String url){if(!url.startsWith("https://")&&!url.startsWith("http://"))return;try{startActivity(new Intent(Intent.ACTION_VIEW,Uri.parse(url)));}catch(Exception e){toast("当前手机无法打开链接");}}
 void showPage(int value){
  stopMove();page=value;liveScroll.setVisibility(value==0?View.VISIBLE:View.GONE);controlScroll.setVisibility(value==1?View.VISIBLE:View.GONE);events.view.setVisibility(value==2?View.VISIBLE:View.GONE);
  for(int i=0;i<3;i++){tabs[i].setTextColor(i==value?TEAL:MUTED);tabs[i].setBackground(shape(i==value?0xffe7f4f1:Color.WHITE,10));}
  if(value==2){if(base.isEmpty())connectionDialog();else events.refresh(true);}
 }
 void loadEvents(String event){events.reset();if(page==2)events.refresh(true);if(event!=null)events.open(event);}
 void openEvent(String event){showPage(2);events.open(event);}
 void connectionDialog(){
  LinearLayout body=column();body.setPadding(dp(22),dp(10),dp(22),0);body.addView(text("2026 年 FPGA 赛道 · 安路视界 v"+VERSION,11,TEAL));
  EditText address=new EditText(this);address.setSingleLine(true);address.setText(base);address.setTextSize(13);address.setHint("https://example.ngrok-free.app");address.setInputType(17);
  body.addView(address,new LinearLayout.LayoutParams(-1,dp(56)));
  Switch listen=new Switch(this);listen.setText("视频保存后通知");listen.setTextSize(13);listen.setChecked(prefs.getBoolean("listen",true));body.addView(listen,new LinearLayout.LayoutParams(-1,dp(48)));
  note(body,"电脑启动端口 8768，再使用 ngrok http 8768。保存 HTTPS 根网址后自动记住。仅在视频保存成功后提醒，无常驻通知。App 打开时及时同步；后台由系统约 15 分钟级检查，省电状态可能更慢。");
  Button refresh=button("刷新画面 / 页面",false);body.addView(refresh);refresh.setOnClickListener(v->{frameVersion=-1;if(!base.isEmpty())loadEvents(null);toast("正在刷新");});
  AlertDialog dialog=new AlertDialog.Builder(this).setTitle("连接电脑端 · v"+VERSION).setView(body).setNegativeButton("取消",null).setPositiveButton("连接并保存",null).create();
  dialog.setOnShowListener(d->dialog.getButton(AlertDialog.BUTTON_POSITIVE).setOnClickListener(v->{
   final String candidate;try{candidate=Server.normalize(address.getText().toString());}catch(Exception e){address.setError(e.getMessage());return;}
   Button save=dialog.getButton(AlertDialog.BUTTON_POSITIVE);save.setEnabled(false);save.setText("连接中…");
   commands.execute(()->{try{
    JSONObject health=Server.get(candidate,"/api/health",10000);requireCompatible(health);
    ui.post(()->{if(destroyed)return;stopMove();base=candidate;frameVersion=-1;configSynced=false;outputSynced=false;
     prefs.edit().putString("url",base).putBoolean("listen",listen.isChecked()).apply();dialog.dismiss();startPreview();
     if(currentBitmap!=null){camera.setImageDrawable(null);currentBitmap=null;}
     if(listen.isChecked())enableListening();else NotificationSync.cancel(this);
     loadEvents(null);toast("已保存连接地址");
    });
   }catch(Exception e){ui.post(()->{if(destroyed)return;save.setEnabled(true);save.setText("连接并保存");address.setError(e.getMessage());});}});
  }));dialog.show();
 }
 static JSONObject json(Object...pairs){JSONObject j=new JSONObject();try{for(int n=0;n<pairs.length;n+=2)j.put((String)pairs[n],pairs[n+1]);}catch(Exception e){throw new IllegalArgumentException(e);}return j;}
 void toast(String message){if(!destroyed)Toast.makeText(this,message,Toast.LENGTH_SHORT).show();}
 void command(String path,JSONObject body,String success,boolean requiresControl){
  if(base.isEmpty()){connectionDialog();return;}
  if(requiresControl&&!canControl()){toast("请先连接开发板，并将拨码设为 1100");return;}
  final String server=base;
  commands.execute(()->{try{Server.post(server,path,body);ui.post(()->{if(!destroyed&&server.equals(base)&&!success.isEmpty())toast(success);});}catch(Exception e){ui.post(()->toast(e.getMessage()));}});
 }
 boolean canControl(){return latest.optBoolean("controlled")&&latest.optBoolean("lease_alive")&&!latest.optBoolean("sd_busy");}
 void setMode(int value){command("/api/config",json("mode",value,"beauty",latest.optString("beauty","auto"),"quality",latest.optInt("quality_index",0),"fps",latest.optInt("fps_set",60)),"模式切换已发送",true);configSynced=false;}
 void startPreview(){previewEnabled=true;frameVersion=-1;previewButton.setText("暂停");setPreview();}
 void setPreview(){int index=rate==null?0:rate.getSelectedItemPosition();int f=new int[]{4,6,2,1}[index];int d=detail==null?0:detail.getSelectedItemPosition();prefs.edit().putInt("preview_detail",d).putInt("preview_rate",index).apply();command("/api/preview",json("enabled",previewEnabled,"fps",f,"detail",d),"",false);}
 void requireCompatible(JSONObject data) throws Exception {
  boolean v5=false;org.json.JSONArray protocols=data.optJSONArray("fpga_control_versions");
  if(protocols!=null)for(int i=0;i<protocols.length();i++)if(protocols.optInt(i)==5)v5=true;
  if(!ClientContract.acceptsServer(data.optString("project_id"),data.optString("software_id"),data.optString("software_version"),data.optInt("api_version",1),v5))
   throw new Exception("请启动 latest_plus_v3_fixed 电脑端 v3.0.2 或更新版本，并重启旧服务器");
 }
 void refresh(){
  if(!resumed||destroyed||base.isEmpty())return;String server=base;
  try{
   NotificationSync.request(this,false);
   JSONObject data=Server.get(server,"/api/status",8000);requireCompatible(data);if(!server.equals(base)||!resumed)return;
   ui.post(()->{if(!destroyed&&resumed&&server.equals(base))render(data);});
   if(page==2)events.refresh(false);
   long version=data.optLong("frame_version",-1);
   if(page==0&&previewEnabled&&data.optBoolean("connected")&&data.optInt("received_frames")>0&&version!=frameVersion){
    byte[] bytes=Server.frame(server,version);Bitmap bitmap=BitmapFactory.decodeByteArray(bytes,0,bytes.length);
    if(bitmap==null)throw new Exception("画面解码失败");if(!server.equals(base)){bitmap.recycle();return;}
    frameVersion=version;ui.post(()->{if(destroyed||!resumed||!server.equals(base)){bitmap.recycle();return;}
     currentBitmap=bitmap;camera.setImageBitmap(bitmap);if(enlargedCamera!=null)enlargedCamera.setImageBitmap(bitmap);});
   }
  }catch(Exception e){ui.post(()->{if(!destroyed&&resumed&&server.equals(base)){connection.setText("● 连接重试中");connection.setTextColor(MUTED);frameState.setText("连接中断，正在自动重试 · "+e.getMessage());}});}
 }
 void render(JSONObject data){
  latest=data.optJSONObject("status");if(latest==null)latest=new JSONObject();media=data.optJSONObject("media");if(media==null)media=new JSONObject();
  boolean connected=data.optBoolean("connected");connection.setText(connected?"● "+data.optString("port")+" 已连接":"● 电脑在线 · 开发板未连接");connection.setTextColor(connected?TEAL:MUTED);
  subtitle.setText("电脑 v"+data.optString("software_version")+" · USB v"+latest.optInt("protocol_version",5));
  double age=data.optDouble("frame_age",Double.NaN);
  frameState.setText(!connected?"请先连接开发板":!previewEnabled?"预览已暂停":Double.isNaN(age)?"正在等待开发板画面":age>5?"画面暂未更新 · "+age+" 秒前":"实时更新 · "+data.optInt("preview_width")+" × "+data.optInt("preview_height"));
  if(!connected){camera.setImageDrawable(null);frameVersion=-1;}
  metricValues[0].setText(latest.optString("mode_name","—"));
  metricValues[1].setText(new String[]{"720p","360p","180p"}[Math.max(0,Math.min(2,latest.optInt("quality_index")))]);
  metricValues[2].setText(connected?data.optInt("preview_width")+"×"+data.optInt("preview_height"):"—");
  metricValues[3].setText(Double.isNaN(age)?"—":String.format(java.util.Locale.US,"%.1fs",age));
  if(latest.optInt("mode")==13 && latest.optInt("protocol_version")>=5){
   StringBuilder labels=new StringBuilder("SORT · "+ClientContract.sortPhase(latest.optInt("sort_phase")));
   org.json.JSONArray targets=latest.optJSONArray("sort_labels");int count=0,mask=latest.optInt("target_mask");
   if(targets!=null)for(int i=0;i<targets.length();i++){
    JSONObject t=targets.optJSONObject(i);if(t==null||(mask&(1<<t.optInt("slot")))==0)continue;
    labels.append(count%2==0?"\n":"   ").append(ClientContract.targetLabel(t.optInt("slot"),t.optInt("digit"),t.optInt("class")));count++;
   }
   recognitionLabel.setText(labels.toString());trackLabel.setText("目标 "+count);
  }else{
   recognitionLabel.setText(latest.optBoolean("face_valid")?"● 已检测到人脸":"人脸 · 未检出");
   trackLabel.setText(latest.optBoolean("track_ready")?"云台 · 跟踪就绪":"云台 · 待机");
  }
  clarityButton.setText(detail.getSelectedItemPosition()==0?"流畅":"清晰");
  modeLabel.setText("FPGA · 内容 "+latest.optInt("fps_set",0)+" FPS");
  if(enlargedState!=null)enlargedState.setText(frameState.getText());
  recordLabel.setText(media.optBoolean("recording")?"● 手动录像中":"USB 视频链路");
  for(View v:controlled)v.setEnabled(connected&&canControl());
  if(!connected||!canControl())stopMove();
  JSONObject events=media.optJSONObject("face_events");
  if(events!=null){boolean enabled=events.optBoolean("enabled");JSONObject active=events.optJSONObject("active");double remaining=events.optDouble("remaining_seconds",Double.NaN);
   autoButton.setText(enabled?"自动录像 · 开":"自动录像 · 关");
   eventLabel.setText(active!=null?(Double.isNaN(remaining)?"● 检测到人脸，正在录像":"消失延录 · "+String.format(java.util.Locale.US,"%.1f",remaining)+" 秒后保存"):!enabled?"自动录像已关闭":connected?"监测中，等待人脸":"等待连接开发板");
  }
  recordButton.setText(media.optBoolean("recording")?"停止录像":"录像");
  if(!configSynced&&latest.has("mode")){mode.setSelection(modeIndex(latest.optInt("mode")));quality.setSelection(Math.min(2,Math.max(0,latest.optInt("quality_index"))));
   beauty.setSelection(latest.optString("beauty").equals("off")?0:latest.optString("beauty").equals("fixed")?2:1);fps.setSelection(latest.optInt("fps_set")==30?1:latest.optInt("fps_set")==15?2:0);syncIsp();configSynced=true;}
  if(!outputSynced&&connected){hdmi.setChecked(latest.optBoolean("hdmi_show"));led.setChecked(latest.optBoolean("led_blink"));alarm.setChecked(latest.optBoolean("alarm"));outputSynced=true;}
 }
 void startMove(String direction){
  if(!canControl())return;stopMove();long generation=moveGeneration;pan=latest.optInt("pan_us",1500);tilt=latest.optInt("tilt_us",1500);
  Runnable tick=new Runnable(){public void run(){
   if(generation!=moveGeneration||!resumed||destroyed)return;
   if(!servoBusy.compareAndSet(false,true)){ui.postDelayed(this,150);return;}
   int step=new int[]{6,15,30}[moveSpeed.getSelectedItemPosition()];
   if(direction.equals("left"))pan+=step;if(direction.equals("right"))pan-=step;if(direction.equals("up"))tilt+=step;if(direction.equals("down"))tilt-=step;
   pan=Math.max(1000,Math.min(2000,pan));tilt=Math.max(1000,Math.min(2000,tilt));JSONObject payload=json("pan",pan,"tilt",tilt);String server=base;
   commands.execute(()->{try{if(generation==moveGeneration&&server.equals(base))Server.post(server,"/api/servo",payload);}catch(Exception e){ui.post(()->{if(generation==moveGeneration){stopMove();toast(e.getMessage());}});}finally{servoBusy.set(false);}});
   ui.postDelayed(this,150);
  }};tick.run();
 }
 void stopMove(){moveGeneration++;}
 void enableListening(){
  if(Build.VERSION.SDK_INT>=33&&checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS)!=PackageManager.PERMISSION_GRANTED){serviceAfterPermission=true;requestPermissions(new String[]{Manifest.permission.POST_NOTIFICATIONS},33);return;}
  NotificationSync.schedule(this);NotificationSync.request(this,true);
 }
 public void onRequestPermissionsResult(int code,String[] names,int[] results){super.onRequestPermissionsResult(code,names,results);if(code==33&&serviceAfterPermission){serviceAfterPermission=false;if(results.length>0&&results[0]==PackageManager.PERMISSION_GRANTED){NotificationSync.schedule(this);NotificationSync.request(this,true);}else toast("控制功能可用，请在系统设置允许视频保存通知");}}
 protected void onResume(){super.onResume();resumed=true;frameVersion=-1;}
 protected void onPause(){resumed=false;stopMove();if(events!=null)events.pause();super.onPause();}
 public void onWindowFocusChanged(boolean focus){super.onWindowFocusChanged(focus);if(!focus)stopMove();}
 protected void onNewIntent(Intent intent){super.onNewIntent(intent);setIntent(intent);if(!base.isEmpty()&&intent.hasExtra("event"))openEvent(intent.getStringExtra("event"));}
 public void onBackPressed(){if(page!=0)showPage(0);else super.onBackPressed();}
 protected void onDestroy(){destroyed=true;resumed=false;stopMove();poller.shutdownNow();commands.shutdownNow();ui.removeCallbacksAndMessages(null);if(consoleDialog!=null)consoleDialog.dismiss();if(previewDialog!=null)previewDialog.dismiss();if(events!=null)events.close();camera.setImageDrawable(null);currentBitmap=null;super.onDestroy();}
}

