# Phase E3 — UX (save/load binary identity) launch report

_Generated: 2026-05-22T04:55:28+02:00_

## Determination

**pass**

## Save artefact

- device path: `/data/data/org.opengoal.gk.jak1/files/saves/E3-android-save.bin`
- pulled to:   `/tmp/E3-android-save.bin`
- bytes:       67584
- sha256:      333efe2f6e1acff6e5bde59a2ba9874ee3592decd1418030c6e0dde2dd7e4645

## SaveActivity logcat

```
05-22 04:55:23.635  1634 11787 I ActivityTaskManager: START u0 {flg=0x10000000 cmp=org.opengoal.gk.jak1/.SaveActivity (has extras)} from uid 2000 from pid 32638 callingPackage com.android.shell
05-22 04:55:23.737  1634  1947 D Boost   : hostingType=pre-top-activity, hostingName={org.opengoal.gk.jak1/org.opengoal.gk.jak1.SaveActivity}, callerPackage=others, isSystem=true, isBoostNeeded=false.
05-22 04:55:23.738  1634  1947 I ActivityManager: Start proc 32651:org.opengoal.gk.jak1/u0a928 for pre-top-activity {org.opengoal.gk.jak1/org.opengoal.gk.jak1.SaveActivity} caller=others
05-22 04:55:23.771  1634  1916 I WindowManager: rotation changed from 0 to 1 due ActivityRecord{c5832b7 u0 org.opengoal.gk.jak1/.SaveActivity t978}
05-22 04:55:23.794  2984  3341 W RecentsModel: getRunningTask   taskInfo=TaskInfo{userId=0 taskId=978 displayId=0 isRunning=true baseIntent=Intent { flg=0x10000000 cmp=org.opengoal.gk.jak1/.SaveActivity } baseActivity=ComponentInfo{org.opengoal.gk.jak1/org.opengoal.gk.jak1.SaveActivity} topActivity=ComponentInfo{org.opengoal.gk.jak1/org.opengoal.gk.SaveActivity} origActivity=ComponentInfo{org.opengoal.gk.jak1/org.opengoal.gk.jak1.SaveActivity} realActivity=ComponentInfo{org.opengoal.gk.jak1/org.opengoal.gk.SaveActivity} numActivities=1 lastActiveTime=105904088 supportsSplitScreenMultiWindow=true supportsMultiWindow=true resizeMode=1 isResizeable=true token=WCT{android.window.IWindowContainerToken$Stub$Proxy@9cfce71} topActivityType=1 pictureInPictureParams=PictureInPictureParams( aspectRatio=null sourceRectHint=null hasSetActions=false isAutoPipEnabled=false isSeamlessResizeEnabled=true) displayCutoutSafeInsets=Rect(0, 102 - 0, 0) topActivityInfo=ActivityInfo{ac78456 org.opengoal.gk.jak1.SaveActivity} launchCookies=[] positionInParent=Point(0, 0) parentTaskId=-1 isFocused=false isVisible=true topActivityInSizeCompat=false locusId= null windowMode=0}
05-22 04:55:23.794  2984  3341 W RecentsModel: getTaskInfoIgnoreHomeAndFreeform   taskInfo=ComponentInfo{org.opengoal.gk.jak1/org.opengoal.gk.jak1.SaveActivity}
05-22 04:55:23.797  2984  3341 E ActivityManagerWrapper: getRecentTasks: taskId=978   userId=0   baseIntent=Intent { act=null flag=268435456 cmp=ComponentInfo{org.opengoal.gk.jak1/org.opengoal.gk.jak1.SaveActivity} }
05-22 04:55:24.148 32651 32651 W System.err: 	at org.opengoal.gk.SaveActivity.onCreate(SaveActivity.java:46)
05-22 04:55:24.198 32651 32651 I opengoal-gk: libgk.so loaded (OpenGOAL gk (Android arm64-v8a, autoport phase 13 runtime))
05-22 04:55:24.201 32651 32651 I opengoal-gk: test save written: /data/data/org.opengoal.gk.jak1/files/saves/E3-android-save.bin
05-22 04:55:24.201 32651 32651 I opengoal-gk: SaveActivity: writeTestSave returned 0, file=/data/data/org.opengoal.gk.jak1/files/saves/E3-android-save.bin size=67584
05-22 04:55:24.229 32651 32651 W Looper  : PerfMonitor looperActivity : package=org.opengoal.gk.jak1/.SaveActivity time=0ms latency=308ms running=0ms  procState=-1  historyMsgCount=4 (msgIndex=3 wall=176ms seq=3 running=140ms runnable=22ms io=2ms h=android.app.ActivityThread$H w=110) (msgIndex=4 wall=126ms seq=4 running=73ms runnable=7ms late=183ms h=android.app.ActivityThread$H w=159)
05-22 04:55:24.358  2984  2984 D RecentsImpl: mActivityStateObserver org.opengoal.gk.SaveActivity
05-22 04:55:24.359  2984  2984 W RecentsImpl: onResumed className=org.opengoal.gk.SaveActivity   mIsInAnotherPro=false   isKeyguardLocked=false
05-22 04:55:24.381  2984  2984 E ActivityManagerWrapper: getRecentTasks: taskId=978   userId=0   baseIntent=Intent { act=null flag=268435456 cmp=ComponentInfo{org.opengoal.gk.jak1/org.opengoal.gk.jak1.SaveActivity} }
05-22 04:55:24.387  2984  3341 E ActivityManagerWrapper: getRecentTasks: taskId=978   userId=0   baseIntent=Intent { act=null flag=268435456 cmp=ComponentInfo{org.opengoal.gk.jak1/org.opengoal.gk.jak1.SaveActivity} }
05-22 04:55:24.390  2984  2984 D QuickstepAppTransitionManagerImpl: getClosingShortcutIcon:CloseShortcutIconUtils.getCloseShortcutIcon  cn=ComponentInfo{org.opengoal.gk.jak1/org.opengoal.gk.jak1.SaveActivity}   userId=0
05-22 04:55:24.390  2984  2984 D LauncherFsGestureCompat: componentName is org.opengoal.gk.jak1/org.opengoal.gk.jak1.SaveActivity
05-22 04:55:24.390  1634  2845 W InputManager-JNI: Input channel object 'Letterbox_left_ActivityRecord{c5832b7 u0 org.opengoal.gk.jak1/.SaveActivity t978} (client)' was disposed without first being removed with the input manager!
05-22 04:55:24.390  1634  2845 W InputManager-JNI: Input channel object 'Letterbox_top_ActivityRecord{c5832b7 u0 org.opengoal.gk.jak1/.SaveActivity t978} (client)' was disposed without first being removed with the input manager!
05-22 04:55:24.390  1634  2845 W InputManager-JNI: Input channel object 'Letterbox_right_ActivityRecord{c5832b7 u0 org.opengoal.gk.jak1/.SaveActivity t978} (client)' was disposed without first being removed with the input manager!
05-22 04:55:24.390  1634  2845 W InputManager-JNI: Input channel object 'Letterbox_bottom_ActivityRecord{c5832b7 u0 org.opengoal.gk.jak1/.SaveActivity t978} (client)' was disposed without first being removed with the input manager!
05-22 04:55:24.400  1634 11873 W InputDispatcher: Letterbox_left_ActivityRecord{c5832b7 u0 org.opengoal.gk.jak1/.SaveActivity t978} has FLAG_SLIPPERY. Please report this in b/157929241
```
