#pragma once

#include "common/util/Timer.h"

class FrameLimiter {
 public:
  FrameLimiter();
  ~FrameLimiter();

  // Negative target_fps means unlimited: reset the timer and skip all pacing.
  void run(double target_fps, bool experimental_accurate_lag, bool do_sleeps, double engine_time);

 private:
  double round_to_nearest_60fps(double current);

  Timer m_timer;
};