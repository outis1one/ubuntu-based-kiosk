const {app,BrowserWindow,BrowserView,globalShortcut,ipcMain,dialog,session}=require('electron');
const {exec,spawn}=require('child_process');
const fs=require('fs');
const path=require('path');
const os=require('os');
const crypto=require('crypto');
// Local-file sites with their own viewer pages: a folder plays as an image
// slideshow (slideshow.js), a .docx renders as a Word document (docview.js).
const slideshow=require('./slideshow');
const docview=require('./docview');
function resolveLocalSite(url){return docview.resolveSiteUrl(slideshow.resolveSiteUrl(url));}

// Suppress EPIPE errors (happen when no terminal attached)
process.stdout.on('error',(e)=>{if(e.code!=='EPIPE')throw e;});
process.stderr.on('error',(e)=>{if(e.code!=='EPIPE')throw e;});
process.on('uncaughtException',(e)=>{
  if(e.code==='EPIPE')return;
  console.error('Uncaught:',e);
});

const CONFIG_FILE=path.join(__dirname,'config.json');
const VERSION='1.0.3';

let mainWindow,views=[],hiddenViews=[],tabs=[],currentIndex=0,showingHidden=false;
let pinWindow=null,promptWindow=null,pauseWindow=null,htmlKeyboardWindow=null;
let pinWindowTimer=null,pauseWindowTimer=null;
const DIALOG_TIMEOUT=30000; // 30 seconds for secondary screens
let tabIndexToViewIndex=[];
let currentHiddenIndex=0;

let masterTimer=null;
let siteStartTime=Date.now();
let lastUserInteraction=Date.now();
let lastMediaCheck=Date.now();
let keyboardOpenTime=0;
let keyboardLastUsed=0;
let inactivityExtensionUntil=0;

let manualNavigationMode=false;
let programmaticNavigation=false;

let mediaIsPlaying=false;
let userRecentlyActive=false;
let keyboardIsOpen=false;
let keyboardClosePending=false;

const USER_ACTIVITY_PAUSE=60000;
const KEYBOARD_AUTO_CLOSE=30000;
const MEDIA_CHECK_INTERVAL=3000;
const MEDIA_GRACE_PERIOD=30000;
const SAFETY_MAX_EXTENSION=14400000;
const INACTIVITY_PROMPT_TIMEOUT=15000;

let lastMediaStateChange=Date.now();

let homeTabIndex=-1;
let inactivityTimeout=120000;
let allowNavigation='same-origin';
let enablePauseButton=true;
let enableKeyboardButton=true;
let enableNavButton=true;
let enablePasswordProtection=false;
let lockoutPassword="";
let lockoutTimeout=0;
let lockoutAtTime="";
let lockoutActiveStart="";
let lockoutActiveEnd="";
let requirePasswordOnBoot=false;
let lockoutCodeType='password'; // 'password' or 'pin' (4-8 digits, keypad)
let bootPassword='';           // separate boot code hash; '' = use lockoutPassword
let bootCodeType='password';

// Password lockout state
let isLockedOut=false;
let lockoutMode='unlock';   // 'boot' while the boot lock screen is up
let lockoutFailures=0;
let lockoutBlockedUntil=0;
let lockoutWindow=null;
let lockoutTimer=null;
let lockoutActivityTime=Date.now();
let requirePasswordAfterDisplay=false;
let lastScheduledLockCheck=0;

// Authelia auto-login state
let autheliaURL='';
let autheliaUsername='';
let autheliaEncryptedPassword='';

function loadConfig(){
  try{
    if(!fs.existsSync(CONFIG_FILE)){
      console.log('[CONFIG] No config file found');
      return [];
    }
    
    const data=fs.readFileSync(CONFIG_FILE,'utf8');
    const config=JSON.parse(data);
    
    homeTabIndex=(config.homeTabIndex!=null)?config.homeTabIndex:-1;
    inactivityTimeout=(config.inactivityTimeout||120)*1000;
    allowNavigation=config.allowNavigation||'same-origin';
    enablePauseButton=(config.enablePauseButton!==false);
    enableKeyboardButton=(config.enableKeyboardButton!==false);
    enableNavButton=(config.enableNavButton!==false);
    enablePasswordProtection=(config.enablePasswordProtection===true);
    lockoutPassword=config.lockoutPassword||"";
    lockoutTimeout=(config.lockoutTimeout||0)*60000; // Convert minutes to ms
    lockoutAtTime=config.lockoutAtTime||"";
    lockoutActiveStart=config.lockoutActiveStart||"";
    lockoutActiveEnd=config.lockoutActiveEnd||"";
    requirePasswordOnBoot=(config.requirePasswordOnBoot===true);
    lockoutCodeType=(config.lockoutCodeType==='pin')?'pin':'password';
    bootPassword=config.bootPassword||'';
    bootCodeType=(config.bootCodeType==='pin')?'pin':'password';
    autheliaURL=config.autheliaURL||'';
    autheliaUsername=config.autheliaUsername||'';
    autheliaEncryptedPassword=config.autheliaEncryptedPassword||'';

    console.log('[CONFIG] ═════════════════════════════════');
    console.log('[CONFIG] Home tab index:',homeTabIndex);
    console.log('[CONFIG] Inactivity timeout:',inactivityTimeout/1000,'seconds');
    console.log('[CONFIG] Navigation:',allowNavigation);
    console.log('[CONFIG] Pause button:',enablePauseButton);
    console.log('[CONFIG] Keyboard button:',enableKeyboardButton);
    console.log('[CONFIG] Password protection:',enablePasswordProtection);
    console.log('[CONFIG] Lockout timeout:',lockoutTimeout/60000,'minutes');
    if(lockoutAtTime)console.log('[CONFIG] Lock at time:',lockoutAtTime);
    if(lockoutActiveStart&&lockoutActiveEnd)console.log('[CONFIG] Active hours:',lockoutActiveStart,'-',lockoutActiveEnd);
    console.log('[CONFIG] Require password on boot:',requirePasswordOnBoot);
    console.log('[CONFIG] Unlock code:',lockoutCodeType,'| boot code:',bootPassword?('separate '+bootCodeType):'same as unlock');
    console.log('[CONFIG] Sites:',config.tabs?.length||0);
    console.log('[CONFIG] ╚═══════════════════════════════╝');
    
    return config.tabs||[];
  }catch(e){
    console.error('[CONFIG] Load error:',e.message);
    return [];
  }
}

function markActivity(){
  const now=Date.now();
  const timeSinceLastActivity=now-lastUserInteraction;

  if(timeSinceLastActivity>5000){
    console.log('[ACTIVITY] User interaction detected');
  }

  lastUserInteraction=now;
  userRecentlyActive=true;

  if(promptWindow&&!promptWindow.isDestroyed()){
    console.log('[ACTIVITY] Closing inactivity prompt');
    promptWindow.close();
    promptWindow=null;
  }
}

function markKeyboardActivity(){
  const now=Date.now();
  keyboardLastUsed=now;
  keyboardOpenTime=now;
  keyboardClosePending=false;
}

// Password lockout functions
function showLockoutScreen(mode){
  if(isLockedOut||!enablePasswordProtection||!lockoutPassword)return;

  isLockedOut=true;
  lockoutMode=(mode==='boot')?'boot':'unlock';
  console.log('[LOCKOUT] Showing lockout screen');
  closeWifiWindow();

  // Detach all browser views to prevent content from being visible
  console.log('[LOCKOUT] Detaching all browser views for security');
  views.forEach(view=>{
    if(mainWindow&&!mainWindow.isDestroyed()){
      try{
        mainWindow.removeBrowserView(view);
      }catch(e){
        console.log('[LOCKOUT] View already detached or error:',e.message);
      }
    }
  });
  hiddenViews.forEach(view=>{
    if(mainWindow&&!mainWindow.isDestroyed()){
      try{
        mainWindow.removeBrowserView(view);
      }catch(e){
        console.log('[LOCKOUT] Hidden view already detached or error:',e.message);
      }
    }
  });

  // Create lockout window
  lockoutWindow=new BrowserWindow({
    fullscreen:true,
    frame:false,
    backgroundColor:'#000000',
    webPreferences:{
      nodeIntegration:true,
      contextIsolation:false
    }
  });

  // The boot screen takes the separate boot code when one is set.
  const codeType=(lockoutMode==='boot'&&bootPassword)?bootCodeType:lockoutCodeType;
  lockoutWindow.loadFile(path.join(__dirname,'lockscreen.html'),{query:{type:codeType,mode:lockoutMode}});

  lockoutWindow.on('closed',()=>{
    lockoutWindow=null;
  });
}

