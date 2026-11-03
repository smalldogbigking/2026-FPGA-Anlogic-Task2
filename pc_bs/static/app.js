"use strict";
const $=id=>document.getElementById(id);
const names=['原图', '灰度', '负片', '原图备用', '热力', '边缘', '卡通', '霓虹', '数字', '运动', '红色跟踪', '预留原图', '人脸跟踪', '智能分拣', '预留原图'];
const shortNames=['RAW', 'GRAY', 'NEG', 'RAW', 'HEAT', 'SOBEL', 'CARTOON', 'NEON', 'DIGIT', 'MOTION', 'TRACK', 'RESERVE', 'FACE', 'SORT', 'RESERVE'];
const activeModes=[0,1,2,4,5,6,7,8,9,10,12,13];
let lastStatus={},lastMediaKey="",authenticated=true,frameVersion=-1,lastPhotoStatus=0,dirty=false,wanted=null,polling=false,toastTimer=null;
let moveToken=0,moveTimer=null,moving=null,outputPending=0;
let frameLoading=false,previewStarted=false,frameError='',lastPollError='';
const embedded=new URLSearchParams(location.search).get('embed');
if(embedded==='events')document.body.classList.add('embedded','embed-events');
async function api(url,body){
 const opt={credentials:"same-origin",headers:{"ngrok-skip-browser-warning":"fpga-vision-app"}};
 if(body!==undefined){opt.method="POST";opt.headers["Content-Type"]="application/json";opt.body=JSON.stringify(body);}
 const controller=typeof AbortController!=='undefined'?new AbortController():null;
 if(controller)opt.signal=controller.signal;
 const timeout=controller?setTimeout(()=>controller.abort(),url.includes('/api/notifications?')?35000:15000):null;
 try{const res=await fetch(url,opt);const data=await res.json();
  if(!res.ok)throw new Error(data.error||"请求失败");return data;
 }finally{clearTimeout(timeout);}
}
function toast(text){$("toast").textContent=text;$("toast").hidden=false;clearTimeout(toastTimer);toastTimer=setTimeout(()=>{$("toast").hidden=true;},4000);}
names.forEach((name,i)=>{
 if(!activeModes.includes(i))return;
 const option=document.createElement("option");option.value=i;option.textContent=activeModes.indexOf(i)+" · "+name+" "+shortNames[i];$("mode").append(option);
 const button=document.createElement("button");button.type="button";button.dataset.mode=i;button.textContent=name;
 const small=document.createElement("small");small.textContent=shortNames[i];button.append(small);
 button.addEventListener("click",()=>{$("mode").value=i;dirty=true;apply().catch(e=>toast(e.message));});
 $("modeTiles").append(button);
});
async function ports(){const d=await api("/api/ports");$("ports").replaceChildren();const blank=document.createElement("option");blank.value="";blank.textContent=d.ports.length?"选择开发板串口":"未发现串口，请连接USB";$("ports").append(blank);d.ports.forEach(p=>{const o=document.createElement("option");o.value=p.port;o.textContent=p.port+" · "+p.description;$("ports").append(o);});if(d.ports.length===1)$("ports").value=d.ports[0].port;}
function selected(){return{mode:Number($("mode").value),beauty:$("beauty").value,quality:Number($("quality").value),fps:Number($("fps").value)};}
async function apply(){const config=selected();const d=await api("/api/config",config);wanted=config;dirty=true;toast(d.message);}
function setEnabled(state){$("apply").disabled=!state;document.querySelectorAll("[data-action],[data-mode],[data-move],#setAngles,#applyOutputs,#testAlarm,#hdmiShow,#ledBlink,#alarm,#applyIsp,#resetIsp").forEach(b=>b.disabled=!state);if(!state)stopMove();}
function histogram(bins){const c=$("histogram"),ctx=c.getContext("2d");ctx.clearRect(0,0,c.width,c.height);ctx.fillStyle="#e4ebef";ctx.fillRect(0,c.height-1,c.width,1);if(!bins.length)return;const max=Math.max(1,...bins);bins.forEach((n,i)=>{const h=(c.height-12)*n/max;ctx.fillStyle="#7abdb3";ctx.fillRect(i*c.width/16+4,c.height-h-2,c.width/16-8,h);});}
async function loadFrame(version){
 if(frameLoading)return;frameLoading=true;
 let nextUrl;
 try{
  const controller=typeof AbortController!=='undefined'?new AbortController():null,timeout=controller?setTimeout(()=>controller.abort(),10000):null;
  let response;
  try{response=await fetch('/api/frame?v='+version,{cache:'no-store',headers:{'ngrok-skip-browser-warning':'fpga-vision-app'},...(controller?{signal:controller.signal}:{})});
   if(!response.ok||!response.headers.get('content-type')?.startsWith('image/'))throw new Error('画面请求失败，请检查电脑和隧道');
   // data: is supported by both the original server policy and the new UI.
   // A still-running older server rejects blob: URLs even for valid PNGs.
   const blob=await response.blob();
   nextUrl=await new Promise((resolve,reject)=>{
    const reader=new FileReader();reader.onload=()=>resolve(reader.result);
    reader.onerror=()=>reject(new Error('画面读取失败'));reader.readAsDataURL(blob);
   });}
  finally{clearTimeout(timeout);}
  await new Promise((resolve,reject)=>{const image=new Image();image.onload=resolve;image.onerror=()=>reject(new Error('画面解码失败'));image.src=nextUrl;});
  if(!previewStarted||!lastConnected)return;
  $('frame').src=nextUrl;$('frame').style.display='block';$('emptyFrame').hidden=true;
  frameVersion=version;frameError='';
 }catch(e){frameError=e.message;$('frameHealth').textContent=frameError;}
 finally{frameLoading=false;}
}
let lastConnected=false;
function render(d){
 const s=d.status||{},connected=d.connected;lastStatus=s;
 if($('softwareVersion'))$('softwareVersion').textContent='电脑 v'+(d.software_version||'3.0.2')+' · USB '+(s.protocol_version?'v'+s.protocol_version:'待连接');
 lastConnected=!!connected;
 $("linkBadge").textContent=connected?d.port+" 已连接":"未连接";$("linkBadge").classList.toggle("online",connected);
 $("modeBadge").textContent=s.mode_name||"等待开发板";
 $("actualMode").textContent=s.mode!==undefined?names[s.mode]+" "+s.mode_name:"—";
 $("actualFps").textContent=s.fps_set?s.fps_set+" FPS":"—";
 $("actualQuality").textContent=s.quality_index!==undefined?["720p","360p","180p"][s.quality_index]:"—";
 $("frameAge").textContent=d.frame_age!==null?d.frame_age+" 秒":"—";
 $("previewInfo").textContent=d.preview_width+" × "+d.preview_height+" · 收到 "+d.received_frames+" 帧";
 const softwareCurrent=!d.software_version||d.software_version==='3.0.2';
 const controlled=connected&&s.controlled&&s.lease_alive&&softwareCurrent;setEnabled(controlled&&!s.sd_busy);
 document.querySelector('[data-action="recenter"]').disabled=!controlled||s.sd_busy||!(s.protocol_version>=3?[10,12]:[11,13]).includes(s.mode);
 $("controlHint").textContent=!connected?"连接USB后，在顶部选择COM端口。":!s.controlled?"拨码设为1100后启用电脑控制。":s.sd_busy?"正在保存照片。":"电脑受控模式 · 方向键按住移动，松开保持位置。";
 if(!softwareCurrent)$('controlHint').textContent='当前仍是旧电脑服务 v'+d.software_version+'。请关闭原服务器窗口，重新启动本目录“启动BS服务器.bat”。';
 if(wanted&&s.mode===wanted.mode&&s.beauty===wanted.beauty&&s.quality_index===wanted.quality&&s.fps_set===wanted.fps){wanted=null;dirty=false;}
 if(!dirty&&s.mode!==undefined){$("mode").value=s.mode;$("beauty").value=s.beauty;$("quality").value=s.quality_index;$("fps").value=s.fps_set;}
 document.querySelectorAll("[data-mode]").forEach(b=>b.classList.toggle("active",Number(b.dataset.mode)===s.mode));
 $("redInfo").textContent=s.target_valid?s.target_count+" 个 · 中心 ("+s.target_center.join(", ")+")":"未检测到稳定目标";
 $("faceInfo").textContent=s.face_valid?"正面人脸 · "+s.face_box.join(", "):"未检测到稳定人脸";
 $("digitInfo").textContent=s.digit_valid?String(s.digit):"—";
 if(s.mode===13&&s.protocol_version>=5){
  const phases=['未进入','抬头就位','等待人脸','人脸留档','返回俯视','等待稳定','视觉分拣中','等待人脸超时'];
  const kinds=['待确认','圆奇数','圆偶数','方3标定','方形异常'];
  const targets=(s.sort_labels||[]).filter(t=>(s.target_mask&(1<<t.slot))!==0);
  $('digitInfo').textContent=s.sort_phase===6?(targets.map(t=>'#'+(t.slot+1)+' '+kinds[t.class]+' D'+(t.digit||'—')).join('；')||'暂无目标'):phases[s.sort_phase]||'状态待更新';
 }
 $("handInfo").textContent=s.hand_valid?({1:"单指",2:"双指",3:"张手",4:"握拳"}[s.hand]||s.hand):"—";
 $("servoInfo").textContent=s.pan_us!==undefined?"A1 "+s.pan_us+" µs / A2 "+s.tilt_us+" µs"+((s.protocol_version>=3?[10,12]:[11,13]).includes(s.mode)?" · 50 Hz"+(s.track_ready?" · 跟踪":" · 归中 "+s.center_seconds+" 秒"):" · 未启用"):"—";
 $("beautyInfo").textContent={off:"关闭",auto:"自动",fixed:"固定校正"}[s.beauty]||"—";
 const normalized=d.isp_normalized||{};
 $("exposureInfo").textContent=s.exposure!==undefined?"曝光 "+normalized.exposure+"% / 增益 "+normalized.gain+"%":"—";
 $("wbInfo").textContent=s.wb_r!==undefined?"红 "+(s.wb_r/64).toFixed(2)+"× / 蓝 "+(s.wb_b/64).toFixed(2)+"×":"—";
 $("meanInfo").textContent=s.mean!==undefined?String(s.mean):"—";
 $("photoInfo").textContent=["空闲","保存中","保存成功","错误 0x"+Number(s.photo_error||0).toString(16).padStart(2,"0")][s.photo_status||0];
 if(s.photo_status===2&&lastPhotoStatus!==2)toast("开发板确认：照片保存成功");
 lastPhotoStatus=s.photo_status||0;
 if(connected&&!previewStarted&&!embedded){previewStarted=true;$('preview').checked=true;preview();}
 if(connected&&!embedded&&$('preview').checked&&d.frame_version!==frameVersion&&d.received_frames>0)loadFrame(d.frame_version);
 $('frameHealth').textContent=frameError||(!connected?'设备未连接':!$('preview').checked?'预览已暂停':d.frame_age===null?'正在获取画面':d.frame_age>5?'画面暂未更新 · '+d.frame_age+' 秒前':'实时更新 · '+d.preview_width+' × '+d.preview_height);
 if(!connected){$("frame").style.display="none";$("frame").removeAttribute('src');$("emptyFrame").hidden=false;frameVersion=-1;previewStarted=false;}
 const media=d.media||{};
 $("recordState").textContent=media.recording?"手动录像中 · "+media.recording_frames+" 帧":"手动录像已停止";
 const key=JSON.stringify(media.files||[]);if(key!==lastMediaKey){lastMediaKey=key;$("savedFiles").replaceChildren();(media.files||[]).slice(0,12).forEach(f=>{const a=document.createElement("a");a.href="/api/files/"+encodeURIComponent(f.id);a.textContent=f.id;a.className="saved-file";$("savedFiles").append(a);});}
 histogram(d.histogram||[]);
 window.dispatchEvent(new CustomEvent('board-status',{detail:d}));
 if(connected){$("outputState").textContent="回传：HDMI "+(s.hdmi_show?"显示":"隐藏")+" · LED "+(s.led_blink?"开":"关")+" · 蜂鸣 "+(s.alarm?"开":"关")+(d.error?" · "+d.error:"");
 if(!outputPending){$("hdmiShow").checked=!!s.hdmi_show;$("ledBlink").checked=!!s.led_blink;$("alarm").checked=!!s.alarm;}}
 else $("outputState").textContent=d.error||"连接后可操作输出";
}
async function poll(){if(!authenticated||polling)return;polling=true;try{render(await api("/api/status"));lastPollError='';}catch(e){$('linkBadge').textContent='服务重连中';$('linkBadge').classList.remove('online');$('frameHealth').textContent='连接中断，正在重试';if(authenticated&&lastPollError!==e.message)toast(e.message);lastPollError=e.message;}finally{polling=false;}}
$("refreshPorts").addEventListener("click",()=>ports().catch(e=>toast(e.message)));
$("connect").addEventListener("click",async()=>{try{await api("/api/connect",{port:$("ports").value});dirty=false;wanted=null;previewStarted=false;$('connectionDialog').close();toast("已连接");await poll();}catch(e){toast(e.message);}});
$("disconnect").addEventListener("click",async()=>{try{await api("/api/disconnect",{});await poll();}catch(e){toast(e.message);}});
$("configForm").addEventListener("submit",e=>{e.preventDefault();apply().catch(err=>toast(err.message));});
["mode","beauty","quality","fps"].forEach(id=>$(id).addEventListener("change",()=>dirty=true));
document.querySelectorAll("[data-action]").forEach(b=>b.addEventListener("click",async()=>{try{const d=await api("/api/action",{action:b.dataset.action});toast(d.message);}catch(e){toast(e.message);}}));
async function preview(){try{await api("/api/preview",{enabled:$("preview").checked,fps:Number($("previewRate").value),detail:Number($("previewDetail").value)});}catch(e){toast(e.message);}}
$("preview").addEventListener("change",preview);$("previewRate").addEventListener("change",preview);$("previewDetail").addEventListener("change",preview);
$('resumePreview').addEventListener('click',()=>{$('preview').checked=true;frameVersion=-1;preview().then(poll);});
document.querySelectorAll('[data-open-connection]').forEach(b=>b.addEventListener('click',()=>{$('connectionDialog').showModal();ports().catch(e=>toast(e.message));}));
$('closeConnection').addEventListener('click',()=>$('connectionDialog').close());
$('fullscreenPreview').addEventListener('click',async()=>{try{if(document.fullscreenElement)await document.exitFullscreen();else await $('screen').requestFullscreen();}catch(e){toast('当前浏览器不支持全屏');}});
document.querySelectorAll('.rail-item').forEach(a=>a.addEventListener('click',()=>{document.querySelectorAll('.rail-item').forEach(x=>x.classList.remove('selected'));a.classList.add('selected');}));
setEnabled(false);setInterval(poll,500);
api("/api/status").then(d=>{render(d);ports().catch(e=>toast(e.message));}).catch(e=>toast(e.message));

