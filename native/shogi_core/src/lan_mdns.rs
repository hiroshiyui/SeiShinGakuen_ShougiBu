//! mDNS / DNS-SD (Bonjour) side of 通信対戦 discovery (ROADMAP Phase 8).
//!
//! A hosting game registers `_seishinshogi._tcp.local.` with its game
//! port and a TXT record (`proto`, `name`); a joining game browses that
//! type. The `mdns-sd` daemon runs on its own thread; GDScript calls
//! `poll()` every frame to collect what it found. Used alongside the
//! UDP broadcast beacon in `scripts/net/LanDiscovery.gd`, not instead of
//! it: whichever reaches the other device first wins.

use godot::prelude::*;
use mdns_sd::{Receiver, ServiceDaemon, ServiceEvent, ServiceInfo};

pub const SERVICE_TYPE: &str = "_seishinshogi._tcp.local.";

#[derive(GodotClass)]
#[class(base=RefCounted)]
pub struct LanMdns {
    daemon: Option<ServiceDaemon>,
    browse_rx: Option<Receiver<ServiceEvent>>,
    registered: Option<String>,
}

#[godot_api]
impl IRefCounted for LanMdns {
    fn init(_base: Base<RefCounted>) -> Self {
        Self { daemon: None, browse_rx: None, registered: None }
    }
}

#[godot_api]
impl LanMdns {
    /// Announces a hosted game. `name` is the player-visible device name;
    /// the instance name gets a random suffix so two devices with the same
    /// model don't collide. Returns false if mDNS can't start here.
    #[func]
    fn advertise(&mut self, name: GString, port: i64, proto: i64) -> bool {
        self.stop();
        let Some((daemon, fullname)) = register_service(&name.to_string(), port, proto) else {
            return false;
        };
        self.registered = Some(fullname);
        self.daemon = Some(daemon);
        true
    }

    /// Starts looking for hosted games; results arrive through `poll()`.
    #[func]
    fn browse(&mut self) -> bool {
        self.stop();
        let Some(daemon) = start_daemon() else { return false };
        match daemon.browse(SERVICE_TYPE) {
            Ok(rx) => {
                self.browse_rx = Some(rx);
                self.daemon = Some(daemon);
                true
            }
            Err(e) => {
                godot_warn!("mdns: browse failed: {e}");
                let _ = daemon.shutdown();
                false
            }
        }
    }

    /// Events since the last call:
    /// `{type: "found", key, name, address, port, proto}` or
    /// `{type: "lost", key}`. `key` is the mDNS full name.
    #[func]
    fn poll(&mut self) -> Array<VarDictionary> {
        let mut out = Array::new();
        let Some(rx) = &self.browse_rx else { return out };
        while let Ok(ev) = rx.try_recv() {
            match ev {
                ServiceEvent::ServiceResolved(svc) => {
                    // IPv4 only (the game's TCP side is v4), and only a
                    // private / link-local address: a record pointing
                    // off the LAN is ignored. Lowest address wins, so the
                    // pick is stable across interfaces.
                    let mut addrs: Vec<_> = svc
                        .get_addresses_v4()
                        .into_iter()
                        .filter(|a| a.is_private() || a.is_link_local())
                        .collect();
                    addrs.sort();
                    let Some(addr) = addrs.first() else { continue };
                    let mut d = VarDictionary::new();
                    d.set("type", "found");
                    d.set("key", svc.get_fullname());
                    let name = svc.get_property_val_str("name").unwrap_or("?");
                    d.set("name", truncate_bytes(name, NAME_MAX_BYTES));
                    d.set("address", addr.to_string().as_str());
                    d.set("port", svc.get_port() as i64);
                    let proto = svc
                        .get_property_val_str("proto")
                        .and_then(|p| p.parse::<i64>().ok())
                        .unwrap_or(-1);
                    d.set("proto", proto);
                    out.push(&d);
                }
                ServiceEvent::ServiceRemoved(_, fullname) => {
                    let mut d = VarDictionary::new();
                    d.set("type", "lost");
                    d.set("key", fullname.as_str());
                    out.push(&d);
                }
                _ => {}
            }
        }
        out
    }

    /// Withdraws the announcement and stops browsing.
    #[func]
    fn stop(&mut self) {
        if let Some(daemon) = self.daemon.take() {
            if let Some(fullname) = self.registered.take() {
                let _ = daemon.unregister(&fullname);
            }
            if self.browse_rx.take().is_some() {
                let _ = daemon.stop_browse(SERVICE_TYPE);
            }
            let _ = daemon.shutdown();
        }
        self.browse_rx = None;
        self.registered = None;
    }
}

impl Drop for LanMdns {
    fn drop(&mut self) {
        self.stop();
    }
}

