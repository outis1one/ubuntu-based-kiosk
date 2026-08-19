const {contextBridge,ipcRenderer}=require('electron');

console.log('════════════════════════════════════════════════════════════');
console.log('  Gestures:');
console.log('    3-finger DOWN: Toggle hidden tabs (PIN required)');
console.log('    2-finger HORIZONTAL: Switch between sites');
console.log('    1-finger HORIZONTAL: Navigate within page');
console.log('  Navigation: Top-left key icon for site menu');
console.log('════════════════════════════════════════════════════════════');

contextBridge.exposeInMainWorld('electronAPI', {
  notifyActivity: () => ipcRenderer.send('user-activity'),
  showKeyboard: () => ipcRenderer.send('show-keyboard'),
  closeKeyboard: () => ipcRenderer.send('close-keyboard'),
  keyboardActivity: () => ipcRenderer.send('keyboard-activity'),
  showPauseDialog: () => ipcRenderer.send('show-pause-dialog')
});

// Pause button state (MUST be outside DOMContentLoaded to persist across page loads)
let pauseButton=null;
let pauseButtonShouldShow=false;
let pauseButtonShown=false;
let pauseButtonHideTimer=null;
const PAUSE_BUTTON_HIDE_DELAY=5000; // Hide after 5 seconds of inactivity

// Pause button functions (must be outside DOMContentLoaded for IPC listener)
function createPauseButton(){
  if(pauseButton)return;

  pauseButton=document.createElement('div');
  pauseButton.id='electron-pause-button';
  pauseButton.innerHTML='<div style="display:flex;gap:4px;"><div style="width:6px;height:24px;background:white;border-radius:2px;"></div><div style="width:6px;height:24px;background:white;border-radius:2px;"></div></div>';
  pauseButton.title='Pause rotation';
  pauseButton.style.cssText=`
    position:fixed;bottom:20px;left:20px;width:60px;height:60px;
    background:rgba(230,126,34,0.95);border:3px solid rgba(255,255,255,0.9);
    border-radius:50%;display:none;align-items:center;justify-content:center;
    font-size:32px;cursor:pointer;z-index:999999;
    box-shadow:0 4px 12px rgba(0,0,0,0.4);user-select:none;
  `;

  pauseButton.addEventListener('click',(e)=>{
    e.preventDefault();
    e.stopPropagation();
    ipcRenderer.send('show-pause-dialog');
  });

  document.body.appendChild(pauseButton);
}

function showPauseButton(){
  if(!pauseButton)createPauseButton();
  pauseButton.style.display='flex';
  pauseButtonShown=true;

  // Clear existing hide timer
  if(pauseButtonHideTimer){
    clearTimeout(pauseButtonHideTimer);
    pauseButtonHideTimer=null;
  }

  // Set new hide timer - button will auto-hide after inactivity
  pauseButtonHideTimer=setTimeout(()=>{
    console.log('[PAUSE-BTN] Auto-hiding after '+PAUSE_BUTTON_HIDE_DELAY+'ms inactivity');
    hidePauseButton();
  },PAUSE_BUTTON_HIDE_DELAY);
}

function hidePauseButton(){
  if(pauseButtonHideTimer){
    clearTimeout(pauseButtonHideTimer);
    pauseButtonHideTimer=null;
  }
  if(pauseButton){
    pauseButton.style.display='none';
    pauseButtonShown=false;
  }
}

// Declare variables at top level so IPC handlers and DOMContentLoaded can share them
let keyboardButtonEnabled=true;
let keyboardVisible=false;
let keyboardIcon=null;
let navButtonEnabled=true;
let navButton=null;
let navButtonShown=false;
let navButtonHideTimer=null;
let navMenu=null;
let navMenuVisible=false;
let navMenuTimer=null;
const NAV_MENU_TIMEOUT=30000; // 30 seconds
const NAV_BUTTON_HIDE_DELAY=5000; // Hide after 5 seconds of inactivity

// Listen for pause button visibility control from main process
// CRITICAL: This must be outside DOMContentLoaded so it doesn't reset on page load
ipcRenderer.on('pause-button-visibility',(event,shouldShow)=>{
  console.log('[PAUSE-BTN] Visibility update: shouldShow='+shouldShow);
  pauseButtonShouldShow=shouldShow;
  if(!shouldShow){
    // If button should not show on this site, hide it immediately
    console.log('[PAUSE-BTN] Hiding button (manual site)');
    hidePauseButton();
  }else{
    console.log('[PAUSE-BTN] Button enabled - will show on user interaction');
  }
  // If shouldShow is true, button will appear on user interaction
});

