"use strict";
let notificationCursor=0,notificationUnread=0,notificationInstance=null;
let messages=[],eventRows=[],oldestEvent=null,openingEvent=false;
const eventElement=id=>document.getElementById(id);
const localTime=value=>value?new Date(value).toLocaleString('zh-CN',{hour12:false}):'—';
const labels={recording:'录像中',completed:'已保存',interrupted:'记录中断',no_video:'无完整视频'};
function textNode(tag,text,className){const e=document.createElement(tag);e.textContent=text;if(className)e.className=className;return e;}
function renderMessages(){
 const list=eventElement('notificationList');list.replaceChildren();
 eventElement('unreadBadge').textContent=notificationUnread;
 if(!messages.length){list.append(textNode('p','暂无消息','subtle'));return;}
 [...messages].reverse().slice(0,50).forEach(m=>{
  const row=textNode('button','',`message-item ${m.read?'':'unread'}`);
  row.append(textNode('strong',m.title),textNode('span',m.body),textNode('small',localTime(m.created_at)));
  row.addEventListener('click',()=>{if(m.kind!=='test')openEvent(m.event_id);});list.append(row);
 });
}
function mergeMessages(items,notify){
 items.forEach(m=>{
  const index=messages.findIndex(x=>x.seq===m.seq);
  if(index>=0)messages[index]=m;else messages.push(m);
  if(notify){
   toast(m.title);
   if('Notification'in window&&Notification.permission==='granted'){
    const n=new Notification(m.title,{body:m.body,tag:m.event_id});
    n.onclick=()=>{window.focus();if(m.kind!=='test')openEvent(m.event_id);n.close();};
   }
  }
 });
 messages.sort((a,b)=>a.seq-b.seq);messages=messages.slice(-100);renderMessages();
}
async function listenMessages(){
 try{
  const init=await api('/api/notifications?recent=1&limit=30');
  notificationCursor=init.latest_seq;notificationInstance=init.instance_id;notificationUnread=init.unread;mergeMessages(init.items,false);
  eventElement('notificationConnection').textContent='消息已连接';
 }catch(e){eventElement('notificationConnection').textContent='连接失败，正在重试';await new Promise(r=>setTimeout(r,2000));return listenMessages();}
 while(true){
  try{
   const d=await api('/api/notifications?after='+notificationCursor+'&wait=20&limit=100');
   if(d.instance_id!==notificationInstance){setTimeout(listenMessages,0);return;}
   notificationUnread=d.unread;
   if(d.items.length){notificationCursor=d.items[d.items.length-1].seq;mergeMessages(d.items,true);refreshEvents();}
   else renderMessages();
   eventElement('notificationConnection').textContent='消息已连接';
  }catch(e){eventElement('notificationConnection').textContent='连接中断，自动重连';await new Promise(r=>setTimeout(r,2000));}
 }
}
function renderEvents(){
 const list=eventElement('eventList');list.replaceChildren();
 if(!eventRows.length){list.append(textNode('p','暂无人脸事件','subtle'));return;}
 eventRows.forEach(e=>{
  const row=textNode('div','','event-item');
  if(e.thumbnail){const image=document.createElement('img');image.src='/api/events/'+encodeURIComponent(e.id)+'/thumbnail';image.alt='事件首帧';image.loading='lazy';row.append(image);}
  const body=textNode('div','','event-info');body.append(textNode('strong',localTime(e.started_at)),
   textNode('span',(labels[e.state]||e.state)+(e.duration_seconds!=null?' · '+e.duration_seconds+' 秒':'')));
  if(e.error)body.append(textNode('small',e.error));
  const b=textNode('button','查看');b.addEventListener('click',()=>openEvent(e.id));row.append(body,b);list.append(row);
 });
 oldestEvent=eventRows[eventRows.length-1].started_unix;
}
async function refreshEvents(older=false){
 try{
  const d=await api('/api/events?limit=30'+(older&&oldestEvent?'&before='+oldestEvent:''));
  if(older){const ids=new Set(eventRows.map(e=>e.id));d.events.forEach(e=>{if(!ids.has(e.id))eventRows.push(e);});}
  else eventRows=d.events;
  renderEvents();eventElement('olderEvents').hidden=d.events.length<30;
 }catch(e){toast(e.message);}
}
async function openEvent(id){
 if(openingEvent)return;openingEvent=true;
 try{
  const d=await api('/api/events/'+encodeURIComponent(id));const e=d.event;
  eventElement('eventTitle').textContent=(e.title||'人脸事件')+' · '+(labels[e.state]||e.state);
  eventElement('eventDescription').textContent='开始：'+localTime(e.started_at)+'；结束：'+localTime(e.ended_at)+
   (e.duration_seconds!=null?'；持续 '+e.duration_seconds+' 秒':'')+(e.error?'；'+e.error:'');
  const video=eventElement('eventVideo');video.pause();video.removeAttribute('src');
  video.hidden=e.state!=='completed';const base='/api/events/'+encodeURIComponent(e.id);
  if(!video.hidden)video.src=base+'/video';video.load();
  const links=eventElement('eventLinks');links.replaceChildren();
  if(e.kind==='face_scan'&&e.thumbnail){const image=document.createElement('img');image.src=base+'/thumbnail';image.alt='人脸扫描留档';image.style.maxWidth='100%';links.append(image);}
  if(e.description){const detail=textNode('p',e.description,'');links.append(detail);}
  [['metadata','事件时间记录'],['timeline','逐帧时间记录'],...(e.state==='completed'?[['video','下载录像']]:[])].forEach(([asset,title])=>{
   const link=textNode('a',title,'button-link');link.href=base+'/'+asset+'?download=1';links.append(link);
  });
  if(!eventElement('eventDialog').open)eventElement('eventDialog').showModal();
 }catch(e){toast(e.message);}finally{openingEvent=false;}
}
window.addEventListener('board-status',e=>{
 const d=e.detail,s=d.media?.face_events;if(!s)return;
 eventElement('eventEnabled').checked=s.enabled;
 eventElement('faceAuto').checked=!!d.media.face_auto;
 eventElement('eventState').textContent=s.active?
  (s.remaining_seconds!==null?'人脸已消失，'+s.remaining_seconds.toFixed(1)+' 秒后保存':'检测到人脸，正在记录')+
   ' · '+s.active.frames+' 帧':!s.enabled?'自动记录已关闭':d.connected?'监测中，等待人脸':'等待连接开发板';
 if(s.error)eventElement('eventState').textContent+=' · '+s.error;
});
eventElement('eventEnabled').addEventListener('change',()=>api('/api/events/settings',{enabled:eventElement('eventEnabled').checked}).catch(e=>toast(e.message)));
eventElement('refreshEvents').addEventListener('click',()=>refreshEvents());
eventElement('olderEvents').addEventListener('click',()=>refreshEvents(true));
eventElement('closeEvent').addEventListener('click',()=>{eventElement('eventVideo').pause();eventElement('eventDialog').close();});
eventElement('eventDialog').addEventListener('close',()=>eventElement('eventVideo').pause());
eventElement('messageJump').addEventListener('click',()=>eventElement('messageCenter').scrollIntoView({behavior:'smooth'}));
eventElement('readMessages').addEventListener('click',async()=>{
 try{await api('/api/notifications/read',{upto:notificationCursor});messages.forEach(m=>m.read=true);notificationUnread=0;renderMessages();}catch(e){toast(e.message);}
});
eventElement('testNotification').addEventListener('click',()=>api('/api/notifications/test',{}).then(()=>toast('测试消息已生成')).catch(e=>toast(e.message)));
eventElement('desktopNotification').hidden=!('Notification'in window);
eventElement('desktopNotification').addEventListener('click',()=>Notification.requestPermission().then(p=>toast(p==='granted'?'桌面通知已允许':'可在浏览器设置中允许通知')));
listenMessages();refreshEvents();
const selectedEvent=new URLSearchParams(location.search).get('event');if(selectedEvent)openEvent(selectedEvent);
setInterval(()=>{if(!document.hidden)refreshEvents();},10000);