function unlockScreen(){
  if(!isLockedOut)return;

  console.log('[LOCKOUT] Unlocking screen');
  isLockedOut=false;
  requirePasswordAfterDisplay=false;

  if(lockoutWindow&&!lockoutWindow.isDestroyed()){
    lockoutWindow.close();
    lockoutWindow=null;
  }

  // Restore current view
  if(showingHidden&&hiddenViews[currentHiddenIndex]){
    try{
      const[w,h]=mainWindow.getContentSize();
      mainWindow.addBrowserView(hiddenViews[currentHiddenIndex]);
      mainWindow.setTopBrowserView(hiddenViews[currentHiddenIndex]);
      hiddenViews[currentHiddenIndex].setBounds({x:0,y:0,width:w,height:h});
    }catch(e){
      console.error('[LOCKOUT] Error restoring hidden view:',e);
      if(views.length>0){
        showingHidden=false;
        attachView(0);
      }
    }
  }else if(views.length>0){
    const idx=(currentIndex>=0&&currentIndex<views.length)?currentIndex:0;
    attachView(idx);
  }

  if(!masterTimer){
    startMasterTimer();
  }

  lockoutActivityTime=Date.now();
}

function isWithinActiveHours(){
  if(!lockoutActiveStart||!lockoutActiveEnd)return true;

  const now=new Date();
  const currentTime=now.getHours()*60+now.getMinutes();

  const[startH,startM]=lockoutActiveStart.split(':').map(Number);
  const[endH,endM]=lockoutActiveEnd.split(':').map(Number);
  const startMinutes=startH*60+startM;
  const endMinutes=endH*60+endM;

  if(startMinutes>endMinutes){
    return currentTime>=startMinutes||currentTime<endMinutes;
  }

  return currentTime>=startMinutes&&currentTime<endMinutes;
}

function checkScheduledLockTime(){
  if(!lockoutAtTime){
    return;
  }
  if(isLockedOut)return;

  const now=new Date();
  const currentHour=now.getHours();
  const currentMin=now.getMinutes();
  const[targetH,targetM]=lockoutAtTime.split(':').map(Number);

  const currentMinute=currentHour*60+currentMin;
  const targetMinute=targetH*60+targetM;

  if(Math.floor(Date.now()/60000)!==Math.floor((Date.now()-1000)/60000)){
    const timeStr=String(currentHour).padStart(2,'0')+':'+String(currentMin).padStart(2,'0');
    console.log('[LOCKOUT-SCHED] Current: '+timeStr+' ('+currentMinute+' min) | Target: '+lockoutAtTime+' ('+targetMinute+' min) | Match: '+(currentMinute===targetMinute));
  }

  if(currentMinute===targetMinute&&lastScheduledLockCheck!==currentMinute){
    lastScheduledLockCheck=currentMinute;
    console.log('[LOCKOUT] *** SCHEDULED LOCK TIME REACHED: '+lockoutAtTime+' ***');
    showLockoutScreen();
  }
}

function checkLockoutTimer(){
  if(!enablePasswordProtection){
    return;
  }
  if(isLockedOut)return;

  const now=Date.now();

  checkScheduledLockTime();

  if(lockoutTimeout>0){
    if(!isWithinActiveHours()){
      if(Math.floor(now/60000)!==Math.floor((now-1000)/60000)){
        console.log('[LOCKOUT] Outside active hours, lockout disabled');
      }
      return;
    }

    if(inactivityExtensionUntil>0&&now<inactivityExtensionUntil){
      const remaining=Math.floor((inactivityExtensionUntil-now)/1000);
      const remMin=Math.floor(remaining/60);
      const remSec=remaining%60;

      if(Math.floor(now/30000)!==Math.floor((now-1000)/30000)){
        console.log('[LOCKOUT-INACT] ⸻ Extension active: '+remMin+'m '+remSec+'s remaining - lockout paused');
      }
      return;
    }else if(inactivityExtensionUntil>0&&now>=inactivityExtensionUntil){
      console.log('[LOCKOUT-INACT] ⏰ Extension expired - resetting lockout timer');
      inactivityExtensionUntil=0;
      lockoutActivityTime=now;
    }

    const timeSinceActivity=now-lockoutActivityTime;
    const minutesSinceActivity=Math.floor(timeSinceActivity/60000);
    const lockoutMinutes=Math.floor(lockoutTimeout/60000);

    if(Math.floor(timeSinceActivity/30000)!==Math.floor((timeSinceActivity-1000)/30000)){
      console.log('[LOCKOUT-INACT] Idle: '+minutesSinceActivity+'m / '+lockoutMinutes+'m');
    }

    if(timeSinceActivity>=lockoutTimeout){
      console.log('[LOCKOUT] Inactivity timeout reached, locking screen');
      showLockoutScreen();
    }
  }
}

function checkMediaPlayback(){
  let view=null;
  if(showingHidden&&hiddenViews[currentHiddenIndex]){
    view=hiddenViews[currentHiddenIndex];
  }else if(views[currentIndex]){
    view=views[currentIndex];
  }
  
  if(!view||!view.webContents){
    if(mediaIsPlaying){
      mediaIsPlaying=false;
      lastMediaStateChange=Date.now();
    }
    return;
  }
  
  if(view.webContents.isLoadingMainFrame()||!view.webContents.getURL()){
    return;
  }
  
  view.webContents.executeJavaScript(`
    (function(){
      try{
        let playing=false;
        let method='';
        let details='';
        
        const videos=document.querySelectorAll("video");
        for(let v of videos){
          if(!v.paused&&!v.ended&&v.readyState>=2&&v.currentTime>0){
            playing=true;
            method='video';
            details='HTML5 video';
            break;
          }
        }
        
        if(!playing){
          const audios=document.querySelectorAll("audio");
          for(let a of audios){
            if(!a.paused&&!a.ended&&a.readyState>=2&&a.currentTime>0){
              playing=true;
              method='audio';
              details='HTML5 audio';
              break;
            }
          }
        }
        
        if(!playing){
          const iframes=document.querySelectorAll(
            'iframe[src*="youtube"],iframe[src*="vimeo"],'+
            'iframe[src*="dailymotion"],iframe[src*="twitch"],'+
            'iframe[src*="plex"],iframe[src*="emby"],iframe[src*="jellyfin"]'
          );
          for(let iframe of iframes){
            const rect=iframe.getBoundingClientRect();
            if(rect.width>200&&rect.height>100&&rect.top<window.innerHeight&&rect.bottom>0){
              playing=true;
              method='iframe';
              const src=iframe.src||'';
              if(src.includes('youtube'))details='YouTube';
              else if(src.includes('plex'))details='Plex';
              else if(src.includes('emby'))details='Emby';
              else if(src.includes('jellyfin'))details='Jellyfin';
              else if(src.includes('vimeo'))details='Vimeo';
              else details='Embedded player';
              break;
            }
          }
        }
        
        if(!playing){
          if(document.querySelector('.Player-progressBar')||
             document.querySelector('[class*="PlayerControls"]')){
            const plexVideo=document.querySelector('video');
            if(plexVideo&&!plexVideo.paused){
              playing=true;
              method='plex-app';
              details='Plex Web';
            }
          }
          
          if(document.querySelector('.videoPlayerContainer')||
             document.querySelector('.nowPlayingBar')){
            const jellyfinVideo=document.querySelector('video');
            if(jellyfinVideo&&!jellyfinVideo.paused){
              playing=true;
              method='jellyfin-app';
              details='Jellyfin Web';
            }
          }
          
          if(document.querySelector('.videoPlayerContainer')||
             document.querySelector('.nowPlayingBar')){
            const embyVideo=document.querySelector('video');
            if(embyVideo&&!embyVideo.paused){
              playing=true;
              method='emby-app';
              details='Emby Web';
            }
          }
        }
        
        return {playing:playing,method:method,details:details};
      }catch(e){
        return {playing:false,error:e.message};
      }
    })();
  `,true).then(result=>{
    const wasPlaying=mediaIsPlaying;
    const now=Date.now();
    
    if(result&&result.playing){
      if(!wasPlaying){
        console.log('[MEDIA] ▶ Started:',result.details||result.method);
      }
      mediaIsPlaying=true;
      lastMediaStateChange=now;
    }else{
      if(wasPlaying){
        console.log('[MEDIA] ⸻ Stopped');
      }
      mediaIsPlaying=false;
      if(wasPlaying){
        lastMediaStateChange=now;
      }
    }
  }).catch(err=>{});
}