async function sendServo(pan,tilt){return api("/api/servo",{pan:Math.max(1000,Math.min(2000,Math.round(pan))),tilt:Math.max(1000,Math.min(2000,Math.round(tilt)))});}
function stopMove(){moveToken++;clearTimeout(moveTimer);moveTimer=null;moving=null;document.querySelectorAll("[data-move]").forEach(b=>b.classList.remove("holding"));}
function startMove(button){
 if(button.disabled||moving)return;
 const dir=button.dataset.move;if(dir==="center")return;
 stopMove();const token=moveToken;
 let pan=lastStatus.pan_us??1500,tilt=lastStatus.tilt_us??1500,last=performance.now()-120;
 moving=dir;button.classList.add("holding");
 const tick=async()=>{
 if(token!==moveToken)return;
 const now=performance.now(),delta=Number($("moveSpeed").value)*Math.min(.15,(now-last)/1000);last=now;
 if(dir==="left")pan+=delta;if(dir==="right")pan-=delta;if(dir==="up")tilt+=delta;if(dir==="down")tilt-=delta;
 pan=Math.max(1000,Math.min(2000,pan));tilt=Math.max(1000,Math.min(2000,tilt));
 try{await sendServo(pan,tilt);}catch(e){if(token===moveToken){stopMove();toast(e.message);}return;}
 if(token===moveToken)moveTimer=setTimeout(tick,120);
 };tick();
}
document.querySelectorAll("[data-move]").forEach(b=>{
 if(b.dataset.move==="center"){b.addEventListener("click",()=>{stopMove();sendServo(1500,1500).catch(e=>toast(e.message));});return;}
 b.addEventListener("pointerdown",e=>{e.preventDefault();b.setPointerCapture(e.pointerId);startMove(b);});
 ["pointerup","pointercancel","lostpointercapture"].forEach(event=>b.addEventListener(event,stopMove));
 b.addEventListener("keydown",e=>{if([" ","Enter"].includes(e.key)){e.preventDefault();if(!e.repeat)startMove(b);}});
 b.addEventListener("keyup",stopMove);b.addEventListener("contextmenu",e=>e.preventDefault());
});
window.addEventListener("blur",stopMove);document.addEventListener("visibilitychange",()=>{if(document.hidden)stopMove();});
$("setAngles").addEventListener("click",()=>sendServo(1000+Number($("panAngle").value)*1000/180,1000+Number($("tiltAngle").value)*1000/180).catch(e=>toast(e.message)));
async function applyOutputs(){outputPending++;try{await api("/api/outputs",{show:$("hdmiShow").checked,led:$("ledBlink").checked,alarm:$("alarm").checked});}finally{outputPending--;await poll();}}
$("applyOutputs").addEventListener("click",()=>applyOutputs().catch(e=>toast(e.message)));
["hdmiShow","ledBlink","alarm"].forEach(id=>$(id).addEventListener("change",()=>applyOutputs().catch(e=>toast(e.message))));
$("testAlarm").addEventListener("click",async()=>{
 if(outputPending)return;
 const prior=$("alarm").checked;outputPending++;
 try{$("alarm").checked=true;await applyOutputs();await new Promise(resolve=>setTimeout(resolve,1000));}
 catch(e){toast(e.message);}finally{$("alarm").checked=prior;try{await applyOutputs();}catch(e){toast(e.message);}outputPending--;await poll();}
});
const limits={wb_r:[40,96],wb_b:[40,96],exposure:[4,1991],gain:[16,80],saturation:[0,8]};
function ispMapping(){const name=$("ispName").value,[lo,hi]=limits[name],v=Number($("ispValue").value),raw=Math.round(lo+v*(hi-lo)/100);
 $("ispMapping").textContent=name==="saturation"?v.toFixed(1)+"% → "+(raw/4).toFixed(2)+"×（K2开启时生效，自动1.75×、固定校准2×；九档）":name.startsWith("wb")?v.toFixed(1)+"% → "+(raw/64).toFixed(2)+"×（范围0.625—1.5×）":v.toFixed(1)+"% → "+raw+"（硬件范围 "+lo+"—"+hi+"）";}