/// Registers the game service and returns the running daemon and the
/// service's full name. Every failure path shuts the daemon down.
fn register_service(name: &str, port: i64, proto: i64) -> Option<(ServiceDaemon, String)> {
    let port = u16::try_from(port).ok()?;
    let name = truncate_bytes(name, NAME_MAX_BYTES);
    let suffix: u32 = rand::random::<u32>() & 0xffff;
    let instance = format!("{}-{suffix:04x}", sanitize(name));
    let host = format!("seishin-{suffix:04x}.local.");
    let proto = proto.to_string();
    let props = [("proto", proto.as_str()), ("name", name)];
    let info = match ServiceInfo::new(SERVICE_TYPE, &instance, &host, "", port, &props[..]) {
        Ok(i) => i.enable_addr_auto(),
        Err(e) => {
            godot_warn!("mdns: bad service info: {e}");
            return None;
        }
    };
    let fullname = info.get_fullname().to_string();
    // Started only after everything that can fail cheaply has passed.
    let daemon = start_daemon()?;
    if let Err(e) = daemon.register(info) {
        godot_warn!("mdns: register failed: {e}");
        let _ = daemon.shutdown();
        return None;
    }
    Some((daemon, fullname))
}

fn start_daemon() -> Option<ServiceDaemon> {
    match ServiceDaemon::new() {
        Ok(d) => Some(d),
        Err(e) => {
            godot_warn!("mdns: cannot start daemon: {e}");
            None
        }
    }
}

/// Longest device name carried in the TXT record (one TXT string may be
/// at most 255 bytes including the `name=` key).
const NAME_MAX_BYTES: usize = 120;
/// A DNS label is at most 63 bytes; leave room for the `-xxxx` suffix.
const LABEL_MAX_BYTES: usize = 57;

/// `s` cut to at most `max` bytes on a UTF-8 character boundary.
fn truncate_bytes(s: &str, max: usize) -> &str {
    if s.len() <= max {
        return s;
    }
    let mut end = max;
    while !s.is_char_boundary(end) {
        end -= 1;
    }
    &s[..end]
}

/// DNS-SD instance labels allow most characters, but keep it tidy: no
/// dots (they would read as extra labels), no control characters, and
/// short enough for one DNS label once the suffix is added.
fn sanitize(name: &str) -> String {
    let s: String = name.chars().filter(|c| *c != '.' && !c.is_control()).collect();
    let s = truncate_bytes(&s, LABEL_MAX_BYTES).to_string();
    if s.trim().is_empty() { "seishin".to_string() } else { s }
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::time::{Duration, Instant};

    #[test]
    fn sanitize_strips_dots_and_caps_length() {
        assert_eq!(sanitize("Pixel 8a"), "Pixel 8a");
        assert_eq!(sanitize("my.host.name"), "myhostname");
        assert_eq!(sanitize("..."), "seishin");
        assert_eq!(sanitize(&"x".repeat(80)).len(), LABEL_MAX_BYTES);
        // 30 kanji = 90 bytes: cut to fit a DNS label, on a char boundary.
        let jp = sanitize(&"将".repeat(30));
        assert!(jp.len() <= LABEL_MAX_BYTES && jp.chars().all(|c| c == '将'));
    }

    /// Needs a multicast-capable interface, like the test below.
    #[test]
    #[ignore]
    fn long_japanese_name_still_registers() {
        let name = "清正学園将棋部のタブレット端末です".repeat(4);
        let (daemon, _) = register_service(&name, 47997, 1).expect("registered");
        let _ = daemon.shutdown();
    }

    /// Registers and browses on this machine through the real daemon.
    /// Ignored by default: needs a multicast-capable interface.
    #[test]
    #[ignore]
    fn advertise_then_browse_finds_it() {
        let host = ServiceDaemon::new().unwrap();
        let info = ServiceInfo::new(SERVICE_TYPE, "test-host", "test-host.local.", "", 47999,
            &[("proto", "1"), ("name", "Tester")][..]).unwrap().enable_addr_auto();
        host.register(info).unwrap();
        let browser = ServiceDaemon::new().unwrap();
        let rx = browser.browse(SERVICE_TYPE).unwrap();
        let deadline = Instant::now() + Duration::from_secs(5);
        let mut found = false;
        while Instant::now() < deadline && !found {
            if let Ok(ServiceEvent::ServiceResolved(svc)) = rx.recv_timeout(Duration::from_millis(200)) {
                found = svc.get_port() == 47999 && svc.get_property_val_str("name") == Some("Tester");
            }
        }
        let _ = host.shutdown();
        let _ = browser.shutdown();
        assert!(found);
    }
}
