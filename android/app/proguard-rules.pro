# WorkManager creates these through reflection, so R8 must not remove their constructors.
-keep class * extends androidx.room.RoomDatabase { <init>(...); }
-keep class * extends androidx.work.ListenableWorker { <init>(...); }
