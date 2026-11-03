package cn.fpgavision.monitor;
import android.app.job.*;
/** OS-managed background checks, with no permanent status notification. */
public class NotificationJobService extends JobService {
 volatile boolean stopped;Thread worker;
 public boolean onStartJob(JobParameters parameters){
  stopped=false;worker=new Thread(()->{
   boolean retry=false;try{NotificationSync.sync(getApplicationContext());}catch(Exception e){retry=true;}
   if(!stopped)jobFinished(parameters,retry);
  },"saved-video-notification-check");worker.start();return true;
 }
 public boolean onStopJob(JobParameters parameters){stopped=true;if(worker!=null)worker.interrupt();return true;}
}

