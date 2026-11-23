# Windows 기본 내장 SQLite(winsqlite3.dll)를 설치 없이 쓰는 최소 도우미. sync.ps1·search.ps1이 불러 쓴다.
if (-not ('WmSql' -as [type])) {
Add-Type -TypeDefinition @'
using System; using System.Text; using System.Collections.Generic; using System.Runtime.InteropServices;
public static class WmSql {
  [DllImport("winsqlite3.dll", CharSet=CharSet.Unicode)] static extern int sqlite3_open16(string f, out IntPtr db);
  [DllImport("winsqlite3.dll")] static extern int sqlite3_close(IntPtr db);
  [DllImport("winsqlite3.dll")] static extern int sqlite3_prepare_v2(IntPtr db, byte[] sql, int n, out IntPtr st, IntPtr tail);
  [DllImport("winsqlite3.dll")] static extern int sqlite3_step(IntPtr st);
  [DllImport("winsqlite3.dll")] static extern int sqlite3_finalize(IntPtr st);
  [DllImport("winsqlite3.dll")] static extern int sqlite3_column_count(IntPtr st);
  [DllImport("winsqlite3.dll")] static extern IntPtr sqlite3_column_text16(IntPtr st, int i);
  [DllImport("winsqlite3.dll")] static extern int sqlite3_bind_text16(IntPtr st, int i, [MarshalAs(UnmanagedType.LPWStr)] string v, int n, IntPtr d);
  [DllImport("winsqlite3.dll")] static extern IntPtr sqlite3_errmsg16(IntPtr db);
  [DllImport("winsqlite3.dll")] static extern IntPtr sqlite3_libversion();
  public static string Version() { return Marshal.PtrToStringAnsi(sqlite3_libversion()); }
  public static IntPtr Open(string f) { IntPtr db; if (sqlite3_open16(f, out db) != 0) throw new Exception("open failed"); return db; }
  public static void Close(IntPtr db) { sqlite3_close(db); }
  public static List<string[]> Run(IntPtr db, string sql, params string[] args) {
    var rows = new List<string[]>(); IntPtr st; byte[] b = Encoding.UTF8.GetBytes(sql + "\0");
    if (sqlite3_prepare_v2(db, b, -1, out st, IntPtr.Zero) != 0) throw new Exception(Marshal.PtrToStringUni(sqlite3_errmsg16(db)));
    try {
      for (int i = 0; i < args.Length; i++) sqlite3_bind_text16(st, i + 1, args[i], -1, new IntPtr(-1));
      int rc; while ((rc = sqlite3_step(st)) == 100) { int n = sqlite3_column_count(st); var r = new string[n];
        for (int i = 0; i < n; i++) r[i] = Marshal.PtrToStringUni(sqlite3_column_text16(st, i)); rows.Add(r); }
      if (rc != 101) throw new Exception(Marshal.PtrToStringUni(sqlite3_errmsg16(db)));
    } finally { sqlite3_finalize(st); }
    return rows;
  }
}
'@
}
