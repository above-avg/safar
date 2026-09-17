function drawDemo(ctx,w,h,t){
  const horizon=h*.365, vanX=w*(.52+.018*Math.sin(t/22));
  const sky=ctx.createLinearGradient(0,0,0,horizon);sky.addColorStop(0,'#526e72');sky.addColorStop(.7,'#a4b4a8');sky.addColorStop(1,'#c7c9ab');ctx.fillStyle=sky;ctx.fillRect(0,0,w,h);
  const sun=ctx.createRadialGradient(w*.69,h*.15,1,w*.69,h*.15,w*.25);sun.addColorStop(0,'#e6e1b977');sun.addColorStop(1,'#e6e1b900');ctx.fillStyle=sun;ctx.fillRect(0,0,w,horizon);
  path(ctx,[[0,horizon],[0,h*.29],[w*.07,h*.25],[w*.16,h*.29],[w*.26,h*.2],[w*.36,h*.29],[w*.45,h*.3],[w*.57,h*.26],[w*.7,h*.32],[w*.9,h*.23],[w,h*.26],[w,horizon]],'#788c7f');
  path(ctx,[[0,h*.33],[w*.09,h*.3],[w*.22,h*.35],[w*.33,h*.31],[w*.45,horizon],[w*.73,horizon],[w*.82,h*.3],[w,h*.28],[w,h],[0,h]],'#57634a');
  const field=ctx.createLinearGradient(0,horizon,0,h);field.addColorStop(0,'#657255');field.addColorStop(1,'#3e4934');ctx.fillStyle=field;ctx.fillRect(0,horizon,w,h-horizon);
  // Deterministic texture is synthetic scenery, never presented as real survey footage.
  for(let i=0;i<350;i++){const y=horizon+((i*71.137+t*14)%(h-horizon)),k=(y-horizon)/(h-horizon),x=((i*137.21)%w);ctx.strokeStyle=i%3?'#a0a37925':'#192b2833';ctx.lineWidth=1+k*2;ctx.beginPath();ctx.moveTo(x,y);ctx.lineTo(x+4+k*18,y-1-k*5);ctx.stroke();}
  const point=(u,side)=>{const bend=Math.sin(u*1.6+t*.015)*w*.022;return[vanX+bend+side*(w*.012+Math.pow(u,1.02)*w*.55),horizon+u*(h-horizon)];};
  const left=[],right=[];for(let i=0;i<=40;i++){left.push(point(i/40,-1));right.push(point(i/40,1));}
  path(ctx,[...left,...right.slice().reverse()],'#414947');
  const asphalt=ctx.createLinearGradient(0,horizon,0,h);asphalt.addColorStop(0,'#9daba520');asphalt.addColorStop(1,'#101b2030');path(ctx,[...left,...right.slice().reverse()],asphalt);
  for(let i=0;i<180;i++){const u=((i*.0713+t*.04)%1),p=point(u,(Math.sin(i*2.33))*.92);ctx.fillStyle='#c2d1c315';ctx.fillRect(p[0],p[1],1+u*3,.7+u);}
  for(const side of [-1,1]){path(ctx,Array.from({length:41},(_,i)=>point(i/40,side*.95)),null,'#deddb7',1.4);path(ctx,Array.from({length:41},(_,i)=>{const p=point(i/40,side*1.09);return[p[0],p[1]-2-i*.15];}),null,'#aeb7a7',1.5);}
  for(let j=0;j<13;j++){const u=((j/13+t*.02)%1),u2=Math.min(1,u+.016+u*.035),l1=point(u,-.007),r1=point(u,.007),l2=point(u2,-.007),r2=point(u2,.007);path(ctx,[l1,r1,r2,l2],'#f0e9b0bb');}
  for(let j=0;j<14;j++){const u=(j/14+t*.013)%1;for(const side of[-1,1]){const p=point(u,side*1.13);ctx.strokeStyle='#c4c8ac';ctx.lineWidth=1+u*3;ctx.beginPath();ctx.moveTo(p[0],p[1]);ctx.lineTo(p[0],p[1]-4-u*28);ctx.stroke();}}
  // Small distant vehicle and roadside vegetation establish depth in the demo.
  const car=point(.16,.4);ctx.fillStyle='#283337';ctx.fillRect(car[0]-w*.009,car[1]-h*.025,w*.023,h*.025);ctx.fillStyle='#96a6a0';ctx.fillRect(car[0]-w*.006,car[1]-h*.023,w*.016,h*.008);
  for(let j=0;j<20;j++){let x=(j*91.37)%w,y=horizon-5-(j%4)*6;if(Math.abs(x-vanX)<w*.13)continue;ctx.fillStyle=j%2?'#344f44':'#3c5546';ctx.beginPath();ctx.ellipse(x,y,8+(j%5)*3,12+(j%4)*5,0,0,Math.PI*2);ctx.fill();}
  if($('overlayToggle').checked){path(ctx,[...left,...right.slice().reverse()],'#4ee5b02f');ctx.save();path(ctx,[...left,...right.slice().reverse()],'#0000');ctx.clip();for(let i=1;i<12;i++){const u=(i/12)**1.5;path(ctx,[point(u,-1),point(u,1)],null,'#a7f1b03f',.8);}for(let i=-5;i<=5;i++){path(ctx,Array.from({length:41},(_,j)=>point(j/40,i/5)),null,'#b3f6b32a',.8);}ctx.restore();}
  if($('lineToggle').checked){path(ctx,left,null,colors.cyan,2);path(ctx,right,null,colors.lime,2);const u=.70,p1=point(u,-1),p2=point(u,1);path(ctx,[p1,p2],null,colors.lime,1.5);for(const p of[p1,p2]){ctx.fillStyle=colors.lime;ctx.beginPath();ctx.arc(p[0],p[1],3,0,Math.PI*2);ctx.fill();path(ctx,[[p[0],p[1]-7],[p[0],p[1]+7]],null,colors.lime,1.5);}}
  const vignette=ctx.createRadialGradient(w*.5,h*.5,w*.15,w*.5,h*.5,w*.66);vignette.addColorStop(0,'#0000');vignette.addColorStop(1,'#08131066');ctx.fillStyle=vignette;ctx.fillRect(0,0,w,h);
}