function startMasterTimer(){
  if(masterTimer){
    clearInterval(masterTimer);
  }

  console.log('[TIMER] ════ MASTER TIMER STARTED ════');
  console.log('[TIMER] Home tab index:',homeTabIndex);
  console.log('[TIMER] Inactivity timeout:',inactivityTimeout/1000,'seconds');
  console.log('[TIMER] Password protection:',enablePasswordProtection);
  if(enablePasswordProtection){
    console.log('[TIMER] Lockout timeout:',lockoutTimeout/60000,'minutes');
    if(lockoutAtTime)console.log('[TIMER] Scheduled lock time:',lockoutAtTime);
    if(lockoutActiveStart&&lockoutActiveEnd)console.log('[TIMER] Active hours:',lockoutActiveStart,'-',lockoutActiveEnd);
  }
  console.log('[TIMER] ╚═══════════════════════════════╝');

  siteStartTime=Date.now();
  lastUserInteraction=Date.now();
  
  masterTimer=setInterval(()=>{
    const now=Date.now();
    
    // 1. KEYBOARD AUTO-CLOSE
    if(keyboardIsOpen&&!keyboardClosePending){
      const idleTime=now-keyboardLastUsed;
      if(idleTime>KEYBOARD_AUTO_CLOSE){
        keyboardClosePending=true;
        closeHTMLKeyboard();
      }
    }

    // 1.5. LOCKOUT TIMER CHECK
    checkLockoutTimer();

    // 1.6. CHECK FOR DISPLAY WAKE FLAG
    const displayWakeFlag=path.join(__dirname,'.display-wake');
    if(enablePasswordProtection&&lockoutPassword&&fs.existsSync(displayWakeFlag)){
      console.log('[LOCKOUT] Display wake detected, requiring password');
      fs.unlinkSync(displayWakeFlag);
      if(!isLockedOut){
        showLockoutScreen();
      }
    }

    // CRITICAL: If locked out, skip all navigation/rotation logic
    if(isLockedOut){
      return;
    }

    // 2. MEDIA CHECK
    if(now-lastMediaCheck>MEDIA_CHECK_INTERVAL){
      checkMediaPlayback();
      lastMediaCheck=now;
    }
    
    // 3. MEDIA BLOCKING
    if(mediaIsPlaying){
      return;
    }
    
    // 4. GRACE PERIOD
    const timeSinceMediaStopped=now-lastMediaStateChange;
    if(timeSinceMediaStopped<MEDIA_GRACE_PERIOD){
      return;
    }
    
    // 5. USER ACTIVITY CHECK
    const timeSinceInteraction=now-lastUserInteraction;
    userRecentlyActive=timeSinceInteraction<USER_ACTIVITY_PAUSE;
    
    if(userRecentlyActive){
      return;
    }
    
    // 6. SITE ROTATION
    if(!showingHidden&&views.length>1){
      if(pauseWindow&&!pauseWindow.isDestroyed()){
        return;
      }

      if(promptWindow&&!promptWindow.isDestroyed()){
        return;
      }

      if(inactivityExtensionUntil>0&&now<inactivityExtensionUntil){
        if(Math.floor(now/30000)!==Math.floor((now-1000)/30000)){
          const remaining=Math.floor((inactivityExtensionUntil-now)/1000);
          const remMin=Math.floor(remaining/60);
          const remSec=remaining%60;
          console.log('[ROTATION] ⸻ Paused - Extension active: '+remMin+'m '+remSec+'s remaining');
        }
        return;
      }

      const currentTabIdx=viewIndexToTabIndex(currentIndex);

      if(currentTabIdx>=0&&tabs[currentTabIdx]){
        const siteDuration=parseInt(tabs[currentTabIdx].duration)||0;

        if(siteDuration>0){
          const timeOnSite=now-siteStartTime;

          if(timeOnSite>=siteDuration*1000){
            rotateToNextSite();
            return;
          }
        }
      }
    }
    
    // 7. HOME RETURN CHECK (manual and hidden sites)
    if(homeTabIndex>=0){
      if(pauseWindow&&!pauseWindow.isDestroyed()){
        return;
      }

      if(promptWindow&&!promptWindow.isDestroyed()){
        return;
      }

      let needsInactivityCheck=false;
      let currentSiteDuration=-999;

      if(showingHidden){
        needsInactivityCheck=true;
        currentSiteDuration=-1;
      }else{
        const homeViewIdx=getHomeViewIndex();
        const currentTabIdx=viewIndexToTabIndex(currentIndex);

        if(homeViewIdx>=0&&currentIndex!==homeViewIdx&&currentTabIdx>=0&&tabs[currentTabIdx]){
          currentSiteDuration=parseInt(tabs[currentTabIdx].duration)||0;

          if(currentSiteDuration===0){
            needsInactivityCheck=true;
          }
        }
      }

      if(needsInactivityCheck){
        const idleTime=now-lastUserInteraction;

        let effectiveTimeout=inactivityTimeout;
        if(inactivityExtensionUntil>0&&now<inactivityExtensionUntil){
          if(Math.floor(idleTime/15000)!==Math.floor((idleTime-1000)/15000)){
            const remaining=Math.floor((inactivityExtensionUntil-now)/1000);
            const remMin=Math.floor(remaining/60);
            const remSec=remaining%60;
            console.log('[HOME] ⏰ Extended mode: '+remMin+'m '+remSec+'s remaining');
          }
          return;
        }else if(inactivityExtensionUntil>0&&now>=inactivityExtensionUntil){
          console.log('[HOME] ⏰ Extension expired - resetting inactivity timer');
          inactivityExtensionUntil=0;
          lastUserInteraction=now;
          siteStartTime=now;
        }

        if(Math.floor(idleTime/15000)!==Math.floor((idleTime-1000)/15000)){
          const idleMinutes=Math.floor(idleTime/60000);
          const idleSeconds=Math.floor((idleTime%60000)/1000);
          const timeoutMinutes=Math.floor(effectiveTimeout/60000);
          const timeoutSeconds=Math.floor((effectiveTimeout%60000)/1000);
          const siteType=currentSiteDuration===-1?'HIDDEN':'MANUAL';
          console.log('[HOME] 🏠 '+siteType+' IDLE: '+idleMinutes+'m '+idleSeconds+'s / '+timeoutMinutes+'m '+timeoutSeconds+'s');
        }

        if(idleTime>=effectiveTimeout){
          console.log('[HOME] 🔔 *** SHOWING PROMPT NOW ('+
            (currentSiteDuration===-1?'hidden tab':'manual site')+') ***');
          showInactivityPrompt();
        }
      }
    }
  },1000);
}

function stopMasterTimer(){
  if(masterTimer){
    clearInterval(masterTimer);
    masterTimer=null;
  }
}

function rotateToNextSite(){
  if(isLockedOut)return;
  if(!views.length||showingHidden)return;
  
  let nextIdx=(currentIndex+1)%views.length;
  const startIdx=nextIdx;
  let found=false;
  let attempts=0;
  
  do{
    const tabIdx=viewIndexToTabIndex(nextIdx);
    if(tabIdx>=0&&tabs[tabIdx]){
      const dur=parseInt(tabs[tabIdx].duration)||0;
      if(dur>0){
        found=true;
        break;
      }
    }
    nextIdx=(nextIdx+1)%views.length;
    attempts++;
  }while(nextIdx!==startIdx&&attempts<views.length);
  
  if(found&&nextIdx!==currentIndex){
    currentIndex=nextIdx;
    attachView(currentIndex);
    inactivityExtensionUntil=0;
    console.log('[ROTATION] Extension cleared - rotated to new site');
  }
}

