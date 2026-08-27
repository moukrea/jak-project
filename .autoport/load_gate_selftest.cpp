#include "game/system/load_gate.h"
#include <cstdio>
#include <thread>
#include <chrono>
#define CHECK(c) do { if(!(c)) { printf("FAIL line %d: %s\n", __LINE__, #c); fails++; } else { printf("  ok: %s\n", #c);} } while(0)
int main() {
  int fails = 0;
  printf("== 1. FAIL-OPEN: nothing has ever published residency ==\n");
  load_gate::reset_for_test();
  CHECK(load_gate::scene_ready("s1", "village1", "beach", 20000) == 1);
  CHECK(load_gate::wants_blocking_loads() == false);
  CHECK(load_gate::level_is_resident("village1") == true);

  printf("== 2. once the feed is alive, a missing level HOLDS ==\n");
  load_gate::reset_for_test();
  load_gate::mark_level_resident("village1");
  CHECK(load_gate::level_is_resident("village1") == true);
  CHECK(load_gate::level_is_resident("beach") == false);
  CHECK(load_gate::scene_ready("s2", "village1", "beach", 20000) == 0);
  CHECK(load_gate::wants_blocking_loads() == true);

  printf("== 3. it OPENS the instant the level lands ==\n");
  load_gate::mark_level_resident("beach");
  CHECK(load_gate::scene_ready("s2", "village1", "beach", 20000) == 1);
  CHECK(load_gate::wants_blocking_loads() == false);

  printf("== 4. already resident -> opens on the FIRST poll (fast machine unchanged) ==\n");
  CHECK(load_gate::scene_ready("s3", "village1", "beach", 20000) == 1);
  CHECK(load_gate::wants_blocking_loads() == false);

  printf("== 5. TIMEOUT: a level that never lands still releases the scene ==\n");
  load_gate::reset_for_test();
  load_gate::mark_level_resident("village1");
  CHECK(load_gate::scene_ready("s4", "never-loads", nullptr, 1) == 0);  // clamped to 250 ms
  std::this_thread::sleep_for(std::chrono::milliseconds(300));
  CHECK(load_gate::scene_ready("s4", "never-loads", nullptr, 1) == 1);

  printf("== 6. ABANDONED arm expires on its own (scene killed mid-wait) ==\n");
  load_gate::reset_for_test();
  load_gate::mark_level_resident("village1");
  CHECK(load_gate::scene_ready("s5", "never-loads", nullptr, 250) == 0);
  CHECK(load_gate::wants_blocking_loads() == true);
  std::this_thread::sleep_for(std::chrono::milliseconds(300));
  CHECK(load_gate::wants_blocking_loads() == false);  // pruned without GOAL coming back

  printf("== 7. eviction removes residency ==\n");
  load_gate::reset_for_test();
  load_gate::mark_level_resident("beach");
  CHECK(load_gate::level_is_resident("beach") == true);
  load_gate::mark_level_evicted("beach");
  CHECK(load_gate::level_is_resident("beach") == false);

  printf("\n%s (%d failure(s))\n", fails ? "TEST FAILED" : "ALL LOAD-GATE SAFETY PROPERTIES HOLD", fails);
  return fails ? 1 : 0;
}
