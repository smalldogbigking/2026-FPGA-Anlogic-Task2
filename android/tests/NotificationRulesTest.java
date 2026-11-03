package cn.fpgavision.monitor;
public class NotificationRulesTest {
 static void check(boolean expected,String kind,String state,String video){
  boolean actual=NotificationRules.isSavedVideo(kind,state,video);
  if(actual!=expected)throw new AssertionError(kind+" / "+state+" / "+video+" expected "+expected);
 }
 public static void main(String[] args){
  check(true,"face_completed","completed","event.mp4");
  check(false,"face_started","completed","event.mp4");
  check(false,"face_completed","recording","event.mp4");
  check(false,"face_completed","no_video","event.mp4");
  check(false,"face_completed","interrupted","event.mp4");
  check(false,"face_completed","completed",null);
  check(false,"face_completed","completed","");
  check(false,"face_completed","completed","null");
  check(false,"test","completed","event.mp4");
  if(!NotificationRules.isSortAlert("square_alert")||!NotificationRules.isSortAlert("sort_error")||NotificationRules.isSortAlert("cal_marker")||NotificationRules.isSortAlert("sort_done"))throw new AssertionError("SORT alert rules");
  System.out.println("PASS: 9 saved-video and 4 SORT notification rules");
 }
}