function attachView(i){
  closeHTMLKeyboard();

  if(isLockedOut){
    console.log('[MAIN] Blocked attachView - screen is locked');
    return;
  }

  if(!mainWindow||!views[i]||showingHidden)return;

  currentIndex=i;

  // Remove all other views to prevent bleeding through
  views.forEach((view,idx)=>{
    if(idx!==i&&mainWindow&&!mainWindow.isDestroyed()){
      try{
        mainWindow.removeBrowserView(view);
      }catch(e){
        // View may not be attached, ignore
      }
    }
  });

  try{
    mainWindow.addBrowserView(views[i]);
  }catch(e){
    console.log('[MAIN] View already attached or error:',e.message);
  }
  mainWindow.setTopBrowserView(views[i]);
  const[w,h]=mainWindow.getContentSize();
  views[i].setBounds({x:0,y:0,width:w,height:h});

  // Force repaint to ensure proper rendering
  if(views[i].webContents){
    views[i].webContents.invalidate();
  }
  
  const tabIdx=viewIndexToTabIndex(i);
  if(tabIdx>=0&&tabs[tabIdx]){
    const configuredUrl=resolveLocalSite(tabs[tabIdx].url);
    const currentUrl=views[i].webContents.getURL();

    if(currentUrl&&!currentUrl.startsWith(configuredUrl)){
      programmaticNavigation=true;
      views[i].webContents.loadURL(configuredUrl);
    }

    const siteDuration=parseInt(tabs[tabIdx].duration)||0;
    const shouldShow=enablePauseButton&&siteDuration>0;
    console.log('[MAIN] Sending pause-button-visibility to tab '+tabIdx+' ('+tabs[tabIdx].url+') - duration='+siteDuration+'s, shouldShow='+shouldShow);
    views[i].webContents.send('pause-button-visibility',shouldShow);
  }

  views[i].webContents.focus();
  siteStartTime=Date.now();
}

function nextTab(){
  if(isLockedOut)return;
  if(!views.length||showingHidden)return;
  console.log('[MANUAL] User switched tab forward → manualNavigationMode=TRUE');
  manualNavigationMode=true;
  currentIndex=(currentIndex+1)%views.length;
  attachView(currentIndex);
  markActivity();
  inactivityExtensionUntil=0;
  console.log('[MANUAL] Extension cleared due to manual tab switch');
}

function prevTab(){
  if(isLockedOut)return;
  if(!views.length||showingHidden)return;
  console.log('[MANUAL] User switched tab backward → manualNavigationMode=TRUE');
  manualNavigationMode=true;
  currentIndex=(currentIndex-1+views.length)%views.length;
  attachView(currentIndex);
  markActivity();
  inactivityExtensionUntil=0;
  console.log('[MANUAL] Extension cleared due to manual tab switch');
}

function getHomeViewIndex(){
  if(homeTabIndex<0)return -1;
  if(homeTabIndex>=tabIndexToViewIndex.length)return -1;
  return tabIndexToViewIndex[homeTabIndex];
}

function returnToHome(){
  if(isLockedOut)return;

  const homeViewIdx=getHomeViewIndex();
  if(homeViewIdx<0)return;

  console.log('[HOME] 🏠 RETURNING TO HOME → manualNavigationMode=FALSE');

  if(showingHidden){
    showingHidden=false;
    currentHiddenIndex=0;
  }

  if(promptWindow&&!promptWindow.isDestroyed()){
    promptWindow.close();
    promptWindow=null;
  }

  manualNavigationMode=false;
  currentIndex=homeViewIdx;
  attachView(currentIndex);

  inactivityExtensionUntil=0;

  if(enablePasswordProtection&&lockoutTimeout>0&&!isLockedOut){
    lockoutActivityTime=Date.now();
  }
  markActivity();
}

function showInactivityPrompt(){
  if(promptWindow&&!promptWindow.isDestroyed())return;
  
  promptWindow=new BrowserWindow({
    width:800,
    height:600,
    frame:false,
    alwaysOnTop:true,
    parent:mainWindow,
    modal:true,
    webPreferences:{nodeIntegration:true,contextIsolation:false}
  });
  
  promptWindow.loadFile(path.join(__dirname,'inactivity-prompt-extended.html'));
  
  promptWindow.on('closed',()=>{
    promptWindow=null;
  });
  
  setTimeout(()=>{
    if(promptWindow&&!promptWindow.isDestroyed()){
      console.log('[PROMPT] No response - returning home');
      promptWindow.close();
      promptWindow=null;
      returnToHome();
    }
  },INACTIVITY_PROMPT_TIMEOUT);
  
  ipcMain.once('user-still-here',(event,minutes)=>{
    if(promptWindow&&!promptWindow.isDestroyed()){
      promptWindow.close();
    }
    promptWindow=null;

    if(minutes===-1){
      inactivityExtensionUntil=0;

      if(enablePasswordProtection&&lockoutTimeout>0&&!isLockedOut){
        lockoutActivityTime=Date.now();
      }
      returnToHome();
    }else if(minutes===0){
      inactivityExtensionUntil=0;

      if(enablePasswordProtection&&lockoutTimeout>0&&!isLockedOut){
        lockoutActivityTime=Date.now();
      }
      markActivity();
      siteStartTime=Date.now();
      console.log('[PROMPT] User confirmed presence - rotation timer reset');
    }else{
      const now=Date.now();
      inactivityExtensionUntil=now+(minutes*60*1000);
      lastUserInteraction=now;
      siteStartTime=now;

      if(enablePasswordProtection&&lockoutTimeout>0&&!isLockedOut){
        lockoutActivityTime=now;
        console.log('[PROMPT] Lockout timer also reset during extension');
      }

      console.log('[PROMPT] Extended for '+minutes+' min until: '+new Date(inactivityExtensionUntil).toLocaleTimeString());
      console.log('[PROMPT] Rotation timer reset - staying on current page');
    }
  });
}

function showPauseDialog(){
  if(pauseWindow&&!pauseWindow.isDestroyed())return;

  pauseWindow=new BrowserWindow({
    width:800,
    height:600,
    frame:false,
    alwaysOnTop:true,
    parent:mainWindow,
    modal:true,
    webPreferences:{nodeIntegration:true,contextIsolation:false}
  });

  pauseWindow.loadFile(path.join(__dirname,'pause-dialog.html'));

  pauseWindow.on('closed',()=>{
    if(pauseWindowTimer){clearTimeout(pauseWindowTimer);pauseWindowTimer=null;}
    pauseWindow=null;
  });

  // Set 30-second auto-dismiss timer
  if(pauseWindowTimer){clearTimeout(pauseWindowTimer);}
  pauseWindowTimer=setTimeout(()=>{
    console.log('[PAUSE] Auto-dismissing dialog after 30 seconds');
    if(pauseWindow&&!pauseWindow.isDestroyed()){
      pauseWindow.close();
    }
    pauseWindow=null;
    pauseWindowTimer=null;
  },DIALOG_TIMEOUT);

  ipcMain.once('pause-time-selected',(event,minutes)=>{
    if(pauseWindowTimer){clearTimeout(pauseWindowTimer);pauseWindowTimer=null;}
    if(pauseWindow&&!pauseWindow.isDestroyed()){
      pauseWindow.close();
    }
    pauseWindow=null;

    if(minutes===0){
      console.log('[PAUSE] Cancelled');
    }else{
      const now=Date.now();
      inactivityExtensionUntil=now+(minutes*60*1000);
      lastUserInteraction=now;
      siteStartTime=now;

      if(enablePasswordProtection&&lockoutTimeout>0&&!isLockedOut){
        lockoutActivityTime=now;
        console.log('[PAUSE] Lockout timer also reset during extension');
      }

      console.log('[PAUSE] Extended for '+minutes+' min until: '+new Date(inactivityExtensionUntil).toLocaleTimeString());
      console.log('[PAUSE] Rotation and inactivity timers paused');
    }
  });
}

