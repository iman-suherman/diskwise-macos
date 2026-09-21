# DiskWise Android — keep MediaStore / Compose entry points
-keepclassmembers class * implements android.os.Parcelable {
    public static final ** CREATOR;
}
