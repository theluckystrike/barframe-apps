#include "CProbe.h"
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <sys/sysctl.h>
#include <libproc.h>
#include <mach/mach.h>
int hr_agent(const char *name) {
 const char *names[]={"claude","codex","gemini","aider","opencode","goose","cursor-agent","amp","copilot","droid","crush","qwen","hermes"};
 if(!name) return 0;
 for(int i=0;i<13;i++) if(strcmp(name,names[i])==0) return 1;
 return 0;
}
static const char *base(const char *p) { const char *s=strrchr(p,'/'); return s?s+1:p; }
static int identify(pid_t pid, const char *comm) {
 char path[PROC_PIDPATHINFO_MAXSIZE]={0};
 if(proc_pidpath(pid,path,sizeof(path))>0 && hr_agent(base(path))) return 1;
 if(hr_agent(comm)) return 1;
 if(!(base(path)[0]>='0' && base(path)[0]<='9')) return 0;
 // Check only argv[0], never environment or arbitrary substrings.
 int mib[]={CTL_KERN,KERN_PROCARGS2,pid}; size_t n=1048576; char *buf=calloc(1,n);
 if(!buf) return 0; int found=0;
 if(sysctl(mib,3,buf,&n,NULL,0)==0 && n>sizeof(int)) {
  size_t i=sizeof(int); while(i<n && buf[i]) i++; while(i<n && !buf[i]) i++;
  if(i<n && memchr(buf+i,0,n-i)) found=hr_agent(base(buf+i));
 }
 free(buf); return found;
}
HRReading hr_read(void) {
 HRReading r={0}; size_t n=sizeof(r.total);
 int totalOK=sysctlbyname("hw.memsize",&r.total,&n,NULL,0)==0;
 vm_statistics64_data_t vm={0}; mach_msg_type_number_t count=HOST_VM_INFO64_COUNT;
 host_t host=mach_host_self(); int vmOK=host_statistics64(host,HOST_VM_INFO64,(host_info64_t)&vm,&count)==KERN_SUCCESS;
 vm_size_t page=0; int pageOK=host_page_size(host,&page)==KERN_SUCCESS; mach_port_deallocate(mach_task_self(),host);
 if(totalOK && vmOK && pageOK) {
  uint64_t anon=vm.internal_page_count>vm.purgeable_count?vm.internal_page_count-vm.purgeable_count:0;
  uint64_t used=(anon+vm.wire_count+(uint64_t)vm.compressor_page_count)*page;
  r.available=r.total>used?r.total-used:0; r.compressed=(uint64_t)vm.compressor_page_count*page;
 }
 struct xsw_usage swap={0}; n=sizeof(swap); int swapOK=sysctlbyname("vm.swapusage",&swap,&n,NULL,0)==0; r.swap=swap.xsu_used;
 n=sizeof(r.pressure); int pressureOK=sysctlbyname("kern.memorystatus_vm_pressure_level",&r.pressure,&n,NULL,0)==0;
 r.memoryOK=totalOK && vmOK && pageOK && swapOK && pressureOK;
 int mib[]={CTL_KERN,KERN_PROC,KERN_PROC_ALL,0}; n=0;
 if(sysctl(mib,3,NULL,&n,NULL,0)!=0 || n==0) return r;
 n+=128*sizeof(struct kinfo_proc); struct kinfo_proc *table=calloc(1,n); if(!table) return r;
 if(sysctl(mib,3,table,&n,NULL,0)!=0) { free(table); return r; }
 size_t len=n/sizeof(*table); char *marked=calloc(len,1); if(!marked) {free(table);return r;}
 r.processesOK=1;
 for(size_t i=0;i<len;i++) if(table[i].kp_eproc.e_ucred.cr_uid==getuid() && table[i].kp_proc.p_pid>0) marked[i]=identify(table[i].kp_proc.p_pid,table[i].kp_proc.p_comm);
 // Count roots once even when an agent invokes another supported agent.
 for(size_t i=0;i<len;i++) if(marked[i]) {
  pid_t parent=table[i].kp_eproc.e_ppid; int nested=0;
  for(size_t depth=0;depth<len && parent>1;depth++) { size_t j=0; for(;j<len;j++) if(table[j].kp_proc.p_pid==parent) break; if(j==len) break; if(marked[j]) {nested=1;break;} pid_t next=table[j].kp_eproc.e_ppid; if(next==parent) break; parent=next; }
  if(!nested) r.agents++;
 }
 int changed=1; while(changed) { changed=0; for(size_t i=0;i<len;i++) if(!marked[i] && table[i].kp_eproc.e_ucred.cr_uid==getuid()) for(size_t j=0;j<len;j++) if(marked[j] && table[i].kp_eproc.e_ppid==table[j].kp_proc.p_pid) {marked[i]=1;changed=1;break;} }
 for(size_t i=0;i<len;i++) if(marked[i]) { struct proc_taskinfo task={0}; if(proc_pidinfo(table[i].kp_proc.p_pid,PROC_PIDTASKINFO,0,&task,sizeof(task))==sizeof(task)) r.resident+=task.pti_resident_size; else r.unreadable++; }
 free(marked); free(table); return r;
}
