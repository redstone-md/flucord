#include "qpc_clock.h"

namespace flucord_video {

std::int64_t QpcTicksToNanoseconds(std::int64_t ticks,
                                   std::int64_t ticks_per_second) {
  constexpr std::int64_t nanoseconds_per_second = 1000000000;
  const std::int64_t whole_seconds = ticks / ticks_per_second;
  const std::int64_t remaining_ticks = ticks % ticks_per_second;
  return whole_seconds * nanoseconds_per_second +
         remaining_ticks * nanoseconds_per_second / ticks_per_second;
}

}  // namespace flucord_video
