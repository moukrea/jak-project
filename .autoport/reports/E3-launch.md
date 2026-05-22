# Phase E3 — UX (save/load binary identity) launch report

_Generated: 2026-05-22T04:45:56+02:00_

## Determination

**pass**

## Save artefact

- device path: `/data/data/org.opengoal.gk.jak1/files/saves/E3-android-save.bin`
- pulled to:   `/tmp/E3-android-save.bin`
- bytes:       67584
- sha256:      333efe2f6e1acff6e5bde59a2ba9874ee3592decd1418030c6e0dde2dd7e4645

## SaveActivity logcat

```
05-22 04:45:51.932  1634  1689 I ActivityTaskManager: START u0 {flg=0x10000000 cmp=org.opengoal.gk.jak1/.SaveActivity (has extras)} from uid 2000 from pid 31203 callingPackage com.android.shell
05-22 04:45:52.028  1634  1947 D Boost   : hostingType=pre-top-activity, hostingName={org.opengoal.gk.jak1/org.opengoal.gk.jak1.SaveActivity}, callerPackage=others, isSystem=true, isBoostNeeded=false.
05-22 04:45:52.029  1634  1947 I ActivityManager: Start proc 31218:org.opengoal.gk.jak1/u0a928 for pre-top-activity {org.opengoal.gk.jak1/org.opengoal.gk.jak1.SaveActivity} caller=others
05-22 04:45:52.100  2984  3341 W RecentsModel: getRunningTask   taskInfo=TaskInfo{userId=0 taskId=975 displayId=0 isRunning=true baseIntent=Intent { flg=0x10000000 cmp=org.opengoal.gk.jak1/.SaveActivity } baseActivity=ComponentInfo{org.opengoal.gk.jak1/org.opengoal.gk.jak1.SaveActivity} topActivity=ComponentInfo{org.opengoal.gk.jak1/org.opengoal.gk.SaveActivity} origActivity=ComponentInfo{org.opengoal.gk.jak1/org.opengoal.gk.jak1.SaveActivity} realActivity=ComponentInfo{org.opengoal.gk.jak1/org.opengoal.gk.SaveActivity} numActivities=1 lastActiveTime=105332395 supportsSplitScreenMultiWindow=true supportsMultiWindow=true resizeMode=1 isResizeable=true token=WCT{android.window.IWindowContainerToken$Stub$Proxy@3924833} topActivityType=1 pictureInPictureParams=PictureInPictureParams( aspectRatio=null sourceRectHint=null hasSetActions=false isAutoPipEnabled=false isSeamlessResizeEnabled=true) displayCutoutSafeInsets=Rect(0, 102 - 0, 0) topActivityInfo=ActivityInfo{1ba77f0 org.opengoal.gk.jak1.SaveActivity} launchCookies=[] positionInParent=Point(0, 0) parentTaskId=-1 isFocused=false isVisible=false topActivityInSizeCompat=false locusId= null windowMode=0}
05-22 04:45:52.100  2984  3341 W RecentsModel: getTaskInfoIgnoreHomeAndFreeform   taskInfo=ComponentInfo{org.opengoal.gk.jak1/org.opengoal.gk.jak1.SaveActivity}
05-22 04:45:52.105  2984  3341 E ActivityManagerWrapper: getRecentTasks: taskId=975   userId=0   baseIntent=Intent { act=null flag=268435456 cmp=ComponentInfo{org.opengoal.gk.jak1/org.opengoal.gk.jak1.SaveActivity} }
05-22 04:45:52.143  1634  1916 I WindowManager: rotation changed from 0 to 1 due ActivityRecord{157e8eb u0 org.opengoal.gk.jak1/.SaveActivity t975}
05-22 04:45:52.641 31218 31218 W System.err: 	at org.opengoal.gk.SaveActivity.onCreate(SaveActivity.java:46)
05-22 04:45:52.719 31218 31218 I opengoal-gk: libgk.so loaded (OpenGOAL gk (Android arm64-v8a, autoport phase 13 runtime))
05-22 04:45:52.721 31218 31218 I opengoal-gk: test save written: /data/data/org.opengoal.gk.jak1/files/saves/E3-android-save.bin
05-22 04:45:52.722 31218 31218 I opengoal-gk: SaveActivity: writeTestSave returned 0, file=/data/data/org.opengoal.gk.jak1/files/saves/E3-android-save.bin size=67584
05-22 04:45:52.751 31218 31218 W Looper  : PerfMonitor looperActivity : package=org.opengoal.gk.jak1/.SaveActivity time=0ms latency=528ms running=0ms  procState=-1  historyMsgCount=4 (msgIndex=1 wall=300ms seq=4 running=118ms runnable=19ms io=35ms late=228ms h=android.app.ActivityThread$H w=159) (msgIndex=2 wall=300ms seq=4 running=118ms runnable=19ms io=35ms late=228ms h=android.app.ActivityThread$H w=159) (msgIndex=3 wall=233ms seq=3 running=159ms runnable=51ms io=7ms h=android.app.ActivityThread$H w=110) (msgIndex=4 wall=300ms seq=4 running=118ms runnable=19ms io=35ms late=228ms h=android.app.ActivityThread$H w=159)
05-22 04:45:52.875  2984  2984 D RecentsImpl: mActivityStateObserver org.opengoal.gk.SaveActivity
05-22 04:45:52.875  2984  2984 W RecentsImpl: onResumed className=org.opengoal.gk.SaveActivity   mIsInAnotherPro=false   isKeyguardLocked=false
05-22 04:45:52.941  2984  3341 E ActivityManagerWrapper: getRecentTasks: taskId=975   userId=0   baseIntent=Intent { act=null flag=268435456 cmp=ComponentInfo{org.opengoal.gk.jak1/org.opengoal.gk.jak1.SaveActivity} }
05-22 04:45:52.964  2984  2984 D QuickstepAppTransitionManagerImpl: getClosingShortcutIcon:CloseShortcutIconUtils.getCloseShortcutIcon  cn=ComponentInfo{org.opengoal.gk.jak1/org.opengoal.gk.jak1.SaveActivity}   userId=0
05-22 04:45:52.967  2984  2984 D LauncherFsGestureCompat: componentName is org.opengoal.gk.jak1/org.opengoal.gk.jak1.SaveActivity
05-22 04:45:52.970  1634  2977 W InputManager-JNI: Input channel object 'Letterbox_left_ActivityRecord{157e8eb u0 org.opengoal.gk.jak1/.SaveActivity t975} (client)' was disposed without first being removed with the input manager!
05-22 04:45:52.970  1634  2977 W InputManager-JNI: Input channel object 'Letterbox_top_ActivityRecord{157e8eb u0 org.opengoal.gk.jak1/.SaveActivity t975} (client)' was disposed without first being removed with the input manager!
05-22 04:45:52.971  1634  2977 W InputManager-JNI: Input channel object 'Letterbox_right_ActivityRecord{157e8eb u0 org.opengoal.gk.jak1/.SaveActivity t975} (client)' was disposed without first being removed with the input manager!
05-22 04:45:52.972  1634  3118 W InputDispatcher: Letterbox_left_ActivityRecord{157e8eb u0 org.opengoal.gk.jak1/.SaveActivity t975} has FLAG_SLIPPERY. Please report this in b/157929241
05-22 04:45:52.975  1634  2977 W InputManager-JNI: Input channel object 'Letterbox_bottom_ActivityRecord{157e8eb u0 org.opengoal.gk.jak1/.SaveActivity t975} (client)' was disposed without first being removed with the input manager!
```
