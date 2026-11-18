# Native read-only view of the unit editor's owner-drawn list control.
if(-not ('KvNanoUnitNative' -as [type])) { Add-Type @'
using System;
using System.Text;
using System.Runtime.InteropServices;
using System.ComponentModel;
public static class KvNanoUnitNative {
 [DllImport("user32.dll",CharSet=CharSet.Unicode)] public static extern IntPtr SendMessage(IntPtr h,int m,IntPtr w,IntPtr l);
 [DllImport("user32.dll")] public static extern int GetScrollPos(IntPtr h,int bar);
 [DllImport("user32.dll")] static extern IntPtr GetParent(IntPtr h);
 [DllImport("user32.dll")] static extern int GetDlgCtrlID(IntPtr h);
 [DllImport("user32.dll",CharSet=CharSet.Unicode)] public static extern int GetWindowText(IntPtr h,StringBuilder s,int n);
 [DllImport("user32.dll")] static extern uint GetWindowThreadProcessId(IntPtr h,out uint p);
 [DllImport("kernel32.dll")] static extern IntPtr OpenProcess(uint a,bool b,int p);
 [DllImport("kernel32.dll")] static extern bool IsWow64Process(IntPtr p,out bool b);
 [DllImport("kernel32.dll")] static extern IntPtr VirtualAllocEx(IntPtr p,IntPtr a,UIntPtr s,uint t,uint f);
 [DllImport("kernel32.dll")] static extern bool VirtualFreeEx(IntPtr p,IntPtr a,UIntPtr s,uint t);
 [DllImport("kernel32.dll")] static extern bool WriteProcessMemory(IntPtr p,IntPtr a,byte[] b,UIntPtr s,out UIntPtr n);
 [DllImport("kernel32.dll")] static extern bool ReadProcessMemory(IntPtr p,IntPtr a,byte[] b,UIntPtr s,out UIntPtr n);
 [DllImport("kernel32.dll")] static extern bool CloseHandle(IntPtr h);
 [DllImport("user32.dll",SetLastError=true)] static extern IntPtr SendMessageTimeout(IntPtr h,uint m,UIntPtr w,IntPtr l,uint f,uint t,out UIntPtr r);
 public static string Text(IntPtr h) { var s=new StringBuilder(8192);GetWindowText(h,s,s.Capacity);return s.ToString(); }
 public static string[] ComboItems(IntPtr h) {
  int n=SendMessage(h,0x146,IntPtr.Zero,IntPtr.Zero).ToInt32();if(n<0||n>256)throw new Exception("KV_UNIT_COMBO_COUNT_INVALID");
  var result=new string[n];for(int i=0;i<n;i++){int len=SendMessage(h,0x149,new IntPtr(i),IntPtr.Zero).ToInt32();var b=Marshal.AllocHGlobal((len+1)*2);try{SendMessage(h,0x148,new IntPtr(i),b);result[i]=Marshal.PtrToStringUni(b);}finally{Marshal.FreeHGlobal(b);}}return result;
 }
 public static void SetCombo(IntPtr h,int pid,int index,string expected) {
  uint owner;GetWindowThreadProcessId(h,out owner);if(owner!=pid)throw new Exception("KV_UNIT_COMBO_PROCESS_MISMATCH");
  var items=ComboItems(h);if(index<0||index>=items.Length||items[index]!=expected)throw new Exception("KV_UNIT_COMBO_OPTION_MISMATCH");
  SendMessage(h,0x14e,new IntPtr(index),IntPtr.Zero);
  if(SendMessage(h,0x147,IntPtr.Zero,IntPtr.Zero).ToInt32()!=index)throw new Exception("KV_UNIT_COMBO_SELECTION_FAILED");
  SendMessage(GetParent(h),0x111,new IntPtr(GetDlgCtrlID(h)|(1<<16)),h);
 }
 public static string[][] Rows(IntPtr h,int pid) {
  uint owner;GetWindowThreadProcessId(h,out owner);if(owner!=pid)throw new Exception("KV_UNIT_LIST_PROCESS_MISMATCH");
  int rows=SendMessage(h,0x1004,IntPtr.Zero,IntPtr.Zero).ToInt32();if(rows<0||rows>512)throw new Exception("KV_UNIT_LIST_COUNT_INVALID");
  var p=OpenProcess(0x1038,false,pid);if(p==IntPtr.Zero)throw new Win32Exception();
  var mem=VirtualAllocEx(p,IntPtr.Zero,new UIntPtr(8192),0x3000,4);bool pending=false;
  try { bool wow;IsWow64Process(p,out wow);bool wide=Environment.Is64BitOperatingSystem&&!wow;var result=new string[rows][];
   for(int i=0;i<rows;i++){result[i]=new string[3];for(int c=0;c<3;c++){
    var b=new byte[96];Array.Copy(BitConverter.GetBytes(i),0,b,4,4);Array.Copy(BitConverter.GetBytes(c),0,b,8,4);
    Array.Copy(wide?BitConverter.GetBytes(mem.ToInt64()+128):BitConverter.GetBytes((uint)(mem.ToInt64()+128)),0,b,wide?24:20,wide?8:4);Array.Copy(BitConverter.GetBytes(2048),0,b,wide?32:24,4);
    UIntPtr n;if(!WriteProcessMemory(p,mem,b,new UIntPtr((uint)b.Length),out n))throw new Win32Exception();
    UIntPtr sent;pending=true;if(SendMessageTimeout(h,0x1073,new UIntPtr((uint)i),mem,2,2000,out sent)==IntPtr.Zero)throw new Exception("KV_UNIT_LIST_READ_TIMEOUT");pending=false;
    var text=new byte[4096];if(!ReadProcessMemory(p,IntPtr.Add(mem,128),text,new UIntPtr(4096),out n))throw new Win32Exception();result[i][c]=Encoding.Unicode.GetString(text).Split('\0')[0];
   }}return result;
  }finally{if(mem!=IntPtr.Zero&&!pending)VirtualFreeEx(p,mem,UIntPtr.Zero,0x8000);CloseHandle(p);}
 }
}
'@ }
