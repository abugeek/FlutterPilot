# FlutterPilot smoke — flutter_pilot_example

2026-10-12T16:09:55.857422 · ALDE6R2516001927 · 3 screens, 3 with findings

| Screen | Layout & accessibility | Errors |
|---|---|---|
| `/` | findings | none |
| `/add` | findings | none |
| `/settings` | findings | none |

## `/`

Audit failed: [connectionLost] The connection to the app dropped during this call (reconnected: false). The action may or may not have run — check with get_app_summary before retrying.
The app crashed in native code: Fatal signal 11 (SIGSEGV), code 1 (SEGV_MAPERR), fault addr 0x0.
Where:
  #00 pc 0000000001c1613c  /data/app/~~BSECGqnBrz7jhZdO-gp_gA==/dev.flutterpilot.flutter_pilot_example-OjEhdLYvh-z97ogNOu8vVQ==/base.apk!libflutter.so (BuildId: e46dd2902eedbe02d23e110f5312e78cf80921a3)
  #01 pc 0000000001fd4650  /data/app/~~BSECGqnBrz7jhZdO-gp_gA==/dev.flutterpilot.flutter_pilot_example-OjEhdLYvh-z97ogNOu8vVQ==/base.apk!libflutter.so (BuildId: e46dd2902eedbe02d23e110f5312e78cf80921a3)
  #02 pc 0000000001fd500c  /data/app/~~BSECGqnBrz7jhZdO-gp_gA==/dev.flutterpilot.flutter_pilot_example-OjEhdLYvh-z97ogNOu8vVQ==/base.apk!libflutter.so (BuildId: e46dd2902eedbe02d23e110f5312e78cf80921a3)
  #03 pc 0000000001fd5708  /data/app/~~BSECGqnBrz7jhZdO-gp_gA==/dev.flutterpilot.flutter_pilot_example-OjEhdLYvh-z97ogNOu8vVQ==/base.apk!libflutter.so (BuildId: e46dd2902eedbe02d23e110f5312e78cf80921a3)
  #04 pc 0000000001fe1f9c  /data/app/~~BSECGqnBrz7jhZdO-gp_gA==/dev.flutterpilot.flutter_pilot_example-OjEhdLYvh-z97ogNOu8vVQ==/base.apk!libflutter.so (BuildId: e46dd2902eedbe02d23e110f5312e78cf80921a3)
  #05 pc 0000000001fe1bec  /data/app/~~BSECGqnBrz7jhZdO-gp_gA==/dev.flutterpilot.flutter_pilot_example-OjEhdLYvh-z97ogNOu8vVQ==/base.apk!libflutter.so (BuildId: e46dd2902eedbe02d23e110f5312e78cf80921a3)
  #06 pc 0000000001fe1790  /data/app/~~BSECGqnBrz7jhZdO-gp_gA==/dev.flutterpilot.flutter_pilot_example-OjEhdLYvh-z97ogNOu8vVQ==/base.apk!libflutter.so (BuildId: e46dd2902eedbe02d23e110f5312e78cf80921a3)
  #07 pc 0000000001fe16f8  /data/app/~~BSECGqnBrz7jhZdO-gp_gA==/dev.flutterpilot.flutter_pilot_example-OjEhdLYvh-z97ogNOu8vVQ==/base.apk!libflutter.so (BuildId: e46dd2902eedbe02d23e110f5312e78cf80921a3)
Full report: adb logcat -b crash -d
Fix the cause, then start the app again (flutter run); FlutterPilot reconnects by itself.


## `/add`

