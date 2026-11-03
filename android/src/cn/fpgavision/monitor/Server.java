package cn.fpgavision.monitor;

import android.net.Uri;
import org.json.JSONObject;
import java.net.HttpURLConnection;
import java.net.URL;
import java.io.InputStream;
import java.io.ByteArrayOutputStream;
import java.io.FilterInputStream;
import java.io.IOException;
import android.webkit.WebResourceRequest;
import android.webkit.WebResourceResponse;
import java.util.HashMap;
import java.util.List;
import java.util.Map;

final class Server {
 static String normalize(String raw) throws Exception {
  String value=raw.trim();
  if(!value.contains("://"))value="https://"+value;
  URL u=new URL(value);
  if((!u.getProtocol().equals("https")&&!u.getProtocol().equals("http"))||u.getHost().isEmpty()
    ||u.getUserInfo()!=null||u.getQuery()!=null||u.getRef()!=null
    ||(!u.getPath().isEmpty()&&!u.getPath().equals("/")))
   throw new Exception("请输入完整的网址，例如 https://example.ngrok-free.app");
  return u.getProtocol()+"://"+u.getAuthority();
 }
 static JSONObject get(String base,String path,int timeout) throws Exception {
  return request(base,path,null,timeout);
 }
 static JSONObject post(String base,String path,JSONObject body) throws Exception {
  return request(base,path,body,12000);
 }
 static JSONObject request(String base,String path,JSONObject body,int timeout) throws Exception {
  HttpURLConnection c=(HttpURLConnection)new URL(base+path).openConnection();
  c.setConnectTimeout(8000);c.setReadTimeout(timeout);
  c.setRequestProperty("ngrok-skip-browser-warning","fpga-vision-app");
  c.setRequestProperty("Accept","application/json");c.setRequestProperty("User-Agent","FPGA-Vision/"+ClientContract.VERSION);
  try {
   if(body!=null){c.setRequestMethod("POST");c.setDoOutput(true);c.setRequestProperty("Content-Type","application/json; charset=utf-8");
    try(java.io.OutputStream out=c.getOutputStream()){out.write(body.toString().getBytes("UTF-8"));}}
   int status=c.getResponseCode();
   InputStream input=status>=400?c.getErrorStream():c.getInputStream();
   if(input==null)throw new Exception("服务器返回 "+status);
   try(InputStream in=input;ByteArrayOutputStream out=new ByteArrayOutputStream()){
    byte[] buffer=new byte[4096];int n;
    while((n=in.read(buffer))!=-1){out.write(buffer,0,n);if(out.size()>2*1024*1024)throw new Exception("响应过大");}
    JSONObject result;
    try{result=new JSONObject(out.toString("UTF-8"));}catch(Exception e){throw new Exception("网址未返回设备数据，请检查隧道地址");}
    if(status!=200)throw new Exception(result.optString("error","服务器返回 "+status));
    return result;
   }
  }finally{c.disconnect();}
 }
 static byte[] frame(String base,long version) throws Exception {
  return image(base,"/api/frame?v="+version);
 }
 static byte[] image(String base,String path) throws Exception {
  HttpURLConnection c=(HttpURLConnection)new URL(base+path).openConnection();
  c.setConnectTimeout(6000);c.setReadTimeout(10000);c.setRequestProperty("ngrok-skip-browser-warning","fpga-vision-app");
  c.setRequestProperty("User-Agent","FPGA-Vision-Native/"+ClientContract.VERSION);c.setUseCaches(false);
  try{
   if(c.getResponseCode()!=200||c.getContentType()==null||!c.getContentType().startsWith("image/"))throw new Exception("画面暂不可用");
   try(InputStream in=c.getInputStream();ByteArrayOutputStream out=new ByteArrayOutputStream()){
    byte[] buffer=new byte[8192];int n;while((n=in.read(buffer))!=-1){out.write(buffer,0,n);if(out.size()>8*1024*1024)throw new Exception("画面过大");}return out.toByteArray();
   }
  }finally{c.disconnect();}
 }
 // WebView does not propagate initial navigation headers to images/video/assets.
 // Forward only same-origin GETs, including Range for MP4 seeking, with the tunnel header.
 static WebResourceResponse proxy(WebResourceRequest request) {
  HttpURLConnection c=null;
  try{
   c=(HttpURLConnection)new URL(request.getUrl().toString()).openConnection();c.setConnectTimeout(8000);c.setReadTimeout(25000);
   c.setRequestProperty("ngrok-skip-browser-warning","fpga-vision-app");c.setRequestProperty("User-Agent","FPGA-Vision-Native/"+ClientContract.VERSION);
   c.setRequestProperty("Accept-Encoding","identity");
   for(Map.Entry<String,String> h:request.getRequestHeaders().entrySet())if(h.getKey().equalsIgnoreCase("Range"))c.setRequestProperty("Range",h.getValue());
   int status=c.getResponseCode();String type=c.getContentType();if(type==null)type="application/octet-stream";
   String mime=type.split(";")[0].trim();Map<String,String> headers=new HashMap<>();
   for(Map.Entry<String,List<String>> h:c.getHeaderFields().entrySet())if(h.getKey()!=null&&!h.getValue().isEmpty())headers.put(h.getKey(),h.getValue().get(0));
   final HttpURLConnection connection=c;InputStream stream=status>=400?c.getErrorStream():c.getInputStream();
   if(stream==null){c.disconnect();stream=new java.io.ByteArrayInputStream(new byte[0]);}
   else stream=new FilterInputStream(stream){public void close() throws IOException{try{super.close();}finally{connection.disconnect();}}};
   return new WebResourceResponse(mime,"UTF-8",status,c.getResponseMessage()==null?"Response":c.getResponseMessage(),headers,stream);
  }catch(Exception e){if(c!=null)c.disconnect();return new WebResourceResponse("text/plain","UTF-8",503,"Unavailable",new HashMap<>(),new java.io.ByteArrayInputStream("连接中断，请检查电脑与 ngrok".getBytes(java.nio.charset.StandardCharsets.UTF_8)));}
 }
 static boolean sameOrigin(String base,String other){
  try{URL a=new URL(base),b=new URL(other);return a.getProtocol().equals(b.getProtocol())&&a.getAuthority().equalsIgnoreCase(b.getAuthority());}
  catch(Exception e){return false;}
 }
}
