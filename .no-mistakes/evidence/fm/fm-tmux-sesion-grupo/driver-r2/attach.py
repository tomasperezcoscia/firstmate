# Attach a real tmux client (the "web viewer") to a session through a pty with a
# non-zero window size, and drain its output until killed.
import fcntl, os, pty, struct, sys, termios, signal
session, socket_dir = sys.argv[1], sys.argv[2]
env = {"HOME": os.environ["HOME"], "PATH": os.environ["PATH"], "TERM": "xterm-256color",
       "TMUX_TMPDIR": socket_dir, "LANG": os.environ.get("LANG", "C.UTF-8")}
pid, fd = pty.fork()
if pid == 0:
    fcntl.ioctl(0, termios.TIOCSWINSZ, struct.pack("HHHH", 50, 200, 0, 0))
    os.execvpe("tmux", ["tmux", "-L", "fm-lab", "attach-session", "-t", session], env)
fcntl.ioctl(fd, termios.TIOCSWINSZ, struct.pack("HHHH", 50, 200, 0, 0))
signal.signal(signal.SIGTERM, lambda *a: (os.kill(pid, signal.SIGHUP), sys.exit(0)))
while True:
    try:
        if not os.read(fd, 65536):
            break
    except OSError:
        break