function showHTMLKeyboard(){
  if(keyboardIsOpen){
    keyboardLastUsed=Date.now();
    keyboardOpenTime=Date.now();
    keyboardClosePending=false;
    return;
  }
  
  if(htmlKeyboardWindow&&!htmlKeyboardWindow.isDestroyed()){
    htmlKeyboardWindow.focus();
    keyboardLastUsed=Date.now();
    keyboardOpenTime=Date.now();
    keyboardIsOpen=true;
    keyboardClosePending=false;
    return;
  }
  
  const{width,height}=mainWindow.getBounds();
  const kbHeight=Math.floor(height*0.4);
  const kbY=height-kbHeight;
  
  htmlKeyboardWindow=new BrowserWindow({
    width:width,
    height:kbHeight,
    x:0,
    y:kbY,
    frame:false,
    alwaysOnTop:true,
    skipTaskbar:true,
    focusable:false,
    webPreferences:{
      nodeIntegration:true,
      contextIsolation:false,
      backgroundThrottling:false
    }
  });
  
  htmlKeyboardWindow.loadFile(path.join(__dirname,'keyboard.html'));
  
  htmlKeyboardWindow.webContents.on('did-finish-load',()=>{
    keyboardIsOpen=true;
    keyboardOpenTime=Date.now();
    keyboardLastUsed=Date.now();
    keyboardClosePending=false;
    notifyKeyboardState(true);
    
    if(mainWindow&&!mainWindow.isDestroyed()){
      mainWindow.focus();
      if(views[currentIndex]&&views[currentIndex].webContents){
        views[currentIndex].webContents.focus();
      }
    }
  });
  
  htmlKeyboardWindow.on('closed',()=>{
    keyboardIsOpen=false;
    keyboardClosePending=false;
    htmlKeyboardWindow=null;
    notifyKeyboardState(false);
  });
}

function closeHTMLKeyboard(){
  if(!keyboardIsOpen)return;
  
  const wasAutoClosed=keyboardClosePending;
  
  if(htmlKeyboardWindow&&!htmlKeyboardWindow.isDestroyed()){
    htmlKeyboardWindow.close();
  }
  htmlKeyboardWindow=null;
  keyboardIsOpen=false;
  keyboardClosePending=false;
  notifyKeyboardState(false);
  
  if(wasAutoClosed){
    const allViews=[...views,...hiddenViews];
    allViews.forEach(view=>{
      if(view&&view.webContents){
        view.webContents.send('keyboard-auto-closed');
      }
    });
  }
  
  if(mainWindow&&!mainWindow.isDestroyed()){
    mainWindow.focus();
  }
}

function notifyKeyboardState(visible){
  const allViews=[...views,...hiddenViews];
  allViews.forEach(view=>{
    if(view&&view.webContents){
      view.webContents.send('keyboard-state-changed',visible);
    }
  });
}

function viewIndexToTabIndex(viewIdx){
  for(let i=0;i<tabIndexToViewIndex.length;i++){
    if(tabIndexToViewIndex[i]===viewIdx)return i;
  }
  return -1;
}

function toggleHidden(){
  if(pinWindow&&!pinWindow.isDestroyed()){
    pinWindow.close();
    pinWindow=null;
    return;
  }
  
  if(!hiddenViews.length)return;
  
  if(showingHidden){
    currentHiddenIndex++;
    if(currentHiddenIndex>=hiddenViews.length){
      currentHiddenIndex=0;
      returnToTabs();
    }else{
      showHiddenTab(currentHiddenIndex);
    }
  }else{
    currentHiddenIndex=0;
    showPinEntry();
  }
}

function returnToTabs(){
  if(!views.length)return;
  
  const[w,h]=mainWindow.getContentSize();
  mainWindow.setTopBrowserView(views[currentIndex]);
  views[currentIndex].setBounds({x:0,y:0,width:w,height:h});
  showingHidden=false;
  currentHiddenIndex=0;
  
  markActivity();
}

function showPinEntry(){
  if(pinWindow&&!pinWindow.isDestroyed()){
    pinWindow.focus();
    return;
  }

  pinWindow=new BrowserWindow({
    width:500,
    height:650,
    frame:false,
    alwaysOnTop:true,
    parent:mainWindow,
    modal:true,
    webPreferences:{nodeIntegration:true,contextIsolation:false}
  });

  pinWindow.loadFile(path.join(__dirname,'pin-entry.html'));
  pinWindow.on('closed',()=>{
    if(pinWindowTimer){clearTimeout(pinWindowTimer);pinWindowTimer=null;}
    pinWindow=null;
  });

  // Set 30-second auto-dismiss timer
  if(pinWindowTimer){clearTimeout(pinWindowTimer);}
  pinWindowTimer=setTimeout(()=>{
    console.log('[PIN] Auto-dismissing after 30 seconds');
    if(pinWindow&&!pinWindow.isDestroyed()){
      pinWindow.close();
    }
    pinWindow=null;
    pinWindowTimer=null;
  },DIALOG_TIMEOUT);

  ipcMain.once('pin-correct',()=>{
    if(pinWindowTimer){clearTimeout(pinWindowTimer);pinWindowTimer=null;}
    if(pinWindow&&!pinWindow.isDestroyed()){
      pinWindow.close();
    }
    pinWindow=null;
    showHiddenTab(currentHiddenIndex);
  });

  ipcMain.once('pin-cancelled',()=>{
    if(pinWindowTimer){clearTimeout(pinWindowTimer);pinWindowTimer=null;}
    if(pinWindow&&!pinWindow.isDestroyed()){
      pinWindow.close();
    }
    pinWindow=null;
  });
}

function showHiddenTab(index){
  if(!hiddenViews[index])return;
  
  const[w,h]=mainWindow.getContentSize();
  mainWindow.setTopBrowserView(hiddenViews[index]);
  hiddenViews[index].setBounds({x:0,y:0,width:w,height:h});
  showingHidden=true;
}

// WiFi screen (hold Shift+W+S+F+H, or Ctrl+Alt+Shift+Super+W): join a WiFi network from the kiosk
// itself, for when the console (Ctrl+Alt+F1..F6) is switched off and the
// admin menu can't be reached. Gated by the hidden-tab PIN (.jitsi-pin,
// same rules as pin-entry.html: no file = 1234, NOPIN = none). The root
// work is done by /usr/local/bin/kiosk-wifi-helper, which the kiosk user
// may run through sudo and nothing else (/etc/sudoers.d/kiosk-wifi).
const WIFI_HELPER='/usr/local/bin/kiosk-wifi-helper';
const WIFI_IDLE_TIMEOUT=5*60000; // closes after 5 minutes untouched
const WIFI_MAX_PIN_TRIES=5;
let wifiWindow=null,wifiUnlocked=false,wifiPinTries=0,wifiIdleTimer=null;

function readHiddenPin(){
  try{
    const stored=fs.readFileSync(path.join(__dirname,'.jitsi-pin'),'utf8').trim();
    if(stored==='NOPIN')return null;
    if(stored)return stored;
  }catch(e){}
  return '1234';
}

function runWifiHelper(action,input){
  return new Promise(resolve=>{
    let out='',err='',done=false;
    const finish=result=>{if(!done){done=true;resolve(result);}};
    let child;
    try{
      child=spawn('sudo',['-n',WIFI_HELPER,action],{stdio:['pipe','pipe','pipe']});
    }catch(e){
      finish({ok:false,error:'Could not run the WiFi helper: '+e.message});
      return;
    }
    const killer=setTimeout(()=>{child.kill();finish({ok:false,error:'The WiFi helper timed out'});},120000);
    child.stdout.on('data',d=>{out+=d;});
    child.stderr.on('data',d=>{err+=d;});
    child.on('error',e=>{clearTimeout(killer);finish({ok:false,error:'Could not run the WiFi helper: '+e.message});});
    child.on('close',()=>{
      clearTimeout(killer);
      const line=out.trim().split('\n').pop();
      try{
        finish(JSON.parse(line));
      }catch(e){
        // Not our JSON - typically sudo refusing ("a password is required")
        // on a kiosk set up before this feature: Upgrade installs the rule.
        console.error('[WIFI] helper output:',out,err);
        finish({ok:false,error:(err.trim()||'The WiFi helper is not installed')+' - run Advanced -> Upgrade from the admin menu'});
      }
    });
    child.stdin.on('error',()=>{});
    child.stdin.end(input?JSON.stringify(input):'');
  });
}

