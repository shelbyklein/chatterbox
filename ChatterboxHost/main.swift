import Foundation

// ChatterboxHost: runs Chatterbox's agent processes so replies outlive the app window.
// The app launches it on demand; it leaves on its own once nothing needs it.

// Its own session, so quitting the app (or its terminal) never takes the host down with it.
setsid()
signal(SIGPIPE, SIG_IGN)
signal(SIGHUP, SIG_IGN)

let host = Host(directory: HostPaths.directory)
host.start()
dispatchMain()