$("ispSlider").addEventListener("input",()=>{$("ispValue").value=$("ispSlider").value;ispMapping();});
$("ispValue").addEventListener("input",()=>{$("ispSlider").value=$("ispValue").value;ispMapping();});
$("ispName").addEventListener("change",()=>{const name=$("ispName").value,[lo,hi]=limits[name],raw=lastStatus[name]??(name.startsWith("wb")?64:lo);$("ispValue").value=Math.max(0,Math.min(100,100*(raw-lo)/(hi-lo))).toFixed(1);$("ispSlider").value=$("ispValue").value;ispMapping();});
$("applyIsp").addEventListener("click",()=>api("/api/isp",{name:$("ispName").value,normalized:Number($("ispValue").value)}).then(d=>toast("参数已接受 · 编码 "+d.raw_value)).catch(e=>toast(e.message)));
ispMapping();
$("resetIsp").addEventListener("click",()=>api("/api/isp",{name:"auto",value:0}).then(()=>toast("已恢复原校正模式")).catch(e=>toast(e.message)));
document.querySelectorAll("[data-media]").forEach(b=>b.addEventListener("click",()=>api("/api/media",{action:b.dataset.media}).then(d=>toast(d.name||"已完成")).catch(e=>toast(e.message))));
$("faceAuto").addEventListener("change",()=>api("/api/media",{action:"faces",enabled:$("faceAuto").checked}).catch(e=>toast(e.message)));
