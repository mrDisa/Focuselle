const chevron='<svg aria-hidden="true" viewBox="0 0 20 20"><path d="m6 8 4 4 4-4" fill="none" stroke="currentColor" stroke-width="1.6" stroke-linecap="round" stroke-linejoin="round"/></svg>';
let anchor;
function positionPicker(){
  const panel=$('picker');
  if(!panel.matches(':popover-open'))return;
  if(!anchor?.isConnected){panel.hidePopover();return}
  const box=anchor.getBoundingClientRect(),pad=10;
  panel.style.left=Math.max(pad,Math.min(box.left,innerWidth-panel.offsetWidth-pad))+'px';
  const top=box.bottom+6+panel.offsetHeight<=innerHeight-pad?box.bottom+6:box.top-panel.offsetHeight-6;
  panel.style.top=Math.max(pad,Math.min(top,innerHeight-pad-panel.offsetHeight))+'px';
}
function showPicker(button,label,content){
  const panel=$('picker');
  anchor=button;
  panel.innerHTML=content;
  panel.setAttribute('aria-label',label);
  panel.showPopover();
  positionPicker();
  (panel.querySelector('[aria-pressed=true]')||panel.querySelector('button')).focus({preventScroll:true});
}
window.addEventListener('resize',positionPicker);
window.addEventListener('scroll',positionPicker,true);
document.addEventListener('keydown',e=>{
  const panel=document.getElementById('picker');
  if(!panel?.matches(':popover-open'))return;
  if(e.key==='Escape'){panel.hidePopover();anchor.focus();e.preventDefault()}
  if(['ArrowDown','ArrowUp'].includes(e.key)){
    const buttons=[...panel.querySelectorAll('button')],i=buttons.indexOf(document.activeElement);
    buttons[(i+(e.key==='ArrowDown'?1:-1)+buttons.length)%buttons.length].focus();
    e.preventDefault();
  }
});
function styleChoices(){
  document.querySelectorAll('#page select').forEach(select=>{
    const button=document.createElement('button');
    button.type='button';button.className='field';button.disabled=select.disabled;
    button.id=select.id+'-field';button.setAttribute('aria-haspopup','dialog');
    const label=select.id==='bt'?'Задача расписания':'Текущая задача';
    function sync(){
      const text=select.selectedOptions[0]?.textContent||'Без задачи';
      button.innerHTML='<span>'+esc(text)+'</span>'+chevron;
      button.setAttribute('aria-label',label+' · '+text);
    }
    sync();select.hidden=true;select.after(button);
    button.onclick=()=>{
      showPicker(button,label,[...select.options].map((o,i)=>`<button class="option" data-index="${i}" aria-pressed="${o.selected}"><span>${esc(o.textContent)}</span>${o.selected?icon('check'):''}</button>`).join(''));
      $('picker').onclick=e=>{
        const choice=e.target.closest('[data-index]');
        if(!choice)return;
        $('picker').hidePopover();select.selectedIndex=Number(choice.dataset.index);sync();
        select.dispatchEvent(new Event('change',{bubbles:true}));$(button.id)?.focus();
      };
    };
  });
}
function calendarPicker(button){
  const owner=button.closest('article')?'page':'aside';
  let month=new Date(day+'T12:00');month.setDate(1);
  function draw(){
    const first=(month.getDay()+6)%7,count=new Date(month.getFullYear(),month.getMonth()+1,0).getDate();
    const prefix=month.getFullYear()+'-'+String(month.getMonth()+1).padStart(2,'0')+'-';
    const days=Array.from({length:count},(_,i)=>{
      const value=prefix+String(i+1).padStart(2,'0');
      return `<button data-date="${value}" aria-label="${value}" aria-pressed="${value===day}">${i+1}</button>`;
    }).join('');
    return `<div class="cal-head"><b>${month.toLocaleDateString('ru',{month:'long',year:'numeric'})}</b><button aria-label="Предыдущий месяц" data-step="-1">‹</button><button aria-label="Следующий месяц" data-step="1">›</button></div><div class="cal-grid">${'Пн Вт Ср Чт Пт Сб Вс'.split(' ').map(w=>'<small>'+w+'</small>').join('')}${'<i></i>'.repeat(first)}${days}</div><button class="cal-today" data-date="${today}">Сегодня</button>`;
  }
  showPicker(button,'Дата плана',draw());
  $('picker').onclick=e=>{
    const item=e.target.closest('button');if(!item)return;
    if(item.dataset.step){month.setMonth(month.getMonth()+Number(item.dataset.step));$('picker').innerHTML=draw();$('picker').querySelector('[data-step="'+item.dataset.step+'"]').focus();positionPicker();return}
    day=item.dataset.date;$('picker').hidePopover();render();$(owner).querySelector('.date-field')?.focus();
  };
}
