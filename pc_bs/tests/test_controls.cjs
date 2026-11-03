// Unit tests for application interactions; no browser or real servo is involved.
const fs=require('fs'),vm=require('vm'),assert=require('assert');
class Element{
 constructor(id=''){this.id=id;this.value='';this.checked=false;this.disabled=false;this.dataset={};this.children=[];this.events={};this.style={};this.classList={add(){},remove(){},toggle(){}};}
 addEventListener(name,fn){(this.events[name]??=[]).push(fn);}
 async emit(name,e={}){for(const fn of this.events[name]||[])await fn({preventDefault(){},pointerId:1,...e});}
 append(e){this.children.push(e);}replaceChildren(){this.children=[];}setPointerCapture(){}
 getContext(){return{clearRect(){},fillRect(){}};}
}
const elements={},el=id=>elements[id]??=new Element(id),moves=['up','left','center','right','down'].map(d=>{const e=new Element();e.dataset.move=d;return e;});
const actions=['calibrate','photo','recenter'].map(d=>{const e=new Element();e.dataset.action=d;return e;});
const media=['photo','record','stop'].map(d=>{const e=new Element();e.dataset.media=d;return e;});
el('moveSpeed').value='100';el('ispName').value='wb_r';el('ispValue').value='42.9';el('previewRate').value='2';el('preview').checked=true;
const status={connected:true,port:'COM5',frame_age:null,frame_version:0,received_frames:0,preview_width:160,preview_height:45,media:{files:[]},status:{controlled:true,lease_alive:true,mode:0,beauty:'off',fps_set:60,quality_index:0,pan_us:1500,tilt_us:1500,hdmi_show:true,alarm:false,led_blink:false}};
const calls=[],winEvents={};
const context={console,performance,setTimeout,clearTimeout,URLSearchParams,location:{search:""},CustomEvent:class{constructor(type,options){this.type=type;this.detail=options.detail;}},setInterval(){},document:{getElementById:el,createElement(){return new Element();},addEventListener(){},hidden:false,
 querySelector(){return actions[2];},querySelectorAll(q){if(q==='[data-open-connection]'||q==='.rail-item')return [];if(q==='[data-move]')return moves;if(q==='[data-action]')return actions;if(q==='[data-media]')return media;if(q==='[data-mode]')return el('modeTiles').children;return [...moves,...actions,...el('modeTiles').children,...['testAlarm','setAngles','applyOutputs','hdmiShow','ledBlink','alarm','applyIsp','resetIsp'].map(el)];}},
 window:{addEventListener(name,fn){winEvents[name]=fn;},dispatchEvent(){}},fetch:async(url,opt={})=>{const body=opt.body?JSON.parse(opt.body):null;calls.push({url,body});
 if(url==='/api/outputs'){Object.assign(status.status,{hdmi_show:body.show,led_blink:body.led,alarm:body.alarm});}
 return{ok:true,status:200,json:async()=>url==='/api/status'?status:url==='/api/ports'?{ports:[]}:{ok:true,raw_value:64}};}};
vm.createContext(context);vm.runInContext(fs.readFileSync(require('path').join(__dirname,'../static/app.js'),'utf8'),context);
const delay=ms=>new Promise(r=>setTimeout(r,ms));
(async()=>{
 assert.equal(el('mode').children.length,12,'all twelve real video modes appear without reserve slots');
 assert.deepEqual(el('mode').children.map(x=>Number(x.value)),[0,1,2,4,5,6,7,8,9,10,12,13],'compact menu keeps compatible wire IDs');
 assert.equal(el('modeTiles').children.length,12,'SORT and all other real functions have tiles');
 await delay(30);assert(!moves[0].disabled,'connected remote must enable movement');
 await moves[1].emit('pointerdown');await delay(450);await moves[1].emit('pointerup');
 const count=calls.filter(x=>x.url==='/api/servo').length;assert(count>=3,'hold sends repeated commands');
 const commands=calls.filter(x=>x.url==='/api/servo');assert(commands.every((c,i)=>!i||c.body.pan>commands[i-1].body.pan),'left increases pan and accumulates instead of stale status');
 await delay(250);assert.equal(calls.filter(x=>x.url==='/api/servo').length,count,'release stops');
 await moves[3].emit('pointerdown');await delay(150);winEvents.blur();const stopped=calls.filter(x=>x.url==='/api/servo').length;
 await delay(200);assert.equal(calls.filter(x=>x.url==='/api/servo').length,stopped,'blur stops');
 for(const [index,axis,sign] of [[0,'tilt',1],[3,'pan',-1],[4,'tilt',-1]]){
   const before=calls.length;await moves[index].emit('pointerdown');await delay(20);await moves[index].emit('pointerup');
   const command=calls.slice(before).find(x=>x.url==='/api/servo');assert(command,'direction emits command');
   assert(sign*(command.body[axis]-1500)>0,'corrected direction '+moves[index].dataset.move);
 }
 el('alarm').checked=true;await el('alarm').emit('change');assert(calls.some(x=>x.url==='/api/outputs'&&x.body.alarm===true),'checkbox immediately sends alarm');
 await el('testAlarm').emit('click');assert.equal(calls.filter(x=>x.url==='/api/outputs').at(-1).body.alarm,true,'test restores prior alarm');
 el('ispName').value='exposure';el('ispValue').value='100';await el('applyIsp').emit('click');await delay(20);
 assert(calls.some(x=>x.url==='/api/isp'&&x.body.normalized===100),'standardized value sent');
 console.log('PASS: hold/release/blur, cumulative servo, immediate alarm/test restore, normalized ISP, initialization');process.exit(0);
})().catch(e=>{console.error(e);process.exit(1);});
