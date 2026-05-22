# Phase E3 — UX (save/load binary identity) launch report

_Generated: 2026-05-22T04:51:50+02:00_

## Determination

**pass**

## Save artefact

- device path: `/data/data/org.opengoal.gk.jak1/files/saves/E3-android-save.bin`
- pulled to:   `/tmp/E3-android-save.bin`
- bytes:       67584
- sha256:      333efe2f6e1acff6e5bde59a2ba9874ee3592decd1418030c6e0dde2dd7e4645

## SaveActivity logcat

```
05-22 04:51:46.252  1634  3262 I ActivityTaskManager: START u0 {flg=0x10000000 cmp=org.opengoal.gk.jak1/.SaveActivity (has extras)} from uid 2000 from pid 32260 callingPackage com.android.shell
05-22 04:51:46.364  1634  1947 D Boost   : hostingType=pre-top-activity, hostingName={org.opengoal.gk.jak1/org.opengoal.gk.jak1.SaveActivity}, callerPackage=others, isSystem=true, isBoostNeeded=false.
05-22 04:51:46.365  1634  1947 I ActivityManager: Start proc 32274:org.opengoal.gk.jak1/u0a928 for pre-top-activity {org.opengoal.gk.jak1/org.opengoal.gk.jak1.SaveActivity} caller=others
05-22 04:51:46.388  1634  1916 I WindowManager: rotation changed from 0 to 1 due ActivityRecord{23f0b75 u0 org.opengoal.gk.jak1/.SaveActivity t977}
05-22 04:51:46.409  2984  3341 W RecentsModel: getRunningTask   taskInfo=TaskInfo{userId=0 taskId=977 displayId=0 isRunning=true baseIntent=Intent { flg=0x10000000 cmp=org.opengoal.gk.jak1/.SaveActivity } baseActivity=ComponentInfo{org.opengoal.gk.jak1/org.opengoal.gk.jak1.SaveActivity} topActivity=ComponentInfo{org.opengoal.gk.jak1/org.opengoal.gk.SaveActivity} origActivity=ComponentInfo{org.opengoal.gk.jak1/org.opengoal.gk.jak1.SaveActivity} realActivity=ComponentInfo{org.opengoal.gk.jak1/org.opengoal.gk.SaveActivity} numActivities=1 lastActiveTime=105686703 supportsSplitScreenMultiWindow=true supportsMultiWindow=true resizeMode=1 isResizeable=true token=WCT{android.window.IWindowContainerToken$Stub$Proxy@ca63e35} topActivityType=1 pictureInPictureParams=PictureInPictureParams( aspectRatio=null sourceRectHint=null hasSetActions=false isAutoPipEnabled=false isSeamlessResizeEnabled=true) displayCutoutSafeInsets=Rect(0, 102 - 0, 0) topActivityInfo=ActivityInfo{bbad2ca org.opengoal.gk.jak1.SaveActivity} launchCookies=[] positionInParent=Point(0, 0) parentTaskId=-1 isFocused=false isVisible=true topActivityInSizeCompat=false locusId= null windowMode=0}
05-22 04:51:46.409  2984  3341 W RecentsModel: getTaskInfoIgnoreHomeAndFreeform   taskInfo=ComponentInfo{org.opengoal.gk.jak1/org.opengoal.gk.jak1.SaveActivity}
05-22 04:51:46.411  2984  3341 E ActivityManagerWrapper: getRecentTasks: taskId=977   userId=0   baseIntent=Intent { act=null flag=268435456 cmp=ComponentInfo{org.opengoal.gk.jak1/org.opengoal.gk.jak1.SaveActivity} }
05-22 04:51:46.878 32274 32274 W System.err: 	at org.opengoal.gk.SaveActivity.onCreate(SaveActivity.java:46)
05-22 04:51:46.914 32274 32274 I opengoal-gk: libgk.so loaded (OpenGOAL gk (Android arm64-v8a, autoport phase 13 runtime))
05-22 04:51:46.918 32274 32274 I opengoal-gk: test save written: /data/data/org.opengoal.gk.jak1/files/saves/E3-android-save.bin
05-22 04:51:46.918 32274 32274 I opengoal-gk: SaveActivity: writeTestSave returned 0, file=/data/data/org.opengoal.gk.jak1/files/saves/E3-android-save.bin size=67584
05-22 04:51:46.936 32274 32274 W Looper  : PerfMonitor looperActivity : package=org.opengoal.gk.jak1/.SaveActivity time=0ms latency=361ms running=0ms  procState=-1  historyMsgCount=4 (msgIndex=3 wall=191ms seq=3 running=155ms runnable=16ms io=1ms h=android.app.ActivityThread$H w=110) (msgIndex=4 wall=156ms seq=4 running=103ms runnable=26ms late=207ms h=android.app.ActivityThread$H w=159)
05-22 04:51:46.942  2984  2984 D RecentsImpl: mActivityStateObserver org.opengoal.gk.SaveActivity
05-22 04:51:46.942  2984  2984 W RecentsImpl: onResumed className=org.opengoal.gk.SaveActivity   mIsInAnotherPro=false   isKeyguardLocked=false
05-22 04:51:47.120  2984  2984 E ActivityManagerWrapper: getRecentTasks: taskId=977   userId=0   baseIntent=Intent { act=null flag=268435456 cmp=ComponentInfo{org.opengoal.gk.jak1/org.opengoal.gk.jak1.SaveActivity} }
05-22 04:51:47.126  2984  2984 D QuickstepAppTransitionManagerImpl: getClosingShortcutIcon:CloseShortcutIconUtils.getCloseShortcutIcon  cn=ComponentInfo{org.opengoal.gk.jak1/org.opengoal.gk.jak1.SaveActivity}   userId=0
05-22 04:51:47.126  2984  2984 D LauncherFsGestureCompat: componentName is org.opengoal.gk.jak1/org.opengoal.gk.jak1.SaveActivity
05-22 04:51:47.127  2984  3341 E ActivityManagerWrapper: getRecentTasks: taskId=977   userId=0   baseIntent=Intent { act=null flag=268435456 cmp=ComponentInfo{org.opengoal.gk.jak1/org.opengoal.gk.jak1.SaveActivity} }
05-22 04:51:47.150  1634  3118 W InputManager-JNI: Input channel object 'Letterbox_left_ActivityRecord{23f0b75 u0 org.opengoal.gk.jak1/.SaveActivity t977} (client)' was disposed without first being removed with the input manager!
05-22 04:51:47.150  1634  3118 W InputManager-JNI: Input channel object 'Letterbox_top_ActivityRecord{23f0b75 u0 org.opengoal.gk.jak1/.SaveActivity t977} (client)' was disposed without first being removed with the input manager!
05-22 04:51:47.150  1634  3118 W InputManager-JNI: Input channel object 'Letterbox_right_ActivityRecord{23f0b75 u0 org.opengoal.gk.jak1/.SaveActivity t977} (client)' was disposed without first being removed with the input manager!
05-22 04:51:47.150  1634  3118 W InputManager-JNI: Input channel object 'Letterbox_bottom_ActivityRecord{23f0b75 u0 org.opengoal.gk.jak1/.SaveActivity t977} (client)' was disposed without first being removed with the input manager!
05-22 04:51:47.163  1634  3157 W InputDispatcher: Letterbox_left_ActivityRecord{23f0b75 u0 org.opengoal.gk.jak1/.SaveActivity t977} has FLAG_SLIPPERY. Please report this in b/157929241
```
