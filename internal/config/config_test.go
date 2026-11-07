package config

import "testing"

// TestTheInstallsBasePathAndHTTPS: the base path is read as the kit reads
// it — slashes or none, empty for the root — and a malformed one, or an
// https mode Notif does not have, stops the start.
func TestTheInstallsBasePathAndHTTPS(t *testing.T) {
	for raw, want := range map[string]string{"": "", "/": "", "k9x2": "/k9x2", "/k9x2/": "/k9x2"} {
		t.Setenv("NX_OPT_BASE_PATH", raw)
		c, err := Load()
		if err != nil || c.BasePath != want {
			t.Errorf("%q: %q %v", raw, c.BasePath, err)
		}
	}
	t.Setenv("NX_OPT_BASE_PATH", "a/b")
	if _, err := Load(); err == nil {
		t.Error("a base path of two segments was taken")
	}
	t.Setenv("NX_OPT_BASE_PATH", "")
	for mode, ok := range map[string]bool{"off": true, "acme": true, "self-signed": true, "letsencrypt": false} {
		t.Setenv("NX_OPT_HTTPS", mode)
		if _, err := Load(); (err == nil) != ok {
			t.Errorf("https %s: %v", mode, err)
		}
	}
}

// TestTheListenAddress: the port is bound on every interface unless the
// install names an address of the server — 127.0.0.1 for a reverse proxy
// beside Notif — and anything but an address stops the start.
func TestTheListenAddress(t *testing.T) {
	t.Setenv("NX_OPT_PORT", "8097")
	for raw, want := range map[string]string{"": ":8097", "127.0.0.1": "127.0.0.1:8097", "::1": "[::1]:8097", "[::1]": "[::1]:8097", " 10.0.0.5 ": "10.0.0.5:8097"} {
		t.Setenv("NX_OPT_LISTEN", raw)
		c, err := Load()
		if err != nil || c.Addr() != want {
			t.Errorf("listen %q: %q %v, want %q", raw, c.Addr(), err, want)
		}
	}
	for _, bad := range []string{"localhost", "127.0.0.1:8097", "0.0.0.0/0"} {
		t.Setenv("NX_OPT_LISTEN", bad)
		if _, err := Load(); err == nil {
			t.Errorf("listen %q was taken", bad)
		}
	}
}