function resetWifiIdleTimer(){
  if(wifiIdleTimer)clearTimeout(wifiIdleTimer);
  wifiIdleTimer=setTimeout(()=>{
    console.log('[WIFI] Closing after 5 minutes idle');
    closeWifiWindow();
  },WIFI_IDLE_TIMEOUT);
}

function closeWifiWindow(){
  if(wifiWindow&&!wifiWindow.isDestroyed())wifiWindow.close();
}

function showWifiWindow(){
  if(isLockedOut)return;
  if(wifiWindow&&!wifiWindow.isDestroyed()){
    wifiWindow.focus();
    return;
  }
  wifiUnlocked=(readHiddenPin()===null);
  wifiPinTries=0;
  let width=720,height=820;
  if(mainWindow&&!mainWindow.isDestroyed()){
    const[w,h]=mainWindow.getContentSize();
    width=Math.min(width,w);
    height=Math.min(height,h);
  }
  wifiWindow=new BrowserWindow({
    width,height,
    frame:false,
    alwaysOnTop:true,
    parent:mainWindow,
    modal:true,
    webPreferences:{nodeIntegration:true,contextIsolation:false}
  });
  wifiWindow.setMenu(null);
  wifiWindow.loadFile(path.join(__dirname,'wifi.html'));
  wifiWindow.on('closed',()=>{
    if(wifiIdleTimer){clearTimeout(wifiIdleTimer);wifiIdleTimer=null;}
    wifiWindow=null;
    wifiUnlocked=false;
  });
  resetWifiIdleTimer();
  console.log('[WIFI] WiFi screen opened');
}

// Shift+W+S+F+H, all held together, opens the WiFi screen. A globalShortcut
// can only have one non-modifier key, so this watches the raw key events
// of every page/window instead (before-input-event): a key counts as held
// from its keyDown (autorepeat keeps refreshing it) until its keyUp, or
// for 1.5s if the keyUp never arrives (focus moved mid-press). Physical
// keys (input.code), so it's the same keys on any keyboard layout. The
// key presses that complete the chord are swallowed, not typed into the
// page.
const WIFI_CHORD_KEYS=['KeyW','KeyS','KeyF','KeyH'];
const WIFI_CHORD_HOLD_MS=1500;
const wifiChordDown=new Map();

function wifiChordInput(event,input){
  if(!WIFI_CHORD_KEYS.includes(input.code))return;
  if(input.type==='keyUp'){wifiChordDown.delete(input.code);return;}
  if(input.type!=='keyDown')return;
  const now=Date.now();
  wifiChordDown.set(input.code,now);
  if(!input.shift||input.control||input.alt||input.meta)return;
  const all=WIFI_CHORD_KEYS.every(k=>now-(wifiChordDown.get(k)||0)<WIFI_CHORD_HOLD_MS);
  if(!all)return;
  event.preventDefault();
  if(input.isAutoRepeat)return;
  wifiChordDown.clear();
  console.log('[WIFI] Shift+W+S+F+H pressed');
  showWifiWindow();
}

app.on('web-contents-created',(e,contents)=>{
  contents.on('before-input-event',wifiChordInput);
});

ipcMain.handle('wifi-request',async(event,req)=>{
  if(!wifiWindow||wifiWindow.isDestroyed()||event.sender!==wifiWindow.webContents){
    return{ok:false,error:'Not allowed'};
  }
  resetWifiIdleTimer();
  const action=req&&req.action;
  if(action==='close'){closeWifiWindow();return{ok:true};}
  if(action==='needs-pin')return{ok:true,needsPin:!wifiUnlocked};
  if(action==='unlock'){
    if(wifiUnlocked)return{ok:true};
    if(String(req.pin||'')===readHiddenPin()){
      wifiUnlocked=true;
      return{ok:true};
    }
    wifiPinTries++;
    console.log('[WIFI] Wrong PIN, attempt',wifiPinTries);
    if(wifiPinTries>=WIFI_MAX_PIN_TRIES){
      setTimeout(closeWifiWindow,1500);
      return{ok:false,error:'Too many wrong PINs'};
    }
    return{ok:false,error:'Incorrect PIN'};
  }
  if(!wifiUnlocked)return{ok:false,error:'Enter the PIN first'};
  if(action==='status'||action==='scan')return runWifiHelper(action);
  if(action==='connect'){
    console.log('[WIFI] Connecting to',JSON.stringify(String(req.ssid||'')));
    const result=await runWifiHelper('connect',{ssid:String(req.ssid||''),password:String(req.password||'')});
    console.log('[WIFI] Connect result:',result.ok?('ok '+result.ip):result.error);
    return result;
  }
  return{ok:false,error:'Unknown request'};
});

function forceReturnToTabs(){
  closeWifiWindow();
  if(pinWindow&&!pinWindow.isDestroyed()){
    pinWindow.close();
    pinWindow=null;
  }
  returnToTabs();
}

function showPowerMenu(){
  const ipAddress=os.networkInterfaces();
  let localIP='No IP';
  let vpnIP='';

  // Get local IP (exclude VPN interfaces)
  for(const name of Object.keys(ipAddress)){
    // Skip VPN interfaces
    if(name.startsWith('tailscale')||name.startsWith('wg')||name.startsWith('netbird')||name.startsWith('tun')||name.startsWith('wt')){
      continue;
    }
    for(const net of ipAddress[name]){
      if(net.family==='IPv4'&&!net.internal){
        localIP=net.address;
        break;
      }
    }
    if(localIP!=='No IP')break;
  }

  // Get VPN IPs (Tailscale, WireGuard, Netbird)
  for(const name of Object.keys(ipAddress)){
    if(name.startsWith('tailscale')||name.startsWith('wg')||name.startsWith('netbird')||name.startsWith('tun')||name.startsWith('wt')){
      for(const net of ipAddress[name]){
        if(net.family==='IPv4'){
          vpnIP+=net.address+' ('+name+') ';
        }
      }
    }
  }

  // For lockout mode, use native dialog (limited options, overlay not available)
  if(isLockedOut){
    console.log('[SECURITY] Showing limited power menu - system is locked out');
    let ipInfo='Local: '+localIP;
    if(vpnIP){ipInfo+='\nVPN: '+vpnIP.trim();}
    const targetWindow=(lockoutWindow&&!lockoutWindow.isDestroyed())?lockoutWindow:mainWindow;
    const r=dialog.showMessageBoxSync(targetWindow,{
      type:'question',
      buttons:['Shutdown','Restart','Cancel'],
      defaultId:2,
      title:'Power Options',
      message:'System is locked. Limited options available.\n\nVersion: '+VERSION+'\n'+ipInfo,
      noLink:true
    });

    if(r===0)exec('systemctl poweroff');
    else if(r===1)exec('systemctl reboot');
    return;
  }

  // For normal mode, use custom overlay with 30-second timeout
  console.log('[POWER] Showing custom power menu overlay');
  const powerInfo={version:VERSION,localIP:localIP,vpnIP:vpnIP.trim()};
  // Send to all views (preload.js runs in views, not mainWindow)
  for(const view of views){
    if(view&&view.webContents&&!view.webContents.isDestroyed()){
      view.webContents.send('display-power-menu',powerInfo);
    }
  }
}

