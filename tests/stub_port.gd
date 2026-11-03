extends RefCounted
## A free local port for tools/fake_supabase.py: starts at a per-process number (parallel test runs) and skips any port
## something already listens on (a stub left over from an earlier run answers with its old state).


static func free_port() -> int:
	var port := 20000 + OS.get_process_id() % 20000
	for i in 200:
		var probe := TCPServer.new()
		if probe.listen(port + i, "127.0.0.1") == OK:
			probe.stop()
			return port + i
	return port
