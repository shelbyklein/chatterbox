' Starts Ollama for Chatterbox in the logged-in desktop session, without a window.
' Ollama can't start from an SSH session (session 0), so a logon task runs this instead.
Set shell = CreateObject("WScript.Shell")
Set env = shell.Environment("Process")
env("OLLAMA_HOST") = "127.0.0.1:11434"
env("OLLAMA_CONTEXT_LENGTH") = "32768"
env("OLLAMA_KEEP_ALIVE") = "30m"
shell.Run """" & shell.ExpandEnvironmentStrings("%LOCALAPPDATA%") & "\Programs\Ollama\ollama.exe"" serve", 0, False