async function autheliaAuthenticate(){
  if(!autheliaURL||!autheliaUsername||!autheliaEncryptedPassword)return;
  try{
    const machineId=fs.readFileSync('/etc/machine-id','utf8').trim();
    const key=crypto.scryptSync(machineId,'kiosk-authelia-v1',32);
    const buf=Buffer.from(autheliaEncryptedPassword,'base64');
    const iv=buf.subarray(0,16);
    const enc=buf.subarray(16);
    const decipher=crypto.createDecipheriv('aes-256-cbc',key,iv);
    const password=Buffer.concat([decipher.update(enc),decipher.final()]).toString('utf8');

    const ctrl=new AbortController();
    const timer=setTimeout(()=>ctrl.abort(),10000);
    const res=await session.defaultSession.fetch(`${autheliaURL}/api/firstfactor`,{
      method:'POST',
      headers:{'Content-Type':'application/json','User-Agent':'kiosk/1.0'},
      body:JSON.stringify({username:autheliaUsername,password,keepMeLoggedIn:true,requestMethod:'GET',targetURL:''}),
      signal:ctrl.signal
    }).finally(()=>clearTimeout(timer));
    const body=await res.json().catch(()=>({}));
    if(res.ok&&body.status==='OK'){
      console.log('[AUTHELIA] Authenticated as',autheliaUsername);
    }else{
      console.error('[AUTHELIA] Auth failed:',res.status,body.message||'');
    }
  }catch(e){
    console.error('[AUTHELIA] Error:',e.message);
  }
}

