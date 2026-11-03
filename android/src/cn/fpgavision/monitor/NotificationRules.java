package cn.fpgavision.monitor;
/** Pure rules shared by foreground and system-scheduled notification checks. */
final class NotificationRules {
 static boolean isSortAlert(String kind){return "square_alert".equals(kind)||"sort_error".equals(kind);}
 static boolean isSavedVideo(String kind,String state,String video){
  return "face_completed".equals(kind)&&"completed".equals(state)&&video!=null&&!video.isEmpty()&&!"null".equals(video);
 }
}

