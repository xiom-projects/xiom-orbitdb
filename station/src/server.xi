// XIOM ORBITDB -- ORBITWIRE v1 Station server: single-threaded poll loop,
// one DBFile per StationActor, per-session ingress/egress buffers.
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// ST1 transport decision: raw TCP on the loopback interface, framed by
// ORBITWIRE. The event loop is single-threaded on purpose -- the engine is a
// single-writer actor and a DBFile is never shared across threads. ST3 moves
// the actor behind a thread boundary with this same dispatch surface.
//
// Backpressure: a session has a bounded outbound queue (MAX_QUEUE_BYTES);
// reads from that session pause while the queue is at/over budget, and
// partial sends resume from out_at on the next tick.
module xiom.station.server

use xiom.net.socket;
use xiom.station.protocol;
use xiom.station.session;
use xiom.station.dispatch;

pub type StationServer = {
  actor: StationActor;
  listener: Int;
  host: Str;
  port: Int;
  next_id: Int;
  sessions: Vec[Session];
}

pub fn server_new() -> StationServer {
  return StationServer{ actor: actor_new(), listener: -1, host: "127.0.0.1",
                        port: 0, next_id: 0, sessions: Vec[Session].new() };
}

fn server_listen(host: Str, port_base: Int, out_port: &mut Int) -> Int {
  var port = port_base;
  if port <= 0 { port = 17867; }
  var attempt = 0;
  while attempt < 100 {
    var fd = -1;
    match socket_tcp() {
      Ok(x) => { fd = x; }
      Err(_) => {}
    }
    if fd >= 0 {
      let _ = socket_reuse_addr(fd, true);
      var ok = true;
      match socket_bind(fd, host, port) {
        Ok(_) => {}
        Err(_) => { ok = false; }
      }
      if ok {
        match socket_listen(fd, 64) {
          Ok(_) => {}
          Err(_) => { ok = false; }
        }
      }
      if ok {
        *out_port = port;
        return fd;
      }
      socket_close(fd);
    }
    port = port + 1;
    attempt = attempt + 1;
  }
  return -1;
}

pub fn server_init(srv: &mut StationServer, path: Str, order: Int,
                   page_format: Int, token: Str, host: Str,
                   port_base: Int) -> Int {
  srv.host = host;
  let code = actor_open(&mut srv.actor, path, order, page_format, token);
  if code != CODE_OK { return code; }
  var bound_port = 0;
  let fd = server_listen(host, port_base, &mut bound_port);
  if fd < 0 {
    actor_close(&mut srv.actor);
    return CODE_STORAGE;
  }
  srv.listener = fd;
  srv.port = bound_port;
  return CODE_OK;
}

fn server_find(srv: &StationServer, fd: Int) -> Int {
  var i = 0;
  while i < srv.sessions.len() {
    if srv.sessions[i].fd == fd && srv.sessions[i].state != STATE_CLOSED {
      return i;
    }
    i = i + 1;
  }
  return -1;
}

fn server_close_session(srv: &mut StationServer, idx: Int) {
  if idx < 0 || idx >= srv.sessions.len() { return; }
  if srv.sessions[idx].state == STATE_CLOSED { return; }
  let sid = srv.sessions[idx].id;
  let _ = actor_release_session(&mut srv.actor, sid);
  session_close(&mut srv.sessions[idx]);
}

fn server_accept(srv: &mut StationServer) {
  if srv.sessions.len() >= MAX_SESSIONS * 2 {
    // Hard stop on churn: all slots closed but not reused below is a bug.
    return;
  }
  var client = -1;
  match socket_accept(srv.listener) {
    Ok(fd) => { client = fd; }
    Err(_) => { return; }
  }
  let _ = socket_set_nodelay(client, true);
  srv.next_id = srv.next_id + 1;
  var peer = "";
  match socket_peer_addr(client) {
    Ok(p) => {
      match p {
        (h, pt) => { peer = h + ":" + pt.to_str(); }
      }
    }
    Err(_) => {}
  }
  var sess = session_new(srv.next_id, client, MAX_QUEUE_BYTES);
  sess.peer = peer;
  var i = 0;
  while i < srv.sessions.len() {
    if srv.sessions[i].state == STATE_CLOSED {
      srv.sessions[i] = sess;
      return;
    }
    i = i + 1;
  }
  if srv.sessions.len() < MAX_SESSIONS {
    srv.sessions.push(sess);
    return;
  }
  session_close(&mut sess);
}