async function createWindow(){
  tabs=loadConfig();
  await autheliaAuthenticate();
  
  mainWindow=new BrowserWindow({
    fullscreen:true,
    kiosk:true,
    frame:false,
    show:false,
    webPreferences:{
      nodeIntegration:false,
      contextIsolation:true,
      sandbox:false,
      preload:path.join(__dirname,'preload.js')
    }
  });
  
  mainWindow.setMenu(null);
  mainWindow.show();
  
  mainWindow.on('focus',()=>markActivity());
  mainWindow.webContents.on('before-input-event',()=>markActivity());
  
  if(!tabs.length){
    mainWindow.loadURL('data:text/html,<body>No Sites Configured</body>');
    return;
  }
  
  let viewIndex=0;
  tabs.forEach((t,tabIdx)=>{
    const view=new BrowserView({
      webPreferences:{
        contextIsolation:true,
        sandbox:false,
        preload:path.join(__dirname,'preload.js'),
        backgroundThrottling:false
      }
    });
    
    mainWindow.addBrowserView(view);
    
    let url=t.url;
    if(t.username&&t.password){
      try{
        const u=new URL(t.url);
        u.username=t.username;
        u.password=t.password;
        url=u.toString();
      }catch(e){}
    }
    url=resolveLocalSite(url);
    
    const initialOrigin=new URL(t.url).origin;
    
    if(allowNavigation==='restricted'){
      view.webContents.on('will-navigate',(e,u)=>{
        if(u!==url&&u!==t.url)e.preventDefault();
      });
      view.webContents.setWindowOpenHandler(()=>({action:'deny'}));
    }else if(allowNavigation==='same-origin'){
      view.webContents.on('will-navigate',(e,u)=>{
        try{
          if(new URL(u).origin!==initialOrigin)e.preventDefault();
        }catch(x){
          e.preventDefault();
        }
      });
    }
    
    view.webContents.on('before-input-event',()=>markActivity());
    view.webContents.on('did-start-loading',()=>{
      if(!programmaticNavigation){
        markActivity();
      }
    });
    view.webContents.on('did-navigate',()=>{
      if(programmaticNavigation){
        programmaticNavigation=false;
      }else{
        markActivity();
      }
    });
    
    view.webContents.setAudioMuted(false);
    slideshow.attach(view.webContents);
    docview.attach(view.webContents);
    view.webContents.loadURL(url);
    
    view.webContents.on('did-finish-load',()=>{
      view.webContents.executeJavaScript(`
        ["mousedown","keydown","touchstart","scroll","click"].forEach(e=>{
          document.addEventListener(e,()=>{
            if(window.electronAPI?.notifyActivity){
              window.electronAPI.notifyActivity();
            }
          },true);
        });
      `).catch(()=>{});

      const siteDuration=parseInt(t.duration)||0;
      const shouldShow=enablePauseButton&&siteDuration>0;
      view.webContents.send('pause-button-visibility',shouldShow);

      view.webContents.send('keyboard-button-enabled',enableKeyboardButton);
      console.log('[MAIN] Page loaded - sending keyboard-button-enabled: '+enableKeyboardButton);

      view.webContents.send('nav-button-enabled',enableNavButton);
      console.log('[MAIN] Page loaded - sending nav-button-enabled: '+enableNavButton);

      console.log('[MAIN] Page loaded - resending pause-button-visibility: '+shouldShow+' for '+t.url);
    });
    
    const isHidden=parseInt(t.duration)===-1;
    if(isHidden){
      hiddenViews.push(view);
      tabIndexToViewIndex[tabIdx]=-1;
    }else{
      views.push(view);
      tabIndexToViewIndex[tabIdx]=viewIndex;
      viewIndex++;
    }
  });
  
  const homeViewIdx=getHomeViewIndex();
  const startIndex=homeViewIdx>=0?homeViewIdx:0;
  
  if(views.length){
    setTimeout(()=>{
      const bootFlag=path.join(__dirname,'.boot-flag');
      if(enablePasswordProtection&&lockoutPassword&&requirePasswordOnBoot&&fs.existsSync(bootFlag)){
        console.log('[LOCKOUT] Boot detected, requiring password BEFORE showing sites');
        fs.unlinkSync(bootFlag);
        showLockoutScreen('boot');
      }else{
        attachView(startIndex);
        startMasterTimer();
      }
    },1000);
  }
  
  ipcMain.on('swipe-left',()=>{nextTab();});
  ipcMain.on('swipe-right',()=>{prevTab();});
  ipcMain.on('show-power-menu',showPowerMenu);
  ipcMain.on('power-action',(event,action)=>{
    console.log('[POWER] Action requested:',action);
    if(action==='shutdown')exec('systemctl poweroff');
    else if(action==='restart')exec('systemctl reboot');
    else if(action==='reload'){app.relaunch();app.quit();}
  });
  ipcMain.on('toggle-hidden',toggleHidden);
  ipcMain.on('return-to-tabs',forceReturnToTabs);
  ipcMain.on('user-activity',markActivity);
  ipcMain.on('show-keyboard',()=>{showHTMLKeyboard();});
  ipcMain.on('close-keyboard',()=>{closeHTMLKeyboard();});
  ipcMain.on('keyboard-activity',()=>{markKeyboardActivity();});
  ipcMain.on('show-pause-dialog',()=>{showPauseDialog();});
  // The lock screen sends the code as typed; compared here as a SHA-256
  // hash (how the menu and Web UI store it). After every 5 wrong codes in
  // a row the screen refuses input for a while - 30s, doubling up to 5
  // minutes - so a 4-digit PIN can't simply be tried through.
  ipcMain.on('check-lockout-password',(event,code)=>{
    if(!lockoutWindow||lockoutWindow.isDestroyed()||event.sender!==lockoutWindow.webContents)return;
    if(Date.now()<lockoutBlockedUntil){
      event.sender.send('password-incorrect',{waitSeconds:Math.ceil((lockoutBlockedUntil-Date.now())/1000)});
      return;
    }
    const expected=(lockoutMode==='boot'&&bootPassword)?bootPassword:lockoutPassword;
    const hash=crypto.createHash('sha256').update(String(code||'')).digest('hex');
    if(hash===expected){
      lockoutFailures=0;
      unlockScreen();
      return;
    }
    lockoutFailures++;
    console.log('[LOCKOUT] Wrong code, attempt',lockoutFailures);
    let waitSeconds=0;
    if(lockoutFailures%5===0){
      waitSeconds=Math.min(300,30*Math.pow(2,lockoutFailures/5-1));
      lockoutBlockedUntil=Date.now()+waitSeconds*1000;
    }
    event.sender.send('password-incorrect',{waitSeconds});
  });

  ipcMain.on('get-config',(event)=>{
    try{
      if(fs.existsSync(CONFIG_FILE)){
        const data=fs.readFileSync(CONFIG_FILE,'utf8');
        const config=JSON.parse(data);
        event.sender.send('config-data',config);
        console.log('[NAV] Sent config data to renderer');
      }else{
        console.error('[NAV] Config file not found');
        event.sender.send('config-data',{tabs:[]});
      }
    }catch(err){
      console.error('[NAV] Error reading config:',err);
      event.sender.send('config-data',{tabs:[]});
    }
  });

  ipcMain.on('navigate-to-tab',(event,tabIndex)=>{
    console.log('[NAV] Navigate to tab '+tabIndex);
    if(showingHidden){
      forceReturnToTabs();
    }
    const viewIndex=tabIndexToViewIndex[tabIndex];
    if(viewIndex!==undefined&&viewIndex>=0&&viewIndex<views.length){
      console.log('[NAV] Switching to view index '+viewIndex);
      currentIndex=viewIndex;
      attachView(currentIndex);
      markActivity();
      console.log('[NAV] Navigation complete, rotation continues');
    }else{
      console.error('[NAV] Invalid view index:',viewIndex);
    }
  });
  
  ipcMain.on('keyboard-type',(event,key)=>{
    markKeyboardActivity();
    
    let view=null;
    if(showingHidden&&hiddenViews[currentHiddenIndex]){
      view=hiddenViews[currentHiddenIndex];
    }else if(views[currentIndex]){
      view=views[currentIndex];
    }
    
    if(!view||!view.webContents)return;

    const safeKey=JSON.stringify(key).slice(1,-1);

    // Sets the value through the native <input>/<textarea> value setter
    // instead of the instance property. Frameworks like React override the
    // instance setter to track the "last known value"; setting el.value
    // directly also updates that tracker, so the framework never sees a
    // real change and its own controlled state stays empty. On the next
    // re-render (focusing a different field, or any unrelated state change
    // such as toggling a checkbox) it redraws the input from that stale
    // empty state, which is why typed text appears to vanish. Going through
    // the native setter keeps the tracker out of sync so the dispatched
    // "input" event actually reaches the framework's handler.
    const setNativeValue=`
      function __kioskSetValue(el,value){
        const proto=el.tagName==="TEXTAREA"?window.HTMLTextAreaElement.prototype:window.HTMLInputElement.prototype;
        const setter=Object.getOwnPropertyDescriptor(proto,"value").set;
        setter.call(el,value);
      }
    `;

    if(key==='Backspace'){
      view.webContents.executeJavaScript(`
        (function(){
          ${setNativeValue}
          const el=document.activeElement;
          if(el&&(el.tagName==="INPUT"||el.tagName==="TEXTAREA")){
            const s=el.selectionStart||0;
            if(s>0){
              const newValue=el.value.substring(0,s-1)+el.value.substring(el.selectionEnd||s);
              __kioskSetValue(el,newValue);
              el.selectionStart=el.selectionEnd=s-1;
              el.dispatchEvent(new Event("input",{bubbles:true}));
            }
          }
        })();
      `).catch(()=>{});
    }else if(key==='Enter'){
      view.webContents.executeJavaScript(`
        (function(){
          ${setNativeValue}
          const el=document.activeElement;
          if(el){
            if(el.tagName==="TEXTAREA"){
              const s=el.selectionStart||0;
              const newValue=el.value.substring(0,s)+"\\n"+el.value.substring(el.selectionEnd||s);
              __kioskSetValue(el,newValue);
              el.selectionStart=el.selectionEnd=s+1;
              el.dispatchEvent(new Event("input",{bubbles:true}));
            }else if(el.tagName==="INPUT"){
              const form=el.closest("form");
              if(form){
                form.dispatchEvent(new Event("submit",{bubbles:true,cancelable:true}));
              }
            }
          }
        })();
      `).catch(()=>{});
    }else if(key==='Tab'){
      view.webContents.executeJavaScript(`
        (function(){
          const selector='input:not([disabled]):not([type="hidden"]), textarea:not([disabled]), select:not([disabled]), button:not([disabled]), a[href], [tabindex]:not([tabindex="-1"])';
          const focusable=Array.prototype.filter.call(
            document.querySelectorAll(selector),
            el=>el.offsetParent!==null
          );
          if(focusable.length>0){
            const idx=focusable.indexOf(document.activeElement);
            const next=idx>=0?focusable[(idx+1)%focusable.length]:focusable[0];
            next.focus();
          }
        })();
      `).catch(()=>{});
    }else if(key===' '){
      view.webContents.executeJavaScript(`
        (function(){
          ${setNativeValue}
          const el=document.activeElement;
          if(el&&(el.tagName==="INPUT"||el.tagName==="TEXTAREA")){
            const s=el.selectionStart||0;
            const newValue=el.value.substring(0,s)+" "+el.value.substring(el.selectionEnd||s);
            __kioskSetValue(el,newValue);
            el.selectionStart=el.selectionEnd=s+1;
            el.dispatchEvent(new Event("input",{bubbles:true}));
          }
        })();
      `).catch(()=>{});
    }else if(key==='Control'||key==='Alt'){
      // Ignore modifier keys - they don't work as standalone keys
      return;
    }else{
      view.webContents.executeJavaScript(`
        (function(){
          ${setNativeValue}
          const text="${safeKey}";
          const el=document.activeElement;
          if(el&&(el.tagName==="INPUT"||el.tagName==="TEXTAREA")){
            const s=el.selectionStart||0;
            const e=el.selectionEnd||s;
            const newValue=el.value.substring(0,s)+text+el.value.substring(e);
            __kioskSetValue(el,newValue);
            el.selectionStart=el.selectionEnd=s+text.length;
            el.dispatchEvent(new Event("input",{bubbles:true}));
            el.dispatchEvent(new Event("change",{bubbles:true}));
          }
        })();
      `).catch(()=>{});
    }
  });
  
  if(views.length>1){
    globalShortcut.register('Control+Tab',()=>{nextTab();});
    globalShortcut.register('Control+Shift+Tab',()=>{prevTab();});
    globalShortcut.register('Control+]',()=>{nextTab();});
    globalShortcut.register('Control+[',()=>{prevTab();});
    globalShortcut.register('Alt+Right',()=>{nextTab();});
    globalShortcut.register('Alt+Left',()=>{prevTab();});
  }
  
  globalShortcut.register('F10',toggleHidden);
  globalShortcut.register('Control+H',toggleHidden);
  globalShortcut.register('Escape',forceReturnToTabs);
  globalShortcut.register('Control+Alt+Delete',showPowerMenu);
  globalShortcut.register('Control+Alt+P',showPowerMenu);
  globalShortcut.register('Control+Alt+Escape',showPowerMenu);
  // Five keys on purpose - not something a visitor hits by accident.
  if(!globalShortcut.register('Control+Alt+Shift+Super+W',showWifiWindow)){
    console.error('[WIFI] Could not register Ctrl+Alt+Shift+Super+W');
  }
  globalShortcut.register('Control+K',()=>{
    if(htmlKeyboardWindow&&!htmlKeyboardWindow.isDestroyed()){
      closeHTMLKeyboard();
    }else{
      showHTMLKeyboard();
    }
  });
  
  mainWindow.on('resize',()=>{
    const[w,h]=mainWindow.getContentSize();
    if(showingHidden&&hiddenViews[currentHiddenIndex]){
      hiddenViews[currentHiddenIndex].setBounds({x:0,y:0,width:w,height:h});
    }else if(views[currentIndex]){
      views[currentIndex].setBounds({x:0,y:0,width:w,height:h});
    }
  });
}

if(!app.requestSingleInstanceLock())app.quit();

// Handle SIGUSR1 from power button trigger script
process.on('SIGUSR1',()=>{
  console.log('[POWER] Received SIGUSR1 signal');
  try{
    if(mainWindow&&!mainWindow.isDestroyed()){
      showPowerMenu();
    }else{
      console.log('[POWER] mainWindow not ready');
    }
  }catch(e){
    console.error('[POWER] Error:',e.message);
  }
});

app.on('certificate-error',(e,w,u,er,c,cb)=>{
  e.preventDefault();
  cb(true);
});

app.on('ready',createWindow);

app.on('will-quit',()=>{
  globalShortcut.unregisterAll();
  stopMasterTimer();
  if(htmlKeyboardWindow&&!htmlKeyboardWindow.isDestroyed()){
    htmlKeyboardWindow.close();
  }
});

app.on('window-all-closed',()=>{
  if(process.platform!=='darwin')app.quit();
});

app.on('activate',()=>{
  if(BrowserWindow.getAllWindows().length===0)createWindow();
});
