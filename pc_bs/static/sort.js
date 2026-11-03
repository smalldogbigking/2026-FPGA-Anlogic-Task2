'use strict';
const byId=id=>document.getElementById(id),phases=['未进入','抬头就位','等待人脸','人脸留档','返回俯视','等待画面稳定','视觉分拣中','等待人脸超时，请退出后重试'];
const classes=['待确认','圆形奇数','圆形偶数','标定标志','方形异常'],shapes=['未知','圆形','方形','不规则'];
async function request(url,body){const r=await fetch(url,body===undefined?{}:{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify(body)});const d=await r.json();if(!r.ok)throw Error(d.error||'连接失败');return d;}
async function action(url,body){try{await request(url,body);byId('feedback').textContent='';await poll();}catch(e){byId('feedback').textContent=e.message;}}
byId('connect').onclick=()=>action('/api/sort/connect',{port:byId('port').value,kind:byId('kind').value});
byId('disconnect').onclick=()=>action('/api/sort/disconnect',{});
let running=false;
byId('preview').onload=()=>{byId('preview').hidden=false;byId('framePlaceholder').hidden=true;};
byId('preview').onerror=()=>{byId('preview').hidden=true;byId('framePlaceholder').hidden=false;};
async function poll(){if(running)return;running=true;try{
 const s=await request('/api/sort/status'),b=s.board,o=s.observation;
 byId('phase').textContent=b.mode===13?'SORT · '+(phases[b.sort_phase]||'状态待更新'):'当前未进入 SORT';
 byId('fresh').textContent=s.connected?(s.stale?'视觉数据待更新':'视觉快照接收中'):'独立数据口未连接';byId('fresh').className='pill'+(s.stale?' bad':'');
 byId('link').textContent=s.connected?s.port+' · '+s.kind:'串口未连接';
 const targets=o.targets||[];byId('targets').replaceChildren();
 const rows=targets.length?targets:(b.sort_labels||[]).filter(t=>(b.target_mask&(1<<t.slot))!==0).map(t=>({...t,x:null,y:null,shape:t.class===1||t.class===2?1:t.class===3||t.class===4?2:0,flags:0}));
 for(const t of rows){const tr=document.createElement('tr');
  for(const value of [t.slot,shapes[t.shape],t.digit||'—',classes[t.class]||'待确认',t.x==null?'需接视觉数据口':`(${t.x}, ${t.y})`,t.flags==null?'—':'0x'+t.flags.toString(16).padStart(2,'0')]){const td=document.createElement('td');td.textContent=String(value);tr.appendChild(td);}byId('targets').appendChild(tr);}
 byId('summary').textContent=targets.length?`序号 ${o.seq} · 源帧 ${o.frame_id} · 错包 ${s.bad_packets} · 丢包 ${s.gaps}`:'暂无独立视觉快照；可先查看开发板模式及已识别标签。';
 if(b.source_valid)byId('preview').src='/api/frame?t='+Date.now();
 }catch(e){byId('feedback').textContent=e.message;}finally{running=false;}}
request('/api/ports').then(d=>{for(const p of d.ports){const o=document.createElement('option');o.value=p.port;o.textContent=p.port+' · '+p.description;byId('port').appendChild(o);}}).catch(e=>byId('feedback').textContent=e.message);
poll();setInterval(poll,1000);