ipcRenderer.on('keyboard-button-enabled',(event,enabled)=>{
  keyboardButtonEnabled=enabled;
  console.log('[KEYBOARD-BTN] Keyboard button enabled: '+enabled);
  // Note: keyboardIcon may not exist yet if page hasn't loaded
  if(keyboardIcon&&!enabled){
    keyboardIcon.style.display='none';
  }
});

ipcRenderer.on('nav-button-enabled',(event,enabled)=>{
  navButtonEnabled=enabled;
  console.log('[NAV-BTN] Navigation button enabled: '+enabled);
  if(navButton&&!enabled){
    navButton.style.display='none';
  }
  if(navMenu&&!enabled){
    navMenu.style.display='none';
  }
});

window.addEventListener('DOMContentLoaded',()=>{
  document.addEventListener('contextmenu',e=>e.preventDefault());

  const SWIPE_THRESHOLD=120;
  const SWIPE_MAX_TIME=500;
  const SWIPE_TOLERANCE=50;

  let touchStartX=0;
  let touchStartY=0;
  let touchStartTime=0;
  let fingerCount=0;
  let lastKeyboardRequest=0;
  let keyboardAutoClosedThisSession=false;
  const KEYBOARD_REQUEST_THROTTLE=1000;
  
  const activityEvents=[
    'mousedown','mouseup','mousemove','click','dblclick',
    'wheel','scroll',
    'keydown','keyup','keypress',
    'touchstart','touchmove','touchend',
    'pointerdown','pointerup','pointermove',
    'input','change'
  ];
  
  let lastActivityNotification=0;
  const ACTIVITY_THROTTLE=1000;
  
  function notifyActivity(){
    const now=Date.now();
    if(now-lastActivityNotification>ACTIVITY_THROTTLE){
      if(window.electronAPI?.notifyActivity){
        window.electronAPI.notifyActivity();
        lastActivityNotification=now;
      }
    }
  }
  
  activityEvents.forEach(eventType=>{
    document.addEventListener(eventType,notifyActivity,{
      passive:true,
      capture:true
    });
  });
  
  ipcRenderer.on('keyboard-state-changed',(event,visible)=>{
    keyboardVisible=visible;
    if(visible){
      showKeyboardIcon();
      keyboardAutoClosedThisSession=false;
    }else{
      hideKeyboardIcon();
    }
  });
  
  ipcRenderer.on('keyboard-auto-closed',()=>{
    keyboardAutoClosedThisSession=true;
  });
  
  function createKeyboardIcon(){
    if(keyboardIcon||!keyboardButtonEnabled)return;
    
    
    keyboardIcon=document.createElement('div');
    keyboardIcon.id='electron-keyboard-icon';
    keyboardIcon.innerHTML='⌨️';
    keyboardIcon.style.cssText=`
      position:fixed;bottom:20px;right:20px;width:60px;height:60px;
      background:rgba(52,152,219,0.95);border:3px solid rgba(255,255,255,0.9);
      border-radius:50%;display:none;align-items:center;justify-content:center;
      font-size:32px;cursor:pointer;z-index:999999;
      box-shadow:0 4px 12px rgba(0,0,0,0.4);user-select:none;
    `;
    
    keyboardIcon.addEventListener('click',(e)=>{
      e.preventDefault();
      e.stopPropagation();
      keyboardAutoClosedThisSession=false;
      if(keyboardVisible){
        ipcRenderer.send('close-keyboard');
      }else{
        ipcRenderer.send('show-keyboard');
      }
    });
    
    document.body.appendChild(keyboardIcon);
  }
  
  function showKeyboardIcon(){
    if(!keyboardButtonEnabled)return;
    if(!keyboardIcon)createKeyboardIcon();
    if(keyboardIcon)keyboardIcon.style.display='flex';
  }
  
  function hideKeyboardIcon(){
    if(keyboardIcon)keyboardIcon.style.display='none';
  }

  function createNavButton(){
    if(navButton||!navButtonEnabled)return;

    navButton=document.createElement('div');
    navButton.id='electron-nav-button';
    // Use SVG key icon instead of emoji for better compatibility
    navButton.innerHTML='<svg width="32" height="32" viewBox="0 0 24 24" fill="white"><path d="M12.65 10C11.7 7.31 8.9 5.5 5.77 6.12c-2.29.46-4.15 2.29-4.63 4.58C.32 14.57 3.26 18 7 18c2.61 0 4.83-1.67 5.65-4H17v2c0 1.1.9 2 2 2s2-.9 2-2v-2c1.1 0 2-.9 2-2s-.9-2-2-2h-8.35zM7 14c-1.1 0-2-.9-2-2s.9-2 2-2 2 .9 2 2-.9 2-2 2z"/></svg>';
    navButton.title='Navigation Menu';
    navButton.style.cssText=`
      position:fixed;top:20px;left:20px;width:60px;height:60px;
      background:rgba(155,89,182,0.95);border:3px solid rgba(255,255,255,0.9);
      border-radius:50%;display:none;align-items:center;justify-content:center;
      cursor:pointer;z-index:999999;
      box-shadow:0 4px 12px rgba(0,0,0,0.4);user-select:none;
    `;

    navButton.addEventListener('click',(e)=>{
      e.preventDefault();
      e.stopPropagation();
      console.log('[NAV] Button clicked');
      try{
        toggleNavMenu();
      }catch(err){
        console.error('[NAV] Error toggling menu:',err);
      }
    });

    document.body.appendChild(navButton);
  }

  // Power button in top-right corner (follows same show/hide logic as nav button)
  let powerButton=null;
  let powerButtonHideTimer=null;
  const POWER_BUTTON_HIDE_DELAY=5000; // Same as nav button
  function createPowerButton(){
    if(powerButton)return;
    powerButton=document.createElement('div');
    powerButton.id='electron-power-button';
    // Power icon SVG
    powerButton.innerHTML='<svg width="28" height="28" viewBox="0 0 24 24" fill="white"><path d="M13 3h-2v10h2V3zm4.83 2.17l-1.42 1.42C17.99 7.86 19 9.81 19 12c0 3.87-3.13 7-7 7s-7-3.13-7-7c0-2.19 1.01-4.14 2.58-5.42L6.17 5.17C4.23 6.82 3 9.26 3 12c0 4.97 4.03 9 9 9s9-4.03 9-9c0-2.74-1.23-5.18-3.17-6.83z"/></svg>';
    powerButton.title='Power Menu';
    powerButton.style.cssText=`
      position:fixed;top:20px;right:20px;width:60px;height:60px;
      background:rgba(231,76,60,0.95);border:3px solid rgba(255,255,255,0.9);
      border-radius:50%;display:none;align-items:center;justify-content:center;
      cursor:pointer;z-index:999999;
      box-shadow:0 4px 12px rgba(0,0,0,0.4);user-select:none;
    `;
    powerButton.addEventListener('click',(e)=>{
      e.preventDefault();
      e.stopPropagation();
      console.log('[POWER] Button clicked');
      ipcRenderer.send('show-power-menu');
    });
    document.body.appendChild(powerButton);
  }

  function showPowerButton(){
    if(!powerButton)createPowerButton();
    if(powerButton){
      powerButton.style.display='flex';
    }

    // Clear existing hide timer
    if(powerButtonHideTimer){
      clearTimeout(powerButtonHideTimer);
      powerButtonHideTimer=null;
    }

    // Set new hide timer - button will auto-hide after inactivity
    powerButtonHideTimer=setTimeout(()=>{
      console.log('[POWER-BTN] Auto-hiding after '+POWER_BUTTON_HIDE_DELAY+'ms inactivity');
      hidePowerButton();
    },POWER_BUTTON_HIDE_DELAY);
  }

  function hidePowerButton(){
    if(powerButtonHideTimer){
      clearTimeout(powerButtonHideTimer);
      powerButtonHideTimer=null;
    }
    if(powerButton){
      powerButton.style.display='none';
    }
  }

  function showNavButton(){
    if(!navButtonEnabled)return;
    if(!navButton)createNavButton();
    if(navButton){
      navButton.style.display='flex';
      navButtonShown=true;
    }

    // Clear existing hide timer
    if(navButtonHideTimer){
      clearTimeout(navButtonHideTimer);
      navButtonHideTimer=null;
    }

    // Set new hide timer - button will auto-hide after inactivity
    navButtonHideTimer=setTimeout(()=>{
      console.log('[NAV-BTN] Auto-hiding after '+NAV_BUTTON_HIDE_DELAY+'ms inactivity');
      hideNavButton();
    },NAV_BUTTON_HIDE_DELAY);
  }

  function hideNavButton(){
    if(navButtonHideTimer){
      clearTimeout(navButtonHideTimer);
      navButtonHideTimer=null;
    }
    if(navButton){
      navButton.style.display='none';
      navButtonShown=false;
    }
  }

  function createNavMenu(){
    if(navMenu)return;
    console.log('[NAV] Creating navigation menu');

    navMenu=document.createElement('div');
    navMenu.id='electron-nav-menu';
    navMenu.style.cssText=`
      position:fixed;top:0;left:0;width:100%;height:100%;
      background:rgba(0,0,0,0.9);display:none;align-items:center;justify-content:center;
      z-index:999998;pointer-events:auto;
    `;

    const content=document.createElement('div');
    content.style.cssText=`
      position:relative;background:rgba(44,62,80,0.98);border-radius:20px;padding:40px;
      max-width:90%;max-height:90%;overflow:hidden;
      box-shadow:0 10px 40px rgba(0,0,0,0.5);
    `;

    const closeBtn=document.createElement('div');
    closeBtn.innerHTML='✕';
    closeBtn.style.cssText=`
      position:absolute;top:10px;right:10px;font-size:32px;color:white;
      cursor:pointer;width:40px;height:40px;display:flex;align-items:center;
      justify-content:center;border-radius:50%;background:rgba(231,76,60,0.8);
      user-select:none;
    `;
    closeBtn.addEventListener('click',(e)=>{
      e.preventDefault();
      e.stopPropagation();
      console.log('[NAV] Close button clicked');
      hideNavMenu();
    });
    content.appendChild(closeBtn);

    const columns=document.createElement('div');
    columns.style.cssText='display:flex;gap:40px;margin-top:20px;max-height:70vh;';

    // Column 1: Sites (scrollable)
    const sitesCol=document.createElement('div');
    sitesCol.style.cssText='flex:1;min-width:300px;display:flex;flex-direction:column;';
    sitesCol.innerHTML='<h2 style="color:white;margin-bottom:20px;">Sites</h2>';
    const sitesList=document.createElement('div');
    sitesList.id='nav-sites-list';
    sitesList.style.cssText='display:flex;flex-direction:column;gap:10px;overflow-y:auto;padding-right:10px;';
    sitesCol.appendChild(sitesList);

    // Column 2: Gesture Cheat Sheet (fixed, no scroll)
    const cheatCol=document.createElement('div');
    cheatCol.style.cssText='flex:1;min-width:300px;overflow-y:hidden;';
    cheatCol.innerHTML=`
      <h2 style="color:white;margin-bottom:20px;">Touch Gestures</h2>
      <div style="color:#ecf0f1;line-height:1.8;font-size:16px;">
        <div style="margin-bottom:15px;">
          <div style="font-weight:bold;color:#3498db;">2-Finger Horizontal Swipe</div>
          <div style="padding-left:15px;">Switch between sites</div>
        </div>
        <div style="margin-bottom:15px;">
          <div style="font-weight:bold;color:#3498db;">1-Finger Horizontal Swipe</div>
          <div style="padding-left:15px;">Navigate within page (arrow keys)</div>
        </div>
        <div style="margin-bottom:15px;">
          <div style="font-weight:bold;color:#9b59b6;">3-Finger Down Swipe</div>
          <div style="padding-left:15px;">Toggle hidden tabs (PIN required)</div>
        </div>
        <div style="margin-bottom:25px;padding-top:15px;border-top:1px solid rgba(255,255,255,0.2);">
          <div style="font-weight:bold;color:#e74c3c;">Keyboard Shortcuts</div>
        </div>
        <div style="margin-bottom:10px;">
          <div style="padding-left:15px;"><kbd style="background:rgba(255,255,255,0.2);padding:2px 8px;border-radius:3px;">Ctrl+Tab</kbd> or <kbd style="background:rgba(255,255,255,0.2);padding:2px 8px;border-radius:3px;">Ctrl+]</kbd> Next tab</div>
        </div>
        <div style="margin-bottom:10px;">
          <div style="padding-left:15px;"><kbd style="background:rgba(255,255,255,0.2);padding:2px 8px;border-radius:3px;">Ctrl+Shift+Tab</kbd> or <kbd style="background:rgba(255,255,255,0.2);padding:2px 8px;border-radius:3px;">Ctrl+[</kbd> Previous tab</div>
        </div>
        <div style="margin-bottom:10px;">
          <div style="padding-left:15px;"><kbd style="background:rgba(255,255,255,0.2);padding:2px 8px;border-radius:3px;">F10</kbd> or <kbd style="background:rgba(255,255,255,0.2);padding:2px 8px;border-radius:3px;">Ctrl+H</kbd> Toggle hidden tabs</div>
        </div>
        <div style="margin-bottom:10px;">
          <div style="padding-left:15px;"><kbd style="background:rgba(255,255,255,0.2);padding:2px 8px;border-radius:3px;">Escape</kbd> Return to normal tabs</div>
        </div>
        <div style="margin-bottom:10px;">
          <div style="padding-left:15px;"><kbd style="background:rgba(255,255,255,0.2);padding:2px 8px;border-radius:3px;">Ctrl+Alt+Delete</kbd> or <kbd style="background:rgba(255,255,255,0.2);padding:2px 8px;border-radius:3px;">Ctrl+Alt+P</kbd> Power menu</div>
        </div>
        <div style="margin-bottom:10px;">
          <div style="padding-left:15px;"><kbd style="background:rgba(255,255,255,0.2);padding:2px 8px;border-radius:3px;">Ctrl+K</kbd> Toggle keyboard</div>
        </div>
      </div>
    `;

    columns.appendChild(sitesCol);
    columns.appendChild(cheatCol);
    content.appendChild(columns);
    navMenu.appendChild(content);

    navMenu.addEventListener('click',(e)=>{
      if(e.target===navMenu){
        console.log('[NAV] Background clicked, closing menu');
        hideNavMenu();
      }
    });

    // Prevent clicks inside content from closing menu
    content.addEventListener('click',(e)=>{
      e.stopPropagation();
    });

    document.body.appendChild(navMenu);
    console.log('[NAV] Navigation menu created and appended to body');
  }

  function toggleNavMenu(){
    console.log('[NAV] Toggle menu, current state:',navMenuVisible);
    if(navMenuVisible){
      hideNavMenu();
    }else{
      showNavMenu();
    }
  }

  function showNavMenu(){
    console.log('[NAV] Showing navigation menu');
    try{
      if(!navMenu){
        createNavMenu();
      }

      // Request sites data
      loadSitesIntoNav();

      navMenu.style.display='flex';
      navMenuVisible=true;

      // Force reflow and repaint to ensure proper rendering
      navMenu.offsetHeight;
      navMenu.style.opacity='0';
      setTimeout(()=>{
        navMenu.style.transition='opacity 0.15s ease-in';
        navMenu.style.opacity='1';
      },10);

      // Set 30-second auto-dismiss timer
      if(navMenuTimer){
        clearTimeout(navMenuTimer);
      }
      navMenuTimer=setTimeout(()=>{
        console.log('[NAV] Auto-dismissing menu after 30 seconds');
        hideNavMenu();
      },NAV_MENU_TIMEOUT);

      console.log('[NAV] Menu displayed, 30-second timer started');
    }catch(err){
      console.error('[NAV] Error showing menu:',err);
    }
  }

  function hideNavMenu(){
    console.log('[NAV] Hiding navigation menu');
    try{
      if(navMenuTimer){
        clearTimeout(navMenuTimer);
        navMenuTimer=null;
      }
      if(navMenu){
        navMenu.style.display='none';
        navMenu.style.opacity='1';
        navMenu.style.transition='';
      }
      navMenuVisible=false;
      console.log('[NAV] Menu hidden');
    }catch(err){
      console.error('[NAV] Error hiding menu:',err);
    }
  }

  // Power menu overlay (with 30-second auto-dismiss)
  let powerMenu=null;
  let powerMenuVisible=false;
  let powerMenuTimer=null;
  const POWER_MENU_TIMEOUT=30000;
  let powerMenuInfo={version:'',localIP:'',vpnIP:''};

  function createPowerMenu(){
    if(powerMenu)return;
    console.log('[POWER-MENU] Creating power menu');

    powerMenu=document.createElement('div');
    powerMenu.id='electron-power-menu';
    powerMenu.style.cssText=`
      position:fixed;top:0;left:0;width:100%;height:100%;
      background:rgba(0,0,0,0.9);display:none;align-items:center;justify-content:center;
      z-index:999998;pointer-events:auto;
    `;

    const content=document.createElement('div');
    content.style.cssText=`
      position:relative;background:rgba(44,62,80,0.98);border-radius:20px;padding:40px;
      min-width:400px;max-width:90%;box-shadow:0 10px 40px rgba(0,0,0,0.5);text-align:center;
    `;

    const closeBtn=document.createElement('div');
    closeBtn.innerHTML='✕';
    closeBtn.style.cssText=`
      position:absolute;top:10px;right:10px;font-size:32px;color:white;
      cursor:pointer;width:40px;height:40px;display:flex;align-items:center;
      justify-content:center;border-radius:50%;background:rgba(231,76,60,0.8);
      user-select:none;
    `;
    closeBtn.addEventListener('click',(e)=>{
      e.preventDefault();
      e.stopPropagation();
      hidePowerMenu();
    });
    content.appendChild(closeBtn);

    const title=document.createElement('h2');
    title.textContent='Power Options';
    title.style.cssText='color:white;margin-bottom:20px;font-size:28px;';
    content.appendChild(title);

    const infoDiv=document.createElement('div');
    infoDiv.id='power-menu-info';
    infoDiv.style.cssText='color:#bdc3c7;margin-bottom:30px;font-size:14px;line-height:1.6;';
    content.appendChild(infoDiv);

    const buttonsDiv=document.createElement('div');
    buttonsDiv.style.cssText='display:flex;flex-direction:column;gap:15px;';

    const btnStyle=`
      padding:20px 40px;font-size:20px;border:none;border-radius:10px;
      cursor:pointer;font-weight:bold;transition:transform 0.2s,opacity 0.2s;
    `;

    const shutdownBtn=document.createElement('button');
    shutdownBtn.textContent='⏻ Shutdown';
    shutdownBtn.style.cssText=btnStyle+'background:#e74c3c;color:white;';
    shutdownBtn.addEventListener('click',()=>{
      hidePowerMenu();
      ipcRenderer.send('power-action','shutdown');
    });

    const restartBtn=document.createElement('button');
    restartBtn.textContent='↻ Restart';
    restartBtn.style.cssText=btnStyle+'background:#f39c12;color:white;';
    restartBtn.addEventListener('click',()=>{
      hidePowerMenu();
      ipcRenderer.send('power-action','restart');
    });

    const reloadBtn=document.createElement('button');
    reloadBtn.textContent='⟳ Reload App';
    reloadBtn.style.cssText=btnStyle+'background:#3498db;color:white;';
    reloadBtn.addEventListener('click',()=>{
      hidePowerMenu();
      ipcRenderer.send('power-action','reload');
    });

    const cancelBtn=document.createElement('button');
    cancelBtn.textContent='Cancel';
    cancelBtn.style.cssText=btnStyle+'background:#7f8c8d;color:white;';
    cancelBtn.addEventListener('click',()=>{
      hidePowerMenu();
    });

    buttonsDiv.appendChild(shutdownBtn);
    buttonsDiv.appendChild(restartBtn);
    buttonsDiv.appendChild(reloadBtn);
    buttonsDiv.appendChild(cancelBtn);
    content.appendChild(buttonsDiv);

    powerMenu.appendChild(content);

    powerMenu.addEventListener('click',(e)=>{
      if(e.target===powerMenu){
        hidePowerMenu();
      }
    });

    content.addEventListener('click',(e)=>{
      e.stopPropagation();
    });

    document.body.appendChild(powerMenu);
  }

  function showPowerMenu(info){
    console.log('[POWER-MENU] Showing power menu');
    try{
      if(!powerMenu)createPowerMenu();

      // Update info display
      const infoDiv=document.getElementById('power-menu-info');
      if(infoDiv&&info){
        let infoText='Version: '+info.version+'<br>Local: '+info.localIP;
        if(info.vpnIP){
          infoText+='<br>VPN: '+info.vpnIP;
        }
        infoDiv.innerHTML=infoText;
      }

      powerMenu.style.display='flex';
      powerMenuVisible=true;

      // Set 30-second auto-dismiss timer
      if(powerMenuTimer){
        clearTimeout(powerMenuTimer);
      }
      powerMenuTimer=setTimeout(()=>{
        console.log('[POWER-MENU] Auto-dismissing after 30 seconds');
        hidePowerMenu();
      },POWER_MENU_TIMEOUT);

    }catch(err){
      console.error('[POWER-MENU] Error showing menu:',err);
    }
  }

  function hidePowerMenu(){
    console.log('[POWER-MENU] Hiding power menu');
    try{
      if(powerMenuTimer){
        clearTimeout(powerMenuTimer);
        powerMenuTimer=null;
      }
      if(powerMenu){
        powerMenu.style.display='none';
      }
      powerMenuVisible=false;
    }catch(err){
      console.error('[POWER-MENU] Error hiding menu:',err);
    }
  }

  // Listen for power menu display request from main process
  ipcRenderer.on('display-power-menu',(event,info)=>{
    showPowerMenu(info);
  });

  function loadSitesIntoNav(){
    console.log('[NAV] Requesting config from main process');
    try{
      ipcRenderer.send('get-config');
    }catch(err){
      console.error('[NAV] Error requesting config:',err);
    }
  }

  ipcRenderer.on('config-data',(event,config)=>{
    console.log('[NAV] Received config data:',config);
    try{
      const sitesList=document.getElementById('nav-sites-list');
      if(!sitesList){
        console.error('[NAV] Sites list element not found');
        return;
      }

      if(!config||!config.tabs){
        console.error('[NAV] Invalid config data');
        sitesList.innerHTML='<div style="color:white;padding:10px;">No sites configured</div>';
        return;
      }

      sitesList.innerHTML='';
      let siteCount=0;

      config.tabs.forEach((tab,index)=>{
        // Skip hidden tabs (duration === -1)
        if(tab.duration===-1){
          console.log('[NAV] Skipping hidden tab at index',index);
          return;
        }

        const siteBtn=document.createElement('div');
        const displayName=tab.name||tab.url;
        siteBtn.textContent=displayName;
        siteBtn.style.cssText=`
          padding:15px 20px;background:rgba(52,152,219,0.7);color:white;
          border-radius:10px;cursor:pointer;font-size:18px;
          transition:all 0.3s;border:3px solid rgba(52,152,219,0.9);
          user-select:none;font-weight:normal;
          box-shadow:0 2px 8px rgba(0,0,0,0.2);
        `;
        siteBtn.addEventListener('mouseenter',()=>{
          siteBtn.style.background='rgba(41,128,185,1)';
          siteBtn.style.borderColor='rgba(255,255,255,0.9)';
          siteBtn.style.fontWeight='bold';
          siteBtn.style.transform='translateY(-2px)';
          siteBtn.style.boxShadow='0 4px 12px rgba(0,0,0,0.4)';
        });
        siteBtn.addEventListener('mouseleave',()=>{
          siteBtn.style.background='rgba(52,152,219,0.7)';
          siteBtn.style.borderColor='rgba(52,152,219,0.9)';
          siteBtn.style.fontWeight='normal';
          siteBtn.style.transform='translateY(0)';
          siteBtn.style.boxShadow='0 2px 8px rgba(0,0,0,0.2)';
        });
        siteBtn.addEventListener('mousedown',()=>{
          siteBtn.style.background='rgba(31,97,141,1)';
          siteBtn.style.transform='translateY(0)';
          siteBtn.style.boxShadow='0 1px 4px rgba(0,0,0,0.3)';
        });
        siteBtn.addEventListener('click',(e)=>{
          e.preventDefault();
          e.stopPropagation();
          console.log('[NAV] Navigating to tab',index);
          try{
            ipcRenderer.send('navigate-to-tab',index);
            hideNavMenu();
          }catch(err){
            console.error('[NAV] Error navigating:',err);
          }
        });

        sitesList.appendChild(siteBtn);
        siteCount++;
      });

      console.log('[NAV] Loaded',siteCount,'sites into menu');
    }catch(err){
      console.error('[NAV] Error processing config data:',err);
    }
  });

  function isTextInput(el){
    if(!el)return false;
    const tag=(el.tagName||'').toLowerCase();
    const type=(el.type||'').toLowerCase();
    const editable=el.isContentEditable||el.contentEditable==='true';
    return(tag==='input'&&['text','email','password','search','tel','url','number'].includes(type))||tag==='textarea'||editable;
  }
  
  document.addEventListener('focusin',(e)=>{
    if(keyboardButtonEnabled&&isTextInput(e.target)){
      showKeyboardIcon();
    }
  },true);
  
  document.addEventListener('focusout',(e)=>{
    if(keyboardButtonEnabled&&isTextInput(e.target)){
      setTimeout(()=>{
        if(!isTextInput(document.activeElement)){
          hideKeyboardIcon();
        }
      },100);
    }
  },true);
  
  document.addEventListener('mousedown',(e)=>{
    if(keyboardButtonEnabled&&isTextInput(e.target)){
      if(keyboardVisible){
        if(window.electronAPI?.keyboardActivity){
          window.electronAPI.keyboardActivity();
        }
      }else{
        keyboardAutoClosedThisSession=false;
        const now=Date.now();
        if(now-lastKeyboardRequest>KEYBOARD_REQUEST_THROTTLE){
          lastKeyboardRequest=now;
          setTimeout(()=>ipcRenderer.send('show-keyboard'),50);
        }
      }
    }
  },true);
  
  // Shared debounce prevents double-firing when both touch and pointer events fire
  let lastSwipeSent=0;
  function sendSwipeIPC(direction){
    const now=Date.now();
    if(now-lastSwipeSent<500)return;
    lastSwipeSent=now;
    ipcRenderer.send(direction);
  }

  document.addEventListener('touchstart',e=>{
    if(e.touches.length>=1){
      touchStartX=e.touches[0].clientX;
      touchStartY=e.touches[0].clientY;
      touchStartTime=Date.now();
      fingerCount=e.touches.length;
    }
  },{passive:true});

  document.addEventListener('touchend',e=>{
    if(e.changedTouches.length>=1){
      const touchEndX=e.changedTouches[0].clientX;
      const touchEndY=e.changedTouches[0].clientY;
      const deltaX=touchEndX-touchStartX;
      const deltaY=touchEndY-touchStartY;
      const deltaTime=Date.now()-touchStartTime;

      if(deltaTime>SWIPE_MAX_TIME)return;

      const absX=Math.abs(deltaX);
      const absY=Math.abs(deltaY);

      if(fingerCount===3&&absY>SWIPE_THRESHOLD&&absX<SWIPE_TOLERANCE&&deltaY>0){
        console.log('[TOUCH] 3-finger DOWN - toggle hidden tabs');
        ipcRenderer.send('toggle-hidden');
      }else if(fingerCount===2&&absX>SWIPE_THRESHOLD&&absY<SWIPE_TOLERANCE){
        console.log('[TOUCH] 2-finger HORIZONTAL - change tab');
        sendSwipeIPC(deltaX>0?'swipe-right':'swipe-left');
      }else if(fingerCount===1&&absX>SWIPE_THRESHOLD&&absY<SWIPE_TOLERANCE){
        const key=deltaX>0?'ArrowRight':'ArrowLeft';
        const keyCode=deltaX>0?39:37;
        ['keydown','keyup'].forEach(eventType=>{
          document.dispatchEvent(new KeyboardEvent(eventType,{
            key:key,code:key,keyCode:keyCode,which:keyCode,bubbles:true,cancelable:true
          }));
        });
      }
    }
  },{passive:true});

  // Pointer event fallback — handles devices/drivers where touchstart/touchend don't fire
  // (e.g. Electron 42 on some Linux touchscreen drivers that only generate PointerEvents)
  let ptrIds=new Set();
  let ptrPeak=0;
  let ptrStartX=0,ptrStartY=0,ptrStartTime=0;

  document.addEventListener('pointerdown',e=>{
    if(e.pointerType!=='touch')return;
    ptrIds.add(e.pointerId);
    if(ptrIds.size===1){ptrStartX=e.clientX;ptrStartY=e.clientY;ptrStartTime=Date.now();ptrPeak=1;}
    else{ptrPeak=Math.max(ptrPeak,ptrIds.size);}
  },{passive:true});

  document.addEventListener('pointerup',e=>{
    if(e.pointerType!=='touch')return;
    ptrIds.delete(e.pointerId);
    if(ptrIds.size!==0)return;
    const deltaTime=Date.now()-ptrStartTime;
    if(deltaTime>SWIPE_MAX_TIME){ptrPeak=0;return;}
    const deltaX=e.clientX-ptrStartX;
    const deltaY=e.clientY-ptrStartY;
    const absX=Math.abs(deltaX);
    const absY=Math.abs(deltaY);
    if(ptrPeak===3&&absY>SWIPE_THRESHOLD&&absX<SWIPE_TOLERANCE&&deltaY>0){
      console.log('[TOUCH] 3-finger DOWN (ptr) - toggle hidden tabs');
      ipcRenderer.send('toggle-hidden');
    }else if(ptrPeak===2&&absX>SWIPE_THRESHOLD&&absY<SWIPE_TOLERANCE){
      console.log('[TOUCH] 2-finger HORIZONTAL (ptr) - change tab');
      sendSwipeIPC(deltaX>0?'swipe-right':'swipe-left');
    }else if(ptrPeak===1&&absX>SWIPE_THRESHOLD&&absY<SWIPE_TOLERANCE){
      const key=deltaX>0?'ArrowRight':'ArrowLeft';
      const keyCode=deltaX>0?39:37;
      ['keydown','keyup'].forEach(eventType=>{
        document.dispatchEvent(new KeyboardEvent(eventType,{
          key:key,code:key,keyCode:keyCode,which:keyCode,bubbles:true,cancelable:true
        }));
      });
    }
    ptrPeak=0;
  },{passive:true});

  // Show pause button on user interaction (for rotation sites only)
  let lastUserInteraction=0;
  const USER_INTERACTION_THROTTLE=500;

  function handleUserInteraction(eventType){
    const now=Date.now();
    if(now-lastUserInteraction<USER_INTERACTION_THROTTLE)return;
    lastUserInteraction=now;

    console.log('[PAUSE-BTN] User interaction ('+eventType+') - shouldShow='+pauseButtonShouldShow+', shown='+pauseButtonShown);
    // Show/refresh pause button if allowed on this site
    if(pauseButtonShouldShow){
      if(!pauseButtonShown){
        console.log('[PAUSE-BTN] Showing pause button now');
      }else{
        console.log('[PAUSE-BTN] Resetting auto-hide timer');
      }
      showPauseButton(); // This will reset the hide timer
    }

    // Always show navigation button on user interaction (if enabled)
    if(navButtonEnabled){
      showNavButton();
    }

    // Always show power button on user interaction
    showPowerButton();
  }

  // Show pause button on any user interaction
  const pauseButtonTriggers=['mousedown','touchstart','keydown'];
  pauseButtonTriggers.forEach(eventType=>{
    document.addEventListener(eventType,()=>handleUserInteraction(eventType),{passive:true,capture:true});
  });
});
