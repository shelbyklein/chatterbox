' Runs one chatterbox-desktop action in the logged-in desktop session, without a window
' (a console flashing up would take the focus from the app being driven).
Set shell = CreateObject("WScript.Shell")
shell.Run "powershell -NoProfile -NonInteractive -ExecutionPolicy Bypass -File """ & WScript.Arguments(0) & """ -Request """ & WScript.Arguments(1) & """", 0, False
