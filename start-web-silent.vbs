' DeepSeek Harness launcher - single icon toggle (start, or confirm-stop when running).
' Hidden-window launcher: runs the toggle .cmd with no console window shown.
Set sh = CreateObject("WScript.Shell")
sh.CurrentDirectory = CreateObject("Scripting.FileSystemObject").GetParentFolderName(WScript.ScriptFullName)
sh.Run "cmd /c start-web.cmd", 0, False
