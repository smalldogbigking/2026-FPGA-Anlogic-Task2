package cn.fpgavision.monitor;
public class ClientContractTest {
 static int checks=0;
 static void check(boolean x){checks++;if(!x)throw new AssertionError("contract check "+checks);}
 public static void main(String[] args){
  check(ClientContract.acceptsServer("latest_plus_v3_fixed","plus_v3_sort_app","3.0.2",1,true));
  check(ClientContract.acceptsServer("latest_plus_v3_fixed","plus_v3_sort_app","3.0.3",1,true));
  check(!ClientContract.acceptsServer("latest_plus_v2_app","plus_v2_face_events_app","3.0.2",1,true));
  check(!ClientContract.acceptsServer("latest_plus_v3_fixed","plus_v3_sort_app","3.0.0",1,true));
  check(!ClientContract.acceptsServer("latest_plus_v3_fixed","plus_v3_sort_app","3.0.1",1,true));
  check(!ClientContract.acceptsServer("latest_plus_v3_fixed","plus_v3_sort_app","3.0.2",1,false));
  check(!ClientContract.acceptsServer("latest_plus_v3_fixed","plus_v3_sort_app","3.0.2",2,true));
  check(!ClientContract.acceptsServer("latest_plus_v3_fixed","plus_v3_sort_app","bad",1,true));
  check(ClientContract.sortPhase(6).equals("视觉分拣中"));
  check(ClientContract.targetLabel(3,5,4).contains("方形异常"));
  check(ClientContract.targetLabel(0,3,3).contains("方3标定"));
  check(ClientContract.VERSION.equals("3.0.2"));
  System.out.println("PASS: "+checks+" Android server/protocol/SORT compatibility checks");
 }
}
