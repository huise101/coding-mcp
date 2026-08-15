Set shell = CreateObject("Shell.Application")
Set fso = CreateObject("Scripting.FileSystemObject")
basePath = fso.GetParentFolderName(WScript.ScriptFullName)
scriptPath = fso.BuildPath(basePath, "launchers\Fix-CloudflaredFirewall-Admin.ps1")
args = "-NoProfile -ExecutionPolicy Bypass -File """ & scriptPath & """"
shell.ShellExecute "powershell.exe", args, basePath, "runas", 1
