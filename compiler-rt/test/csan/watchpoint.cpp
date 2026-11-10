// RUN: %clangxx -O2 -I%S/../../lib %s -o %t && %run %t

// Exercise addresses with bit 31 set and PCs packed alongside size/flag bits.
// No memory at these addresses is accessed.
#include "csan/csan_watch.h"
#include <assert.h>

int main() {
  using namespace __csan;
  using Table = WatchpointTable<8192, 1>;
  alignas(8) u64 Slots[4] = {};
  Table Watchpoints(Slots);
  const uptr Address = 0xfffffff0u;
  const uptr PC = 0xfedcba98u;
  u64 *WP = Watchpoints.Insert(Address, 16, true, 0);
  assert(WP);
  u64 Encoded;
  assert(Watchpoints.Find(Address + 8, 8, true, 0, Encoded) == WP);
  assert(Watchpoints.TryConsume(WP, Encoded, PC, false, 4));
  void *Peer;
  int PeerAccess;
  u32 PeerSize;
  assert(!Watchpoints.Consume(WP, Peer, PeerAccess, PeerSize));
  assert(reinterpret_cast<uptr>(Peer) == PC);
  assert(PeerAccess == 0);
  assert(PeerSize == 4);
  Watchpoints.Remove(WP);
  assert(!Watchpoints.Find(Address, 16, false, 0, Encoded));
}