Could not go to this route: [connectionLost] No running Flutter app found. Call launch_app to build and start it, or start it yourself with "flutter run" (or "flutterpilot dev", your IDE) in its project folder or under the workspace; FlutterPilot then finds it. Otherwise call connect_app(uri: ...) with the VM service URI "flutter run" prints.
The app crashed in native code: Fatal signal 11 (SIGSEGV), code 1 (SEGV_MAPERR), fault addr 0x0.
Where:
  #00 pc 0000000001c1613c  /data/app/~~BSECGqnBrz7jhZdO-gp_gA==/dev.flutterpilot.flutter_pilot_example-OjEhdLYvh-z97ogNOu8vVQ==/base.apk!libflutter.so (BuildId: e46dd2902eedbe02d23e110f5312e78cf80921a3)
  #01 pc 0000000001fd4650  /data/app/~~BSECGqnBrz7jhZdO-gp_gA==/dev.flutterpilot.flutter_pilot_example-OjEhdLYvh-z97ogNOu8vVQ==/base.apk!libflutter.so (BuildId: e46dd2902eedbe02d23e110f5312e78cf80921a3)
  #02 pc 0000000001fd500c  /data/app/~~BSECGqnBrz7jhZdO-gp_gA==/dev.flutterpilot.flutter_pilot_example-OjEhdLYvh-z97ogNOu8vVQ==/base.apk!libflutter.so (BuildId: e46dd2902eedbe02d23e110f5312e78cf80921a3)
  #03 pc 0000000001fd5708  /data/app/~~BSECGqnBrz7jhZdO-gp_gA==/dev.flutterpilot.flutter_pilot_example-OjEhdLYvh-z97ogNOu8vVQ==/base.apk!libflutter.so (BuildId: e46dd2902eedbe02d23e110f5312e78cf80921a3)
  #04 pc 0000000001fe1f9c  /data/app/~~BSECGqnBrz7jhZdO-gp_gA==/dev.flutterpilot.flutter_pilot_example-OjEhdLYvh-z97ogNOu8vVQ==/base.apk!libflutter.so (BuildId: e46dd2902eedbe02d23e110f5312e78cf80921a3)
  #05 pc 0000000001fe1bec  /data/app/~~BSECGqnBrz7jhZdO-gp_gA==/dev.flutterpilot.flutter_pilot_example-OjEhdLYvh-z97ogNOu8vVQ==/base.apk!libflutter.so (BuildId: e46dd2902eedbe02d23e110f5312e78cf80921a3)
  #06 pc 0000000001fe1790  /data/app/~~BSECGqnBrz7jhZdO-gp_gA==/dev.flutterpilot.flutter_pilot_example-OjEhdLYvh-z97ogNOu8vVQ==/base.apk!libflutter.so (BuildId: e46dd2902eedbe02d23e110f5312e78cf80921a3)
  #07 pc 0000000001fe16f8  /data/app/~~BSECGqnBrz7jhZdO-gp_gA==/dev.flutterpilot.flutter_pilot_example-OjEhdLYvh-z97ogNOu8vVQ==/base.apk!libflutter.so (BuildId: e46dd2902eedbe02d23e110f5312e78cf80921a3)
Full report: adb logcat -b crash -d
Fix the cause, then start the app again (flutter run); FlutterPilot reconnects by itself.


## `/settings`

Could not go to this route: [connectionLost] No running Flutter app found. Call launch_app to build and start it, or start it yourself with "flutter run" (or "flutterpilot dev", your IDE) in its project folder or under the workspace; FlutterPilot then finds it. Otherwise call connect_app(uri: ...) with the VM service URI "flutter run" prints.
The app crashed in native code: Fatal signal 11 (SIGSEGV), code 1 (SEGV_MAPERR), fault addr 0x0.
Where:
  #00 pc 0000000001c1613c  /data/app/~~BSECGqnBrz7jhZdO-gp_gA==/dev.flutterpilot.flutter_pilot_example-OjEhdLYvh-z97ogNOu8vVQ==/base.apk!libflutter.so (BuildId: e46dd2902eedbe02d23e110f5312e78cf80921a3)
  #01 pc 0000000001fd4650  /data/app/~~BSECGqnBrz7jhZdO-gp_gA==/dev.flutterpilot.flutter_pilot_example-OjEhdLYvh-z97ogNOu8vVQ==/base.apk!libflutter.so (BuildId: e46dd2902eedbe02d23e110f5312e78cf80921a3)
  #02 pc 0000000001fd500c  /data/app/~~BSECGqnBrz7jhZdO-gp_gA==/dev.flutterpilot.flutter_pilot_example-OjEhdLYvh-z97ogNOu8vVQ==/base.apk!libflutter.so (BuildId: e46dd2902eedbe02d23e110f5312e78cf80921a3)
  #03 pc 0000000001fd5708  /data/app/~~BSECGqnBrz7jhZdO-gp_gA==/dev.flutterpilot.flutter_pilot_example-OjEhdLYvh-z97ogNOu8vVQ==/base.apk!libflutter.so (BuildId: e46dd2902eedbe02d23e110f5312e78cf80921a3)
  #04 pc 0000000001fe1f9c  /data/app/~~BSECGqnBrz7jhZdO-gp_gA==/dev.flutterpilot.flutter_pilot_example-OjEhdLYvh-z97ogNOu8vVQ==/base.apk!libflutter.so (BuildId: e46dd2902eedbe02d23e110f5312e78cf80921a3)
  #05 pc 0000000001fe1bec  /data/app/~~BSECGqnBrz7jhZdO-gp_gA==/dev.flutterpilot.flutter_pilot_example-OjEhdLYvh-z97ogNOu8vVQ==/base.apk!libflutter.so (BuildId: e46dd2902eedbe02d23e110f5312e78cf80921a3)
  #06 pc 0000000001fe1790  /data/app/~~BSECGqnBrz7jhZdO-gp_gA==/dev.flutterpilot.flutter_pilot_example-OjEhdLYvh-z97ogNOu8vVQ==/base.apk!libflutter.so (BuildId: e46dd2902eedbe02d23e110f5312e78cf80921a3)
  #07 pc 0000000001fe16f8  /data/app/~~BSECGqnBrz7jhZdO-gp_gA==/dev.flutterpilot.flutter_pilot_example-OjEhdLYvh-z97ogNOu8vVQ==/base.apk!libflutter.so (BuildId: e46dd2902eedbe02d23e110f5312e78cf80921a3)
Full report: adb logcat -b crash -d
Fix the cause, then start the app again (flutter run); FlutterPilot reconnects by itself.

