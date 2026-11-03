package cn.fpgavision.monitor;

/** Pure Java compatibility rules, shared by connection checks and offline tests. */
final class ClientContract {
 static final String VERSION="3.0.2";
 static boolean acceptsServer(String project,String software,String version,int api,boolean protocol5) {
  if(!"latest_plus_v3_fixed".equals(project)||!"plus_v3_sort_app".equals(software)||api!=1||!protocol5)return false;
  try {
   String[] parts=version.split("\\.");if(parts.length!=3)return false;
   int major=Integer.parseInt(parts[0]),minor=Integer.parseInt(parts[1]),patch=Integer.parseInt(parts[2]);
   return major==3 && minor>=0 && patch>=0 && (minor>0 || patch>=2);
  }catch(Exception e){return false;}
 }
 static String sortPhase(int phase) {
  String[] labels={"未进入","抬头就位","等待人脸","人脸留档","返回俯视","等待稳定","视觉分拣中","等待人脸超时"};
  return phase>=0&&phase<labels.length?labels[phase]:"状态待更新";
 }
 static String targetLabel(int slot,int digit,int category) {
  String[] kinds={"待确认","圆奇","圆偶","方3标定","方形异常"};
  return "#"+(slot+1)+" "+(category>=0&&category<kinds.length?kinds[category]:"待确认")+" D"+(digit>0?String.valueOf(digit):"—");
 }
}
