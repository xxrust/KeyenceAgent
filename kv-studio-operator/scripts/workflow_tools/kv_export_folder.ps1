# Native shell-folder selection for dialogs whose tree exposes no UIA items.
# WM_USER pointers must be allocated in the receiving process, not in PowerShell.
function Initialize-KvExportFolderNative {
  param([IntPtr]$DialogHwnd,[IntPtr]$TreeHwnd,[int]$ProcessId,[string]$Path)
  if(-not ('KvExportFolderNative' -as [type])) {
    Add-Type -TypeDefinition @'
using System;
using System.Collections.Generic;
using System.ComponentModel;
using System.Runtime.InteropServices;
using System.Text;
public static class KvExportFolderNative {
  [DllImport("user32.dll")] static extern uint GetWindowThreadProcessId(IntPtr window,out uint pid);
  [DllImport("user32.dll",CharSet=CharSet.Unicode)] static extern int GetClassName(IntPtr window,StringBuilder text,int count);
  [DllImport("user32.dll")] static extern IntPtr GetParent(IntPtr window);
  [DllImport("user32.dll",SetLastError=true)] static extern IntPtr SendMessageTimeout(IntPtr window,uint message,UIntPtr wparam,IntPtr lparam,uint flags,uint timeout,out UIntPtr result);
  [DllImport("kernel32.dll",SetLastError=true)] static extern IntPtr OpenProcess(uint access,bool inherit,int pid);
  [DllImport("kernel32.dll",SetLastError=true)] static extern bool IsWow64Process(IntPtr process,out bool wow64);
  [DllImport("kernel32.dll",SetLastError=true)] static extern IntPtr VirtualAllocEx(IntPtr process,IntPtr address,UIntPtr size,uint allocation,uint protection);
  [DllImport("kernel32.dll")] static extern bool VirtualFreeEx(IntPtr process,IntPtr address,UIntPtr size,uint type);
  [DllImport("kernel32.dll",SetLastError=true)] static extern bool WriteProcessMemory(IntPtr process,IntPtr address,byte[] bytes,UIntPtr size,out UIntPtr count);
  [DllImport("kernel32.dll",SetLastError=true)] static extern bool ReadProcessMemory(IntPtr process,IntPtr address,byte[] bytes,UIntPtr size,out UIntPtr count);
  [DllImport("kernel32.dll")] static extern bool CloseHandle(IntPtr handle);
  static bool pending;
  static UIntPtr Send(IntPtr window,uint message,uint wparam,IntPtr lparam) {
    UIntPtr result;
    pending=true;
    if(SendMessageTimeout(window,message,new UIntPtr(wparam),lparam,2,2000,out result)==IntPtr.Zero)
      throw new Win32Exception(Marshal.GetLastWin32Error(),"KV_EXPORT_FOLDER_MESSAGE_TIMEOUT");
    pending=false;
    return result;
  }
  static void Write(IntPtr process,IntPtr address,byte[] bytes) {
    UIntPtr count;
    if(!WriteProcessMemory(process,address,bytes,new UIntPtr((uint)bytes.Length),out count) || count.ToUInt64()!=(ulong)bytes.Length)
      throw new Win32Exception(Marshal.GetLastWin32Error());
  }
  static void Pointer(byte[] bytes,int offset,long value,bool wide) {
    Array.Copy(wide?BitConverter.GetBytes(value):BitConverter.GetBytes((uint)value),0,bytes,offset,wide?8:4);
  }
  public static string[] Select(IntPtr dialog,IntPtr tree,int pid,string path) {
    uint dialogPid,treePid; GetWindowThreadProcessId(dialog,out dialogPid); GetWindowThreadProcessId(tree,out treePid);
    var cls=new StringBuilder(256); GetClassName(tree,cls,cls.Capacity);
    if(dialogPid!=pid || treePid!=pid || cls.ToString()!="SysTreeView32") throw new InvalidOperationException("KV_EXPORT_FOLDER_NATIVE_IDENTITY_MISMATCH");
    var ancestor=tree;
    for(int depth=0;ancestor!=dialog && ancestor!=IntPtr.Zero && depth<8;depth++) ancestor=GetParent(ancestor);
    if(ancestor!=dialog) throw new InvalidOperationException("KV_EXPORT_FOLDER_TREE_NOT_OWNED");
    var process=OpenProcess(0x1038,false,pid);
    if(process==IntPtr.Zero) throw new Win32Exception(Marshal.GetLastWin32Error());
    IntPtr memory=IntPtr.Zero; pending=false;
    try {
      bool wow64; if(!IsWow64Process(process,out wow64)) throw new Win32Exception(Marshal.GetLastWin32Error());
      bool wide=Environment.Is64BitOperatingSystem && !wow64;
      if(wide && IntPtr.Size!=8) throw new InvalidOperationException("KV_EXPORT_FOLDER_64BIT_CLIENT_REQUIRED");
      byte[] pathBytes=Encoding.Unicode.GetBytes(path+"\0");
      int size=Math.Max(8192,pathBytes.Length);
      memory=VirtualAllocEx(process,IntPtr.Zero,new UIntPtr((uint)size),0x3000,4);
      if(memory==IntPtr.Zero) throw new Win32Exception(Marshal.GetLastWin32Error());
      Write(process,memory,pathBytes);
      Send(dialog,0x467,1,memory); // BFFM_SETSELECTIONW: absolute path in receiver memory.
      var names=new List<string>();
      var item=new IntPtr(unchecked((long)Send(tree,0x110A,9,IntPtr.Zero).ToUInt64())); // TVGN_CARET
      while(item!=IntPtr.Zero && names.Count<64) {
        byte[] info=new byte[wide?56:40]; info[0]=1; // TVIF_TEXT
        Pointer(info,wide?8:4,item.ToInt64(),wide);
        Pointer(info,wide?24:16,IntPtr.Add(memory,128).ToInt64(),wide);
        Array.Copy(BitConverter.GetBytes(2048),0,info,wide?32:20,4);
        Write(process,memory,info);
        if(Send(tree,0x113E,0,memory).ToUInt64()==0) throw new InvalidOperationException("KV_EXPORT_FOLDER_SELECTED_ITEM_UNREADABLE");
        byte[] text=new byte[4096]; UIntPtr count;
        if(!ReadProcessMemory(process,IntPtr.Add(memory,128),text,new UIntPtr((uint)text.Length),out count) || count.ToUInt64()!=(ulong)text.Length)
          throw new Win32Exception(Marshal.GetLastWin32Error());
        names.Add(Encoding.Unicode.GetString(text).Split('\0')[0]);
        item=new IntPtr(unchecked((long)Send(tree,0x110A,3,item).ToUInt64())); // TVGN_PARENT
      }
      return names.ToArray();
    } finally {
      // A timed-out receiver could still dereference the pointer. Leave that
      // small allocation until the process exits rather than free it early.
      if(memory!=IntPtr.Zero && !pending) VirtualFreeEx(process,memory,UIntPtr.Zero,0x8000);
      CloseHandle(process);
    }
  }
}
'@
  }
}