fn server_read(srv: &mut StationServer, idx: Int) {
  if idx < 0 || idx >= srv.sessions.len() { return; }
  if srv.sessions[idx].state == STATE_CLOSED { return; }
  // Backpressure: pause ingress while the outbound budget is consumed.
  if !session_can_read(&srv.sessions[idx]) { return; }
  var bytes = Vec[UInt8].new();
  var recv_failed = false;
  match socket_recv(srv.sessions[idx].fd, 65536) {
    Ok(b) => { bytes = b; }
    Err(_) => { recv_failed = true; }
  }
  if recv_failed {
    server_close_session(srv, idx);
    return;
  }
  if bytes.len() == 0 {
    server_close_session(srv, idx);
    return;
  }
  if !session_feed(&mut srv.sessions[idx], &bytes) {
    server_close_session(srv, idx);
    return;
  }
  var loop_guard = 0;
  while loop_guard < 1024 {
    let st = session_pull(&mut srv.sessions[idx]);
    if st == 0 { return; }
    if st < 0 {
      let code = srv.sessions[idx].pull_code;
      let reply = err_frame(0, 0, code, code_name(code));
      let _ = session_queue(&mut srv.sessions[idx], &reply);
      srv.sessions[idx].closing = true;
      return;
    }
    let reply = dispatch(&mut srv.actor, &mut srv.sessions[idx]);
    if !session_queue(&mut srv.sessions[idx], &reply) {
      srv.sessions[idx].closing = true;
      return;
    }
    if srv.sessions[idx].closing { return; }
    loop_guard = loop_guard + 1;
  }
}

// One event-loop tick. Returns the number of sockets serviced, or -1 on a
// listener/poll failure. `timeout_ms` bounds the wait when idle.
pub fn server_step(srv: &mut StationServer, timeout_ms: Int) -> Int {
  if srv.listener < 0 { return -1; }
  var fds = Vec[Int].new();
  fds.push(srv.listener);
  var i = 0;
  while i < srv.sessions.len() {
    // Backpressure: a session at/over its outbound budget is not polled for
    // reads (it is still flushed below); this avoids a readable-fd busy loop
    // while a slow client drains.
    if srv.sessions[i].state != STATE_CLOSED && srv.sessions[i].fd >= 0 &&
       !srv.sessions[i].closing && session_can_read(&srv.sessions[i]) {
      fds.push(srv.sessions[i].fd);
    }
    i = i + 1;
  }
  var ready = Vec[Int].new();
  match socket_poll_read(&fds, timeout_ms) {
    Ok(r) => { ready = r; }
    Err(_) => { return -1; }
  }
  var events = 0;
  i = 0;
  while i < ready.len() {
    if ready[i] == srv.listener {
      server_accept(srv);
      events = events + 1;
    }
    i = i + 1;
  }
  i = 0;
  while i < ready.len() {
    let fd = ready[i];
    if fd != srv.listener {
      let idx = server_find(srv, fd);
      if idx >= 0 {
        server_read(srv, idx);
        events = events + 1;
      }
    }
    i = i + 1;
  }
  i = 0;
  while i < srv.sessions.len() {
    if srv.sessions[i].state != STATE_CLOSED && srv.sessions[i].fd >= 0 {
      let pending = session_flush(&mut srv.sessions[i]);
      if pending < 0 {
        server_close_session(srv, i);
      } else if srv.sessions[i].closing && pending == 0 {
        server_close_session(srv, i);
      }
    }
    i = i + 1;
  }
  return events;
}

pub fn server_run(srv: &mut StationServer) {
  var running = true;
  while running {
    let events = server_step(srv, 50);
    if events < 0 { running = false; }
  }
}

pub fn server_shutdown(srv: &mut StationServer) {
  var i = 0;
  while i < srv.sessions.len() {
    server_close_session(srv, i);
    i = i + 1;
  }
  if srv.listener >= 0 {
    socket_close(srv.listener);
    srv.listener = -1;
  }
  actor_close(&mut srv.actor);
}
